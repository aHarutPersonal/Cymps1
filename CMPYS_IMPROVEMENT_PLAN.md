# CMPYS Improvement Plan

**Created:** 2026-05-14  
**Scope:** Full-stack improvements across security, architecture, code quality, testing, performance, and feature delivery  
**Status:** Draft — prioritized for Harut's review

---

## Executive Summary

CMPYS is a solid product with a compelling core loop (compare → plan → daily execution → mentor chat). The P0 content quality work is done, and the infrastructure (streak, daily focus, notifications) is in place. The biggest opportunities now are:

1. **Security hygiene** — leaked API keys in `.env`, no rate limiting, JWT secret is default
2. **Testing** — essentially zero coverage on both backend and frontend
3. **Feature completion** — P1-P7 items from the PRD, especially notification settings UI and agentic activation flow
4. **Code architecture** — some god-object API files, no error handling standardization, JSON repair hack in LLM client
5. **Operational maturity** — no CI/CD, no monitoring, no health checks beyond a stub

---

## 🔴 P0 — Critical (Do First)

### 0.1 Rotate Leaked API Keys

**Problem:** The `.env` file contains hardcoded OpenAI API keys, Tavily API key, and Gemini API key committed to the git repo. The `.gitignore` does include `.env`, but these files are already tracked.

**Impact:** Anyone with repo access has production API keys. Cost and abuse risk.

**Actions:**
- [ ] Rotate all three API keys immediately (OpenAI, Gemini, Tavily)
- [ ] Remove `.env` from git tracking: `git rm --cached cmpys/backend/.env`
- [ ] Add `.env` to `.gitignore` (already there, but verify)
- [ ] Store secrets in a proper secret manager or at minimum a `~/.cmpys-env` file outside the repo
- [ ] Scan git history for leaked keys and consider `git filter-branch` or BFG Repo-Cleaner

### 0.2 Change Default JWT Secret

**Problem:** `config.py` defaults to `jwt_secret_key = "change-me-in-production-use-openssl-rand-hex-32"`. This is a well-known placeholder and trivially exploitable.

**Impact:** Anyone can forge authentication tokens.

**Actions:**
- [ ] Generate a proper JWT secret: `python -c "import secrets; print(secrets.token_hex(32))"`
- [ ] Set it in `.env` as `JWT_SECRET_KEY=<generated>`
- [ ] Add a startup check that refuses to boot if the secret is the default value

### 0.3 Add Rate Limiting to LLM Endpoints

**Problem:** Idol import, plan generation, chat, and content generation endpoints have no rate limiting. A single user could trigger thousands of dollars in LLM costs.

**Impact:** Financial exposure. No protection against abuse.

**Actions:**
- [ ] Add `slowapi` or custom middleware with per-user rate limits
- [ ] Idol import: max 5/minute per user
- [ ] Plan generation: max 2/minute per user
- [ ] Chat: max 30/minute per user
- [ ] Image generation: max 3/minute per user

---

## 🟠 P1 — High Priority

### 1.1 Backend Test Coverage

**Problem:** Zero test coverage. The `tests/` directory exists with ~2,500 lines but they appear to be integration scripts rather than a proper test suite. No CI to enforce them.

**Actions:**
- [ ] Set up `pytest` with `pytest-asyncio` properly in `conftest.py`
- [ ] Create test database fixture (separate test DB, auto-migrate)
- [ ] Add unit tests for critical services:
  - `services/llm/client.py` — JSON repair, response parsing, retry logic
  - `services/planning/generator.py` — plan generation pipeline
  - `services/content_resources.py` — duration calculation, word count validation
  - `services/chat/responder.py` — jargon guard, response filtering
  - `services/extraction/` — idol data extraction
  - `services/ingestion/pipeline.py` — ingestion pipeline
- [ ] Add API integration tests for key endpoints:
  - Auth flow (register, login, token refresh)
  - Idol import + job status polling
  - Plan creation + item detail retrieval
  - Chat thread creation + message flow
