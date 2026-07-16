# Architecture Decision Records

**Project:** CMPYS  
**Last Updated:** 2026-07-16

---

## ADR-001: Content Duration Calculated from Word Count

**Date:** 2026-05-13  
**Status:** Accepted

### Context

All content resources (book modules, plan item lessons, materials) previously used hardcoded `duration_minutes = 15`. This created a fundamental mismatch where the UI showed "15 min" for content that could be read in 2-3 minutes.

### Decision

Calculate `duration_minutes` from actual word count using the formula: `max(5, round(word_count / 200))`.

- 200 wpm is the industry standard for non-fiction reading speed
- Minimum of 5 minutes prevents absurdly short durations
- Applied consistently across all content generation paths

### Consequences

- Users see accurate reading times
- Backend no longer needs manual duration adjustments
- Content that's genuinely thin will show short durations, prompting improvement rather than hiding behind inflated claims
- Existing resources with hardcoded 15 min will need recalculation on next generation

---

## ADR-002: LLM Output Validation with Retry

**Date:** 2026-05-13  
**Status:** Accepted

### Context

LLM-generated content was frequently too thin (200-800 word "15-minute modules"). Without validation, this shallow content was stored and served to users.

### Decision

Add post-generation validation with a single retry:

1. **Book modules**: Require 3,200-4,500 words plus structure, practice, anti-filler, and grounding checks; retry once with the exact failed checks
2. **Plan item details**: Require each lesson to remain within the accepted 1,900-4,200-word range (target 2,400-2,800), all required sections, valid material references, and actionable substeps. Repair substeps alone when they are the only defect; otherwise retry only the failed lesson while preserving valid checkpoints.
3. **Plan generation**: `BinaryTask` schema enforces `description` min_length=10

Use the retry result only if it's deeper than the original.

### Consequences

- One retry adds ~2-3 seconds per generation but catches most thin content
- No infinite retry loops (max 1 retry)
- Logged warnings track thin content for prompt improvement
- Does not fix fundamentally bad prompts — that's what the prompt rewrites address

---

## ADR-003: Preserve LLM-Generated estimated_hours and daily_instructions

**Date:** 2026-05-13  
**Status:** Accepted

### Context

The `BinaryTask` Pydantic schema was dropping `estimated_hours` and `daily_instructions` from LLM output. The generator then computed `estimated_hours` by dividing weekly hours by task count, which could produce nonsensical values (e.g., "1.5 hours" for a daily habit).

### Decision

- `BinaryTask` schema now includes `estimated_hours` (float, default 1.0) and `daily_instructions` (optional string)
- `generator.py` uses the LLM-provided `estimated_hours` directly instead of computing from weekly hours
- `daily_instructions` stored in `PlanItem.meta_json` for frontend access

### Consequences

- Frontend can display "Today: Read chapters 1-3 of 'The Intelligent Investor' and write a margin-of-safety analysis (40 min)" instead of a generic task title
- Duration claims match what the LLM actually intended for each task
- `meta_json` now contains `{"primary_mission": "...", "predicted_friction": "...", "friction_solution": "...", "daily_instructions": "..."}` for habit/practice tasks

---

## ADR-004: Content Resource Deduplication via Canonical Keys

**Date:** 2026-05-11  
**Status:** Accepted (pre-existing)

### Context

Multiple plan items reference the same book or video. Without deduplication, the same resource is generated multiple times.

### Decision

Use `canonical_key` (e.g., `book:benjamin_graham:intelligent_investor`) to deduplicate content resources. When a material references a book that already exists, the existing resource is reused.

### Consequences

- Same book referenced across multiple plans shares one content resource
- `PlanItemContentResource` links plan items to shared resources
- Content generation (book modules) only runs once per canonical key
- Library page shows all accessible resources regardless of plan

---

## ADR-005: Progressive Semantic Plan Generation

**Date:** 2026-07-16
**Status:** Accepted (supersedes the 2026-05-11 all-items policy)

### Context

Generating all lessons for all twelve weeks up front spends heavily on work a
user may never reach and delays the first usable lesson behind unrelated long
outputs. Generating a whole mission as one all-or-nothing artifact also loses
completed work when one lesson is slow or fails validation.

### Decision

- Generate the compact twelve-week backbone in one bulk call, then expand only
  the current week into execution-ready task copy.
- Start current-week detail work immediately. Reserve high-priority capacity
  for the first mission and send remaining current-week missions to the normal
  queue.
- Within a mission, persist the shared outline, generate and persist lesson one
  first, then generate lessons two and three concurrently. Each complete lesson
  is a resumable semantic checkpoint; arbitrary token chunks are not persisted.
- Expose a validated partial checkpoint to the client so lesson one can be read
  while later lessons continue. Placeholder steps cannot be completed.
- Start the next week's low-priority preparation only after the learner
  completes the first current lesson.
- Isolate high-, default-, and low-priority Celery consumers so speculative
  work cannot consume every interactive slot.

### Consequences

- Time to first usable lesson no longer includes the slowest of three lessons.
- Valid lessons survive retries and worker failures, reducing duplicate tokens.
- Future-week provider spend follows demonstrated progress rather than plan
  creation.
- The checkpoint is stored in the existing `details_json`/job `result_json`
  fields, so this decision requires no schema migration.
