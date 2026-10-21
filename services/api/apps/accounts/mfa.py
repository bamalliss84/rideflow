"""Administrator MFA: RFC 6238 TOTP (SHA-1, 6 digits, 30 s) with encrypted secrets and replay protection.

Login for staff (admin app) and platform admins is two-step: the first factor (OTP / password) returns a
short-lived signed *challenge*; tokens are issued only after a valid TOTP for that challenge. Tokens carry
the claim `mfa: true`; without it, staff roles and the platform scope are not granted (authentication.py).
"""

import base64
import hashlib
import hmac
import secrets
import struct
import time
from urllib.parse import quote

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings
from django.core import signing
from django.core.cache import cache

PERIOD = 30
DIGITS = 6
DRIFT_STEPS = 1
CHALLENGE_SALT = "rideflow.mfa.challenge"
CHALLENGE_TTL = 300
MAX_ATTEMPTS_PER_CHALLENGE = 5
ISSUER = "RideFlow"


class ChallengeInvalid(Exception):
    pass


def _fernet():
    key = settings.MFA_ENCRYPTION_KEY
    if not key:
        # Derived key (documented): rotating SECRET_KEY then requires re-enrolment.
        key = base64.urlsafe_b64encode(hashlib.sha256(f"rideflow-mfa:{settings.SECRET_KEY}".encode()).digest())
    return Fernet(key)


def encrypt_secret(secret):
    return _fernet().encrypt(secret.encode()).decode()


def decrypt_secret(token):
    try:
        return _fernet().decrypt(token.encode()).decode()
    except InvalidToken as exc:
        raise ChallengeInvalid("MFA secret cannot be decrypted (key rotated?)") from exc


def new_secret():
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp(secret, step):
    padded = secret + "=" * (-len(secret) % 8)
    digest = hmac.new(base64.b32decode(padded), struct.pack(">Q", step), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % 10**DIGITS
    return f"{value:0{DIGITS}d}"


def current_step(at=None):
    return int((at if at is not None else time.time()) // PERIOD)


def matching_step(secret, code, at=None):
    """Returns the matched time step (allowing +-1 step clock drift) or None."""
    if not code or len(code) != DIGITS or not code.isdigit():
        return None
    now = current_step(at)
    for step in range(now - DRIFT_STEPS, now + DRIFT_STEPS + 1):
        if hmac.compare_digest(totp(secret, step), code):
            return step
    return None


def provisioning_uri(secret, account):
    label = quote(f"{ISSUER}:{account}")
    return f"otpauth://totp/{label}?secret={secret}&issuer={quote(ISSUER)}&algorithm=SHA1&digits={DIGITS}&period={PERIOD}"


def make_challenge(user, *, scope, tenant=None, app=None):
    payload = {"uid": str(user.pk), "scope": scope, "n": secrets.token_hex(8)}
    if tenant is not None:
        payload["tid"] = str(tenant.pk)
    if app is not None:
        payload["app"] = app.client_id
    return signing.dumps(payload, salt=CHALLENGE_SALT, compress=True)


def read_challenge(token):
    try:
        return signing.loads(token, salt=CHALLENGE_SALT, max_age=CHALLENGE_TTL)
    except signing.BadSignature as exc:  # includes SignatureExpired
        raise ChallengeInvalid("MFA challenge is invalid or expired.") from exc


def register_attempt(token):
    """Counts verification attempts per challenge; returns False once the limit is exceeded."""
    key = "mfa_attempts:" + hashlib.sha256(token.encode()).hexdigest()
    attempts = (cache.get(key) or 0) + 1
    cache.set(key, attempts, CHALLENGE_TTL)
    return attempts <= MAX_ATTEMPTS_PER_CHALLENGE
