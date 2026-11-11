"""Phone notifications through Firebase Cloud Messaging (HTTP v1), for when the app is closed or in the background.

Push is best-effort: the persisted notification and the REST snapshot stay the source of truth (ADR-0004). Only the
events a person should act on get a visible notification (`TEXTS`); everything else stays a socket hint. The phone shows
it only while the app is not on screen: an open app already reacts to the socket.

Sending happens on a small thread pool after the transaction commits, so a slow or failing Google call never holds up
a request. The service account key lives outside the repository (`FIREBASE_CREDENTIALS_FILE`); without it nothing is
sent and the reason is logged once.
"""

import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import jwt
from django.conf import settings

logger = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
CHANNEL_ID = "rides"

# kind -> (Arabic title, Arabic text, English title, English text, seconds the notification is still worth showing).
# Texts may use payload fields, e.g. {landmark}. No amounts here: the app shows them in the operator's currency.
TEXTS = {
    # driver
    "ride.offer": ("طلب جديد قريب منك", "افتح التطبيق وقدّم عرضك.", "New request near you", "Open the app to send your offer.", 180),
    "ride.price_raised": (
        "الراكب رفع السعر",
        "طلب قدّمت عليه صار بسعر أعلى.",
        "The rider raised the price",
        "A request you bid on now pays more.",
        300,
    ),
    "ride.selected": (
        "الراكب اختار عرضك",
        "أكّد الرحلة الآن قبل انتهاء المهلة.",
        "The rider picked your offer",
        "Confirm the trip now, before time runs out.",
        90,
    ),
    "ride.match_expired": (
        "انتهت مهلة التأكيد",
        "عاد الطلب لاستقبال العروض.",
        "Confirmation time ran out",
        "The request is open for offers again.",
        600,
    ),
    "subscription.activated": (
        "تم تفعيل اشتراكك",
        "يمكنك الاتصال واستقبال الطلبات.",
        "Your subscription is active",
        "You can go online and receive requests.",
        86400,
    ),
    "subscription.claim_rejected": (
        "لم يُقبل إيصال الإيداع",
        "افتح التطبيق لمعرفة السبب.",
        "Your deposit receipt was not accepted",
        "Open the app to see why.",
        86400,
    ),
    # rider
    "ride.bid_created": (
        "وصلك عرض جديد",
        "افتح التطبيق واختر السائق المناسب.",
        "You have a new offer",
        "Open the app and choose a driver.",
        300,
    ),
    "ride.match_released": ("السائق لم يؤكد", "اختر عرضًا آخر.", "The driver didn't confirm", "Choose another offer.", 600),
    "ride.assigned": ("السائق أكّد رحلتك", "السائق في الطريق إليك.", "Your driver confirmed", "The driver is on the way.", 1800),
    "ride.driver_arrived": (
        "السائق وصل",
        "السائق ينتظرك عند نقطة الانطلاق.",
        "Your driver is here",
        "The driver is waiting at the pickup.",
        900,
    ),
    "ride.driver_waiting": (
        "السائق ينتظرك",
        "السائق عند نقطة الانطلاق ويحاول التواصل معك.",
        "Your driver is waiting",
        "The driver is at the pickup and trying to reach you.",
        900,
    ),
    "ride.expired": ("لم تصل عروض", "يمكنك إعادة الطلب.", "No offers came in", "You can request again.", 1800),
    "ride.completed": (
        "وصلت بالسلامة",
        "ادفع الأجرة نقدًا للسائق وقيّم رحلتك.",
        "You've arrived",
        "Pay the driver in cash and rate your trip.",
        3600,
    ),
    # both
    "ride.cancelled": ("أُلغيت الرحلة", "افتح التطبيق للتفاصيل.", "The trip was cancelled", "Open the app for details.", 1800),
}

_pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="push")
_token_lock = threading.Lock()
_access = {"token": None, "expires": 0.0}
_warned = set()


def _warn_once(key, message, *args):
    if key not in _warned:
        _warned.add(key)
        logger.warning(message, *args)


