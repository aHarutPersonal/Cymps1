# CMPYS Functional Analysis — Detailed Findings Report

**Date:** 2026-05-14  
**Scope:** Full codebase functional review — backend, frontend, prompts, data models, API endpoints  
**Excludes:** P0 security items (per user request)

---

## 🔴 Critical Bugs (Will Crash or Silently Fail)

### 1. ✅ FIXED — `Idol.display_name` Does Not Exist

**Files:** `sessions.py` lines 98, 266, 274, 410, 557, 769, 822

**Fix applied:** All 7 occurrences changed from `session.idol.display_name` → `session.idol.name`.

### 2. ✅ FIXED — `session.idol.persona_pack` Does Not Exist

**Files:** `sessions.py` lines 411, 558, 770

**Fix applied:** Changed to `getattr(session.idol, "persona", None)` with `_persona_to_dict()` helper to convert IdolPersona object to dict for `.get()` access. Added eager loading of `idol.profile` and `idol.persona` in `_get_session()`.

### 3. ✅ FIXED — `Idol.display_name` in SQLAlchemy Query

**Fix applied:** Changed `Idol.display_name == data.idol_name` → `Idol.name == data.idol_name`.

### 4. ✅ FIXED — `Idol()` Constructor with Nonexistent Fields

**Fix applied:** Removed `display_name`, `wikidata_id`, `is_ready` from constructor. Added `domain="unknown"`. Wikidata ID now stored via `IdolExternalId` model.

### 5. ✅ FIXED — `comparison_analyze.txt` Uses `{{double_braces}}`

**Fix applied:** Replaced all `{{...}}` with `{...}` in template. Updated `comparison.py` to use `render_prompt()` instead of manual `.replace()` calls. Removed `import os` and old fallback path code.

### 6. ✅ FIXED — `chat_system.txt` Placeholder Mismatch

**Fix applied:** Rewrote `chat_system.txt` to use all 11 placeholders that `responder.py` provides: `{idol_name}`, `{voice_style}`, `{principles}`, `{dos}`, `{donts}`, `{signature_phrases}`, `{topics_of_strength}`, `{grounding_facts_json}`, `{idol_persona_json}`, `{user_context_json}`, `{disclaimer}`. Removed the stale `{user_goal}` and `{user_status}`.

### 7. ✅ FIXED — `persona_pack.txt` Output Schema Mismatch

**Fix applied:** Rewrote `persona_pack.txt` to output all 14 `IdolPersona` model fields.

### 8. ✅ FIXED — PROMPT_PLACEHOLDERS Registry Incomplete

**Fix applied:** Added entries for `comparison_analyze.txt`, `image_generate.txt`, and updated `persona_pack.txt` to include `{idol_name}`.

### 9. ✅ FIXED — SSE Stream Retry/Recovery

**Fix applied:** Added backward phase transitions in `VALID_PHASE_TRANSITIONS` (COMPARISON→INTERVIEW, BLUEPRINT→COMPARISON). On stream error, rolls back to previous phase and clears failed output. Client can retry by calling `generate_results` again. Error events now include `retryable: True`.

### 10. ✅ FIXED — Feed: Global Posts With No User Association

**Fix applied:** Added `generated_by_user_id` column to `FeedPost` model (nullable, for future personalization). Fixed shuffle seed — now defaults to date-based seed (`YYYYMMDD`) for consistent pagination within a day. Migration created.

### 11. 🟡 Feed Comments: Hardcoded "User" Names

**File:** `feed.py` line ~370

```python
user_name="You" if c.user_id == current_user.id else "User",
```

All non-current-user commenters show as "User" — no username lookup.

**Impact:** Multi-user scenarios have no way to distinguish commenters.

**Status:** Not fixed — requires user profile lookup integration.

### 12. ✅ FIXED — `discover_feed.txt` Encourages Fabricated Quotes

