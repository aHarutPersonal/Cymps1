# CMPYS Implementation Changelog

**Last Updated:** 2026-07-14

---

## 2026-07-14: Deferred Book Guide Completion & Request Control

- Fixed deferred book guides and prefetched lesson artifacts failing inside Celery with `Timeout context manager should be used inside a task`; all catalog entry points now reuse the worker-local event loop, and the shared Gemini client is recreated if the active loop changes.
- Preserved the warm connection pool on stable workers while preventing an async HTTP session from leaking across event loops.
- Made failed catalog work schedule its own bounded retry in addition to the durable Beat recovery path, and added Celery Beat to the local launcher so development matches production retry behavior.
- Replaced repeatable “Check guide” requests with a shared, cached, single-flight resolver and sparse bounded polling across both the mission page and lesson reader; the action is disabled as “Preparing…” while one check is active.
- Live recovery of the reported material rejected a thin 2,080-word first draft, completed the quality fallback, and published a 3,480-word guide with the full quality report passing.
- Verification: all 398 backend tests and all 138 Flutter tests passed, together with Ruff, Python compilation, Flutter analysis, shell validation, diff validation, and a release web build.

---

## 2026-07-13: Mentor Selection & Interview Retry Recovery

- Fixed mentor selection crashing when legacy ingestion left multiple catalog rows with the same name; selection now resolves all matches deterministically and prefers the published Wikidata-backed identity.
- Deduplicated cached, catalog, and generated mentor suggestions, and preserved Wikidata identity from the suggestion card through the Flutter selection request.
- Changed onboarding Retry to repeat failed mentor setup before sending the interview kickoff, preventing the invalid `idol_selection` → interview request that returned HTTP 409.
- Made interview retries reuse unanswered learner turns, replay an already-persisted opening question without another model call, and resume a durable pending answer after screen reconstruction.
- Rejected empty interview output and replaced raw provider diagnostics with a safe terminal error while retaining immediate, proxy-safe SSE behavior.
- Live-data verification found both duplicate Elon Musk rows, selected the canonical Wikidata identity, and confirmed the failed session remained cleanly in `idol_selection` with no partial mentor or thread linkage. The recovered session's real kickoff completed in 7.0 seconds; retry replay returned in 18 ms with zero duplicate messages. All 395 backend tests and 135 Flutter tests passed, along with Ruff, Python compilation, Flutter analysis, diff validation, and a release web build.

---

## 2026-07-13: Mentor Chat First-Turn & Streaming Reliability

- Fixed first-message chat failure caused by asynchronously lazy-loading a newly created thread's empty message relationship; thread creation, session linkage, and the learner turn now commit atomically before streaming.
- Made manual retry reuse the unanswered learner turn instead of duplicating it, and excluded abandoned unanswered turns from later mentor context.
- Established the SSE connection immediately, disabled proxy buffering, gave the client a safe timeout margin, and treated `done` as terminal without waiting for a clean socket close.
- Rejected empty and explicitly truncated model replies, kept partial replies out of storage, returned safe user-facing errors, and removed hidden client reposts that could duplicate messages and model cost.
- Added bounded recent conversation history plus the learner goal and blueprint excerpt to the mentor prompt, with a 1,200-token concise-response ceiling and first-text/finish telemetry.
- Live provider verification: first text arrived in 1.7 seconds and the complete 354-character response finished in 1.8 seconds. All 382 backend tests and 134 Flutter tests passed, along with Ruff, Python compilation, Flutter analysis, diff validation, and a release web build.

---

## 2026-07-13: Plan Lesson Generation Reliability

- Fixed contradictory lesson-writer guidance whose section ranges could exceed the artifact ceiling and whose own examples violated the substep and duration rules.
- Kept the 1,200-1,800-word quality floor, while targeting 1,400-1,600 words to give the model a safe counting margin.
- Changed semantic validation to report every defect in one pass and repair only invalid lessons concurrently, preserving already-valid lessons and materials instead of regenerating the complete artifact.
- Added a small substep-only repair path for an otherwise complete lesson, plus a quality-tier escalation for a lesson that still fails deterministic checks.
- Accepted only a narrow 601-650-word overrun for in-app readings while retaining the 400-600-word prompt target; materially short or long content still fails validation.
- Added explicit repair/material progress states and provider finish-reason logging so terminal failures are diagnosable instead of appearing as unexplained generation failures.
- Verification: a real failed local mission regenerated and persisted in 46.3 seconds with three 1,409-1,480-word lessons, compliant substeps, and three materials. All 373 backend tests and 131 Flutter tests passed, along with Ruff, Python compilation, Flutter analysis, diff validation, and a release web build.

