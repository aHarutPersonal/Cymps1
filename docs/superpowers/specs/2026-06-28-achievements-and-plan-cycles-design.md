# Achievements & Progressive Plan Cycles — Design

**Date:** 2026-06-28
**Status:** Approved (brainstorm), pending implementation plan
**Scope:** Backend (`cmpys/backend`) + Flutter frontend (`fe/cmpys`), one Alembic migration

## Problem

A generated 12-week plan currently has no completion behavior. When a user
finishes it, nothing happens — no record of what they accomplished, no next
cycle. The `UserAchievement` model exists and the plan generator already reads
achievements as "Recent Wins" context, but nothing ever writes achievements
from plan progress, so the loop is never closed.

## Goals

1. Let users **register achievements** at two moments:
   - **In-flight:** completing a mission task or a week milestone prompts an
     editable, AI-phrased achievement they confirm or skip.
   - **End of cycle:** when all mission tasks are done, a completion form recaps
     the cycle's achievements and confirms the plan is finished.
2. **Generate a progressive next 12-week plan** that builds on the completed
   cycle and the logged achievements, with the same mentor.

## Non-Goals (YAGNI)

Badges/points, streaks, social sharing, mentor-switching at the cycle boundary
(same-mentor progression was chosen), retroactive achievements for past/demo
data.

## Key Definitions

- **Mission task** — plan item with `type ∈ {project, course, reading}`
  (multi-hour, ~2–3 per week). These drive completion and achievement prompts.
- **Daily rhythm** — plan item with `type ∈ {habit, practice}` (20–45 min,
  repeated). Counts toward progress but does not gate completion and is not
  individually prompted for an achievement.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Which completions log an achievement? | Mission tasks, via an **input moment**; week milestones get an acknowledgment that surfaces those |
| Input UX | **Pre-filled & editable**, confirm or skip |
| Pre-fill source | **AI-phrased** (Approach B) with `success_metric` as instant fallback |
| Plan "finished" trigger | **All mission tasks done** |
| Next cycle start | **Achievements form → recap → CTA → progressive plan**, same mentor |

## Data Model

One Alembic migration covering:

### `user_achievements` (extend)
- `source` enum `achievement_source`: `manual | plan_item | plan_cycle` (default `manual`)
- `plan_id` UUID nullable FK → `plans.id` ON DELETE SET NULL
- `plan_item_id` UUID nullable FK → `plan_items.id` ON DELETE SET NULL
- `cycle_number` int default 1
- Unique constraint on (`plan_item_id`, `source`) where `source = 'plan_item'`
  so re-confirming updates rather than duplicates.
- Existing fields unchanged (title, category, achievement_date, notes,
  evidence_link).

### `plans` (extend)
- `cycle_number` int default 1
- `completed_at` timestamptz nullable
- `previous_plan_id` UUID nullable self-FK → `plans.id` ON DELETE SET NULL

### `plan_generation_jobs` (extend)
- `cycle_number` int default 1
- `previous_plan_id` UUID nullable

## Completion Detection

The existing `POST /plan-items/{item_id}/toggle-complete` handler, after writing
the `PlanItemCompletion`, counts remaining incomplete **mission** tasks in the
item's plan:

- When remaining hits 0 and `plan.completed_at` is null → stamp `completed_at`.
- When a mission task is un-checked and `completed_at` is set **but no next
  cycle exists yet** → clear `completed_at` (accidental-tap recovery). Once the
  next cycle exists, `completed_at` is sticky and the plan is archived.

The response gains two fields:
- `planComplete: bool`
- `missionTasksRemaining: int`

No new polling — this piggybacks on the toggle the user already performed.
Detection requires ≥1 mission task to exist, so `planComplete` can never trip
falsely on a degenerate plan.

## The Two Achievement Moments

### Moment 1 — per mission task (in-flight)

**Provenance is item-centric to stay unambiguous:** the achievement-input sheet
fires when a `toggle-complete` flips a **mission task** to done, and the saved
row always ties to that one `plan_item`. A **week milestone** (the last item of
a week completed) does **not** create its own achievement row — it shows a brief
"Week N complete" acknowledgment that surfaces the achievements already captured
for that week's mission tasks. This honors the milestone moment without a second,
loosely-defined provenance type.

FE trigger: a `toggle-complete` that flips a **mission task** to done. The FE
opens an **Achievement sheet**:

1. Opens instantly, pre-filled with the item's `success_metric` + a category
   guessed from item type/domain.
2. Background call `POST /plan-items/{item_id}/achievement-suggestion` →
   Gemini Flash phrases a first-person achievement line from the item title,
   description, `success_metric`, idol, and recent achievements. Returns
   `{title, category}`. **2.5s timeout; on slow/error/offline it is a no-op**
   and the `success_metric` text stays.
3. When AI text arrives, it swaps into the still-editable field **unless the
   user has already started typing**.
4. **Confirm** → save `UserAchievement` (`source=plan_item`, `plan_item_id`,
   `plan_id`, `cycle_number`). **Skip** → nothing saved.

