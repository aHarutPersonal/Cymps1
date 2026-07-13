#!/bin/bash
set -e

# Automatically figure out the directory this script lives in
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Clean up function to shut down the background processes when Flutter closes
cleanup() {
    echo -e "\nShutting down backend services..."
    if [ ! -z "$UVICORN_PID" ]; then 
        kill -TERM $UVICORN_PID 2>/dev/null || true
    fi
    if [ ! -z "$CELERY_PID" ]; then 
        kill -TERM $CELERY_PID 2>/dev/null || true
    fi
    echo "Goodbye."
}

# Bind the cleanup function to script exit, interrupt, or termination
trap cleanup EXIT INT TERM

echo "--------------------------------------------------------"
echo "🚀 Starting CMPYS Stack"
echo "--------------------------------------------------------"

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
celery -A app.core.celery worker -Q high_priority,default,low_priority,catalog,catalog_control --loglevel=info > celery.log 2>&1 &
CELERY_PID=$!
echo "✅ Celery running in background (PID: $CELERY_PID)"
echo "   (Logs: tail -f cmpys/backend/celery.log)"

echo "Waiting for the generation worker..."
WORKER_READY=false
for _ in {1..20}; do
    if ! kill -0 "$CELERY_PID" 2>/dev/null; then
        break
    fi
    if celery -A app.core.celery inspect ping --timeout=1 2>/dev/null | grep -q "pong"; then
        WORKER_READY=true
        break
    fi
    sleep 0.5
done
if [ "$WORKER_READY" != true ]; then
    echo "❌ Generation worker did not become ready. See cmpys/backend/celery.log"
    exit 1
fi

echo "--------------------------------------------------------"
echo "Starting Flutter Frontend on iOS Simulator..."
echo "(Press 'q' in this terminal to quit and stop the backend)"
echo "--------------------------------------------------------"

# 3. Start Frontend
cd "$DIR/fe/cmpys"
echo "Looking for active iOS simulator..."

# The launcher owns a local backend and worker, so make the target explicit.
# Without this define, iOS debug builds previously fell back to the deployed
# API and silently bypassed both local services.
LOCAL_API_BASE_URL="${API_BASE_URL:-http://localhost:8000/api/v1}"
FLUTTER_API_ARGS=(--dart-define="API_BASE_URL=$LOCAL_API_BASE_URL")

# Parse flutter devices to extract the UUID of the first iOS device
IOS_DEVICE_ID=$(flutter devices | grep -i "ios" | head -n 1 | awk -F'•' '{print $2}' | tr -d ' ')

if [ ! -z "$IOS_DEVICE_ID" ]; then
    echo "Found iOS simulator: $IOS_DEVICE_ID"
    flutter run -d "$IOS_DEVICE_ID" "${FLUTTER_API_ARGS[@]}"
else
    echo "No active iOS simulator found. Flutter will prompt you to choose:"
    flutter run "${FLUTTER_API_ARGS[@]}"
fi
