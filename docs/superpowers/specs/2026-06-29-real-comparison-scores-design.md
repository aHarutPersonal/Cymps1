# Real Comparison Scores — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorm), pending implementation plan
**Scope:** Backend (`cmpys/backend`) + Flutter frontend (`fe/cmpys`), one Alembic migration

## Problem

The Compare screen's quantitative side is **hardcoded demo data**. The verdict
prose is real (LLM-generated from the user's interview, stored in
`comparison_output`), but the dimension scores, the "You/idol index", the
"53% of <idol>", the radar, and the milestones all come from a fixed
`const cmpysComparison` in `fe/cmpys/lib/features/cmpys/data/cmpys_seed.dart`.
They are identical for every user — which is why a user with **0 recorded
achievements** still sees "53% of Zuckerberg" with Buffett-flavored notes under
Zuckerberg. The backend `comparison_generate.txt` only ever produced prose, so
the app had nothing real to populate the gauges with.

## Goal

Make the Compare screen's **dimension scores and milestones** real —
LLM-generated and grounded in the user's interview + the idol's verified facts —
so the indices, 53%, radar, dimension bars/notes, and milestone checklist are
personalized rather than seeded.

## Non-Goals (YAGNI)

Strengths list and headline/summary stay seeded for now. Dimensions remain the
**5 fixed** ones (the radar UI is built for exactly these axes); the LLM scores
them, it does not invent new dimensions.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| What becomes real? | **Dimension scores (+ notes) and milestones** |
| Dimensions | The **fixed 5**: `capital`, `knowledge`, `habits`, `network`, `clarity` |
| Generation | **Approach A** — a separate non-streaming `generate_json` call after the prose comparison |
| Honesty | Scores are the model's **grounded estimates** (interview + verified idol facts), not measured truth |

## Key Definitions

- **Fixed dimension ids** (must match the FE radar + `_dimShort` map exactly):
  `capital`, `knowledge`, `habits` (shown as "Discipline"), `network`,
  `clarity`.