Rules:
- The achievement is **optional and independent of completion**. Skipping, or
  later un-checking the item, never deletes a saved achievement.
- One item → at most one achievement (re-confirming updates the existing row).

### Moment 2 — end of cycle (all mission tasks done)

When `planComplete: true`, the FE routes to a **Cycle Completion form**:

1. Recaps every `UserAchievement` from this cycle (grouped by category/week),
   each still editable.
2. `POST /plans/{plan_id}/cycle-summary` → one Gemini call returns a short
   narrative ("Over 12 weeks with Franklin you…") + an optional suggested
   `plan_cycle` capstone achievement. On failure, the narrative degrades to a
   simple count and the capstone is omitted.
3. Optional capstone reflection field.
4. **Confirm** finalizes the cycle and advances to the recap → CTA.

## Progressive Next Plan

Recap screen shows achievements + narrative + finished cycle number, with a
single CTA **"Start your next 12 weeks."**

`POST /plans/generate-next` with the completed `plan_id`:
1. Load completed plan + `cycle_number` (N) + all cycle `UserAchievement`s.
2. Create `PlanGenerationJob` with `cycle_number = N+1`,
   `previous_plan_id = <completed plan>`, same idol, same `weekly_hours`,
   age-bumped if a birthday passed.
3. Dispatch `run_plan_generation`; return `job_id`.
4. FE polls with **existing machinery** (`onJobIdChanged` → `_startPolling`).
5. Resulting `Plan` carries `cycle_number = N+1` + `previous_plan_id`, so
   `/plans/current` (already scoped to the latest session idol) serves it.

**Idempotency:** `generate-next` keys on `previous_plan_id` — if a job/plan for
cycle N+1 from this parent already exists, return it instead of creating a
duplicate.

### Progressive prompt (`plan_generate.txt`)

A new **optional** block, populated only for cycle ≥ 2:

> **Previous cycle (cycle N):** thesis, completed mission tasks, logged
> achievements.
> Directive: assume mastery of cycle N's foundations — do not repeat them. Open
> at the level cycle N ended. Escalate difficulty, depth, and idol-proximity.
> Reference the user's actual logged achievements so cycle N+1 visibly builds on
> what they did.

When empty (cycle 1) the prompt behaves exactly as today — fully backward
compatible.

## Endpoints Summary

| Endpoint | Purpose |
|---|---|
| `POST /plan-items/{id}/toggle-complete` (extend) | + `planComplete`, `missionTasksRemaining`; stamp/clear `completed_at` |
| `POST /plan-items/{id}/achievement-suggestion` (new) | AI-phrased `{title, category}` + fallback |
| `POST /achievements` (extend) | Save with provenance (`source`, `plan_id`, `plan_item_id`, `cycle_number`) |
| `POST /plans/{id}/cycle-summary` (new) | Narrative + suggested capstone |
| `POST /plans/generate-next` (new) | Enqueue progressive cycle N+1, idempotent |

## Error Handling

- AI suggestion fails/offline → `success_metric` text remains; AI never on the
  critical path.
- Cycle-summary fails → editable achievement list still shows; narrative
  degrades to a count; capstone skippable.
- Un-check after `completed_at`: sticky once next cycle exists; otherwise clears
  and re-hides the finish form.
- Double-generate next cycle → idempotent on `previous_plan_id`.
- Re-confirm an item's achievement → updates existing row (unique constraint).

## Testing

**Backend**
- Migration up/down.
- `toggle-complete` flips `planComplete` only when the last **mission** task
  completes (daily habits ignored); un-check recovery clears `completed_at`
  while no next cycle exists.
- `achievement-suggestion` returns AI text; falls back on timeout/error.
- `generate-next` carries `cycle_number` + `previous_plan_id`; idempotent.
- `/plans/current` returns the newest cycle.
- Prompt render: previous-cycle block present for cycle ≥ 2, absent for cycle 1.

**Frontend**
- Achievement sheet pre-fills `success_metric`, swaps in AI text unless the
  user typed; Confirm saves with provenance; Skip saves nothing.
- Finish form appears on `planComplete`.
- Recap CTA enqueues next plan and reuses existing polling.

## Affected Files (indicative)

**Backend**
- `app/models/user_achievement.py`, `app/models/plan.py`, `app/models/plan_job.py`
- `alembic/versions/<new>.py`
- `app/api/v1/plans.py` (toggle-complete, generate-next, cycle-summary)
- `app/api/v1/achievements.py` (provenance on save)
- `app/tasks/plans.py` (cycle-aware generation context)
- `app/services/planning/generator.py` (thread previous-cycle context)
- `prompts/plan_generate.txt` (optional previous-cycle block)
- `app/schemas/plan.py`, `app/schemas/...` (new request/response fields)

**Frontend**
- `lib/features/plan/data/plan_repository.dart` (new endpoints)
- `lib/features/plan/state/current_plan_provider.dart` (planComplete routing)
- `lib/features/plan/presentation/` (Achievement sheet, Cycle Completion form,
  recap screen)
- `lib/features/plan/models/plan_models.dart` (new fields)