- [ ] Target: 60% coverage on services, 80% on API endpoints

### 1.2 Frontend Test Coverage

**Problem:** Only 10 test files, 345 lines. Essentially untested for a 60K-line codebase.

**Actions:**
- [ ] Add widget tests for critical screens:
  - Home screen (streak badge, continue reading, daily focus)
  - Chat screen (message rendering, streaming)
  - Plan screen (task completion, progress rings)
  - Onboarding / intake flow
- [ ] Add unit tests for controllers:
  - `HomeController` — load guards, state transitions
  - `ChatController` — initialization, message sending
  - `IdolsController` — suggest, discover, import
- [ ] Add integration tests for API client:
  - `DioClient` — auth headers, error handling, retry logic
  - Token store — secure storage, refresh flow

### 1.3 Error Handling Standardization

**Problem:** API endpoints use inconsistent error handling. Some return `HTTPException`, some return custom errors, some let exceptions propagate. The frontend likely has inconsistent error states.

**Actions:**
- [ ] Create a standardized `AppError` exception hierarchy:
  ```python
  class AppError(Exception):
      status_code: int
      error_code: str
      message: str
      details: dict | None

  class NotFoundError(AppError): ...
  class ValidationError(AppError): ...
  class LLMError(AppError): ...
  class RateLimitError(AppError): ...
  ```
- [ ] Add a global exception handler in `main.py` that catches `AppError` and returns consistent JSON:
  ```json
  {"error": {"code": "IDOL_NOT_FOUND", "message": "...", "details": {}}}
  ```
- [ ] Replace all `HTTPException` calls with appropriate `AppError` subclasses
- [ ] On frontend, create a centralized `ApiErrorHandler` that maps error codes to user-friendly messages

### 1.4 API File Decomposition

**Problem:** Several API files are 600-1000+ lines:
- `idols.py`: 1,028 lines
- `intake.py`: 965 lines  
- `plans.py`: 899 lines
- `chat.py`: 690 lines
- `comparison.py`: 614 lines

These combine request models, response models, service logic, and route handlers in single files.

**Actions:**
- [ ] Split `idols.py` into: `idols_search.py`, `idols_import.py`, `idols_crud.py`, `idols_images.py`
- [ ] Split `intake.py` into: `intake_questions.py`, `intake_answers.py`, `intake_profile.py`
- [ ] Split `plans.py` into: `plans_crud.py`, `plans_items.py`, `plans_generation.py`
- [ ] Extract inline Pydantic models from API files into `schemas/` where missing
- [ ] Move service logic out of API handlers into service classes (some already exist, some are inline)

---

## 🟡 P2 — Medium Priority

### 2.1 Database Migration Discipline

**Problem:** Alembic is configured but it's unclear how consistently migrations are used. Models have changed significantly (see `daily_task_completion.py`, `feed_comment.py`, `feed_post.py` added recently).

**Actions:**
- [ ] Audit all model files vs. migration history
- [ ] Generate a catch-up migration if needed: `alembic revision --autogenerate -m "sync models"`
- [ ] Add `alembic upgrade head` to `start_app.sh` before uvicorn
- [ ] Document migration workflow in backend README

### 2.2 LLM Client Refactoring

**Problem:** `client.py` is 793 lines. The `_repair_json()` function handles JSON repair, retry logic is scattered across service files, and the `DummyLLMClient` pattern makes testing harder than it should be.

**Actions:**
- [ ] Extract `_repair_json()` into its own module: `services/llm/json_repair.py`
- [ ] Create a proper `RetryPolicy` dataclass with configurable `max_retries`, `backoff_ms`, `retry_on`
- [ ] Add structured logging for LLM calls: prompt hash, model, tokens, latency, retry count
- [ ] Add token usage tracking to `GeminiLLMClient` and `OpenAILLMClient`
- [ ] Consider streaming support for chat responses (partial front-end support exists)

### 2.3 Prompt Management

