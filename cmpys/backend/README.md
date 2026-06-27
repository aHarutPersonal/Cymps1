# CMPYS Backend

FastAPI service powering CMPYS: authentication, the agentic mentorship session,
all LLM generation (mentor suggestions, interview, comparison, blueprint, chat,
feed), and content resources.

## Stack

- Python 3.11, FastAPI (async)
- PostgreSQL via SQLAlchemy (async) + Alembic migrations
- Redis + Celery for background jobs
- Google Gemini (`gemini-2.5-flash`) for LLM generation
- Tavily for web-grounded search

## Setup

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env        # fill in keys
.venv/bin/alembic upgrade heads
.venv/bin/uvicorn app.main:app --port 8000 --reload
```

Health check: `curl http://localhost:8000/health`

## Environment (`.env`)

| Key | Purpose |
|---|---|
| `DATABASE_URL` | Async Postgres (`postgresql+psycopg://...`) |
| `REDIS_URL` | Redis for Celery |
| `GEMINI_API_KEY` | Google Gemini API key |
| `TAVILY_API_KEY` | Web search grounding |
| `SECRET_KEY` | JWT signing |

## Session state machine

```
intake > idol_selection > interview > comparison > blueprint > guided_learning > completed
```

Each phase is driven by an endpoint; LLM-heavy ones stream over SSE.

## API

See [docs/API.md](docs/API.md) for the full endpoint reference.

### Core endpoints

| Endpoint | What |
|---|---|
| `POST /auth/register\|login\|refresh` | Auth + JWT tokens |
| `POST /sessions` | Create session from `{age, financial_status, interests}` |
| `POST /sessions/{id}/suggest-idols` | LLM mentor suggestions |
| `POST /sessions/{id}/select-idol` | Set mentor, open interview |
| `POST /sessions/{id}/interview` | SSE interview stream |
| `POST /sessions/{id}/generate-results` | SSE comparison + blueprint |
| `POST /sessions/{id}/guided-learning` | SSE mentor chat |
| `GET /feed` | LLM idea-card quotes |
| `GET /sessions/latest` | Source of truth for client sync |

## Layout

```
app/
  main.py            app wiring, middleware
  api/v1/            routers: auth, sessions, feed, idols, plans, ...
  services/          LLM clients (gemini.py), tavily, content resources
  models/            SQLAlchemy ORM
  core/              config, db, middleware, celery, security
migrations/          Alembic revisions
tests/               pytest suite
fixtures/            JSON test data
```

## Tests

```bash
.venv/bin/pytest
```

## Deploy

```bash
./deploy.sh
```

Builds the Docker image, pushes it to the server, runs migrations, and restarts.
See [deploy.sh](deploy.sh) for details.