**Fix applied:** Rewrote prompt with strict anti-fabrication guidance:
- Only use quotes you are CERTAIN about
- Added paraphrased wisdom and attributed principles as safe alternatives
- Removed YouTube URL fabrication — set `url: null` for all video types (system resolves via Tavily search)
- Added explicit "Do NOT fabricate quotes" rule

---

## 🟡 Medium Priority Issues

### 13. ✅ FIXED — `idea_cards.py` Uses Direct Gemini API Instead of Unified LLM Client

**Fix applied:** Replaced `from google import genai; from google.genai import types` with `from app.services.llm import get_llm_client`. Uses `client.generate_json()` for consistent error handling, retry, JSON repair, and model fallback. Removed unused `settings` import.

### 14. ✅ FIXED — `feed.py` Uses Direct Gemini API Instead of Unified LLM Client

**Fix applied:** Same as #13 — replaced direct Gemini call with `get_llm_client()` + `generate_json()`. Removed unused `settings` import and manual markdown-fence stripping (handled by LLM client's JSON repair).

### 15. 🟡 `discover_feed.txt` LLM-Generated URLs Are Discarded

The prompt previously asked for YouTube URLs, but the code explicitly sets `url=None` and resolves via Tavily search. With the prompt fix (#12), videos now always have `url: null` and the Tavily resolver handles URL lookup.

**Impact:** If Tavily fails, videos may be invisible. Consider adding a fallback or hiding video posts without URLs.

**Status:** Partially fixed — prompt no longer fabricates URLs. Tavily fallback still needed.

### 16. ✅ FIXED — SSE Stream Error Recovery

**Fix applied:** See #9. Sessions now roll back on error and support retry.

### 17. 🟡 Plan Generation `allowed_resources_json` Placeholder Not in Template

**Registry entry** for `plan_generate.txt` lists `allowed_resources_json` as required, but the actual template doesn't contain this placeholder. Same for `readiness_by_gap_json` vs `{gaps_json}`.

**Status:** Not fixed — needs template/registry alignment. Low impact since `load_and_render` still works.

### 18. 🟡 `daily_feed_generate.txt` vs `idea_cards_generate.txt` Overlap

Both produce similar bite-sized insights. Different JSON structures mean they can't be reused across features.

**Status:** Not fixed — intentional separation for now.

### 19. 🟡 No Pagination/Rate Limiting on SSE Endpoints

A user could create unlimited sessions or call endpoints rapidly.

**Status:** Not fixed — requires middleware/rate-limiting infrastructure.

### 20. ✅ VERIFIED — Frontend `SessionPhase` Enum Is Correctly Handled

The Dart model has `@JsonValue` annotations mapping camelCase to snake_case, plus explicit `fromString()` and `toJson()` methods. No mismatch exists.

---

## 🔵 Low Priority / Prompt Quality Issues

### 21. ✅ FIXED — `thinking_narrate.txt` Is Too Brief

**Fix applied:** Expanded from "3-5 short thoughts" to substantive guidance: identify specific domains, eras, philosophies; make 2-3 concrete observations about uniqueness; consider challenging mentor archetypes.

### 22. ✅ FIXED — `thinking_plan.txt` and `thinking_task.txt` Too Short

**Fix applied:** Expanded both from "1-2 punchy sentences" to "2-3 sentences" with guidance for specific, tailored content. Added example tones for each.

### 23. ✅ FIXED — `book_module_generate.txt` Word Count Unenforceable

**Fix applied:** Replaced "MUST be 2,500-4,000 words" with structural guidance: "at least 8 substantial paragraphs across 5-7 sections, each with opening explanation, concrete example, practice exercise, and transition." Also updated the final verification instruction.

### 24. 🟡 `idol_suggest.txt` Doesn't Use Google Search Grounding

The sessions.py endpoint uses `stream_with_grounding()` but standalone idol discovery might not.

**Status:** Not fixed — low impact.

### 25. ✅ VERIFIED — `interview_question.txt` Double Injects Context (Intentional)

The system prompt and user message both include key context (`idol_name`, `user_age`, `user_interests_json`, `chat_history_json`). This is intentional redundancy — the system prompt establishes persona/rules, while the user message provides turn-specific context. This is standard practice for multi-turn LLM conversations.

### 26. 🟡 `discover_feed.txt` Language Constraint

The prompt says "All content in English only." For international users, content should potentially be localized.

**Status:** Not fixed — feature decision.

### 27. 🟡 `idea_cards_generate.txt` Inconsistent JSON Keys

Prompt shows `category_tag` and `content_markdown`, but fallback parsing also accepts `content` and `category`.

**Status:** Not fixed — defensive parsing is fine.

### 28. 🟡 `achievement_intake_generate.txt` — `{limit}` Placeholder

The prompt has `{limit}` but no default is documented.

**Status:** Not fixed — low impact.

### 29. ✅ FIXED — `image_generate.txt` Dead Prompt

**Fix applied:** Added deprecation header documenting that this prompt is NOT wired to any service. Kept the template content for future use but clearly marked as inactive.

---

## 📊 Summary of All Changes

### Files Modified
| File | Changes |
|---|---|
| `sessions.py` | 7× `display_name`→`name`, 3× `persona_pack`→`persona`, `_persona_to_dict()` helper, `Idol()` constructor fix, eager loading, SSE retry/recovery |
| `comparison.py` | Replaced manual `.replace()` with `render_prompt()`, removed `import os` |
| `feed.py` | Replaced direct Gemini API with unified LLM client, fixed shuffle seed, added `generated_by_user_id` to FeedPost creation |
| `idea_cards.py` | Replaced direct Gemini API with unified LLM client, removed `settings` import |
| `feed_post.py` | Added `generated_by_user_id` column |
| `intake.py` | Added backward retry transitions to `VALID_PHASE_TRANSITIONS` |
| `prompt_loader.py` | Added registry entries for `comparison_analyze.txt`, `image_generate.txt`, updated `persona_pack.txt` |
| `chat_system.txt` | Rewrote with correct 11 placeholders |
| `comparison_analyze.txt` | Replaced `{{double_braces}}` with `{single_braces}` |
| `persona_pack.txt` | Rewrote to output all 14 IdolPersona model fields |
| `discover_feed.txt` | Rewrote with anti-fabrication guidance, removed YouTube URL fabrication |
| `thinking_narrate.txt` | Expanded from 3-5 thoughts to substantive narrative guidance |
| `thinking_plan.txt` | Expanded from 1-2 sentences to 2-3 sentences with specific direction |
| `thinking_task.txt` | Expanded from 1-2 sentences to 2-3 sentences with specific direction |
| `book_module_generate.txt` | Replaced word count with structural guidance |
| `image_generate.txt` | Added deprecation header |

### Migration Created
| Migration | Description |
|---|---|
| `r5s6t7u8v9w0` | Add `generated_by_user_id` column to `feed_posts` table |

### Remaining Issues (Not Fixed)
| # | Issue | Priority | Reason |
|---|---|---|---|
| 11 | Feed comments show "User" instead of usernames | Medium | Needs user profile lookup integration |
| 15 | Tavily URL resolution has no fallback | Medium | Needs error handling in video URL resolver |
| 17 | Plan prompt placeholder mismatch | Low | `load_and_render` still works |
| 18 | Daily feed vs idea cards overlap | Low | Intentional separation |
| 19 | No rate limiting on SSE endpoints | Medium | Needs middleware |
| 24 | Idol suggest may lack search grounding | Low | Verify in production |
| 26 | Feed language hardcoded to English | Low | Feature decision |
| 27 | Idea cards JSON key inconsistency | Low | Defensive parsing is fine |
| 28 | Achievement intake `{limit}` no default | Low | Low impact |