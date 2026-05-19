# CMPYS Prompt Changelog

## Audit Date: 2026-05-11 (Original)
## Updated: 2026-05-13

---

## Critical Bug Found

### `plan_generate.txt` — Double-brace syntax never substituted
- **Severity:** 🔴 CRITICAL — The prompt uses `{{variable}}` (double braces) but `prompt_loader.py`'s `render_prompt()` only replaces `{variable}` (single braces).
- **Impact:** The LLM receives literal `{{user_goal}}`, `{{idol_name}}`, `{{hours_per_week}}`, `{{user_context}}` strings instead of actual values. The plan is generated with zero user context.
- **Fix:** Changed to single-brace `{variable}` syntax.

### `comparison_analyze.txt` — Same double-brace bug
- **Severity:** 🔴 CRITICAL — Same `{{variable}}` syntax issue.
- **Fix:** Changed to single-brace `{variable}` syntax.

---

## Prompt-by-Prompt Audit

### 1. `plan_generate.txt` — 🔴 MAJOR REWRITE (Updated 2026-05-13)

**Phase 1 (2026-05-11):**
- Fixed `{{}}` → `{}` syntax bug
- Added new variables: `idol_profile_json`, `idol_persona_json`, `idol_milestones_json`, `target_age`, `gaps_json`, `readiness_by_gap_json`
- Rewrote instructions to mandate idol-domain-specific tasks
- Enforced substantial tasks (2-8 hours each)
- Required idol-specific references (books by/about idol, techniques, habits)
- Anti-goals must be specific to the idol's domain
- Each week: 2-3 substantial tasks, not 5 micro-tasks

**Phase 2 — Content Depth Fixes (2026-05-13):**
- Added Rule #12 "SUBSTANCE MINIMUMS": mission descriptions >= 50 words, daily rhythm descriptions >= 30 words, `primary_mission` >= 30 words referencing specific skill/deliverable
- Changed `daily_instructions` from "2-3 sentences" to "3-5 sentences (40-80 words) with specific, measurable action"
- **Backend change:** `BinaryTask` Pydantic schema now preserves `estimated_hours` (float) and `daily_instructions` (optional string) from LLM output instead of dropping them
- **Backend change:** `generator.py` stores `daily_instructions` in `meta_json` on PlanItem

### 2. `plan_item_details.txt` — 🟡 IMPROVED (Updated 2026-05-13)

**Phase 1 (2026-05-11):**
- Added `idol_name` and `idol_domain` variables
- Updated prompt to ground steps in the idol's domain
- Added guidance for step duration (30-90 minutes)
- Request idol-specific materials

**Phase 2 — Content Depth Fixes (2026-05-13):**
- `lesson_content` minimum increased: 500-1,200 words (was: 200-400 words)
- Structured lesson format required: opening context (2-3 sentences), core concept explanation (3-5 paragraphs), real-world example from idol's life, practice guide (3-5 numbered steps), reflection prompt
- `content_markdown` for materials: 600-1,000 words (was: 200-400 words)
- `substeps` must be 20-50 words each (was: bare strings)
- Anti-vague-instruction rule: "'practice regularly' is forbidden"
- Steps claiming 60+ minutes must have 800+ word `lesson_content`
- Anti-filler-language rule added
- Idea cards must be 40-80 words with specific examples
- **Backend change:** Content quality validation added — retries once if `lesson_content` < 300 words or `content_markdown` < 400 words

### 3. `book_module_generate.txt` — 🔴 MAJOR REWRITE (2026-05-13)

**Before:** No word count requirements. Modules typically produced 200-800 words (1-4 min reading) while claiming "15 minutes."

**After:**
- Minimum word count: `content_markdown` must be 2,500-4,000 words
- Section summaries: 80-150 words (was: no requirement)
- Section exercises: 40-80 words with specific tool, time, and success criteria
- Idea card content: 40-80 words with specific example + actionable takeaway
- Content structure required: opening hook (2-3 paragraphs), ## headings, ### exercise subheadings, **bold** key terms, concrete examples per section, closing synthesis paragraph
- Quality rule: "Every claim must reference a specific event, quote, or decision from {author}'s life. Generic advice like 'stay focused' is forbidden."
- Word count verification instruction at end
- **Backend change:** `generate_book_module()` validates word count >= 1,500 and retries once with stronger prompt if too thin
- **Backend change:** `max_tokens` increased from 8,000 to 16,000
- **Backend change:** `duration_minutes` calculated from word count (words / 200) instead of hardcoded 15

### 4-12. Other prompts — 🟢 NO CHANGES

`chat_system.txt`, `chat_reply.txt`, `comparison_generate.txt`, `interview_system.xml`, `interview_question.txt`, `idol_discover.txt`, `intake_questions_generate.txt`, and all extraction/normalization prompts are solid and unchanged.

---

## Backend Code Changes

### `generator.py`
- Added parameters: `idol_profile`, `idol_persona`, `idol_milestones`, `gaps`, `readiness_by_gap`, `target_age`
- Passes structured data to `render_prompt()` for `plan_generate.txt`
- Uses LLM-provided `estimated_hours` directly instead of computing from weekly hours
- Stores `daily_instructions` in `meta_json`

### `plans.py` (task runner)
- Passes structured idol data (profile, persona, milestones, gaps, readiness) to `generate_plan()`
- Passes idol context to detail generation for `plan_item_details.txt`
- Added content depth validation with retry for thin lesson content and material content

### `schemas.py`
- `BinaryTask`: Added `estimated_hours` (float, default 1.0) and `daily_instructions` (optional string, max 2000)
- `PlanItemCreate`: Changed `description` min_length from 1 to 10, added `dailyInstructions` field

### `ingestion.py`
- `_normalize_plan_item_details()`: Added word count logging for thin content (lesson_content < 300 words, content_markdown < 400 words)

### `content_resources.py`
- `generate_book_module()`: Increased max_tokens to 16,000. Added word count validation with retry for content_markdown < 1,500 words. Calculates duration_minutes from word count.
- `material_to_resource_payload()`: Calculates duration_minutes from content_markdown word count instead of defaulting to 15
- `lookup_public_domain_book()`: Calculates duration from content length instead of hardcoding 15
- `get_or_create_book_module_resource()`: Calculates duration from word count for both source-lookup and LLM-generated paths

### `prompt_loader.py`
- Updated `PROMPT_PLACEHOLDERS` for `plan_generate.txt` with all new variables
- Updated `PROMPT_PLACEHOLDERS` for `plan_item_details.txt` with `idol_name`, `idol_domain`
- Updated `PROMPT_PLACEHOLDERS` for `blueprint_generate.txt` with new variables