# CMPYS API HTTPS

This setup adds trusted HTTPS to the existing API IPv4 address without a domain
or service restart. It uses the official Certbot 5.4.0 container pinned by digest,
HTTP-01 webroot validation, a six-day certificate, and a systemd renewal check
every four hours. Certificate state and keys remain on the server.

## Deploy

Copy this directory to the existing server, then run `sudo bash setup.sh prepare
PUBLIC_IPV4`. Preparation backs up nginx, corrects proxy buffering for streamed
responses, creates the challenge webroot, installs the renewal scripts and units,
and verifies the local API. It does not create an ACME account, request a
certificate, accept legal terms, or enable the renewal timer.

Before issuance, the owner must authorize acceptance of the
[Let’s Encrypt Subscriber Agreement](https://letsencrypt.org/repository/).
After that authorization, run:

```sh
sudo bash setup.sh enable PUBLIC_IPV4 --accept-subscriber-agreement
```

The enable action tests issuance against isolated staging state, obtains the
production certificate, validates its IP and expiration, tests/reloads nginx,
verifies HTTPS trust locally, enables renewal, and runs a renewal dry run. A
configuration failure restores the previous nginx file. A renewal dry-run
failure leaves the issued certificate and renewal timer active for diagnosis.
No client should be switched to HTTPS until this external check passes:

```sh
curl --fail --show-error --max-time 15 https://PUBLIC_IPV4/ready
```

HTTP remains available for existing clients and certificate validation during
the migration. Once clients are migrated, redirect API HTTP traffic to HTTPS;
keep the challenge location on port 80. No firewall rules are modified.

Login and registration share a per-IP limit of 10 POST requests/minute with a
10-request burst. Token refresh has its own 60/minute limit and 30-request burst
to accommodate concurrent session recovery. Excess requests fail immediately
with JSON HTTP 429 and `Retry-After: 6`, instead of delaying the application.
Auth bodies are limited to 16 KiB. OPTIONS/preflight and other API routes do not
consume these limits; onboarding, SSE, and general API body limits are unchanged.
The public-edge proxy uses the connected client address, so a forged
`X-Forwarded-For` cannot bypass the limits. Both protocols share the same zones.

## Renewal and recovery

```sh
sudo systemctl status cmpys-cert-renew.timer cmpys-cert-renew.service
sudo journalctl -u cmpys-cert-renew.service --since '2 days ago'
sudo /usr/local/sbin/cmpys-cert-renew --dry-run
```

Certbot renews based on the saved short-lived profile and ACME renewal guidance.
The wrapper compares the certificate with the last certificate loaded by nginx,
tests nginx before reloading, retries a previously failed reload, and fails the
service if the remaining certificate lifetime falls below 24 hours. Certbot
failure is recorded by systemd and the next timer run retries. Production
monitoring should alert on timer failures and externally observed TLS expiry.
The timer is persistent across reboots. Renewal does not silently accept revised
legal terms or update the pinned container image.

Backups are stored under `/var/backups/cmpys-nginx/`. To restore a reviewed backup,
copy it over `/etc/nginx/conf.d/cmpys.conf`, run `sudo nginx -t`, then
`sudo systemctl reload nginx`. Do not delete certificate or ACME account state.

References:

- [Let’s Encrypt IP certificates with Certbot](https://letsencrypt.org/2026/03/11/shorter-certs-certbot)
- [Certbot renewal guide](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)
