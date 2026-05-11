<!--
## Sync Impact Report
- **Version change**: 0.0.0 → 1.0.0
- **Modified principles**: N/A (initial creation)
- **Added sections**:
  - I. PostgreSQL Is Truth
  - II. Async-by-Default Processing
  - III. Historical Purity (NON-NEGOTIABLE)
  - IV. Full-Stack Serialization Contract
  - V. LLM Isolation
  - VI. Test-First for Contracts
  - VII. Simplicity & YAGNI
  - Technology & Infrastructure Constraints
  - Development Workflow
- **Removed sections**: None
- **Templates requiring updates**:
  - `.specify/templates/plan-template.md` ✅ aligned (Constitution Check section present)
  - `.specify/templates/spec-template.md` ✅ aligned (priority-based stories, acceptance scenarios)
  - `.specify/templates/tasks-template.md` ✅ aligned (phase-based, user-story-driven)
- **Follow-up TODOs**: None
-->

# CMPYS Constitution

## Core Principles

### I. PostgreSQL Is Truth

PostgreSQL is the single source of truth for all application state. Every business
entity MUST be stored in and read from PostgreSQL. Redis is used ONLY as a Celery
broker and for ephemeral caching — it MUST NOT hold canonical data. Frontend state
is always derived from API responses backed by the database.

**Rationale**: A single source of truth eliminates data consistency bugs between
stores and simplifies debugging, migration, and backup strategies.

### II. Async-by-Default Processing

Any operation that calls an external API (Wikidata, LLM, Tavily, Gemini) or
performs CPU-heavy extraction MUST execute in a Celery background task. The API
endpoint MUST return immediately with a job/status object. Frontend MUST poll
or subscribe for completion.

**Pattern**:
- `POST` returns resource with `is_ready: false` or a job ID.
- Background worker processes, then sets `is_ready: true` in PostgreSQL.
- Frontend polls `GET` every 3 seconds until ready.

**Rationale**: External API calls have unpredictable latency. Blocking the HTTP
request thread degrades UX and risks gateway timeouts.

### III. Historical Purity (NON-NEGOTIABLE)

All LLM-generated content representing historical figures (idol chat personas,
timeline narration, comparison text) MUST be free of modern startup jargon.
Banned terms include but are not limited to: "synergy", "deep dive", "Q3",
"leverage", "disrupt", "pivot", "scale", "align", "circle back".

Every prompt in `/prompts/` that generates idol-facing text MUST include an
explicit jargon-ban instruction. The `test_jargon_guard` test suite MUST pass
before any prompt change is merged.

**Rationale**: The product's credibility depends on historically authentic voice.
Modern business vocabulary breaks immersion and cheapens the user experience.

### IV. Full-Stack Serialization Contract

- Python (backend, DB, API output): `snake_case`.
- Flutter (frontend internal logic): `camelCase`.
- Flutter models MUST use `@JsonKey(name: 'snake_case_field')` for every field
  whose Dart name differs from the API response.

**Rule**: When a backend model or schema field is added, renamed, or removed,
the corresponding Flutter model MUST be updated in the same logical change.
When a Flutter model field is added, the backend endpoint MUST already serve
that field.

**Rationale**: Mismatched serialization is the #1 source of silent runtime bugs
in cross-platform projects.

### V. LLM Isolation

All LLM interactions MUST go through the `app/services/llm/` abstraction layer.
No API route or model file may import `openai`, `google.generativeai`, or any
provider SDK directly. Prompt templates MUST live in `/prompts/*.txt` — never
hardcoded inline.

The application MUST function in `dummy` LLM mode (no API keys) for all
non-LLM-dependent features. Endpoints requiring LLM MUST return HTTP 503 with
a clear error message when LLM is not configured.

**Rationale**: Provider independence allows swapping LLMs without touching
business logic. Dummy mode enables local development without API costs.

### VI. Test-First for Contracts

Every LLM prompt template MUST have a corresponding test in `tests/` that
validates placeholder substitution and output structure. Tests MUST:
- Verify all `{placeholders}` in prompt templates resolve without error.
- Assert that jargon-guard rules pass on sample outputs.
- Validate plan completion logic and edge cases.

Integration tests for Wikidata/Wikipedia MUST use mocked responses (fixtures in
`fixtures/`) — never call live external APIs in CI.

**Rationale**: Prompt regressions are silent and expensive. Automated checks
catch template breakage before it reaches users.

### VII. Simplicity & YAGNI

Start with the simplest viable implementation. Do not add abstraction layers,
caching strategies, or features "for the future". Every line of code MUST serve
a current requirement.

- No placeholder `pass` implementations unless explicitly requested.
- No speculative database columns or API fields.
- Prefer flat module structures over deep nesting.

**Rationale**: Premature complexity is the enemy of shipping. CMPYS is a
fast-moving product; unused abstractions become maintenance debt.

## Technology & Infrastructure Constraints

| Layer           | Technology                                      |
|-----------------|-------------------------------------------------|
| **Backend**     | Python 3.11+, FastAPI, SQLAlchemy 2.x (async), Pydantic v2 |
| **Database**    | PostgreSQL 16 (Docker), Alembic migrations      |
| **Task Queue**  | Celery + Redis 7 (broker only)                  |
| **Auth**        | bcrypt password hashing, PyJWT (HS256)          |
| **LLM**        | OpenAI GPT-4.1-mini (primary), GPT-4o-mini (fast), Google Gemini (grounding) |
| **Search**      | Tavily (real-time web search for materials)     |
| **Frontend**    | Flutter (latest stable), Riverpod, Dio, GoRouter |
| **Infra**       | Docker Compose (local dev), `uvicorn` (server)  |

- All models use UUID primary keys (`UUIDMixin`), timestamp tracking
  (`TimestampMixin` / `TimestampUpdateMixin`).
- Configuration via `pydantic-settings` with `.env` file support.
- CORS is fully open in development (`allow_origins=["*"]`). Production
  deployments MUST restrict origins.

## Development Workflow

1. **Schema changes**: Modify SQLAlchemy model → `alembic revision --autogenerate`
   → `alembic upgrade head` → update Pydantic schema → update Flutter model.
2. **Prompt changes**: Edit `/prompts/*.txt` → run `pytest tests/` →
   verify `test_prompt_placeholders` and `test_jargon_guard` pass.
3. **New endpoints**: Add route in `app/api/v1/` → add schema in `app/schemas/`
   → update `README.md` endpoint table → update Flutter API client.
4. **Background tasks**: Add task in `app/tasks/` → register with Celery →
   add polling endpoint → add frontend polling logic.

All changes MUST pass existing tests before merge. No silent test skipping.

## Governance

This constitution supersedes all ad-hoc practices. Any principle amendment
requires:
1. A written justification documenting what changed and why.
2. An updated version number following semantic versioning.
3. A review of all dependent templates (plan, spec, tasks) for alignment.

All code reviews MUST verify compliance with these principles. Complexity
beyond what is documented here MUST be explicitly justified with a rationale
in the PR description.

Use the project's `MEMORY` rules (`architecture.md`, `cmpys.md`) as runtime
development guidance — they complement but do not override this constitution.

**Version**: 1.0.0 | **Ratified**: 2026-02-20 | **Last Amended**: 2026-02-20
