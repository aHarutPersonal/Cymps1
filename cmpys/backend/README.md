# CMPYS Backend

FastAPI service powering CMPYS: authentication, the agentic mentorship session,
all LLM generation (mentor suggestions, interview, comparison, blueprint, chat,
feed), and content resources.

## Stack

- Python 3.11, FastAPI (async)
- PostgreSQL via SQLAlchemy (async) + Alembic migrations
- Redis + Celery for background jobs
- Celery Beat catalog scheduler with daily job budgets and retry backoff
- Google Gemini (`gemini-2.5-flash`) for LLM generation
- Tavily for web-grounded search
- Wikiquote for free source-backed quote discovery

## Setup

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env        # fill in keys
.venv/bin/alembic upgrade heads
.venv/bin/uvicorn app.main:app --port 8000 --reload
.venv/bin/celery -A app.core.celery.celery_app worker -Q default,high_priority,low_priority,catalog,catalog_control
.venv/bin/celery -A app.core.celery.celery_app beat
```

Health check: `curl http://localhost:8000/health`

## Environment (`.env`)

| Key | Purpose |
|---|---|
| `DATABASE_URL` | Async Postgres (`postgresql+psycopg://...`) |
| `REDIS_URL` | Redis for Celery |
| `GEMINI_API_KEY` | Google Gemini API key |
| `TAVILY_API_KEY` | Web search grounding |
| `JWT_SECRET_KEY` | JWT signing; required in production |
| `CATALOG_SCHEDULER_ENABLED` | Enable continuous catalog ingestion |
| `CATALOG_DAILY_JOB_LIMIT` | Maximum catalog jobs started per UTC day |
| `CATALOG_DISPATCH_PER_TICK` | Maximum jobs leased each scheduler tick |
| `CATALOG_QUOTES_PER_IDOL_LIMIT` | Maximum sourced quotes retained per idol/import |
| `CATALOG_QUOTE_MIN_CONFIDENCE` | Deterministic quote provenance threshold |
| `CATALOG_QUOTE_VERIFICATION_ENABLED` | Enable independent Gemini Search cross-checks |
| `CATALOG_QUOTE_VERIFICATION_BATCH_SIZE` | Quotes checked in one grounded call (default 4) |
| `CATALOG_QUOTE_VERIFICATION_DAILY_LIMIT` | Maximum grounded quote calls per UTC day (default 2) |
| `LLM_USAGE_TELEMETRY_ENABLED` | Persist tokens, latency, status, and quality outcome |
| `ADAPTIVE_ROUTING_ENABLED` | Enable quality-gated Fast-Lite canaries |
| `ADAPTIVE_ROUTING_CANARY_PERCENT` | Initial eligible traffic sent to Fast-Lite (default 10%) |
| `ADAPTIVE_ROUTING_MIN_SAMPLES` | Good Fast-Lite samples required before expansion (default 20) |

## Continuous catalog ingestion

Celery Beat runs `catalog_tick` every minute. Each tick:

1. recovers stale job leases;
2. seeds missing idol profiles, pending books, and source-backed quote imports;
3. enforces the configured daily start limit;
4. dispatches a small priority-ordered batch to the `catalog` queue.

Book cache misses are inserted idempotently using their canonical key. Failed
jobs use exponential backoff and stop after `CATALOG_MAX_ATTEMPTS`. Generated
books and idols become visible to database-first APIs only after their quality
gate changes catalog status to `published`.

Quote imports use no LLM. The parser accepts only Wikiquote entries with a
specific nested citation and rejects disputed, misattributed, unsourced, and
generic attributed sections. Feed responses expose speaker, citation, source
URL, and `is_sourced`; the LLM is called only for remaining feed capacity.

The highest-ranked source-backed quotes are independently cross-checked in
small Gemini + Google Search batches. Exact text similarity, confidence, and a
non-aggregator grounded source must all pass deterministic gates before the
API exposes `is_verified=true`. Contradicted quotes are flagged and disappear
from the feed. Every verification call records model, token counts, duration,
search-query count, and outcome in `llm_usage_events`. With defaults, at most
eight quotes are cross-checked per day.

Usage telemetry also covers book draft/repair/fallback calls, plan generation,
feed fallback generation, grounded mentor/material lookups, and each idol
extraction stage. Book calls retain the downstream deterministic quality score,
so token spend can be compared against whether the module passed publication
requirements. `/feed/quality-stats` returns today's operations ordered by total
token use, with call counts, success rate inputs, latency, and average quality.

For book modules and plan-item details, adaptive routing starts with a stable
10% weekly Fast-Lite canary. Any schema or deterministic quality failure is
retried on the balanced model. Fast-Lite expands beyond the canary only after
the configured sample count meets both success-rate and average-quality
thresholds; five weak early samples stop the canary. Routing evaluates draft
calls only, so a successful Flash fallback cannot inflate Fast-Lite's score.
The stats response groups usage by operation and model and includes routing
decision reasons.

Every telemetry row also stores a paid-tier USD estimate using the configured
model's token counts, including hidden thinking tokens. Autonomous book, idol,
and quote-verification jobs share a `$0.50/day` background budget by default
(about `$15/month` at full use). At 85% only source-only quote imports continue;
paid jobs stay queued until the next UTC day. User-triggered app requests are
not blocked by this catalog guard. Per-job reserves for already running work
prevent parallel workers from consuming the same remaining budget twice.

Gemini 2.5 Search overage is excluded by default because the catalog's normal
two grounded calls per day are inside Google's paid-tier free allowance. Set
`LLM_BUDGET_INCLUDE_SEARCH_OVERAGE=true` for a conservative worst-case estimate
after that allowance is exceeded. Pricing assumptions are versioned in every
usage event and follow the official [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing).

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
| `GET /feed` | Database-first source-backed ideas + generated fallback |
| `GET /feed/quality-stats` | Quote quality + today's token, USD, and budget-state breakdown |
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
