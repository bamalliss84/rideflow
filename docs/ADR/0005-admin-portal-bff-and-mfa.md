# ADR-0005 Admin portal: Next.js BFF with HttpOnly sessions and mandatory administrator MFA

Status: ACCEPTED (D029, D030) | 2026-10-22

## Context

- **Clients.** The administration web app (D024) serves two audiences:
  - transport-operator staff, scoped to one tenant;
  - RideFlow platform staff, who provision tenants only.
- **Phase 1 gap.** Phase 1 left administrator MFA open (R01-04, T13).
- **Token storage.** Privileged long-lived tokens must not live in browser storage.

## Decision

1. **App.** `apps/admin` is a Next.js App Router app (TypeScript strict, Tailwind CSS 4). It runs as its own container, `admin`, on port 3000.
2. **BFF (backend-for-frontend).**
   - The browser only ever calls the same-origin Next.js server.
   - Route handlers keep the access and refresh JWTs in HttpOnly cookies (`SameSite=Strict`, `Secure` outside local http) and attach them to Django calls server-side.
   - `/api/proxy/*` forwards to `/api/v1/*`. `/api/auth/*` handles the login steps, refresh and logout.
3. **CSRF protection.**
   - Every mutation needs a same-origin `Origin` header.
   - It also needs a double-submit token: the readable `rf_csrf` cookie echoed in the `x-rf-csrf` header.
   - Login endpoints check the Origin.
4. **Token refresh.**
   - The proxy never refreshes tokens itself.
   - The browser client performs one single-flight refresh on a 401, then retries. Parallel requests therefore never rotate the same refresh token twice. Refresh tokens are rotated and blacklisted after use.
5. **MFA.** Administrator MFA is RFC 6238 TOTP. Secrets are encrypted with Fernet (`MFA_ENCRYPTION_KEY`).
   - **First factor.** The first factor (OTP for operator staff, password for platform staff) returns only a signed challenge, valid 5 minutes, with at most 5 attempts.
   - **Second factor.** A valid TOTP returns tokens that carry `mfa: true`. Replay of an already-used time step is rejected.
   - **No claim, no privileges.** Without the claim, staff roles are removed from the session and the platform scope is refused. A rider-app token of a staff member therefore never grants admin rights.
6. **Portal separation.**
   - Operator and platform portals use separate sessions (`rf_scope`) and separate route trees (`/operator`, `/platform`).
   - Route protection in the UI is convenience only. The API enforces every permission and every tenant boundary (RLS and fail-closed manager unchanged).
7. **Workspace.** On the login screen the tenant is the operator workspace: the client id of a registered admin application (D023, trusted app context). A white-label deployment can pin it with `DEFAULT_WORKSPACE`.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Tokens in `localStorage` | Exposed to XSS. |
| Django session cookies across origins | Couples the portal to Django templates and CSRF middleware, and complicates white-label domains. |
| SMS as the second factor | No provider is approved, and SMS is weaker than TOTP. |

## Consequences

- The admin portal must be served over HTTPS in any shared environment (`COOKIE_SECURE` defaults to true).
- **Lost devices:**
  - an owner or admin can reset an authenticator for staff who belong only to their tenant;
  - RideFlow platform staff reset owners and cross-tenant staff.
- Recovery codes are not implemented yet.