def build_message(kind, payload, locale="ar"):
    """The FCM message body without its target, or None when this event gets no visible notification."""
    text = TEXTS.get(kind)
    if text is None:
        return None
    ar_title, ar_body, en_title, en_body, ttl = text
    title, body = (en_title, en_body) if str(locale).startswith("en") else (ar_title, ar_body)
    data = {"kind": kind, **{k: str(v) for k, v in payload.items() if v is not None and not isinstance(v, (dict, list))}}
    # One notification per trip and side: a newer one replaces the older instead of piling up.
    tag = f"{payload.get('ride_id') or kind}:{kind.split('.')[0]}"
    return {
        "notification": {"title": title, "body": body.format_map(_Blank(data))},
        "data": data,
        "android": {
            "priority": "HIGH",
            "ttl": f"{ttl}s",
            "collapse_key": str(payload.get("ride_id") or kind)[:64],
            "notification": {"channel_id": CHANNEL_ID, "tag": tag, "sound": "default"},
        },
    }


class _Blank(dict):
    def __missing__(self, key):
        return ""


def send_push(user, kind, payload, tenant=None):
    """Called after commit by `notify`. Never raises: a lost push only means the app learns on its next read."""
    provider = settings.PUSH_PROVIDER
    if provider == "none":
        return
    if provider != "fcm":
        raise NotImplementedError(f"Unknown push provider: {provider}")
    if user is None or tenant is None:
        return
    message = build_message(kind, payload, getattr(tenant, "locale", "ar"))
    if message is None:
        return
    from apps.core.context import tenant_context

    from .models import DeviceToken

    with tenant_context(tenant):
        tokens = list(DeviceToken.objects.filter(user=user).values_list("token", flat=True))
    if tokens:
        _pool.submit(_deliver, tenant.pk, tokens, message)


def _deliver(tenant_id, tokens, message):
    try:
        credentials = _credentials()
        if credentials is None:
            return
        access = _access_token(credentials)
        url = f"https://fcm.googleapis.com/v1/projects/{credentials['project_id']}/messages:send"
        for token in tokens:
            status, body = _post_json(url, {"message": {**message, "token": token}}, {"Authorization": f"Bearer {access}"})
            if status == 200:
                continue
            if status == 404 or "UNREGISTERED" in body or ("INVALID_ARGUMENT" in body and "token" in body.lower()):
                _forget(tenant_id, token)  # the app was removed or the token replaced
            else:
                logger.warning("push not delivered (%s): %s", status, body[:300])
    except Exception:  # best-effort by design
        logger.warning("push delivery failed", exc_info=True)


def _credentials():
    path = settings.FIREBASE_CREDENTIALS_FILE
    if not path:
        _warn_once("nofile", "push: FIREBASE_CREDENTIALS_FILE is not set; nothing is sent")
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError:
        _warn_once("missing", "push: no Firebase service account key at %s; nothing is sent", path)
        return None
    if data.get("type") != "service_account" or not data.get("private_key") or not data.get("project_id"):
        _warn_once("invalid", "push: %s is not a Firebase service account key; nothing is sent", path)
        return None
    return data


def _access_token(credentials):
    """OAuth access token for FCM, from a signed service-account assertion; reused until 5 minutes before it ends."""
    with _token_lock:
        if _access["token"] and _access["expires"] - 300 > time.time():
            return _access["token"]
        now = int(time.time())
        token_uri = credentials.get("token_uri") or "https://oauth2.googleapis.com/token"
        assertion = jwt.encode(
            {"iss": credentials["client_email"], "scope": FCM_SCOPE, "aud": token_uri, "iat": now, "exp": now + 3600},
            credentials["private_key"],
            algorithm="RS256",
            headers={"kid": credentials.get("private_key_id", "")},
        )
        form = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion})
        status, body = _post(token_uri, form.encode(), {"Content-Type": "application/x-www-form-urlencoded"})
        if status != 200:
            raise RuntimeError(f"push: Google refused the access token ({status}): {body[:200]}")
        data = json.loads(body)
        _access.update(token=data["access_token"], expires=now + int(data.get("expires_in", 3600)))
        return _access["token"]


def _post_json(url, payload, headers):
    return _post(url, json.dumps(payload).encode(), {"Content-Type": "application/json", **headers})


def _post(url, data, headers):
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def _forget(tenant_id, token):
    from apps.core.context import system_context

    from .models import DeviceToken

    with system_context():
        DeviceToken.all_tenants.filter(tenant_id=tenant_id, token=token).delete()
