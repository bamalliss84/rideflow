"""Upload validation and private, tenant-namespaced storage paths (T11)."""

import hashlib
import os
import uuid

from django.conf import settings
from django.http import FileResponse, Http404
from django.utils.deconstruct import deconstructible
from rest_framework.exceptions import ValidationError

from .context import require_tenant

SIGNATURES = {
    b"\xff\xd8\xff": ("image/jpeg", ".jpg"),
    b"\x89PNG\r\n\x1a\n": ("image/png", ".png"),
    b"%PDF-": ("application/pdf", ".pdf"),
}


def validate_upload(upload, max_bytes=None):
    """Checks size and real file type by magic bytes; returns (content_type, extension, sha256 hex)."""
    if upload is None:
        raise ValidationError({"file": "A file is required."})
    limit = max_bytes or settings.UPLOAD_MAX_BYTES
    if upload.size > limit:
        raise ValidationError({"file": f"File exceeds the maximum size of {limit} bytes."})
    upload.seek(0)
    head = upload.read(16)
    upload.seek(0)
    detected = next((meta for sig, meta in SIGNATURES.items() if head.startswith(sig)), None)
    if detected is None:
        raise ValidationError({"file": "Only JPEG, PNG or PDF files are accepted."})
    digest = hashlib.sha256()
    for chunk in upload.chunks():
        digest.update(chunk)
    upload.seek(0)
    return detected[0], detected[1], digest.hexdigest()


@deconstructible
class TenantUploadTo:
    """upload_to storing files under tenants/<tenant_id>/<category>/<uuid><ext> (random, non-guessable names)."""

    def __init__(self, category):
        self.category = category

    def __call__(self, instance, filename):
        ext = os.path.splitext(filename)[1].lower()[:8]
        tenant_id = instance.tenant_id or require_tenant().pk
        return f"tenants/{tenant_id}/{self.category}/{uuid.uuid4().hex}{ext}"

    def __eq__(self, other):
        return isinstance(other, TenantUploadTo) and other.category == self.category


def tenant_upload_to(category):
    return TenantUploadTo(category)


def private_file_response(field_file, content_type=None):
    if not field_file:
        raise Http404
    try:
        handle = field_file.open("rb")
    except FileNotFoundError:
        raise Http404
    response = FileResponse(handle, content_type=content_type or "application/octet-stream")
    response["Cache-Control"] = "private, no-store"
    response["X-Content-Type-Options"] = "nosniff"
    return response