**Problem:** 28 prompt files in `/prompts/` are plain text with `{variable}` interpolation. No versioning, no A/B testing, no cost tracking per prompt. The `PROMPT_CHANGELOG.md` tracks changes manually.

**Actions:**
- [ ] Add prompt metadata headers (version, model, purpose, expected output schema)
- [ ] Create a prompt registry that logs: which prompt, which model, how many tokens, cost, latency
- [ ] Add prompt unit tests: feed fixture inputs, assert output schema compliance
- [ ] Consider a lightweight prompt management system (even just versioned YAML with metadata)

### 2.4 Frontend State Management Audit

**Problem:** 60K lines of Dart code with Riverpod controllers. No clear pattern for loading/error/success states across all features. Some controllers use `if (state is HomeLoading) return` guards (added recently), others may not.

**Actions:**
- [ ] Audit all controllers for consistent state patterns:
  - Loading → Success → Error pattern
  - Request deduplication guards
  - Error recovery (retry) actions
- [ ] Create a shared `AsyncState<T>` sealed class pattern:
  ```dart
  sealed class AsyncState<T> {}
  class AsyncInitial<T> extends AsyncState<T> {}
  class AsyncLoading<T> extends AsyncState<T> {}
  class AsyncSuccess<T> extends AsyncState<T> {}
  class AsyncError<T> extends AsyncState<T> { final String message; ... }
  ```
- [ ] Add pull-to-refresh on all list screens
- [ ] Add empty state widgets (some exist as `empty_state.dart`, verify all screens use them)

### 2.5 CORS Hardening

**Problem:** `main.py` has `allow_origins=["*"]`. In production, this allows any origin to make authenticated API calls.

**Actions:**
- [ ] Set `CORS_ORIGINS` in `.env` / `config.py`
- [ ] Restrict to actual frontend origins (localhost for dev, production domain for prod)
- [ ] Remove `allow_credentials=True` with `allow_origins=["*"]` (these are incompatible per spec anyway)

---

## 🟢 P3 — Feature Completion (From PRD)

### 3.1 Notification Settings UI (P1-04)

**Status:** Backend done. Frontend missing.

**Actions:**
- [ ] Create `NotificationSettingsScreen` in `features/profile/`
- [ ] Fields: enable/disable notifications, preferred time, timezone
- [ ] Save via existing notification service
- [ ] Add navigation from Profile screen

### 3.2 Chat-to-Content Linking (P2-03)

**Status:** Enhanced system prompt done. Actual linking not implemented.

**Actions:**
- [ ] Add `related_content_resource_id` field to `ChatMessage` model
- [ ] When LLM references a book/module in chat, store the link
- [ ] Frontend: render content links as tappable cards in chat messages
- [ ] Navigate to book module reader on tap

### 3.3 Agentic Activation Flow (P3)

**Status:** In progress. Need to reduce onboarding from 8-10 screens to 4-5.

**Actions:**
- [ ] Merge `IdolSuggest` + `IdolConfirm` into single screen with inline confirmation
- [ ] Streamline intake wizard: combine age/interests/goals into single conversational screen
- [ ] Position blueprint as "strategic verdict" (not a second plan)
- [ ] Add progress indicator showing steps remaining (e.g., "Step 2 of 4")
- [ ] A/B test: original flow vs. agentic flow

### 3.4 Content Personalization (P4)

**Status:** Not started.

**Actions:**
- [ ] `GET /feed?week=N` endpoint: prioritize idea cards relevant to user's current plan week
- [ ] Add `relevant_week` field to `IdeaCard` model
- [ ] Frontend: show "Relevant to Week X" badge on idea cards
- [ ] Add `plan_item_id` to `IdeaCard` for cross-linking
- [ ] Home screen: "Based on your Week 3 plan" section

### 3.5 Reflection & Journaling (P5)

**Status:** Not started.