---

## 2026-07-13: Comparison Completion Contract Repair

- Fixed the session response schema so FastAPI no longer strips already-generated `comparisonScores`; the Compare screen now receives the five dimensions and milestones persisted during Mentor Lab.
- Added response-model serialization coverage at the actual Pydantic filtering boundary, plus client compatibility coverage for both camel-case and snake-case score payloads.
- Made Compare polling immediate, cancellable, and bounded with explicit unavailable, timeout, and retry states instead of an indefinite spinner.
- Prevented taps from restarting active polling and persisted generated scores locally for instant cold-start rendering.
- Added a store hydration barrier so a delayed preferences read cannot overwrite fresher backend session data.
- Verification: all 347 backend tests and all 128 Flutter tests passed, along with Flutter analysis and the response-model wire-contract check.

---

## 2026-07-13: Plan Detail Loading Hardening

- Fixed the simulator launcher so its local API and Celery worker are the services Flutter actually uses; debug iOS/desktop now defaults to localhost, while `API_BASE_URL` remains an explicit override.
- Added startup migration/API/worker readiness checks so Flutter is not launched against unavailable or outdated local services.
- Completed legacy missions now return a terminal completed detail state and never spend tokens or remain on a contradictory “Done” + “Writing your lesson” screen.
- Replaced repeated full-detail downloads with typed lightweight detail-job polling, live stage/percentage feedback, adaptive backoff, and a bounded foreground wait that lets the user leave while generation continues.
- Promoted an opened prefetched lesson to the user-facing queue, while atomically claiming jobs so low/high-priority copies cannot both generate the same expensive artifact.
- Added a detail-job heartbeat migration, queue/running lease windows aligned with worker limits, a soft timeout, pre-prompt failure persistence, and terminal broker-publication failures.
- Moved comparison-score backfill polling out of the global Today/Plan shell and into Compare, eliminating the unrelated `/sessions/latest` loop visible beside plan-detail polling.
- Verification: all 346 backend tests (including the live local migration integration test) and all 123 Flutter tests passed, along with Ruff, Python compilation, Flutter analysis, shell validation, migration-head validation, diff validation, and a release web build.

---

## 2026-07-13: Automatic Post-Interview Mentor Lab

- Replaced the separate comparison reveal and blueprint waiting screens with one automatic Mentor Lab transition immediately after the final interview answer.
- Staged the plan job as soon as result generation begins, then dispatched it only after comparison and blueprint were persisted so faster UX does not weaken personalization.
- Made result generation idempotent across comparison, blueprint, and completed phases: retries reuse finished artifacts, completed sessions replay safely, and failed plan work gets a fresh job without repeating successful LLM calls.
- Added six swipeable product-benefit cards covering interview personalization, mentor evidence, sequential focus, deep lessons, daily rhythm, and observable progress, with live generation status and progress.
- Entry to the app is enabled only after the real persisted twelve-week plan, comparison, and blueprint are all ready; there is no fixed-delay readiness state.
- Added regression coverage for staged/one-time plan dispatch, completed-session replay, blueprint-only retry, automatic UI startup, card swiping, and real plan readiness.
- Verification: 340 database-independent backend tests and 119 Flutter tests passed, along with Ruff, Python compilation, Flutter analysis, diff validation, and a release-mode web build. The existing migration integration test still requires a running local PostgreSQL instance; this feature adds no migration.

---

## 2026-07-13: Plan Detail, Daily Rhythm & Week Progression Repair

- Stopped infinite plan-item polling: failed or stale lesson jobs now become a visible terminal state with an explicit, idempotent retry instead of being silently requeued forever.
- Made habit/practice details instant and daily-aware; daily rhythms no longer trigger long-form lesson generation or become permanently completed plan items.
- Classified both `habit` and `practice` as daily rhythms throughout Flutter and excluded them from mission-detail pre-generation.
- Changed Today/Daily Focus from calendar-age weeks to the first week with unfinished mission work, matching sequential plan progression.
- Hydrated `/plans/current` from authoritative completion records and synchronized item status/progress on item and lesson completion, so finishing Week 1 unlocks Week 2 immediately.
- Tightened the mission lesson availability gate to require all three complete 1,200+ word lessons.
- Verification: 335 database-independent backend tests, 117 Flutter tests, Ruff, Python compilation, Flutter analysis, diff validation, and a release-mode web build passed. The database migration integration test could not run because local PostgreSQL was unavailable; this change adds no migration.

---

## 2026-07-12: Prompt Alignment & End-to-End Performance

