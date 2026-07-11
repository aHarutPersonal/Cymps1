# CMPYS Implementation Changelog

**Last Updated:** 2026-05-13

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
