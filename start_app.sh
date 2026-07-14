#!/bin/bash
set -e

# Automatically figure out the directory this script lives in
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# The app uses the deployed backend unless a local API is requested explicitly.
APP_API_BASE_URL="${API_BASE_URL:-http://54.158.122.215/api/v1}"
case "$APP_API_BASE_URL" in
    http://localhost:*|http://127.0.0.1:*|http://10.0.2.2:*)
        USE_LOCAL_BACKEND=true
        ;;
    *)
        USE_LOCAL_BACKEND=false
        ;;
esac

# Clean up function to shut down the background processes when Flutter closes
cleanup() {
    if [ "$USE_LOCAL_BACKEND" = true ]; then
        echo -e "\nShutting down local backend services..."
        if [ ! -z "$UVICORN_PID" ]; then
            kill -TERM "$UVICORN_PID" 2>/dev/null || true
        fi
        if [ ! -z "$CELERY_BEAT_PID" ]; then
            kill -TERM "$CELERY_BEAT_PID" 2>/dev/null || true
        fi
        if [ ! -z "$CATALOG_CONTROL_PID" ]; then
            kill -TERM "$CATALOG_CONTROL_PID" 2>/dev/null || true
        fi
        if [ ! -z "$CATALOG_WORKER_PID" ]; then
            kill -TERM "$CATALOG_WORKER_PID" 2>/dev/null || true
        fi
        if [ ! -z "$CELERY_PID" ]; then
            kill -TERM "$CELERY_PID" 2>/dev/null || true
        fi
    fi
    echo "Goodbye."
}

# Bind the cleanup function to script exit, interrupt, or termination
trap cleanup EXIT INT TERM

echo "--------------------------------------------------------"
echo "🚀 Starting CMPYS Stack"
echo "--------------------------------------------------------"

if [ "$USE_LOCAL_BACKEND" = true ]; then
# 0. Start Databases (Postgres & Redis) via Docker
echo "Starting Database Infrastructure..."
cd "$DIR/cmpys/infra"
docker compose up -d
sleep 2

# 1. Start Backend FastAPI Server
echo "Starting FastAPI Backend..."
cd "$DIR/cmpys/backend"
source .venv/bin/activate

echo "Applying database migrations..."
MIGRATIONS_READY=false
for _ in {1..30}; do
    if alembic upgrade head > alembic.log 2>&1; then
        MIGRATIONS_READY=true
        break
    fi
    sleep 0.5
done
if [ "$MIGRATIONS_READY" != true ]; then
    echo "❌ Database migrations failed. See cmpys/backend/alembic.log"
    exit 1
fi

uvicorn app.main:app --port 8000 --reload > uvicorn.log 2>&1 &
UVICORN_PID=$!
echo "✅ FastAPI running in background (PID: $UVICORN_PID)"
echo "   (Logs: tail -f cmpys/backend/uvicorn.log)"

# Do not launch Flutter until the API it will use is actually ready. This also
# fails fast when a migration/import error prevents Uvicorn from starting.
echo "Waiting for the local API..."
API_READY=false
for _ in {1..40}; do
    if curl --silent --fail http://localhost:8000/health >/dev/null; then
        API_READY=true
        break
    fi
    sleep 0.5
done
if [ "$API_READY" != true ]; then
    echo "❌ Local API did not become ready. See cmpys/backend/uvicorn.log"
    exit 1
fi

# 2. Start Celery Worker
echo "Starting Celery Worker..."
celery -A app.core.celery worker -n interactive@%h -Q high_priority,default,low_priority --loglevel=info > celery.log 2>&1 &
CELERY_PID=$!
echo "✅ Celery running in background (PID: $CELERY_PID)"
echo "   (Logs: tail -f cmpys/backend/celery.log)"

# Autonomous catalog generation must not consume the worker slots used by
# onboarding, plans, or lessons. Long catalog work and its lightweight control
# plane therefore have their own bounded workers.
echo "Starting Catalog Worker..."
CATALOG_WORKER_CONCURRENCY="${CATALOG_WORKER_CONCURRENCY:-2}"
celery -A app.core.celery worker \
    -n catalog@%h \
    -Q catalog \
    --concurrency="$CATALOG_WORKER_CONCURRENCY" \
    --loglevel=info > celery-catalog.log 2>&1 &