**Actions:**
- [ ] Create `Reflection` model: `id`, `user_id`, `plan_item_id`, `content`, `created_at`
- [ ] `POST /reflections` and `GET /reflections` endpoints
- [ ] Frontend: reflection bottom sheet after task completion
- [ ] Frontend: weekly summary card on home screen
- [ ] Feed reflection prompts from `daily_focus` API

### 3.6 Dark Theme (P6-02)

**Status:** Not started.

**Actions:**
- [ ] Extend `app/theme.dart` with dark color scheme
- [ ] Add `ThemeMode` provider (system/light/dark)
- [ ] Persist preference via `shared_preferences`
- [ ] Test all screens in dark mode (many custom colors need dark variants)
- [ ] Update `design_tokens.dart` with dark token set

---

## 🔵 P4 — Nice to Have / Polish

### 4.1 CI/CD Pipeline

**Problem:** No CI. No automated tests. No deployment pipeline.

**Actions:**
- [ ] GitHub Actions workflow:
  - Lint (ruff for Python, dart analyze for Flutter)
  - Backend tests
  - Frontend tests
  - Build verification (Flutter build, Docker build)
- [ ] Pre-commit hooks for linting
- [ ] Staging deployment on merge to `main`

### 4.2 Logging & Monitoring

**Problem:** Logging exists but is file-based (`uvicorn.log`, `celery.log`). No structured logging, no metrics, no alerting.

**Actions:**
- [ ] Replace `print` and basic `logging` with structured JSON logs
- [ ] Add request ID middleware for tracing
- [ ] Add `/health` endpoint with DB + Redis + Celery connectivity checks
- [ ] Add basic metrics: request count, latency percentiles, error rate by endpoint
- [ ] Consider Sentry for error tracking (free tier covers small apps)

### 4.3 API Documentation

**Problem:** FastAPI auto-generates Swagger docs, but the existing `api_reference.md` (31KB) is manually maintained and likely stale.

**Actions:**
- [ ] Add proper `description`, `response_model`, and `responses` to all route decorators
- [ ] Add `example` fields to all Pydantic schemas
- [ ] Remove manual `api_reference.md` (or generate it from OpenAPI)
- [ ] Add auth examples in Swagger UI

### 4.4 Frontend Build Optimization

**Problem:** Flutter build times for a 60K-line codebase can be slow. No code generation setup (freezed is a dependency but not configured).

**Actions:**
- [ ] Set up `build_runner` + `freezed` for immutable model classes
- [ ] Set up `json_serializable` for model serialization
- [ ] Audit and remove unused dependencies in `pubspec.yaml`
- [ ] Add `flutter analyze` to CI

### 4.5 Database Indexes

