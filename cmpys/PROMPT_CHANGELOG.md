# CMPYS Prompt Changelog

## Audit Date: 2026-05-11

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

### 1. `plan_generate.txt` — 🔴 MAJOR REWRITE
- Fixed `{{}}` → `{}` syntax bug
- Added new variables: `idol_profile_json`, `idol_persona_json`, `idol_milestones_json`, `target_age`, `gaps_json`, `readiness_by_gap_json`
- Rewrote instructions to mandate idol-domain-specific tasks
- Enforced substantial tasks (2-8 hours each)
- Required idol-specific references (books by/about idol, techniques, habits)
- Anti-goals must be specific to the idol's domain
- Each week: 2-3 substantial tasks, not 5 micro-tasks

### 2. `plan_item_details.txt` — 🟡 IMPROVED
- Added `idol_name` and `idol_domain` variables
- Updated prompt to ground steps in the idol's domain
- Added guidance for step duration (30-90 minutes)
- Request idol-specific materials

### 3. `blueprint_generate.txt` — 🟢 MINOR TWEAKS
- Added `idol_persona_json` and `idol_profile_json` variables
- Minor wording improvements for domain grounding

### 4-12. Other prompts — 🟢 NO CHANGES
`chat_system.txt`, `chat_reply.txt`, `comparison_generate.txt`, `interview_system.xml`, `interview_question.txt`, `idol_discover.txt`, `intake_questions_generate.txt`, and all extraction/normalization prompts are solid and unchanged.

---

## Backend Code Changes

### `generator.py`
- Added parameters: `idol_profile`, `idol_persona`, `idol_milestones`, `gaps`, `readiness_by_gap`, `target_age`
- Passes structured data to `render_prompt()` for `plan_generate.txt`

### `plans.py` (task runner)
- Passes structured idol data (profile, persona, milestones, gaps, readiness) to `generate_plan()`
- Passes idol context to detail generation for `plan_item_details.txt`

### `prompt_loader.py`
- Updated `PROMPT_PLACEHOLDERS` for `plan_generate.txt` with all new variables
- Updated `PROMPT_PLACEHOLDERS` for `plan_item_details.txt` with `idol_name`, `idol_domain`
- Updated `PROMPT_PLACEHOLDERS` for `blueprint_generate.txt` with new variables
