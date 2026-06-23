# CMPYS Backend

FastAPI service that powers CMPYS: authentication, the agentic mentorship
session state machine, and all LLM generation (mentor suggestions, the
idol-led interview, the comparison verdict, the growth blueprint, Socratic
chat, and idea-card quotes).

## Stack

- **Python 3.11 · FastAPI** (async)
- **PostgreSQL** via SQLAlchemy (async) + **Alembic** migrations
- **Redis** + Celery for background work
- **LLM**: Google **Gemini** (`gemini-2.5-flash`) and/or **OpenAI**, selected by
  `LLM_PROVIDER`; **Tavily** for web-grounded search

## Setup

```bash
cd cmpys/backend
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env        # then fill in the keys below
.venv/bin/alembic upgrade heads
.venv/bin/uvicorn app.main:app --port 8000 --reload
```

Health check: `curl http://localhost:8000/health` → `{"status":"ok"}`

### Environment (`.env`)

| Key | Purpose |
|---|---|
| `DATABASE_URL` | Async Postgres URL (`postgresql+psycopg://…`) |
| `REDIS_URL` | Redis for Celery |
| `LLM_PROVIDER` | `gemini` or `openai` |
| `GEMINI_API_KEY` | Gemini key |
| `OPENAI_API_KEY` / `OPENAI_MODEL` | OpenAI key + model |
| `TAVILY_API_KEY` | Web search grounding |
| `PLAN_GENERATOR_MODE` | Plan generation strategy |

> **Migrations note:** the migration graph has multiple heads, so use
> `alembic upgrade heads` (plural). A missing migration is the usual cause of a
> 500 from `/feed` (the `generated_by_user_id` column) — running `heads` fixes it.

## The agentic session

A session is a small state machine. Phases:

```
intake → idol_selection → interview → comparison → blueprint
                                                  ↘ guided_learning → completed
```

Each phase is driven by an endpoint; the LLM-heavy ones stream over SSE.

| Step | Endpoint | What it does |
|---|---|---|
| Create | `POST /api/v1/sessions` | New session from `{age, financial_status, interests}`; auto-advances to `idol_selection`. 409 if an active session already exists. |
| Suggest | `POST /api/v1/sessions/{id}/suggest-idols` | **LLM** + search → 3 mentors with `relevance_summary`, `confidence`, `wikidata_id`. |
| Select | `POST /api/v1/sessions/{id}/select-idol` | Sets the mentor, opens the interview thread → `interview`. |
| Interview | `POST /api/v1/sessions/{id}/interview` (SSE) | The mentor asks the next question **in persona**, adapting to prior answers. `done` carries `turn`, `max_turns`, `phase_transition`. |
| Results | `POST /api/v1/sessions/{id}/generate-results` (SSE) | Streams two sections: `comparison` (the verdict) then `blueprint`. → `completed`. |
| Chat | `POST /api/v1/sessions/{id}/guided-learning` (SSE) | Socratic mentor chat — used by the app's Chat tab. |
| Feed | `GET /api/v1/feed` | LLM idea-card quotes tuned to interests/goals/mentor. |
| Latest | `GET /api/v1/sessions/latest` | Most recent session **including completed** — the client's source of truth for "who is my mentor / what did they write". |
| Current | `GET /api/v1/sessions/current` | Most recent **non-completed** session (resume). |
| Abandon | `DELETE /api/v1/sessions/current` | Force-completes any active session so a fresh onboarding starts clean. |

All `/sessions/*` endpoints require a Bearer token (`get_current_user`).
A fuller endpoint list is in [docs/API.md](docs/API.md).

## Layout

```
app/
  main.py            app wiring, middleware, /media mount
  api/v1/            routers: auth, sessions, feed, idols, plans, …
  services/          LLM clients (gemini.py), tavily, content resources
  models/            SQLAlchemy models (intake session, idol, chat, feed, …)
  core/              config, db, middleware, celery
migrations/          Alembic revisions
tests/               pytest suite
```

## Tests

```bash
.venv/bin/pytest
```
