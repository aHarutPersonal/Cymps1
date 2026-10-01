#!/usr/bin/env bash
# Pinned official Certbot 5.4.0 multi-platform image (includes ARM64).
set -euo pipefail

IMAGE='certbot/certbot@sha256:c23159d30afdd9c97960578aa4654f5901de6cae394958f894074dedd55e599d'
CERTBOT_STATE="${CMPYS_CERTBOT_STATE:-/etc/letsencrypt}"
case "$CERTBOT_STATE" in
  /etc/letsencrypt|/etc/letsencrypt-staging) ;;
  *) echo 'Unsupported certificate state directory' >&2; exit 2 ;;
esac

exec /usr/bin/docker run --rm --pull never \
  --cap-drop ALL --security-opt no-new-privileges \
  --memory 256m --cpus 0.5 \
  --mount "type=bind,src=$CERTBOT_STATE,dst=/etc/letsencrypt" \
  --mount type=bind,src=/var/lib/letsencrypt,dst=/var/lib/letsencrypt \
  --mount type=bind,src=/var/log/letsencrypt,dst=/var/log/letsencrypt \
  --mount type=bind,src=/var/www/cmpys-acme,dst=/var/www/cmpys-acme \
  "$IMAGE" "$@"
