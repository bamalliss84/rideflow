from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.views import exception_handler

from .context import CrossTenantWrite, TenantContextMissing


class Conflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The resource changed or is in a conflicting state."
    default_code = "conflict"


class VersionConflict(Conflict):
    default_detail = "expected_version does not match the current version; refresh and retry."
    default_code = "version_conflict"


class InvalidTransition(Conflict):
    default_detail = "This action is not allowed in the current state."
    default_code = "invalid_transition"


class BusinessRuleViolation(APIException):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    default_detail = "The request violates a business rule."
    default_code = "business_rule"


class NotEligible(APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = "Not eligible for this action."
    default_code = "not_eligible"


def raise_rule(code, detail, exc=BusinessRuleViolation):
    raise exc(detail=detail, code=code)


def api_exception_handler(exc, context):
    if isinstance(exc, DjangoValidationError):
        exc = DRFValidationError(detail=exc.message_dict if hasattr(exc, "message_dict") else exc.messages)
    if isinstance(exc, (TenantContextMissing, CrossTenantWrite)):
        # Never reveal details; this indicates a programming error or an isolation attack.
        exc = APIException(detail="Not found.", code="not_found")
        exc.status_code = status.HTTP_404_NOT_FOUND
    response = exception_handler(exc, context)
    if response is None or not isinstance(exc, APIException):
        return response
    if isinstance(exc, DRFValidationError):
        response.data = {"code": "invalid", "errors": response.data}
        return response
    code = _first_code(exc.get_codes()) or exc.default_code
    data = response.data
    if isinstance(data, dict) and "detail" in data and len(data) == 1:
        data = data["detail"]
    response.data = {"code": code, "detail": data}
    return response


def _first_code(codes):
    if isinstance(codes, str):
        return codes
    if isinstance(codes, dict):
        codes = list(codes.values())
    for item in codes or []:
        found = _first_code(item)
        if found:
            return found
    return None