- Separated the strategic blueprint from the executable twelve-week plan and added runtime enforcement for ordered weeks, capacity-based task counts, daily scripts, success metrics, and hour caps.
- Reworked persona/interview/tutor prompts around a truthful, source-grounded AI portrayal; aligned persona, comparison, partial-date, and lesson-detail schemas with runtime models.
- Reduced a standard five-turn activation flow from eight grounded model responses to two while keeping the fact lookup and age-matched comparison grounded.
- Removed decorative model calls, compacted prompt JSON, added native structured output, deferred book-module generation with reader late binding, and validated direct video relevance before accepting the fast path.
- Released database connections before long model/search work, reduced scalar relationship queries, narrowed job polling to one joined query, suppressed successful poll logs, and moved request/media blocking work off the asyncio loop.
- Coalesced streamed UI updates, narrowed Riverpod watches, parallelized independent plan startup requests, shortened returning-launch splash time, and made release networking/logging safe.
- Verification: 327 backend tests, 113 Flutter tests, Ruff, Flutter analysis, and a release-mode web build passed.
- Full evidence and caveats: `business/prompt_performance_audit_2026-07-12.md`.

---

## 2026-07-11: Focused Lesson Reader & Honest Duration

- Expanded every generated lesson to 1,200-1,800 words with a required framework, example, failure modes, guided practice, knowledge check, and exact references.
- Derived lesson duration from reading time plus 30-45 minutes of timed practice, constrained to a 40-60 minute session.
- Added a dedicated full-screen lesson reader with section paging, selectable text, contents, type/theme controls, and relevant book/material links.
- Added one-at-a-time lesson focus: completed lessons stay reviewable, the earliest incomplete lesson is current, and later lessons remain locked in both UI and API.
- Existing short lessons regenerate automatically when opened.

---

## 2026-05-13: Content Depth & Quality Fixes (P0-A through P0-E)

### P0-A: Book Module Prompt Rewrite
**File:** `/prompts/book_module_generate.txt`

Changes:
- Added minimum word count requirement: `content_markdown` must be 3,200-4,500 words
- Section summaries must be 80-150 words (was: no requirement)
- Section exercises must be 40-80 words (was: "A short action")
- Idea card content must be 40-80 words with specific example + actionable takeaway
- `content_markdown` must include: opening hook, ## headings, ### exercise subheadings, **bold** key terms, concrete examples per section, closing synthesis paragraph
- Added quality rule: "Every claim must reference a specific event, quote, or decision from {author}'s life"
- Added word count verification instruction at end

### P0-B: Plan Item Details Prompt Rewrite
**File:** `/prompts/plan_item_details.txt`

Changes:
- `lesson_content` minimum: 500-1,200 words per step (was: 200-400 words)
- Structured lesson format: opening context, core concept explanation (3-5 paragraphs), real-world example from idol's life, practice guide (3-5 numbered steps), reflection prompt
- `content_markdown` for materials: 600-1,000 words (was: 200-400 words)
- `substeps` must be 20-50 words each (was: bare strings)
- Added anti-vague-instruction rule: "'practice regularly' is forbidden"
- Steps claiming 60+ minutes must have 800+ word `lesson_content`
- Added anti-filler-language rule
- Idea cards must be 40-80 words with specific examples

### P0-C: Plan Generator Prompt + Schema Fixes
**Files:** `/prompts/plan_generate.txt`, `/backend/app/services/llm/schemas.py`, `/backend/app/services/planning/generator.py`, `/backend/app/schemas/plan.py`

Changes:
- **Prompt:** Added Rule #12 "SUBSTANCE MINIMUMS": mission descriptions >= 50 words, daily rhythm descriptions >= 30 words, `primary_mission` >= 30 words referencing specific skill/deliverable/outcome
- **Prompt:** Changed `daily_instructions` from "2-3 sentences" to "3-5 sentences (40-80 words) with specific, measurable action"
- **Pydantic `BinaryTask`:** Added `estimated_hours: float` (default 1.0, range 0.1-40.0) and `daily_instructions: str | None` (max 2000 chars)
- **Pydantic `PlanItemCreate`:** Changed `description` min_length from 1 to 10, added `dailyInstructions: str | None`
- **generator.py:** Uses LLM-provided `estimated_hours` instead of computing from weekly hours, stores `daily_instructions` in `meta_json`

### P0-D: Backend Content Quality Validation
**Files:** `/backend/app/tasks/ingestion.py`, `/backend/app/tasks/plans.py`, `/backend/app/services/content_resources.py`

