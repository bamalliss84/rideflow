from drf_spectacular.extensions import OpenApiAuthenticationExtension


class TenantJWTScheme(OpenApiAuthenticationExtension):
    target_class = "apps.accounts.authentication.TenantJWTAuthentication"
    name = "BearerJWT"

    def get_security_definition(self, auto_schema):
        return {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "Access token from /api/v1/auth/otp/verify (tenant scope) or /api/v1/auth/platform/login.",
        }