CATALOG_WORKER_PID=$!
echo "✅ Catalog worker running in background"
echo "   (PID: $CATALOG_WORKER_PID, concurrency: $CATALOG_WORKER_CONCURRENCY)"

echo "Starting Catalog Control Worker..."
celery -A app.core.celery worker -n catalog-control@%h -Q catalog_control --concurrency=1 --loglevel=info > celery-catalog-control.log 2>&1 &
CATALOG_CONTROL_PID=$!
echo "✅ Catalog control worker running in background (PID: $CATALOG_CONTROL_PID)"

echo "Waiting for the generation worker..."
WORKER_READY=false
for _ in {1..20}; do
    if ! kill -0 "$CELERY_PID" 2>/dev/null \
        || ! kill -0 "$CATALOG_WORKER_PID" 2>/dev/null \
        || ! kill -0 "$CATALOG_CONTROL_PID" 2>/dev/null; then
        break
    fi
    PONG_COUNT=$(celery -A app.core.celery inspect ping --timeout=1 2>/dev/null | grep -c "pong" || true)
    if [ "$PONG_COUNT" -ge 3 ]; then
        WORKER_READY=true
        break
    fi
    sleep 0.5
done
if [ "$WORKER_READY" != true ]; then
    echo "❌ Generation workers did not become ready. See cmpys/backend/celery*.log"
    exit 1
fi

# Retry delayed catalog work (including deferred book guides) and recover jobs
# left queued across worker restarts. Production already runs this process;
# local development needs the same scheduler contract.
echo "Starting Celery Beat..."
celery -A app.core.celery beat --loglevel=info --schedule=/tmp/cmpys-celerybeat-schedule > celery-beat.log 2>&1 &
CELERY_BEAT_PID=$!
sleep 0.5
if ! kill -0 "$CELERY_BEAT_PID" 2>/dev/null; then
    echo "❌ Catalog scheduler did not become ready. See cmpys/backend/celery-beat.log"
    exit 1
fi
echo "✅ Catalog scheduler running in background (PID: $CELERY_BEAT_PID)"
else
    REMOTE_READY_URL="${API_READY_URL:-${APP_API_BASE_URL%/api/v1}/ready}"
    echo "Checking deployed backend readiness..."
    if ! curl --silent --show-error --fail --max-time 12 "$REMOTE_READY_URL" >/dev/null; then
        echo "❌ Deployed API is not ready: $REMOTE_READY_URL"
        exit 1
    fi
    echo "✅ Deployed API is ready"
fi

echo "--------------------------------------------------------"
echo "Starting Flutter Frontend on iOS Simulator..."
if [ "$USE_LOCAL_BACKEND" = true ]; then
    echo "(Press 'q' in this terminal to quit and stop the local backend)"
else
    echo "(Press 'q' in this terminal to quit Flutter)"
fi
echo "--------------------------------------------------------"

# 3. Start Frontend
cd "$DIR/fe/cmpys"
echo "Looking for active iOS simulator..."

# Run the simulator against the deployed backend by default so it uses the
# shared remote data. Local development remains available as an explicit
# override: API_BASE_URL=http://localhost:8000/api/v1 ./start_app.sh
FLUTTER_API_ARGS=(--dart-define="API_BASE_URL=$APP_API_BASE_URL")
echo "Flutter API target: $APP_API_BASE_URL"

# Parse flutter devices to extract the UUID of the first iOS device
IOS_DEVICE_ID=$(flutter devices | grep -i "ios" | head -n 1 | awk -F'•' '{print $2}' | tr -d ' ')

if [ ! -z "$IOS_DEVICE_ID" ]; then
    echo "Found iOS simulator: $IOS_DEVICE_ID"
    flutter run -d "$IOS_DEVICE_ID" "${FLUTTER_API_ARGS[@]}"
else
    echo "No active iOS simulator found. Flutter will prompt you to choose:"
    flutter run "${FLUTTER_API_ARGS[@]}"
fi
