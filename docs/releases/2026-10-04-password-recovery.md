# Password recovery integration

## Client contract

- `GET /api/v1/auth/password-reset/availability`: `200 {"available": false}` until a sender is configured. Show a truthful unavailable state and allow existing-code entry.
- `POST /api/v1/auth/password-reset/request`, JSON `{"email":"..."}`: `202 {"message":"If an account uses this email, a recovery code will arrive shortly."}`. The response is identical for known and unknown addresses. `503` means recovery is unavailable; `429` includes `Retry-After`.
- `POST /api/v1/auth/password-reset/confirm`, JSON `{"token":"43-character code from email","password":"..."}`: `204` on success. Clear local authentication and return to sign in. `400` means expired/invalid/used code, `422` invalid form, `429` rate limited, `503` limiter unavailable.

The user copies the code from the email into Account access → Enter recovery code. No domain purchase, external reset page or custom URL scheme is required. Passwords require 8–72 characters and at most 72 UTF-8 bytes, matching registration.

## Backend safeguards

Cryptographically random 256-bit codes expire in 20 minutes. Only SHA-256 digests are stored. A new request replaces a previous code. A single conditional SQL update consumes a valid, unexpired digest, changes the bcrypt password and increments the authentication version. Existing access/refresh tokens then fail; pre-migration sessions keep working until their account resets its password.

Redis atomically limits request volume for both client IP and hashed email identity, and limits confirmation by client IP. A limiter outage fails closed. The application uses the framework's client address and never reads an untrusted forwarding header itself. The final deployment binds the web service only to host loopback. Host nginx overwrites forwarding headers, and the web process trusts forwarded addresses only within that host/project-container trust boundary. Public traffic cannot reach the app port directly; this prevents all external clients sharing the proxy address quota. Counters contain hashed identifiers, not email addresses or raw codes.

Delivery runs after the HTTP response so SMTP time does not expose whether the account exists. The adapter requires validated TLS for remote SMTP. Cleartext is allowed only for a loopback test stand. Failures log the exception class without addresses, credentials or codes. Background email delivery is not a durable mail queue: a process failure can lose a delivery; users can request another code within the rate limit. Production activation must include a real delivery test and monitoring for delivery failures.

## Remaining production connection

Activate trusted HTTPS for the public API and switch the client before enabling real recovery. Use an existing verified SMTP sender. Configure `RECOVERY_SMTP_HOST`, `RECOVERY_SMTP_PORT`, `RECOVERY_SMTP_TLS` (`starttls` or `ssl`), `RECOVERY_EMAIL_SENDER`, and protected SMTP credentials when required. Do not paste credentials into chat or commit them. No provider account has been created and no external email has been sent during this implementation. The current deployment remains unavailable for real recovery until that connection is supplied and verified.

Migration `m4n5o6p7q8r9` adds nullable recovery fields and an authentication version defaulting to zero. Downgrade deliberately refuses to discard revocations. Deployment must migrate before starting new application processes; image rollback can retain the additive columns. After the first real password reset, never roll back to an older image that ignores authentication versions: it would accept revoked sessions. The current release keeps SMTP disabled, so its initial activation rollback has no such issued recovery sessions.

## Validation

Tests cover code/password validation, identical known/unknown responses, explicit unconfigured behavior, old access/refresh rejection, secret-free error logging, loopback-only cleartext allowance, real SMTP delivery into a controlled loopback server, Redis failure/limit responses, and real PostgreSQL expiry, replacement, one-time consumption and password change. Test SMTP delivery is not evidence of production email delivery.
