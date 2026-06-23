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
uvicorn app.main:app --port 8000 --reload > uvicorn.log 2>&1 &
UVICORN_PID=$!
echo "✅ FastAPI running in background (PID: $UVICORN_PID)"
echo "   (Logs: tail -f cmpys/backend/uvicorn.log)"

# 2. Start Celery Worker
echo "Starting Celery Worker..."
celery -A app.core.celery worker -Q high_priority,default,low_priority --loglevel=info > celery.log 2>&1 &
CELERY_PID=$!
echo "✅ Celery running in background (PID: $CELERY_PID)"
echo "   (Logs: tail -f cmpys/backend/celery.log)"

echo "--------------------------------------------------------"
echo "Starting Flutter Frontend on iOS Simulator..."
echo "(Press 'q' in this terminal to quit and stop the backend)"
echo "--------------------------------------------------------"

# 3. Start Frontend
cd "$DIR/fe/cmpys"
echo "Looking for active iOS simulator..."

# Parse flutter devices to extract the UUID of the first iOS device
IOS_DEVICE_ID=$(flutter devices | grep -i "ios" | head -n 1 | awk -F'•' '{print $2}' | tr -d ' ')

if [ ! -z "$IOS_DEVICE_ID" ]; then
    echo "Found iOS simulator: $IOS_DEVICE_ID"
    flutter run -d "$IOS_DEVICE_ID"
else
    echo "No active iOS simulator found. Flutter will prompt you to choose:"
    flutter run
fi
