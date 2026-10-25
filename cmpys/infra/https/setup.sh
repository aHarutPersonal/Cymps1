#!/usr/bin/env bash
# Run on the existing CMPYS Amazon Linux host, as root.
# prepare never creates an ACME account or accepts legal terms.
set -euo pipefail
umask 077

ACTION="${1:-}"
PUBLIC_IP="${2:-}"
CONSENT="${3:-}"
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE=/etc/nginx/conf.d/cmpys.conf
CERT=/etc/letsencrypt/live/cmpys-api/fullchain.pem
IMAGE='certbot/certbot@sha256:c23159d30afdd9c97960578aa4654f5901de6cae394958f894074dedd55e599d'

if [[ "$EUID" != 0 || ! "$ACTION" =~ ^(prepare|enable)$ ]]; then
  echo 'Usage: sudo ./setup.sh prepare|enable PUBLIC_IPV4 [--accept-subscriber-agreement]' >&2
  exit 2
fi
python3 - "$PUBLIC_IP" <<'PY'
import ipaddress, sys
address = ipaddress.ip_address(sys.argv[1])
if address.version != 4 or not address.is_global:
    raise SystemExit('A public IPv4 address is required')
PY
if [[ "$ACTION" == enable && "$CONSENT" != --accept-subscriber-agreement ]]; then
  echo 'Issuance requires the owner to authorize the Let’s Encrypt Subscriber Agreement.' >&2
  echo 'Review https://letsencrypt.org/repository/ before passing --accept-subscriber-agreement.' >&2
  exit 2
fi

exec 9>/run/lock/cmpys-tls.lock
flock -n 9 || { echo 'Another CMPYS certificate operation is running' >&2; exit 1; }
[[ -s "$LIVE" ]] || { echo 'Existing CMPYS nginx configuration is required' >&2; exit 1; }
nginx -t
systemctl is-active --quiet nginx
systemctl is-active --quiet docker

install -d -m 700 /var/backups/cmpys-nginx /var/lib/cmpys-tls \
  /etc/letsencrypt /etc/letsencrypt-staging /var/lib/letsencrypt /var/log/letsencrypt
install -d -m 755 /var/www/cmpys-acme /var/www/cmpys-acme/.well-known \
  /var/www/cmpys-acme/.well-known/acme-challenge
BACKUP="/var/backups/cmpys-nginx/cmpys.conf.$(date -u +%Y%m%dT%H%M%SZ).$$"
cp -p "$LIVE" "$BACKUP"
cp -p /etc/nginx/nginx.conf "$BACKUP.main"

restore_nginx() {
  local code=$?
  trap - ERR
  cp -p "$BACKUP" "$LIVE"
  if nginx -t; then systemctl reload nginx; fi
  echo "TLS setup failed; previous nginx config restored from $BACKUP" >&2
  exit "$code"
}
trap restore_nginx ERR

render_config() {
  local include_tls="$1"
  python3 - "$SOURCE" "$PUBLIC_IP" "$include_tls" "$LIVE.next" <<'PY'
from pathlib import Path
import sys
source, public_ip, include_tls, target = sys.argv[1:]
source = Path(source)
config = (source / 'nginx-http.conf.template').read_text()
if include_tls == 'true':
    config += (source / 'nginx-https.conf.template').read_text()
config = config.replace('__PUBLIC_IP__', public_ip)
config = config.replace('__PROXY_DIRECTIVES__', (source / 'nginx-proxy.conf.template').read_text().rstrip())
config = config.replace('__AUTH_LOCATIONS__', (source / 'nginx-auth-locations.conf.template').read_text().rstrip())
Path(target).write_text(config)
PY
  chmod 644 "$LIVE.next"
  mv "$LIVE.next" "$LIVE"
  nginx -t
  systemctl reload nginx
}

install -m 755 "$SOURCE/certbot.sh" /usr/local/sbin/cmpys-certbot
install -m 755 "$SOURCE/renew.sh" /usr/local/sbin/cmpys-cert-renew
install -m 644 "$SOURCE/cmpys-cert-renew.service" /etc/systemd/system/cmpys-cert-renew.service
install -m 644 "$SOURCE/cmpys-cert-renew.timer" /etc/systemd/system/cmpys-cert-renew.timer
systemctl daemon-reload
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  timeout 5m docker pull "$IMAGE"
fi
/usr/local/sbin/cmpys-certbot --version

if [[ -s "$CERT" ]]; then render_config true; else render_config false; fi
printf '%s\n' 'cmpys-acme-ready' >/var/www/cmpys-acme/.well-known/acme-challenge/cmpys-https-probe
chmod 644 /var/www/cmpys-acme/.well-known/acme-challenge/cmpys-https-probe
curl --noproxy '*' --fail --silent --show-error --max-time 15 \
  --retry 5 --retry-delay 1 --retry-all-errors --retry-max-time 30 \
  -H "Host: $PUBLIC_IP" http://127.0.0.1/.well-known/acme-challenge/cmpys-https-probe
curl --noproxy '*' --fail --silent --show-error --max-time 15 \
  --retry 5 --retry-delay 1 --retry-all-errors --retry-max-time 30 http://127.0.0.1/ready

if [[ "$ACTION" == prepare ]]; then
  trap - ERR
  echo 'Prepared: streaming proxy and ACME challenge are live; no certificate account or issuance requested.'
  exit 0
fi

# Prove ACME validation with isolated staging state before production issuance.
COMMON=(certonly --non-interactive --agree-tos --register-unsafely-without-email
  --webroot --webroot-path /var/www/cmpys-acme --preferred-profile shortlived
  --ip-address "$PUBLIC_IP" --cert-name cmpys-api)
CMPYS_CERTBOT_STATE=/etc/letsencrypt-staging timeout --kill-after=30s 8m \
  /usr/local/sbin/cmpys-certbot "${COMMON[@]}" --staging
timeout --kill-after=30s 8m /usr/local/sbin/cmpys-certbot "${COMMON[@]}"
openssl x509 -noout -checkip "$PUBLIC_IP" -in "$CERT"
openssl x509 -noout -checkend 86400 -in "$CERT"
render_config true

# Connect locally while still verifying the trusted certificate against the IP.
curl --noproxy '*' --fail --silent --show-error --max-time 15 \
  --retry 5 --retry-delay 1 --retry-all-errors --retry-max-time 30 \
  --connect-to "$PUBLIC_IP:443:127.0.0.1:443" "https://$PUBLIC_IP/ready"
sha256sum "$CERT" | cut -d ' ' -f 1 >/var/lib/cmpys-tls/loaded-certificate.sha256
systemctl enable --now cmpys-cert-renew.timer
trap - ERR

# Release the shared lock before invoking the installed renewal wrapper.
flock -u 9
/usr/local/sbin/cmpys-cert-renew --dry-run --agree-tos
systemctl list-timers cmpys-cert-renew.timer --no-pager
echo 'HTTPS enabled; verify the public HTTPS endpoint from outside the host before migrating clients.'
