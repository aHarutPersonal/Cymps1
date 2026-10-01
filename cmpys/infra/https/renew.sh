#!/usr/bin/env bash
set -euo pipefail
umask 077

exec 9>/run/lock/cmpys-tls.lock
flock -n 9 || exit 0

CERT=/etc/letsencrypt/live/cmpys-api/fullchain.pem
STATE=/var/lib/cmpys-tls/loaded-certificate.sha256
if [[ ! -s "$CERT" ]]; then
  echo 'CMPYS certificate is missing; initial issuance is required' >&2
  exit 1
fi

# Certbot's saved shortlived profile and ARI select when renewal is needed.
# No legal-acceptance flag: a changed subscriber agreement requires review.
timeout --signal=TERM --kill-after=30s 8m \
  /usr/local/sbin/cmpys-certbot renew --cert-name cmpys-api \
  --non-interactive --no-random-sleep-on-renew "$@"

# Compare with the last certificate actually loaded by nginx. This also retries
# a reload after a previous process crash or a failed nginx config validation.
CURRENT="$(sha256sum "$CERT" | cut -d ' ' -f 1)"
LOADED="$(cat "$STATE" 2>/dev/null || true)"
if [[ "$CURRENT" != "$LOADED" ]]; then
  nginx -t
  systemctl reload nginx
  printf '%s\n' "$CURRENT" >"$STATE.next"
  mv "$STATE.next" "$STATE"
fi

if ! openssl x509 -checkend 86400 -noout -in "$CERT"; then
  echo 'CMPYS certificate expires in less than 24 hours; renewal needs attention' >&2
  exit 1
fi
