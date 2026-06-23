# CMPYS Optimization & Content Quality Plan

This document outlines performance optimizations and content quality fixes for the CMPYS system.

## ✅ Completed Changes

### 1. Backend: Enqueue ALL Plan Tasks for Background Processing
- [x] Modified `_enqueue_week1_details_generation_async` to fetch and enqueue ALL `PlanItem`s
- [x] Renamed to `_enqueue_all_details_generation_async`
- [x] Query ordered by `week_start` ascending

### 2. Backend: Avatar Idempotency
- [x] Added early return if `idol.image_url` already exists in `generate_idol_image`

### 3. Frontend: Request Deduplication
- [x] Added `if (state is HomeLoading) return` guard in `HomeController`
- [x] Added `if (state is ChatLoading) return` guard in `ChatController`

### 4. Frontend: Navigation Safety
- [x] Guarded `context.pop()` with `context.canPop()` in `chat_threads_screen.dart`

### 5. Content Depth & Quality (P0-A through P0-E)

#### P0-A: Book Module Prompt Rewrite
- [x] `book_module_generate.txt` now requires 2,500-4,000 word `content_markdown`
- [x] Section summaries 80-150 words, exercises 40-80 words
- [x] Idea cards 40-80 words with specific examples
- [x] Backend validates word count >= 1,500, retries once if thin

#### P0-B: Plan Item Details Prompt Rewrite
- [x] `lesson_content` minimum 500-1,200 words per step
- [x] `content_markdown` for materials 600-1,000 words
- [x] `substeps` must be 20-50 words each
- [x] Backend validates and retries thin content

#### P0-C: Plan Generator Prompt + Schema
- [x] Rule #12 "SUBSTANCE MINIMUMS" added
- [x] `daily_instructions` changed to 3-5 sentences (40-80 words)
- [x] `BinaryTask` schema: `estimated_hours` (float), `daily_instructions` (optional string)
- [x] `generator.py` preserves LLM-provided `estimated_hours` and `daily_instructions`
- [x] `PlanItemCreate`: `description` min_length=10, `dailyInstructions` field added

#### P0-D: Backend Content Quality Validation
- [x] `_normalize_plan_item_details()`: logs warnings for thin content
- [x] `regenerate_plan_item_details()`: validates and retries once if thin
- [x] `generate_book_module()`: validates word count, retries once, max_tokens=16000

#### P0-E: Duration from Word Count
- [x] All `duration_minutes` calculated from `word_count / 200` (min 5)
- [x] Removed all hardcoded `duration_minutes = 15` defaults
- [x] Applied in `generate_book_module()`, `material_to_resource_payload()`, `get_or_create_book_module_resource()`, `lookup_public_domain_book()`

---

## 🚨 Original Identified Issues (All Fixed)

1.  **Frontend Request Storms** — Fixed with load guards
2.  **Redundant LLM Generation** — Fixed with avatar idempotency
3.  **Task Details Slow Loading** — Fixed with all-weeks pre-generation
4.  **Unsafe Navigation** — Fixed with bounded pop
5.  **Content Depth Mismatch** — Fixed with prompt rewrites, schema changes, validation + retry, and word-count-based duration