Changes:
- **ingestion.py `_normalize_plan_item_details()`:** Added word count logging for `lesson_content` < 300 words and `content_markdown` < 400 words
- **plans.py `regenerate_plan_item_details()`:** Added content depth validation — if any step's `lesson_content` < 300 words or material's `content_markdown` < 400 words, retries once with a stronger prompt emphasizing depth
- **content_resources.py `generate_book_module()`:** Increased `max_tokens` from 8000 to 16000. Added validation that `content_markdown` >= 1,500 words, retries once with stronger prompt if too thin. Calculates `duration_minutes` from word count after generation.

### P0-E: Duration Minutes from Word Count
**Files:** `/backend/app/services/content_resources.py`

Changes:
- **`material_to_resource_payload()`:** Calculates `duration_minutes` from `content_markdown` word count instead of defaulting to 15
- **`lookup_public_domain_book()`:** Calculates `duration_minutes` from content length instead of hardcoding 15
- **`get_or_create_book_module_resource()`:** Calculates duration from word count for both source-lookup and LLM-generated paths
- **`generate_book_module()`:** Recalculates `duration_minutes` from word count after validation/retry
- **Formula:** `max(5, round(word_count / 200))` — 200 wpm reading speed, 5-minute minimum

---

## 2026-05-12: P0 Infrastructure & Daily Engagement (P0-COMPLETE, P1)

### Backend: Content Library API
**File:** `/backend/app/api/v1/content_resources.py`

- `GET /content-resources/library` — returns all content resources accessible to user (vault + plan-linked + public domain), with kind filter, search, and sort
- `GET /content-resources/continue-reading` — returns most recent in-progress resource

### Backend: Streak & Daily Focus API
**File:** `/backend/app/api/v1/daily_tasks.py`

- `GET /streak` — returns current streak, longest streak, last active date
- `GET /daily-focus` — returns today's focus item, reflection prompt, streak count

### Backend: Chat Context Enhancement
**File:** `/backend/app/api/v1/chat.py`

- Enhanced system prompt with: recently completed tasks, stashed ideas, currently reading resource

### Frontend: Library Upgrade
**File:** `/fe/cmpys/lib/features/session/presentation/library_screen.dart`

- Tabs changed from Stashed/Resources/Feed to Reading/Insights/Saved
- Reading tab: all accessible content resources
- Insights tab: stashed idea cards
- Saved tab: vault/bookmarked items

### Frontend: Home Enhancements
**File:** `/fe/cmpys/lib/features/home/presentation/home_screen.dart`

- Added `StreakBadge` widget (shows streak count or hidden when 0)
- Added `ContinueReadingCard` widget (shows in-progress resource with progress bar)
- `ReflectionCard` now uses dynamic prompts from `dailyFocusProvider`

### Frontend: Chat Quick Actions
**File:** `/fe/cmpys/lib/features/notes/presentation/studio_screen.dart`

- Dynamic quick actions based on plan state, reading progress, and daily focus
- Replaced hardcoded chips with contextual options

### Frontend: Notification Service
**Files:** `/fe/cmpys/lib/core/notifications/notification_service.dart`, `/fe/cmpys/lib/core/notifications/notification_provider.dart`

- `NotificationService` with `initialize()`, `requestPermissions()`, `scheduleDailyReminder()`, `cancelDailyReminder()`, `getSettings()`
- `NotificationSettings` data class
- Riverpod providers for notification service and settings

### Dependencies
**File:** `/fe/cmpys/pubspec.yaml`

- Added `flutter_local_notifications: ^18.0.1` and `timezone: ^0.9.4`

---

## 2026-05-11: Prompt Audit & Performance Optimization

### Prompt Bug Fixes
**File:** `/prompts/plan_generate.txt`, `/prompts/comparison_analyze.txt`

- Fixed double-brace `{{}}` syntax that was never substituted (critical bug)
- Changed to single-brace `{}` syntax for `prompt_loader.py` compatibility

### Backend: Plan Task Pre-Generation
**File:** `/backend/app/tasks/plans.py`

- Changed from enqueuing only Week 1 to enqueuing ALL plan items for background detail generation

### Backend: Avatar Idempotency
**File:** `/backend/app/api/v1/idols.py`

- Added early return if `idol.image_url` already exists, preventing duplicate DALL-E calls

### Frontend: Request Deduplication
**Files:** `home_controller.dart`, `chat_controller.dart`

- Added `if (state is HomeLoading) return` guard
- Added `if (state is ChatLoading) return` guard

### Frontend: Navigation Safety
**File:** `chat_threads_screen.dart`

- Guarded `context.pop()` with `context.canPop()` check