- **`you` score / `idol` score**: integers 0–100. `you` grounded in what the
  user revealed in the interview; `idol` grounded in `idol_facts_json` (the
  idol's web-searched achievements by `user_age`).

## Data Model

One Alembic migration:

### `intake_sessions` (extend)
- `comparison_scores_json` JSONB, nullable.

Stored shape:
```json
{
  "dimensions": [
    {"id": "capital",   "label": "Capital at work",  "you": 22, "idol": 70,
     "you_note": "…", "idol_note": "…"},
    {"id": "knowledge", "label": "Knowledge base",    "you": 48, "idol": 88, "you_note": "…", "idol_note": "…"},
    {"id": "habits",    "label": "Daily discipline",  "you": 41, "idol": 82, "you_note": "…", "idol_note": "…"},
    {"id": "network",   "label": "Trusted network",   "you": 35, "idol": 64, "you_note": "…", "idol_note": "…"},
    {"id": "clarity",   "label": "Strategic clarity", "you": 52, "idol": 78, "you_note": "…", "idol_note": "…"}
  ],
  "milestones": [
    {"text": "Defined a written personal philosophy", "hit_by_age": 21},
    … (~5 idol-specific, each with hit_by_age)
  ]
}
```

## Backend Generation

New prompt `cmpys/prompts/comparison_scores.txt` + a server-side scorer invoked
inside `generate_results` (`app/api/v1/sessions.py`), **after** the prose
comparison has streamed and persisted:

1. One `client.generate_json(...)` call (Gemini JSON mode + the existing
   JSON-retry-on-error pattern), grounded in: the interview transcript,
   `idol_facts_json`, the just-generated comparison prose, and `user_age`.
2. **Validate + normalize server-side:** force exactly the 5 fixed dimension
   ids; clamp `you`/`idol` to 0–100; for any missing/invalid dimension, fall
   back to that dimension's seed values so the radar always has 5. Cap
   milestones at a small number (~5).
3. Persist the normalized object to `session.comparison_scores_json`.
4. **Best-effort isolation:** wrap the whole scorer in try/except — any failure
   (LLM error, invalid JSON after retry, validation miss) leaves
   `comparison_scores_json` null and is logged; it MUST NOT fail the
   already-succeeded results stream.
5. Emit `data: {"type": "comparison_scores", "ready": true}` after the prose's
   `done` event (optional live consumer). The persisted column is the source of
   truth.

This runs in the same flow as the (already-working) blueprint + plan-job
enqueue, so it generates once during onboarding.

## API

`_build_session_response` (`app/api/v1/sessions.py`) adds `comparisonScores`
(the dict, or null) to the session response, alongside `comparison_output` /
`blueprint_output`. No new endpoint — the FE already hydrates via
`/sessions/current` → `syncFromSession`.

## Frontend

- **Session model** (`fe/cmpys/lib/features/session/models/session_models.dart`):
  add `comparisonScores`, parsed into typed
  `ComparisonScores { List<ComparisonDim> dimensions; List<ComparisonMilestone> milestones; }`
  with `ComparisonDim { String id; String label; int you; int idol; String youNote; String idolNote; }`
  and `ComparisonMilestone { String id; String text; int hitByAge; }`.
  `ComparisonDim.id` is the dimension id (`capital`…). `ComparisonMilestone.id`
  is assigned by **position** — `m1`, `m2`, … — matching the seed's id scheme so
  the claim map (`st.milestones[id]`) stays stable across reloads. Null when
  absent; `fromJson` tolerates partial/missing fields.
- **Store** (`fe/cmpys/lib/features/cmpys/state/cmpys_store.dart`):
  `syncFromSession` copies the parsed dims + milestones into new nullable state
  fields (`liveComparisonDims`, `liveComparisonMilestones`).
- **`liveDims()`**: return the real store dims when present, else
  `cmpysComparison.dimensions` (seed). The existing `dimShift` reassessment
  overlay still applies on top. A parallel accessor returns real milestones when
  present, else `cmpysComparison.milestones`.
- **Compare screen** (`compare_screen.dart`): the only change is swapping the
  two direct `cmpysComparison` reads for store accessors — dimensions already
  flow through `liveDims()`; the milestone list reads `cmpysComparison.milestones`
  directly today and switches to a new `st.liveMilestones()` (real-or-seed). It
  already computes `youAvg`/`idolAvg`/`overall` (the 53%) and renders the radar,
  dimension bars/notes, and milestone list — so they become real once those
  accessors return real data. The
  "MILESTONES {idol} HIT BY {age}" line uses each milestone's `hitByAge`; the
  claimable checkboxes (`st.milestones[id]`) key off the real milestone ids.

## Backward Compatibility

Old sessions and any failed scoring call → `comparisonScores` null → seed
fallback (exactly today's behavior). New onboardings get real data. Nothing
breaks; no data migration of existing rows.

## Error Handling

- Scorer LLM error / invalid JSON after one retry / validation miss → null
  `comparison_scores_json`; results stream still completes.
- Partial dims from the LLM → missing dims filled from seed (always 5).
- FE parse of malformed `comparisonScores` → treat as null → seed fallback.

## Testing

**Backend**
- Migration up/down.
- Scorer normalization: enforces the 5 fixed ids, clamps 0–100, fills a missing
  dim from seed, caps milestones.
- Scorer fallback: on LLM error / unrepairable JSON, returns null and does not
  raise (results stream unaffected).
- `_build_session_response` includes `comparisonScores`.

**Frontend**
- `ComparisonScores.fromJson` parses full + partial payloads; returns null-safe
  structures.
- `liveDims()` returns real dims when present and seed dims when null.
- Indices (`youAvg`/`idolAvg`/`overall`) compute correctly from real dims.
- Milestone ids round-trip to the `st.milestones` claim map.

## Affected Files (indicative)

**Backend**
- `app/models/intake.py` (new column)
- `alembic/versions/<new>.py`
- `prompts/comparison_scores.txt` (new)
- `app/api/v1/sessions.py` (scorer in `generate_results`; `_build_session_response`)
- `app/services/...` (a small `comparison_scores` helper for the call + normalization)
- `app/schemas/...` (session response field)

**Frontend**
- `lib/features/session/models/session_models.dart` (model + parse)
- `lib/features/cmpys/state/cmpys_store.dart` (`syncFromSession`, `liveDims`, state fields)
- `lib/features/cmpys/presentation/compare_screen.dart` (only if a milestone accessor swap is needed)