**Problem:** No evidence of database indexes beyond primary keys. Common queries (user's plans, idol search, feed items by user) likely do sequential scans.

**Actions:**
- [ ] Add indexes for common query patterns:
  - `plan.user_id`
  - `plan_item.plan_id` + `plan_item.week_start`
  - `chat_message.thread_id` + `chat_message.created_at`
  - `idol_profile.name` (for search)
  - `idea_card.user_id` + `idea_card.created_at`
  - `user_achievement.user_id`
- [ ] Verify with `EXPLAIN ANALYZE` on slow queries
- [ ] Add Alembic migration for new indexes

### 4.6 Celery Task Monitoring

**Problem:** Celery tasks run in background but there's no visibility into failures, queue depth, or processing time.

**Actions:**
- [ ] Add Celery task result backend (currently appears to use default, not persistent)
- [ ] Add `flower` for real-time Celery monitoring (lightweight web UI)
- [ ] Add task-level logging: start time, duration, retry count
- [ ] Alert on task failures (at minimum, log to structured logger)
- [ ] Consider Celery task priorities more carefully (high/default/low already exist but verify usage)

---

## 📊 Priority Matrix

| # | Item | Impact | Effort | Priority |
|---|------|--------|--------|----------|
| 0.1 | Rotate leaked API keys | Critical | 1h | 🔴 Now |
| 0.2 | Change default JWT secret | Critical | 15min | 🔴 Now |
| 0.3 | Rate limiting on LLM endpoints | Critical | 4h | 🔴 Now |
| 1.1 | Backend test coverage | High | 3-5 days | 🟠 Week 1-2 |
| 1.2 | Frontend test coverage | High | 3-5 days | 🟠 Week 2-3 |
| 1.3 | Error handling standardization | High | 2-3 days | 🟠 Week 1 |
| 1.4 | API file decomposition | Medium | 2-3 days | 🟠 Week 2 |
| 2.1 | Database migration discipline | Medium | 4h | 🟡 Week 3 |
| 2.2 | LLM client refactoring | Medium | 2-3 days | 🟡 Week 3-4 |
| 2.3 | Prompt management | Medium | 2-3 days | 🟡 Week 4 |
| 2.4 | Frontend state management audit | Medium | 2-3 days | 🟡 Week 4 |
| 2.5 | CORS hardening | Medium | 30min | 🟡 Now |
| 3.1 | Notification settings UI | Medium | 1 day | 🟢 Week 5 |
| 3.2 | Chat-to-content linking | Medium | 2-3 days | 🟢 Week 5-6 |
| 3.3 | Agentic activation flow | High | 1 week | 🟢 Week 5-6 |
| 3.4 | Content personalization | Medium | 3-4 days | 🟢 Week 7 |
| 3.5 | Reflection & journaling | Medium | 3-4 days | 🟢 Week 8 |
| 3.6 | Dark theme | Medium | 2-3 days | 🟢 Week 8-9 |
| 4.1 | CI/CD pipeline | Medium | 1-2 days | 🔵 Week 10 |
| 4.2 | Logging & monitoring | Medium | 2-3 days | 🔵 Week 10-11 |
| 4.3 | API documentation | Low | 1-2 days | 🔵 Week 11 |
| 4.4 | Frontend build optimization | Low | 1-2 days | 🔵 Week 12 |
| 4.5 | Database indexes | Medium | 4h | 🔵 Week 9 |
| 4.6 | Celery task monitoring | Medium | 1 day | 🔵 Week 10 |

---

## 🏗️ Architecture Notes

### Current Stack
- **Backend:** Python 3.11+, FastAPI, SQLModel/SQLAlchemy, PostgreSQL, Redis, Celery
- **Frontend:** Flutter (Dart), Riverpod, GoRouter
- **LLM:** Gemini (primary) + OpenAI (fallback), with dummy mode for dev
- **Infra:** Docker Compose (Postgres + Redis), local Celery workers

### Key Observations
1. **20+ models** in backend covering: User, Idol, IdolProfile, IdolPersona, IdolTimeline, IdolTag, IdolSource, IdolExternalId, IdolAlias, Plan, PlanItem, PlanJob, SuggestJob, ItemDetailJob, ContentResource, IdeaCard, StashedIdea, FeedPost, FeedLike, FeedComment, ChatMessage, ChatThread, UserAchievement, AchievementEvidence, DailyTaskCompletion, Note, Intake, Session
2. **28 prompt templates** driving all LLM interactions — this is the intellectual core of the app
3. **Celery task queues** (high_priority, default, low_priority) for background LLM generation
4. **Idol ingestion pipeline**: Wikidata → extraction → LLM enrichment → persona/timeline/profile generation
5. **Chat system** with jargon guard, persona enforcement, and grounding in idol facts
6. **Content quality pipeline** with validation + retry for thin content

### Technical Debt
- No migrations in git (or they're not being used properly)
- `start_app.sh` doesn't run migrations before starting
- `.env` with production secrets is tracked in git
- JSON repair function in LLM client suggests frequent LLM output parsing issues
- Frontend has `mock_data.dart` — should be removed before production
- No database indexes beyond primary keys
- No CORS restriction for production
- Several scratch/test scripts in backend root (`test_*.py`, `scratch_*.py`)

---

*This plan is a living document. Update priorities as work progresses. Check off items in task.md as they're completed.*