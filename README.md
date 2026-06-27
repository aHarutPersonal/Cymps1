# CMPYS

AI-powered mentorship app. Pick a legendary figure as your mentor, get interviewed
by them, see how you compare at the same age, and work the growth plan they write
for you.

## Repos

| Path | What |
|---|---|
| `fe/cmpys/` | Flutter mobile client (iOS, Android, web) |
| `cmpys/backend/` | FastAPI backend (Python 3.11, PostgreSQL, Gemini) |
| `cmpys/prompts/` | LLM prompt templates used by the backend |

## Quick start

```bash
# Backend
cd cmpys/backend
python3.11 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env   # fill in keys
.venv/bin/alembic upgrade heads
.venv/bin/uvicorn app.main:app --port 8000 --reload

# Frontend
cd fe/cmpys
flutter pub get
flutter run
```

## Production

- Backend: `54.158.122.215` (AWS EC2, Docker)
- Deploy: `cd cmpys/backend && ./deploy.sh`
