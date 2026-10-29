# CMPYS — technical guide and operations

Updated: 25 October 2026.

[Business requirements](../README.md) · [Application guide](APP_GUIDE.md)

- [Background generation, research, and cost control](#background-generation-research-and-cost-control)
- [Architecture and source map](#architecture-and-source-map)
- [Development, testing, deployment, and recovery](#development-testing-deployment-and-recovery)
- [API capability inventory](#api-capability-inventory)
- [Third-party image assets](#third-party-image-assets)
- [Launch-screen asset maintenance](#launch-screen-asset-maintenance)
- [Documentation ownership and cleanup](#documentation-ownership-and-cleanup)

## Background generation, research, and cost control

### Interactive work

FastAPI handles request/response and streamed interactions. Celery/Redis handle long-running plan, tutorial, catalog, and curriculum work. Generation jobs expose queued/running/progress/completed/failed states and bounded recovery. Separate queues protect first-use work from slower speculative and catalog jobs.

Tutorial preparation separates shared outlining, private exercise/solution construction, teaching prose, structural validation, and review. Accepted steps and review provenance are checkpointed. Recovery reuses compatible accepted artifacts, retries the failed stage, and limits repairs. Identity/hash checks prevent a checkpoint or review from being reused against different content. Protected learner work must survive retries and capacity adjustment.

### Model/provider routing

The text-provider interface supports multiple adapters. The latest live tutorial verification used direct Z.ai with GLM-5.3/GLM-5.3-Flash. A clean unconfigured source checkout defaults to the dummy provider, so explicit environment configuration is required for live generation. Exact model names, routes, availability, and costs are deployment settings; the old claims that every operation uses one historic provider no longer describe the application.

Routing can use cheaper models for eligible bounded work, quality fallback for failures, and cached/reusable results. Narration uses its own provider configuration. Research/source lookups can use separate services. Provider quota exhaustion, timeouts, invalid structured output, failed reviews, and budget denial are different failure reasons and need different recovery.

### Shared catalog

The catalog scheduler can populate mentor profiles, book guides, and source-backed quotes. It deduplicates candidates, enforces leases and retry/backoff, and publishes only after the relevant quality checks. Optional idle discovery admits work only when configured interactive queues and recent activity allow it. Book and mentor discovery retain source identities; portrait publication includes source/license requirements.

### Reusable curriculum factory

The optional curriculum pipeline performs bounded research, source curation/verification, teaching-technique planning, outline/write/review/repair, and versioned publication. It preserves source/evidence records and independent quality reports. Catalog-first lesson delivery matches a suitable published module and personalizes it to the learner's goals, baseline, constraints, project, previous practice, and relevant mentor evidence. Weak matches or failed composition fall back to bespoke preparation.

These paths are feature-gated. In source, `CURRICULUM_ENABLED` and `LESSON_CATALOG_FIRST_ENABLED` default to false. Their presence is not proof they are enabled in a given deployment. Durable spaced-practice delivery has its own gate; do not describe an automatic spaced-repetition schedule as universally active.

### Usage and budgets

Usage telemetry records model/operation, token use, duration, status, estimated cost, and quality outcomes where available. Background job and dollar caps, in-flight reserves, and bounded retries limit autonomous spending. Unknown provider usage must remain reserved until it can be reconciled. Background/catalog budgets, provider-account balance, and an explicitly authorized QA ceiling are separate controls.

Successful cache reuse avoids repeating accepted work; it does not waive a required review after a material change. No fixed “cost per tutorial” or generation-time promise is guaranteed by the app: content size, retries, reviews, model settings, and provider performance vary. The current documentation cleanup performs no paid generation.

Source: [configuration](../cmpys/backend/app/core/config.py), [Celery configuration](../cmpys/backend/app/core/celery.py), [plan tasks](../cmpys/backend/app/tasks/plans.py), [catalog tasks](../cmpys/backend/app/tasks/catalog.py), [curriculum services](../cmpys/backend/app/services/curriculum), and [job API](../cmpys/backend/app/api/v1/jobs.py).

## Architecture and source map

| Area | Source of behavior |
|---|---|
| Mobile client | [fe/cmpys](../fe/cmpys): Flutter/Dart, Riverpod, GoRouter, Dio |
| Main routes and session-preserving tabs | [router.dart](../fe/cmpys/lib/app/router.dart) and [app shell](../fe/cmpys/lib/core/ui/app_shell.dart) |
| API base URL resolution | [env.dart](../fe/cmpys/lib/app/env.dart) |
| Design system | [design tokens](../fe/cmpys/lib/app/design_tokens.dart) and [shared UI](../fe/cmpys/lib/core/ui) |
| Backend | [cmpys/backend](../cmpys/backend): Python 3.11, FastAPI, SQLAlchemy, PostgreSQL, Alembic |
| API mounting | [API router](../cmpys/backend/app/api/router.py) and [application](../cmpys/backend/app/main.py) |
| Background execution | [tasks](../cmpys/backend/app/tasks), Celery workers, Redis, and Beat |
| Prompt templates | [cmpys/prompts](../cmpys/prompts): runtime inputs, retained as application files |
| Models and schemas | [models](../cmpys/backend/app/models) and [schemas](../cmpys/backend/app/schemas) |
| Database migrations | [migrations](../cmpys/backend/migrations) |
| Production topology | [production Compose](../cmpys/infra/docker-compose.prod.yml) |
| CI/deployment | [deployment workflow](../.github/workflows/deploy.yml) and [release script](../cmpys/infra/deploy.sh) |
| HTTPS lifecycle | [HTTPS scripts and templates](../cmpys/infra/https) |
| Backend validation | [backend tests](../cmpys/backend/tests) |
| Client validation | [Flutter tests](../fe/cmpys/test) and [integration tests](../fe/cmpys/integration_test) |

The API uses JSON and server-sent events for streamed flows. Database entities separate users/sessions, shared mentors/content, plans/progress, practice artifacts, catalog/curriculum jobs, and usage telemetry. Current screens should be traced from the router and their callbacks rather than inferred from every historical/prototype widget still present in the source tree.

## Development, testing, deployment, and recovery

### Local backend

From the repository root:

```sh
cd cmpys/backend
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env
# Configure the database, Redis, signing secret, and intended provider locally.
.venv/bin/alembic upgrade head
.venv/bin/uvicorn app.main:app --port 8000 --reload
```

Use a local PostgreSQL instance with the extensions required by the migrations; CI uses pgvector/PostgreSQL 16. Redis and Celery workers are needed for asynchronous work. The production Compose configuration defines separate `default`, `high_priority`, `low_priority`, `catalog`, `catalog_control`, `curriculum`, and `curriculum_control` queues plus Beat. A representative local worker is:

```sh
cd cmpys/backend
.venv/bin/celery -A app.core.celery.celery_app worker --concurrency=1 -Q default,high_priority,low_priority
```

Choose local worker pools/queue coverage appropriate to the work being tested. Starting Beat or catalog/curriculum workers can admit provider work when their flags and credentials enable it; ordinary documentation validation does not require them.

### Client

```sh
cd fe/cmpys
flutter pub get
flutter run
```

iOS debug/simulator and release builds default to the configured deployed API. Android debug emulator builds use the host alias; web/desktop debug builds use localhost. Use an explicit override for a local backend, including the `/api/v1` prefix:

```sh
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

A physical device needs a reachable host address. API endpoints/flavor are compiled from environment settings; reinstall/rebuild with the intended configuration when switching environments. Never assume a simulator is isolated merely because it runs locally.

### Configuration responsibilities

| Configuration family | Purpose |
|---|---|
| `DATABASE_URL`, `REDIS_URL`, signing/security settings | Database, queue, and authentication infrastructure |
| `LLM_PROVIDER`, provider model/key/secret settings | Text generation and fallback routing |
| `ZAI_FAST_MODEL`, `ZAI_MODEL`, `ZAI_QUALITY_MODEL` | Z.ai model roles when that provider is selected |
| `TAVILY_API_KEY` and research settings | Optional external source research |
| `BOOK_NARRATION_PROVIDER`, Gemini/other narration settings | Speech generation, voice, and model selection |
| Catalog scheduler/discovery/job limits | Admission and retries for shared background content |
| Curriculum enablement, catalog-first, and spacing flags | Optional reusable curriculum and delivery paths |
| Usage telemetry and budget settings | Token/cost tracking, routing evaluation, and spend controls |
| Password-recovery/email settings | Recovery availability and delivery |

The exact keys, defaults, and validation live in [config.py](../cmpys/backend/app/core/config.py) and [.env.example](../cmpys/backend/.env.example). Do not copy secrets, tokens, personal test-account credentials, or deployment environment files into this guide.

### Tests

```sh
cd cmpys/backend
.venv/bin/python -m pytest -q
```

```sh
cd fe/cmpys
flutter analyze
flutter test
```

Use targeted tests for changed behavior and the configured database for integration checks. Live-provider tests are separate from ordinary offline/unit tests and consume quota/budget. For documentation-only changes, verify local links, API/source coverage, removed-file references, and unchanged application source; paid generation and a full simulator rerun are unnecessary.

### Release and rollback

The GitHub deployment workflow tests against a migrated database, builds an ARM64 image, pushes a commit-tagged artifact, and invokes the release script. Deployment is triggered by configured backend/infrastructure/prompt/workflow paths on `main`, or manual dispatch. Deleting Markdown under those paths can still match the workflow's path filters if pushed; this cleanup does not itself push or deploy.

The release script serializes deployment on the host, retains rollback state, runs migrations and readiness/worker checks, and only promotes a successful release. Verify the running image revision, database/Redis readiness, and queue workers after a release. An image rollback does not automatically undo a database migration; use the release's migration and backup plan.

Health endpoints, the API root, generated OpenAPI schema, and the diagnostics endpoints support operational inspection. Diagnostics expose status/model and prompt filenames/registry rather than credentials. Runtime settings and server logs are the source for a deployment's current state.

### HTTPS maintenance

The scripts in `cmpys/infra/https` manage IP-based HTTPS, nginx templates, HTTP-01 validation, and automated short-lived-certificate renewal. `setup.sh prepare PUBLIC_IPV4` prepares configuration and backups. Certificate issuance via `setup.sh enable PUBLIC_IPV4 --accept-subscriber-agreement` requires authorization for the CA's subscriber agreement; preparation alone does not accept it.

The renewal service/timer validates configuration before nginx reload, preserves certificate/account state, and reports renewal or near-expiry failures. Check the timer/service, its journal, an external trusted-HTTPS `/ready` request, and a renewal dry run. Restore a reviewed nginx backup only after configuration validation. Preserve the challenge endpoint required for renewal. Auth request limits and proxy streaming behavior are specified in the nginx templates; changing them is an operational change, not a documentation cleanup.

## API capability inventory

Paths below are relative to `/api/v1`. They are extracted from the mounted v1 router source as of this document's update. The running service's `/openapi.json` is the field-level reference for request/response schemas. Private-resource routes require the applicable authentication and ownership checks. The table includes backend-only and legacy capabilities so their existence is not confused with a current mobile screen.

### Achievements API

| Method | Path | Capability |
|---|---|---|
| POST | `/achievements` | Create a new user achievement. |
| GET | `/achievements` | List user achievements with optional filters. |
| GET | `/achievements/{achievement_id}` | Get a specific achievement. |
| PATCH | `/achievements/{achievement_id}` | Update an achievement. |
| DELETE | `/achievements/{achievement_id}` | Delete an achievement. |

### Auth API

| Method | Path | Capability |
|---|---|---|
| POST | `/auth/register` | Register a new user. |
| POST | `/auth/login` | Login with email and password. |
| POST | `/auth/refresh` | Refresh access token. |
| GET | `/auth/password-reset/availability` | Check whether email password recovery is configured. |
| POST | `/auth/password-reset/request` | Request a password-recovery email/code. |
| POST | `/auth/password-reset/confirm` | Validate the recovery code and set the new password. |

### Comparison API

| Method | Path | Capability |
|---|---|---|
| GET | `/comparison` | Compare user achievements to idol milestones. |
| GET | `/comparison/ai` | AI-enhanced comparison between user achievements and idol milestones. |

### Content Resources API

| Method | Path | Capability |
|---|---|---|
| GET | `/content-resources` | List reusable resources, optionally filtered by kind/search. |
| GET | `/content-resources/vault` | List the current user's saved books, videos, articles, and lessons. |
| GET | `/content-resources/library` | List all content resources available to the user. |
| GET | `/content-resources/continue-reading` | Get the most recent in-progress content resource for the current user. |
| GET | `/content-resources/original-source` | Resolve a verified public-domain original independently of AI guides. |
| GET | `/content-resources/reading-source` | Verified originals or explicitly labelled author-published excerpts. |
| GET | `/content-resources/resolve` | Late-bind a deferred material once its quality-gated module is ready. |
| GET | `/content-resources/{resource_id}` | Get a shared resource and this user's save/progress state. |
| POST | `/content-resources/{resource_id}/narration` | Prepare expressive AI narration for a passage in this book. |
| POST | `/content-resources/{resource_id}/save` | Save a shared resource into the current user's Vault. |
| DELETE | `/content-resources/{resource_id}/save` | Remove a shared resource from the current user's Vault. |
| PATCH | `/content-resources/{resource_id}/progress` | Update user-specific reading/watch progress for a shared resource. |
| GET | `/content-resources/{resource_id}/highlights` | List this user's highlights/notes for a shared resource. |
| POST | `/content-resources/{resource_id}/highlights` | Create a user-specific highlight or note on a shared resource. |
| DELETE | `/content-resources/{resource_id}/highlights/{highlight_id}` | Delete one of the current user's notes/highlights for a shared resource. |

### Daily Tasks API

| Method | Path | Capability |
|---|---|---|
| POST | `/plan-items/{item_id}/daily-toggle` | Toggle today's completion for a habit/practice plan item. |
| GET | `/plans/{plan_id}/today` | Get today's view of all habit/practice items for the current plan week. |
| GET | `/plan-items/{item_id}/daily-status` | Get the 7-day dot grid (Mon-Sun) for a habit/practice item. |
| GET | `/streak` | Get the user's current and longest daily streak. |
| GET | `/daily-focus` | Get today's primary focus item, a reflection prompt, and current streak. |

### Debug API

| Method | Path | Capability |
|---|---|---|
| GET | `/debug/llm` | Get LLM configuration status. |
| GET | `/debug/prompts` | List available/loaded prompt filenames and the operation registry. |

### Feed API

| Method | Path | Capability |
|---|---|---|
| GET | `/feed` | Discover feed — mix of DB posts + fresh AI posts. |
| GET | `/feed/quality-stats` | Expose catalog quality and grounded-call usage for budget monitoring. |
| POST | `/feed/{post_id}/like` | Toggle like on a feed post. Returns new like state and count. |
| GET | `/feed/{post_id}/comments` | Get all comments for a feed post. |
| POST | `/feed/{post_id}/comments` | Add a comment to a feed post. |

### Idols API

| Method | Path | Capability |
|---|---|---|
| GET | `/idols/search` | Search idols by name or alias. |
| GET | `/idols/suggest-legacy` | Legacy suggest endpoint - simple tag-based suggestions from local DB only. |
| GET | `/idols/discover` | Discover idols by name from Wikidata. |
| POST | `/idols/import` | Import an idol from an external provider. |
| GET | `/idols/my` | Return profiles for idols the current user has imported or selected. |
| POST | `/idols/{idol_id}/select` | Validate that an idol can be selected by the current user. |
| GET | `/idols/{idol_id}` | Get detailed information about an idol. |
| GET | `/idols/{idol_id}/profile` | Get the extracted profile for an idol. |
| GET | `/idols/{idol_id}/timeline` | Get the timeline of events for an idol. |
| GET | `/idols/{idol_id}/persona` | Get the chat persona for an idol. |
| POST | `/idols/{idol_id}/generate-image` | Resolve/cache a sourced portrait, with generated-art fallback where allowed. |

### Jobs API

| Method | Path | Capability |
|---|---|---|
| GET | `/jobs/{job_id}` | Read generation/import job state, progress, and available result information. |
| POST | `/jobs/{job_id}/start` | Manually trigger a queued job to start. |

### Me API

| Method | Path | Capability |
|---|---|---|
| GET | `/me` | Get current user information. |
| PATCH | `/me` | Update current user profile. |

### Notes API

| Method | Path | Capability |
|---|---|---|
| POST | `/notes` | Create a new note. |
| GET | `/notes` | List user notes with optional search. |
| GET | `/notes/{note_id}` | Get a specific note. |
| PATCH | `/notes/{note_id}` | Update a note. |
| DELETE | `/notes/{note_id}` | Delete a note. |

### Plans API

| Method | Path | Capability |
|---|---|---|
| POST | `/plans/generate` | Trigger asynchronous plan generation. |
| GET | `/plans/current` | Read the learner’s current plan and its progress. |
| POST | `/plans/{plan_id}/items` | Manually add an item to a plan. |
| GET | `/plan-items/{plan_item_id}` | Get a specific plan item. |
| PATCH | `/plan-items/{plan_item_id}` | Update a plan item's notes. |
| PUT | `/plan-items/{item_id}/reflection` | Save the learner’s daily reflection. |
| GET | `/plan-items/{item_id}/detailed` | Get a plan item with details, steps, materials, and progress. |
| POST | `/plan-items/{item_id}/toggle-complete` | Toggle completion status for a plan item. |
| POST | `/plan-items/{item_id}/steps/{step_id}/toggle` | Toggle completion status for a specific step. |
| POST | `/plan-items/{item_id}/regenerate-details` | Trigger async regeneration of item details (steps + materials) via LLM. |
| POST | `/plan-items/{item_id}/achievement-suggestion` | Suggest an editable achievement title for a completed item. |
| GET | `/plans/{plan_id}/weeks/{week}/summary` | Get summary of progress for a specific week. |
| POST | `/plans/{plan_id}/generate-next` | Start the next plan cycle. |
| POST | `/plans/{plan_id}/cycle-summary` | Generate or retrieve a plan-cycle narrative and capstone summary. |

### Practice API

| Method | Path | Capability |
|---|---|---|
| GET | `/plan-items/{item_id}/steps/{step_id}/practice` | Read the current workbook, saved work, and assessment state. |
| POST | `/plan-items/{item_id}/steps/{step_id}/practice/prepare` | Prepare the workbook for the selected tutorial. |
| PUT | `/plan-items/{item_id}/steps/{step_id}/practice/draft` | Save answers with revision/conflict checks. |
| POST | `/plan-items/{item_id}/steps/{step_id}/practice/hint` | Request permitted help for the active practice activity. |
| POST | `/plan-items/{item_id}/steps/{step_id}/practice/submit` | Submit answers for assessment and persist the attempt. |

### Sessions API

| Method | Path | Capability |
|---|---|---|
| POST | `/sessions` | Create a new agentic session with intake data. |
| POST | `/sessions/{session_id}/abandon` | Abandon an in-progress session so the user can start a fresh one. |
| POST | `/sessions/{session_id}/suggest-idols` | Generate 3 idol suggestions based on intake data. |
| POST | `/sessions/{session_id}/select-idol` | Select an idol for the session. |
| GET | `/sessions/current` | Get the user's most recent non-completed session, if any. |
| GET | `/sessions/latest` | Return the user's newest session, including completed onboarding. |
| GET | `/sessions/{session_id}` | Get the current state of a session. |
| POST | `/sessions/{session_id}/comparison-scores/retry` | Explicitly retry a terminal structured-comparison failure. |
| POST | `/sessions/{session_id}/interview` | Send a message during the interview phase (SSE stream). |
| POST | `/sessions/{session_id}/generate-results` | Run the automatic post-interview strategy pipeline (SSE stream). |
| POST | `/sessions/{session_id}/learning-materials` | Fetch curated learning materials for a specific blueprint topic. |
| GET | `/sessions/{session_id}/guided-learning/messages` | Read the saved mentor-chat conversation. |
| POST | `/sessions/{session_id}/guided-learning` | Stream a mentor tutoring response for the session. |
| GET | `/sessions/{session_id}/feed` | Generate a daily feed of bite-sized insights (Idea Cards) from the idol. |

### Tools API

| Method | Path | Capability |
|---|---|---|
| GET | `/tools/news` | Fetch a bounded news feed without blocking other API requests. |


Additional application routes include the `/api/v1/` welcome endpoint, `/health`, `/ready`, `/media/{filename}`, generated API documentation, and `/openapi.json`. Media serving uses the application's configured media storage. Job progress/thinking information is exposed through job/session responses; helper functions in source are not automatically separate public endpoints.

## Third-party image assets

### Mentor Lab voices

- `fe/cmpys/assets/images/voices/isaac_newton.jpg` — Godfrey Kneller, *Portrait of
  Isaac Newton (1642–1727)*, 1689, head-shot crop. Wikimedia Commons,
  public-domain artwork and reproduction:
  <https://commons.wikimedia.org/wiki/File:Portrait_of_Sir_Isaac_Newton,_1689_(head_shot_crop).jpg>
- `fe/cmpys/assets/images/voices/seneca.jpg` — Peter Paul Rubens, *Bust-length portrait
  of Seneca*. Wikimedia Commons, public-domain artwork and CC0 digital
  reproduction:
  <https://commons.wikimedia.org/wiki/File:Peter_Paul_Rubens_-_Brustbild_des_Philosophen_Seneca_-_178_-_Staatliche_Kunsthalle_Karlsruhe.jpg>
- `fe/cmpys/assets/images/voices/warren_buffett.jpg` — Warren Buffett at the 2015
  SelectUSA Investment Summit, USA International Trade Administration.
  Wikimedia Commons, United States federal-government public domain:
  <https://commons.wikimedia.org/wiki/File:Warren_Buffett_at_the_2015_SelectUSA_Investment_Summit_(cropped).jpg>

The Mentor Lab quotation sources are shown on their cards. Seneca uses Richard
M. Gummere's 1917 public-domain translation of *Moral Letters to Lucilius*,
Letter 11. Newton is quoted from his 5 February 1676 letter to Robert Hooke,
with the original spelling of “sholders” modernized to “shoulders.” Buffett is
quoted from Columbia Business School's 2015 *Fast Forward: Warren Buffett ’51*.

## Launch-screen asset maintenance

Customize the iOS launch-screen images in `fe/cmpys/ios/Runner/Assets.xcassets/LaunchImage.imageset/`. From `fe/cmpys`, open `ios/Runner.xcworkspace` in Xcode and edit `Runner/Assets.xcassets`, or replace the intended image files directly. Retain the asset catalog's required image names and metadata. This incorporates the former asset-directory README.

## Documentation ownership and cleanup

The maintained application documentation is exactly these three files:

- [README.md](../README.md): purpose, business needs, scope, priorities, and acceptance criteria.
- [APP_GUIDE.md](APP_GUIDE.md): user journeys, feature behavior, availability, and known gaps.
- [TECHNICAL_GUIDE.md](TECHNICAL_GUIDE.md): implementation, source map, APIs, operations, and attribution.

Update the relevant file when behavior changes. Proposed behavior must remain labeled as a requirement until implemented and verified. API schemas and source code determine the executable contract.

The previous standalone application narratives were consolidated and backed up outside the repository. Historical machine-readable reports, generated research/pilot evidence, one-off release scripts, screenshots, and council-cache records remain supporting artifacts; they are not current feature specifications. Active application tests, runtime prompts, deployment scripts, build configuration, attribution files, and operational agent instructions/preferences also remain in place. A proposed separate cleanup of these artifacts requires approval because some paths are referenced by test tooling.
