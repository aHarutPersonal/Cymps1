#!/usr/bin/env bash
set -euo pipefail
ROLE="${1:-web}"
case "$ROLE" in
  web)     exec uvicorn app.main:app --host 0.0.0.0 --port 8000 ;;
  worker)  exec celery -A app.core.celery.celery_app worker --loglevel=info --concurrency="${CELERY_CONCURRENCY:-4}" -Q default,high_priority,low_priority ;;
  catalog-worker) exec celery -A app.core.celery.celery_app worker --loglevel=info --concurrency="${CATALOG_WORKER_CONCURRENCY:-1}" -Q catalog ;;
  catalog-control) exec celery -A app.core.celery.celery_app worker --loglevel=info --concurrency=1 -Q catalog_control ;;
  beat)    exec celery -A app.core.celery.celery_app beat --loglevel=info --schedule="${CELERY_BEAT_SCHEDULE:-/tmp/celerybeat-schedule}" ;;
  migrate) exec alembic upgrade heads ;;
  *) echo "unknown role: $ROLE" >&2; exit 1 ;;
esac
