# Achievements & Progressive Plan Cycles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture AI-phrased user achievements as mission tasks complete, recap them when all mission tasks are done, and generate a progressive next 12-week plan that builds on the finished cycle.

**Architecture:** Extend existing models (`UserAchievement`, `Plan`, `PlanGenerationJob`) with provenance + cycle fields via one Alembic migration. Completion detection piggybacks on the existing `toggle-complete` handler. Two new AI endpoints (achievement suggestion, cycle summary) degrade to deterministic fallbacks so they are never on the critical path. A `generate-next` endpoint reuses the existing `run_plan_generation` Celery task and the existing FE polling. Progression is a new optional block in `plan_generate.txt`, populated only for cycle ≥ 2.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, Celery, Gemini (via `app.services.llm`), Flutter/Riverpod (Dio).

## Global Constraints

- Backend Python tests run with: `cd cmpys/backend && source .venv/bin/activate && python -m pytest <path> -q`
- Backend tests favor pure-function unit tests with hand-rolled fakes (see `tests/test_plan_session_trigger.py`), not live HTTP/DB. Follow that style.
- Alembic head is `t7u8v9w0x1y2`; the new migration's `down_revision` is `t7u8v9w0x1y2`.
- Mission task = `PlanItemType` ∈ {`PROJECT`, `COURSE`, `READING`}. Daily rhythm = {`HABIT`, `PRACTICE`}. Mission tasks gate completion; daily rhythms do not.
- AI calls use `app.services.llm.get_llm_client(fast=True)`; every AI endpoint MUST fall back deterministically on timeout/error.
- New SQLAlchemy enums MUST use `values_callable=lambda e: [x.value for x in e]` (project convention — see `app/models/idol.py`).
- Flutter analyze must stay clean: `cd fe/cmpys && flutter analyze lib`.
- Response schemas use camelCase aliases (see `app/schemas/plan.py`, `app/schemas/achievement.py`).

---

### Task 1: Data model + Alembic migration

**Files:**
- Modify: `cmpys/backend/app/models/user_achievement.py`
- Modify: `cmpys/backend/app/models/plan.py` (class `Plan`)
- Modify: `cmpys/backend/app/models/plan_job.py` (class `PlanGenerationJob`)
- Create: `cmpys/backend/migrations/versions/ach_cycle_0001_achievements_and_plan_cycles.py`
- Test: `cmpys/backend/tests/test_achievement_cycle_models.py`

**Interfaces:**
- Produces: `AchievementSource` enum (`MANUAL="manual"`, `PLAN_ITEM="plan_item"`, `PLAN_CYCLE="plan_cycle"`); `UserAchievement.source`, `.plan_id`, `.plan_item_id`, `.cycle_number`; `Plan.cycle_number`, `.completed_at`, `.previous_plan_id`; `PlanGenerationJob.cycle_number`, `.previous_plan_id`.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_achievement_cycle_models.py`:

```python
"""New columns for achievement provenance and plan cycles exist on the models."""
from app.models.user_achievement import UserAchievement, AchievementSource
from app.models.plan import Plan
from app.models.plan_job import PlanGenerationJob


def test_achievement_source_enum_values():
    assert AchievementSource.MANUAL.value == "manual"
    assert AchievementSource.PLAN_ITEM.value == "plan_item"
    assert AchievementSource.PLAN_CYCLE.value == "plan_cycle"


def test_user_achievement_has_provenance_columns():
    cols = UserAchievement.__table__.columns
    assert "source" in cols
    assert "plan_id" in cols
    assert "plan_item_id" in cols
    assert "cycle_number" in cols


def test_plan_has_cycle_columns():
    cols = Plan.__table__.columns
    assert "cycle_number" in cols
    assert "completed_at" in cols
    assert "previous_plan_id" in cols


def test_plan_generation_job_has_cycle_columns():
    cols = PlanGenerationJob.__table__.columns
    assert "cycle_number" in cols
    assert "previous_plan_id" in cols
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_achievement_cycle_models.py -q`
Expected: FAIL with `ImportError: cannot import name 'AchievementSource'`

- [ ] **Step 3: Add the enum + columns to `user_achievement.py`**

In `app/models/user_achievement.py`, add the enum after `AchievementCategory`:

```python
class AchievementSource(str, Enum):
    MANUAL = "manual"
    PLAN_ITEM = "plan_item"
    PLAN_CYCLE = "plan_cycle"
```

Inside `class UserAchievement`, after `evidence_link`, add:

```python
    source: Mapped[AchievementSource] = mapped_column(
        SQLEnum(
            AchievementSource,
            name="achievement_source",
            values_callable=lambda e: [x.value for x in e],
        ),
        nullable=False,
        default=AchievementSource.MANUAL,
    )
    plan_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plans.id", ondelete="SET NULL"),
        nullable=True,
    )
    plan_item_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_items.id", ondelete="SET NULL"),
        nullable=True,
    )
    cycle_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
```

Add `Integer` to the `sqlalchemy` import line at the top of the file (it currently imports `Date, Enum as SQLEnum, ForeignKey, String, Text`).

- [ ] **Step 4: Add cycle columns to `plan.py`**

Inside `class Plan` (after `weekly_hours`), add:

```python
    cycle_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    previous_plan_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plans.id", ondelete="SET NULL"),
        nullable=True,
    )
```

Ensure `from datetime import datetime` and `from sqlalchemy import DateTime` (or the existing equivalents) are imported at the top of `plan.py`.

- [ ] **Step 5: Add cycle columns to `plan_job.py`**

Inside `class PlanGenerationJob` (after `weekly_hours`), add:

```python
    cycle_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    previous_plan_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False), nullable=True
    )
```

- [ ] **Step 6: Run the model test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_achievement_cycle_models.py -q`
Expected: PASS (4 tests)

- [ ] **Step 7: Write the migration**

Create `cmpys/backend/migrations/versions/ach_cycle_0001_achievements_and_plan_cycles.py`:

```python
"""achievements provenance and plan cycles

Revision ID: ach_cycle_0001
Revises: t7u8v9w0x1y2
Create Date: 2026-06-28

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "ach_cycle_0001"
down_revision: Union[str, None] = "t7u8v9w0x1y2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    achievement_source = sa.Enum(
        "manual", "plan_item", "plan_cycle", name="achievement_source"
    )
    achievement_source.create(op.get_bind(), checkfirst=True)

    op.add_column(
        "user_achievements",
        sa.Column(
            "source", achievement_source, nullable=False, server_default="manual"
        ),
    )
    op.add_column(
        "user_achievements", sa.Column("plan_id", sa.UUID(), nullable=True)
    )
    op.add_column(
        "user_achievements", sa.Column("plan_item_id", sa.UUID(), nullable=True)
    )
    op.add_column(
        "user_achievements",
        sa.Column("cycle_number", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_foreign_key(
        "fk_user_ach_plan", "user_achievements", "plans", ["plan_id"], ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_user_ach_plan_item", "user_achievements", "plan_items",
        ["plan_item_id"], ["id"], ondelete="SET NULL",
    )
    op.create_index(
        "uq_ach_plan_item_source",
        "user_achievements",
        ["plan_item_id"],
        unique=True,
        postgresql_where=sa.text("source = 'plan_item'"),
    )

    op.add_column(
        "plans",
        sa.Column("cycle_number", sa.Integer(), nullable=False, server_default="1"),
    )
    op.add_column(
        "plans", sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "plans", sa.Column("previous_plan_id", sa.UUID(), nullable=True)
    )
    op.create_foreign_key(
        "fk_plan_previous", "plans", "plans", ["previous_plan_id"], ["id"],
        ondelete="SET NULL",
    )

    op.add_column(
        "plan_generation_jobs",
        sa.Column("cycle_number", sa.Integer(), nullable=False, server_default="1"),
    )
    op.add_column(
        "plan_generation_jobs",
        sa.Column("previous_plan_id", sa.UUID(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("plan_generation_jobs", "previous_plan_id")
    op.drop_column("plan_generation_jobs", "cycle_number")
    op.drop_constraint("fk_plan_previous", "plans", type_="foreignkey")
    op.drop_column("plans", "previous_plan_id")
    op.drop_column("plans", "completed_at")
    op.drop_column("plans", "cycle_number")
    op.drop_index("uq_ach_plan_item_source", table_name="user_achievements")
    op.drop_constraint("fk_user_ach_plan_item", "user_achievements", type_="foreignkey")
    op.drop_constraint("fk_user_ach_plan", "user_achievements", type_="foreignkey")
    op.drop_column("user_achievements", "cycle_number")
    op.drop_column("user_achievements", "plan_item_id")
    op.drop_column("user_achievements", "plan_id")
    op.drop_column("user_achievements", "source")
    sa.Enum(name="achievement_source").drop(op.get_bind(), checkfirst=True)
```

- [ ] **Step 8: Verify the migration applies and reverses against a scratch DB**

Run: `cd cmpys/backend && source .venv/bin/activate && alembic upgrade head && alembic downgrade -1 && alembic upgrade head`
Expected: no errors; head ends at `ach_cycle_0001`. (Requires a reachable `DATABASE_URL`; use the local dev DB.)

- [ ] **Step 9: Commit**

```bash
git add cmpys/backend/app/models/user_achievement.py cmpys/backend/app/models/plan.py cmpys/backend/app/models/plan_job.py cmpys/backend/migrations/versions/ach_cycle_0001_achievements_and_plan_cycles.py cmpys/backend/tests/test_achievement_cycle_models.py
git commit -m "feat(backend): add achievement provenance + plan cycle columns"
```

---

### Task 2: Completion detection in toggle-complete

**Files:**
- Modify: `cmpys/backend/app/api/v1/plans.py` (add helper + extend `toggle_item_complete`, ~604-691)
- Modify: `cmpys/backend/app/schemas/plan.py` (class `ToggleCompleteResponse`, ~185)
- Test: `cmpys/backend/tests/test_mission_completion.py`

**Interfaces:**
- Consumes: `PlanItemType` from `app.models.plan`.
- Produces: `MISSION_TYPES: set[PlanItemType]`; `_count_remaining_missions(items: list, completed_item_ids: set[str]) -> int` in `plans.py`; `ToggleCompleteResponse.planComplete: bool`, `.missionTasksRemaining: int`.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_mission_completion.py`:

```python
"""Mission-task completion detection: daily habits never gate completion."""
from types import SimpleNamespace

from app.api.v1.plans import _count_remaining_missions, MISSION_TYPES
from app.models.plan import PlanItemType


def _item(item_id, type_):
    return SimpleNamespace(id=item_id, type=type_)


def test_mission_types_are_project_course_reading():
    assert MISSION_TYPES == {
        PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING
    }


def test_remaining_counts_only_incomplete_missions():
    items = [
        _item("a", PlanItemType.PROJECT),
        _item("b", PlanItemType.READING),
        _item("c", PlanItemType.HABIT),   # daily — ignored
        _item("d", PlanItemType.PRACTICE),  # daily — ignored
    ]
    # only "a" completed; "b" mission still open; habits irrelevant
    assert _count_remaining_missions(items, {"a"}) == 1


def test_remaining_zero_when_all_missions_done():
    items = [
        _item("a", PlanItemType.PROJECT),
        _item("c", PlanItemType.HABIT),
    ]
    assert _count_remaining_missions(items, {"a"}) == 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_mission_completion.py -q`
Expected: FAIL with `ImportError: cannot import name '_count_remaining_missions'`

- [ ] **Step 3: Add the helper and constant to `plans.py`**

Near the top of `app/api/v1/plans.py` (after imports), add:

```python
MISSION_TYPES = {PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING}


def _count_remaining_missions(items, completed_item_ids: set[str]) -> int:
    """Number of mission tasks (project/course/reading) not yet completed.

    Daily rhythm items (habit/practice) never gate plan completion.
    """
    return sum(
        1
        for it in items
        if it.type in MISSION_TYPES and str(it.id) not in completed_item_ids
    )
```

Ensure `PlanItemType` is imported in `plans.py` (it imports from `app.models.plan` already; add `PlanItemType` to that import if absent).

- [ ] **Step 4: Run the helper test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_mission_completion.py -q`
Expected: PASS (3 tests)

- [ ] **Step 5: Extend the schema**

In `app/schemas/plan.py`, change `ToggleCompleteResponse`:

```python
class ToggleCompleteResponse(BaseModel):
    """Response for toggling item completion."""
    completed: bool
    progress: ItemProgress
    planComplete: bool = False
    missionTasksRemaining: int | None = None
```

- [ ] **Step 6: Wire detection into `toggle_item_complete`**

In `app/api/v1/plans.py`, replace the final block of `toggle_item_complete` (the `await db.commit()` … `return ToggleCompleteResponse(...)` at ~683-691) with:

```python
    await db.commit()

    # Recompute progress
    progress, _ = await _compute_item_progress(db, current_user.id, item)

    # Completion detection: count remaining mission tasks across the plan.
    items_stmt = select(PlanItem).where(PlanItem.plan_id == item.plan_id)
    items = (await db.execute(items_stmt)).scalars().all()
    comp_stmt = select(PlanItemCompletion.plan_item_id).where(
        PlanItemCompletion.user_id == current_user.id,
        PlanItemCompletion.completed_at.isnot(None),
        PlanItemCompletion.plan_item_id.in_([str(i.id) for i in items]),
    )
    completed_ids = {str(r) for r in (await db.execute(comp_stmt)).scalars().all()}
    has_missions = any(i.type in MISSION_TYPES for i in items)
    remaining = _count_remaining_missions(items, completed_ids)

    plan = await db.get(Plan, item.plan_id)
    plan_complete = False
    if has_missions and remaining == 0:
        if plan and plan.completed_at is None:
            plan.completed_at = datetime.now(timezone.utc)
            await db.commit()
        plan_complete = True
    elif plan and plan.completed_at is not None and plan.previous_plan_id is None:
        # Re-opened before any next cycle exists: only clear if THIS plan was
        # never used as a parent for a next cycle.
        next_exists = await db.scalar(
            select(func.count())
            .select_from(Plan)
            .where(Plan.previous_plan_id == plan.id)
        )
        if not next_exists:
            plan.completed_at = None
            await db.commit()

    return ToggleCompleteResponse(
        completed=new_completed,
        progress=progress,
        planComplete=plan_complete,
        missionTasksRemaining=remaining if has_missions else None,
    )
```

Confirm `PlanItem`, `Plan`, `func`, `datetime`, `timezone` are imported in `plans.py` (they are used elsewhere in the file; add any missing).

- [ ] **Step 7: Run the full plan test suite**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/ -k "plan or mission or completion" -q`
Expected: PASS (existing + new)

- [ ] **Step 8: Commit**

```bash
git add cmpys/backend/app/api/v1/plans.py cmpys/backend/app/schemas/plan.py cmpys/backend/tests/test_mission_completion.py
git commit -m "feat(backend): detect plan completion from mission tasks in toggle-complete"
```

---

### Task 3: Achievement-suggestion endpoint (AI + fallback)

**Files:**
- Create: `cmpys/backend/app/services/achievements/suggestion.py`
- Modify: `cmpys/backend/app/api/v1/plans.py` (new route on `items_router`)
- Modify: `cmpys/backend/app/schemas/plan.py` (response schema)
- Test: `cmpys/backend/tests/test_achievement_suggestion.py`

**Interfaces:**
- Produces: `fallback_suggestion(item) -> dict` with keys `title`, `category`; `AchievementSuggestionResponse(title: str, category: str)`; route `POST /plan-items/{item_id}/achievement-suggestion`.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_achievement_suggestion.py`:

```python
"""Achievement suggestion falls back to success_metric + mapped category."""
from types import SimpleNamespace

from app.services.achievements.suggestion import fallback_suggestion, category_for_item
from app.models.plan import PlanItemType


def _item(success_metric, type_, domain=None):
    return SimpleNamespace(
        success_metric=success_metric, type=type_, title="t", description="d",
        meta_json={"domain": domain} if domain else None,
    )


def test_fallback_uses_success_metric_as_title():
    item = _item("Wrote a 2-page company teardown", PlanItemType.READING)
    out = fallback_suggestion(item)
    assert out["title"] == "Wrote a 2-page company teardown"
    assert out["category"] == "learning"


def test_category_mapping_for_each_type():
    assert category_for_item(_item("x", PlanItemType.READING)) == "learning"
    assert category_for_item(_item("x", PlanItemType.COURSE)) == "learning"
    assert category_for_item(_item("x", PlanItemType.PROJECT)) == "career"


def test_fallback_handles_empty_success_metric():
    item = _item("", PlanItemType.PROJECT)
    out = fallback_suggestion(item)
    assert out["title"]  # non-empty
    assert out["category"] == "career"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_achievement_suggestion.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'app.services.achievements'`

- [ ] **Step 3: Create the suggestion service**

Create `cmpys/backend/app/services/achievements/__init__.py` (empty) and `cmpys/backend/app/services/achievements/suggestion.py`:

```python
"""Achievement suggestion: AI-phrased line with a deterministic fallback."""
import asyncio
import logging

from app.models.plan import PlanItemType
from app.services.llm import get_llm_client

logger = logging.getLogger(__name__)

_CATEGORY_BY_TYPE = {
    PlanItemType.READING: "learning",
    PlanItemType.COURSE: "learning",
    PlanItemType.PRACTICE: "learning",
    PlanItemType.HABIT: "mindset",
    PlanItemType.PROJECT: "career",
    PlanItemType.REFLECTION: "mindset",
}


def category_for_item(item) -> str:
    return _CATEGORY_BY_TYPE.get(item.type, "other")


def fallback_suggestion(item) -> dict:
    """Instant, no-LLM suggestion derived from the item's success_metric."""
    title = (getattr(item, "success_metric", "") or "").strip()
    if not title:
        title = f"Completed: {(getattr(item, 'title', '') or '').strip()}"
    return {"title": title[:200], "category": category_for_item(item)}


_SUGGESTION_SCHEMA = {
    "type": "object",
    "properties": {"achievement": {"type": "string"}},
    "required": ["achievement"],
}


async def ai_suggestion(item, idol_name: str, timeout_s: float = 2.5) -> dict:
    """AI-phrased achievement; returns fallback on timeout/error.

    Uses the client's only single-shot method, generate_json (returns
    LLMResponse with a `.data` dict and an optional `.error`).
    """
    fb = fallback_suggestion(item)
    try:
        client = get_llm_client(fast=True)
        prompt = (
            f"The user just completed this task while learning from {idol_name}:\n"
            f"Title: {item.title}\nWhat done looks like: {item.success_metric}\n\n"
            "Return JSON {\"achievement\": \"...\"} where the value is ONE "
            "first-person past-tense sentence (max 20 words) the user could log "
            "as a personal achievement. No quotes inside, no preamble."
        )
        resp = await asyncio.wait_for(
            client.generate_json(
                system_prompt="You phrase achievements as JSON.",
                user_prompt=prompt,
                json_schema=_SUGGESTION_SCHEMA,
            ),
            timeout=timeout_s,
        )
        text = ((resp.data or {}).get("achievement") or "").strip().strip('"')
        if not resp.error and text:
            return {"title": text[:200], "category": fb["category"]}
    except Exception as e:  # noqa: BLE001 — fallback is the contract
        logger.info(f"[ACH] AI suggestion fell back: {e}")
    return fb
```

- [ ] **Step 4: Run the fallback test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_achievement_suggestion.py -q`
Expected: PASS (3 tests)

- [ ] **Step 5: Add response schema**

In `app/schemas/plan.py`, add:

```python
class AchievementSuggestionResponse(BaseModel):
    title: str
    category: str
```

- [ ] **Step 6: Add the route**

In `app/api/v1/plans.py`, on `items_router`:

```python
@items_router.post(
    "/{item_id}/achievement-suggestion",
    response_model=AchievementSuggestionResponse,
)
async def achievement_suggestion(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AchievementSuggestionResponse:
    from app.services.achievements.suggestion import ai_suggestion
    item = await _get_item_for_user(db, item_id, current_user.id)
    plan = await db.get(Plan, item.plan_id)
    idol = await db.get(Idol, plan.idol_id) if plan else None
    out = await ai_suggestion(item, idol.name if idol else "your mentor")
    return AchievementSuggestionResponse(**out)
```

Import `AchievementSuggestionResponse` from `app.schemas.plan` and ensure `Idol` is imported in `plans.py`.

- [ ] **Step 7: Verify import wiring**

Run: `cd cmpys/backend && source .venv/bin/activate && python -c "import app.api.v1.plans; print('OK')"`
Expected: `OK`

- [ ] **Step 8: Commit**

```bash
git add cmpys/backend/app/services/achievements/ cmpys/backend/app/api/v1/plans.py cmpys/backend/app/schemas/plan.py cmpys/backend/tests/test_achievement_suggestion.py
git commit -m "feat(backend): achievement-suggestion endpoint with deterministic fallback"
```

---

### Task 4: Provenance on achievement create (upsert per item)

**Files:**
- Modify: `cmpys/backend/app/schemas/achievement.py` (class `AchievementCreate`, `AchievementResponse`)
- Modify: `cmpys/backend/app/api/v1/achievements.py` (`create_achievement`, `_to_response`)
- Test: `cmpys/backend/tests/test_achievement_provenance.py`

**Interfaces:**
- Consumes: `AchievementSource` from Task 1.
- Produces: `AchievementCreate.source`, `.planId`, `.planItemId`, `.cycleNumber`; `_upsert_plan_item_achievement(db, user_id, data) -> UserAchievement` helper that updates an existing row when `(plan_item_id, source=plan_item)` matches.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_achievement_provenance.py`:

```python
"""create payload carries provenance; plan_item achievements upsert."""
from app.schemas.achievement import AchievementCreate
from app.models.user_achievement import AchievementSource


def test_create_schema_accepts_provenance():
    data = AchievementCreate(
        title="Did the thing",
        source="plan_item",
        planId="11111111-1111-1111-1111-111111111111",
        planItemId="22222222-2222-2222-2222-222222222222",
        cycleNumber=1,
    )
    assert data.source == AchievementSource.PLAN_ITEM
    assert data.planItemId.endswith("2222")
    assert data.cycleNumber == 1


def test_create_schema_defaults_to_manual():
    data = AchievementCreate(title="Solo win")
    assert data.source == AchievementSource.MANUAL
    assert data.planItemId is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_achievement_provenance.py -q`
Expected: FAIL (`AchievementCreate` has no field `source`)

- [ ] **Step 3: Extend `AchievementCreate` and `AchievementResponse`**

In `app/schemas/achievement.py`, add to `AchievementCreate`:

```python
    source: AchievementSource = AchievementSource.MANUAL
    planId: str | None = None
    planItemId: str | None = None
    cycleNumber: int = 1
```

Import `from app.models.user_achievement import AchievementSource` at the top. Add the same four (camelCase) fields to `AchievementResponse` so callers can read provenance.

- [ ] **Step 4: Run the schema test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_achievement_provenance.py -q`
Expected: PASS (2 tests)

- [ ] **Step 5: Upsert in the create endpoint**

In `app/api/v1/achievements.py`, replace the body of `create_achievement` with:

```python
    # plan_item achievements upsert: re-confirming an item updates its row.
    if data.source == AchievementSource.PLAN_ITEM and data.planItemId:
        existing = (
            await db.execute(
                select(UserAchievement).where(
                    UserAchievement.user_id == current_user.id,
                    UserAchievement.plan_item_id == data.planItemId,
                    UserAchievement.source == AchievementSource.PLAN_ITEM,
                )
            )
        ).scalar_one_or_none()
        if existing:
            existing.title = data.title
            existing.category = AchievementCategory(data.category.value)
            existing.notes = data.notes
            existing.evidence_link = data.evidenceLink
            await db.commit()
            await db.refresh(existing)
            return _to_response(existing)

    achievement = UserAchievement(
        user_id=current_user.id,
        title=data.title,
        category=AchievementCategory(data.category.value),
        achievement_date=data.achievementDate,
        notes=data.notes,
        evidence_link=data.evidenceLink,
        source=data.source,
        plan_id=data.planId,
        plan_item_id=data.planItemId,
        cycle_number=data.cycleNumber,
    )
    db.add(achievement)
    await db.commit()
    await db.refresh(achievement)
    return _to_response(achievement)
```

Import `AchievementSource` and update `_to_response` to include `source`, `planId`, `planItemId`, `cycleNumber`.

- [ ] **Step 6: Verify import wiring**

Run: `cd cmpys/backend && source .venv/bin/activate && python -c "import app.api.v1.achievements; print('OK')"`
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add cmpys/backend/app/schemas/achievement.py cmpys/backend/app/api/v1/achievements.py cmpys/backend/tests/test_achievement_provenance.py
git commit -m "feat(backend): achievement provenance + per-item upsert"
```

---

### Task 5: Cycle-summary endpoint (AI narrative + capstone, degrade on failure)

**Files:**
- Modify: `cmpys/backend/app/services/achievements/suggestion.py` (add `cycle_summary`)
- Modify: `cmpys/backend/app/api/v1/plans.py` (new route on `router`)
- Modify: `cmpys/backend/app/schemas/plan.py` (response schema)
- Test: `cmpys/backend/tests/test_cycle_summary.py`

**Interfaces:**
- Produces: `fallback_cycle_summary(count: int) -> dict` with keys `narrative`, `capstoneTitle` (None); `CycleSummaryResponse(narrative: str, capstoneTitle: str | None)`; route `POST /plans/{plan_id}/cycle-summary`.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_cycle_summary.py`:

```python
"""Cycle summary degrades to a count-based narrative with no capstone."""
from app.services.achievements.suggestion import fallback_cycle_summary


def test_fallback_uses_count_and_no_capstone():
    out = fallback_cycle_summary(14)
    assert "14" in out["narrative"]
    assert out["capstoneTitle"] is None


def test_fallback_handles_zero():
    out = fallback_cycle_summary(0)
    assert out["narrative"]
    assert out["capstoneTitle"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_cycle_summary.py -q`
Expected: FAIL (`cannot import name 'fallback_cycle_summary'`)

- [ ] **Step 3: Add fallback + AI summary to `suggestion.py`**

Append to `app/services/achievements/suggestion.py`:

```python
def fallback_cycle_summary(count: int) -> dict:
    return {
        "narrative": f"You logged {count} achievement(s) this cycle. Strong work.",
        "capstoneTitle": None,
    }


async def cycle_summary(
    idol_name: str, achievement_titles: list[str], timeout_s: float = 4.0
) -> dict:
    """One-shot narrative recap; degrades to a count-based summary on failure."""
    fb = fallback_cycle_summary(len(achievement_titles))
    if not achievement_titles:
        return fb
    try:
        client = get_llm_client(fast=True)
        bullet = "\n".join(f"- {t}" for t in achievement_titles[:30])
        prompt = (
            f"A user spent 12 weeks learning from {idol_name} and logged:\n"
            f"{bullet}\n\nReturn JSON {{\"narrative\": \"...\", \"capstone\": \"...\"}}. "
            "narrative = 2-3 warm sentences summarizing their progress in second "
            "person ('you'). capstone = one short title naming their single biggest "
            "accomplishment."
        )
        resp = await asyncio.wait_for(
            client.generate_json(
                system_prompt="You write growth recaps as JSON.",
                user_prompt=prompt,
                json_schema=_SUMMARY_SCHEMA,
            ),
            timeout=timeout_s,
        )
        data = resp.data or {}
        narrative = (data.get("narrative") or "").strip()
        if not resp.error and narrative:
            capstone = (data.get("capstone") or "").strip()[:200] or None
            return {"narrative": narrative, "capstoneTitle": capstone}
    except Exception as e:  # noqa: BLE001
        logger.info(f"[ACH] cycle summary fell back: {e}")
    return fb
```

Add the schema constant near the top of the appended section:

```python
_SUMMARY_SCHEMA = {
    "type": "object",
    "properties": {
        "narrative": {"type": "string"},
        "capstone": {"type": "string"},
    },
    "required": ["narrative"],
}
```

- [ ] **Step 4: Run the fallback test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_cycle_summary.py -q`
Expected: PASS (2 tests)

- [ ] **Step 5: Add schema + route**

In `app/schemas/plan.py`:

```python
class CycleSummaryResponse(BaseModel):
    narrative: str
    capstoneTitle: str | None = None
```

In `app/api/v1/plans.py` on `router`:

```python
@router.post("/{plan_id}/cycle-summary", response_model=CycleSummaryResponse)
async def plan_cycle_summary(
    plan_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CycleSummaryResponse:
    from app.services.achievements.suggestion import cycle_summary
    plan = await db.get(Plan, plan_id)
    if not plan or plan.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Plan not found")
    idol = await db.get(Idol, plan.idol_id)
    titles = (
        await db.execute(
            select(UserAchievement.title).where(
                UserAchievement.user_id == current_user.id,
                UserAchievement.plan_id == plan_id,
            )
        )
    ).scalars().all()
    out = await cycle_summary(idol.name if idol else "your mentor", list(titles))
    return CycleSummaryResponse(**out)
```

Ensure `UserAchievement`, `CycleSummaryResponse` are imported in `plans.py`.

- [ ] **Step 6: Verify import wiring**

Run: `cd cmpys/backend && source .venv/bin/activate && python -c "import app.api.v1.plans; print('OK')"`
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add cmpys/backend/app/services/achievements/suggestion.py cmpys/backend/app/api/v1/plans.py cmpys/backend/app/schemas/plan.py cmpys/backend/tests/test_cycle_summary.py
git commit -m "feat(backend): cycle-summary endpoint with count-based fallback"
```

---

### Task 6: Progressive generation context + prompt block

**Files:**
- Modify: `cmpys/backend/app/tasks/plans.py` (build previous-cycle context; set cycle fields on the new `Plan`)
- Modify: `cmpys/backend/app/services/planning/generator.py` (`generate_plan`/`_generate_llm_items` accept `previous_cycle`)
- Modify: `cmpys/backend/prompts/plan_generate.txt` (optional previous-cycle block)
- Test: `cmpys/backend/tests/test_previous_cycle_context.py`

**Interfaces:**
- Produces: `build_previous_cycle_block(cycle_number, prior_thesis, completed_missions, achievements) -> str` in `app/tasks/plans.py` (empty string for cycle 1); a `{previous_cycle_block}` placeholder in `plan_generate.txt`.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_previous_cycle_context.py`:

```python
"""Previous-cycle block is empty for cycle 1, populated for cycle >= 2."""
from app.tasks.plans import build_previous_cycle_block


def test_cycle_one_is_empty():
    assert build_previous_cycle_block(1, "thesis", ["m"], ["a"]) == ""


def test_cycle_two_includes_directive_and_data():
    block = build_previous_cycle_block(
        2, "Master fundamentals", ["Read Security Analysis"], ["Wrote a teardown"]
    )
    assert "cycle 1" in block.lower()
    assert "Master fundamentals" in block
    assert "Read Security Analysis" in block
    assert "Wrote a teardown" in block
    assert "assume mastery" in block.lower()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_previous_cycle_context.py -q`
Expected: FAIL (`cannot import name 'build_previous_cycle_block'`)

- [ ] **Step 3: Implement the builder in `plans.py`**

Add to `app/tasks/plans.py`:

```python
def build_previous_cycle_block(
    cycle_number: int,
    prior_thesis: str,
    completed_missions: list[str],
    achievements: list[str],
) -> str:
    """Render the previous-cycle directive. Empty for cycle 1 (backward compat)."""
    if cycle_number < 2:
        return ""
    prev = cycle_number - 1
    missions = "\n".join(f"- {m}" for m in completed_missions[:20]) or "- (none)"
    wins = "\n".join(f"- {a}" for a in achievements[:20]) or "- (none)"
    return (
        f"## PREVIOUS CYCLE (cycle {prev}) — THIS IS CYCLE {cycle_number}\n"
        f"Prior thesis: {prior_thesis}\n"
        f"Completed mission tasks:\n{missions}\n"
        f"Logged achievements:\n{wins}\n\n"
        "Directive: assume mastery of cycle "
        f"{prev}'s foundations — do NOT repeat them. Open at the level cycle "
        f"{prev} ended. Escalate difficulty, depth, and idol-proximity. Reference "
        "the user's actual logged achievements so this cycle visibly builds on them.\n"
    )
```

- [ ] **Step 4: Run the builder test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_previous_cycle_context.py -q`
Expected: PASS (2 tests)

- [ ] **Step 5: Add the placeholder to the prompt**

In `cmpys/backend/prompts/plan_generate.txt`, insert on its own line just before `## YOUR OBJECTIVE`:

```
{previous_cycle_block}
```

- [ ] **Step 6: Thread the block through the generator**

In `app/services/planning/generator.py`, add a `previous_cycle_block: str = ""` kwarg to `generate_plan` and `_generate_llm_items`, and include it in the `render_prompt(...)` variables dict as `"previous_cycle_block": previous_cycle_block`. In `_generate_deterministic_items` it is ignored.

In `app/tasks/plans.py` `_run_plan_generation_async`, before calling `generate_plan(...)`, build the block from the job's cycle fields and the prior plan, and pass it:

```python
previous_cycle_block = ""
if job.cycle_number and job.cycle_number >= 2 and job.previous_plan_id:
    prior = await db.get(Plan, job.previous_plan_id)
    prior_items = (await db.execute(
        select(PlanItem).where(PlanItem.plan_id == job.previous_plan_id)
    )).scalars().all() if prior else []
    completed_missions = [
        i.title for i in prior_items if i.type in {
            PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING}
    ]
    ach_titles = (await db.execute(
        select(UserAchievement.title).where(
            UserAchievement.plan_id == job.previous_plan_id)
    )).scalars().all()
    prior_thesis = (prior.roadmap_json or {}).get("roadmap_thesis", "") if prior else ""
    previous_cycle_block = build_previous_cycle_block(
        job.cycle_number,
        prior_thesis,
        completed_missions,
        list(ach_titles),
    )
```

Pass `previous_cycle_block=previous_cycle_block` into the `generate_plan(...)` call. Ensure `PlanItem`, `UserAchievement`, `PlanItemType`, `Plan` are imported in `plans.py`.

- [ ] **Step 7: Set cycle fields on the created Plan**

In `app/tasks/plans.py`, where the `Plan(...)` row is built (~341, currently `idol_id=job.idol_id`), add:

```python
                cycle_number=job.cycle_number or 1,
                previous_plan_id=job.previous_plan_id,
```

- [ ] **Step 8: Run a prompt-render smoke test**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_previous_cycle_context.py tests/test_prompt_placeholders.py -q`
Expected: PASS (the placeholder renders; cycle-1 path stays empty)

- [ ] **Step 9: Commit**

```bash
git add cmpys/backend/app/tasks/plans.py cmpys/backend/app/services/planning/generator.py cmpys/backend/prompts/plan_generate.txt cmpys/backend/tests/test_previous_cycle_context.py
git commit -m "feat(backend): progressive plan context for cycle >= 2"
```

---

### Task 7: generate-next endpoint (idempotent)

**Files:**
- Modify: `cmpys/backend/app/api/v1/plans.py` (new route on `router`)
- Modify: `cmpys/backend/app/schemas/plan.py` (response reuse `IdolImportResponse`)
- Test: `cmpys/backend/tests/test_generate_next.py`

**Interfaces:**
- Consumes: `PlanGenerationJob.cycle_number`, `.previous_plan_id` (Task 1); `run_plan_generation`.
- Produces: route `POST /plans/{plan_id}/generate-next` returning `IdolImportResponse`; helper `_existing_next_job(db, previous_plan_id) -> PlanGenerationJob | None`.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_generate_next.py`:

```python
"""Idempotency helper: an existing job for the parent is reused."""
from types import SimpleNamespace
import pytest

from app.api.v1.plans import _next_cycle_fields


def test_next_cycle_increments_and_links():
    prev = SimpleNamespace(
        id="p1", cycle_number=2, idol_id="i1", weekly_hours=10, target_age=25
    )
    fields = _next_cycle_fields(prev)
    assert fields["cycle_number"] == 3
    assert fields["previous_plan_id"] == "p1"
    assert fields["idol_id"] == "i1"
    assert fields["weekly_hours"] == 10
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_generate_next.py -q`
Expected: FAIL (`cannot import name '_next_cycle_fields'`)

- [ ] **Step 3: Add the pure helper + route**

In `app/api/v1/plans.py`:

```python
def _next_cycle_fields(prev_plan) -> dict:
    """Fields for the next cycle's PlanGenerationJob, derived from the parent."""
    return {
        "cycle_number": (prev_plan.cycle_number or 1) + 1,
        "previous_plan_id": str(prev_plan.id),
        "idol_id": prev_plan.idol_id,
        "weekly_hours": prev_plan.weekly_hours,
        "duration_weeks": prev_plan.duration_weeks,
        "target_age": prev_plan.target_age,
    }


@router.post("/{plan_id}/generate-next", response_model=IdolImportResponse,
             status_code=status.HTTP_201_CREATED)
async def generate_next_plan(
    plan_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IdolImportResponse:
    prev = await db.get(Plan, plan_id)
    if not prev or prev.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Plan not found")

    # Idempotent: reuse an existing job for this parent.
    existing = (
        await db.execute(
            select(PlanGenerationJob)
            .where(PlanGenerationJob.previous_plan_id == str(prev.id))
            .order_by(PlanGenerationJob.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing:
        return IdolImportResponse(
            idolId=existing.idol_id, jobId=str(existing.id), status=existing.status
        )

    fields = _next_cycle_fields(prev)
    job = PlanGenerationJob(
        user_id=current_user.id,
        session_id=None,
        focus=None,
        status="pending",
        progress_percent=0,
        step="analyzing_gaps",
        **fields,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    from app.tasks.plans import run_plan_generation
    run_plan_generation.delay(str(job.id))
    return IdolImportResponse(idolId=job.idol_id, jobId=str(job.id), status="pending")
```

Ensure `PlanGenerationJob` and `IdolImportResponse` are imported in `plans.py`.

- [ ] **Step 4: Run the helper test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_generate_next.py -q`
Expected: PASS

- [ ] **Step 5: Full backend suite**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/ -q`
Expected: PASS (all)

- [ ] **Step 6: Commit**

```bash
git add cmpys/backend/app/api/v1/plans.py cmpys/backend/tests/test_generate_next.py
git commit -m "feat(backend): idempotent generate-next endpoint for progressive cycles"
```

---

### Task 8: Frontend — models + repository methods

**Files:**
- Modify: `fe/cmpys/lib/features/plan/models/plan_models.dart`
- Modify: `fe/cmpys/lib/features/plan/data/plan_repository.dart`
- Test: `fe/cmpys/test/plan_toggle_complete_test.dart`

**Interfaces:**
- Produces: `ToggleResult(completed: bool, planComplete: bool, missionTasksRemaining: int?)`; `PlanRepository.toggleItemComplete` returns `ToggleResult`; `fetchAchievementSuggestion(itemId) -> ({String title, String category})`; `saveAchievement({...}) -> void`; `fetchCycleSummary(planId) -> ({String narrative, String? capstoneTitle})`; `generateNext(planId) -> String jobId`.

- [ ] **Step 1: Write the failing test**

Create `fe/cmpys/test/plan_toggle_complete_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';

void main() {
  test('ToggleResult parses planComplete and missionTasksRemaining', () {
    final r = ToggleResult.fromJson({
      'completed': true,
      'planComplete': true,
      'missionTasksRemaining': 0,
    });
    expect(r.completed, true);
    expect(r.planComplete, true);
    expect(r.missionTasksRemaining, 0);
  });

  test('ToggleResult defaults planComplete to false', () {
    final r = ToggleResult.fromJson({'completed': false});
    expect(r.planComplete, false);
    expect(r.missionTasksRemaining, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd fe/cmpys && flutter test test/plan_toggle_complete_test.dart`
Expected: FAIL (`ToggleResult` undefined)

- [ ] **Step 3: Add `ToggleResult` model**

In `fe/cmpys/lib/features/plan/models/plan_models.dart`:

```dart
class ToggleResult {
  const ToggleResult({
    required this.completed,
    this.planComplete = false,
    this.missionTasksRemaining,
  });

  final bool completed;
  final bool planComplete;
  final int? missionTasksRemaining;

  factory ToggleResult.fromJson(Map<String, dynamic> j) => ToggleResult(
        completed: j['completed'] as bool? ?? false,
        planComplete: j['planComplete'] as bool? ?? false,
        missionTasksRemaining: (j['missionTasksRemaining'] as num?)?.toInt(),
      );
}
```

- [ ] **Step 4: Run the model test to verify it passes**

Run: `cd fe/cmpys && flutter test test/plan_toggle_complete_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Update repository methods**

In `fe/cmpys/lib/features/plan/data/plan_repository.dart`, change `toggleItemComplete` to return `ToggleResult` (parse the full body, not just `completed`). Add:

```dart
  Future<({String title, String category})> fetchAchievementSuggestion(
      String itemId) async {
    final r = await _dioClient.post('/plan-items/$itemId/achievement-suggestion');
    final d = r.data as Map<String, dynamic>;
    return (title: d['title'] as String? ?? '', category: d['category'] as String? ?? 'other');
  }

  Future<void> saveAchievement({
    required String title,
    required String category,
    String? notes,
    String? evidenceLink,
    required String source,
    String? planId,
    String? planItemId,
    int cycleNumber = 1,
  }) async {
    await _dioClient.post('/achievements', data: {
      'title': title,
      'category': category,
      'source': source,
      if (planId != null) 'planId': planId,
      if (planItemId != null) 'planItemId': planItemId,
      'cycleNumber': cycleNumber,
      if (notes != null) 'notes': notes,
      if (evidenceLink != null) 'evidenceLink': evidenceLink,
    });
  }

  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(
      String planId) async {
    final r = await _dioClient.post('/plans/$planId/cycle-summary');
    final d = r.data as Map<String, dynamic>;
    return (narrative: d['narrative'] as String? ?? '',
        capstoneTitle: d['capstoneTitle'] as String?);
  }

  Future<String> generateNext(String planId) async {
    final r = await _dioClient.post('/plans/$planId/generate-next');
    return (r.data as Map<String, dynamic>)['jobId'] as String? ?? '';
  }
```

Update the existing `toggleItemComplete` caller(s) for the new return type (search `toggleItemComplete(`), adjusting any `bool` usage to `.completed`.

- [ ] **Step 6: Analyze**

Run: `cd fe/cmpys && flutter analyze lib test/plan_toggle_complete_test.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add fe/cmpys/lib/features/plan/models/plan_models.dart fe/cmpys/lib/features/plan/data/plan_repository.dart fe/cmpys/test/plan_toggle_complete_test.dart
git commit -m "feat(fe): plan repo methods + ToggleResult for achievement cycles"
```

---

### Task 9: Frontend — achievement sheet on mission-task completion

**Files:**
- Create: `fe/cmpys/lib/features/plan/presentation/achievement_sheet.dart`
- Modify: the widget that calls `toggleItemComplete` (search `toggleItemComplete(` under `lib/features/plan/presentation/` — likely `plan_item_detail_screen.dart` and/or `plan_screen.dart`)
- Test: `fe/cmpys/test/achievement_sheet_test.dart`

**Interfaces:**
- Consumes: `PlanRepository.fetchAchievementSuggestion`, `saveAchievement`; `ToggleResult`.
- Produces: `showAchievementSheet(BuildContext, {required PlanItem item, required String planId, required int cycleNumber})` that opens a modal pre-filled with `item.successMetric`, swaps in the AI suggestion unless the user typed, and Confirm/Skip.

- [ ] **Step 1: Write the failing widget test**

Create `fe/cmpys/test/achievement_sheet_test.dart` exercising the sheet's pure presenter logic: a `AchievementSheetState` class that holds `text`, `userEdited`, and an `applySuggestion(String)` method that only overwrites when `!userEdited`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plan/presentation/achievement_sheet.dart';

void main() {
  test('AI suggestion applies only when user has not typed', () {
    final s = AchievementSheetState(initial: 'metric line');
    s.applySuggestion('AI line');
    expect(s.text, 'AI line');

    s.onUserType('my own words');
    s.applySuggestion('late AI line');
    expect(s.text, 'my own words'); // not overwritten
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd fe/cmpys && flutter test test/achievement_sheet_test.dart`
Expected: FAIL (`achievement_sheet.dart` / `AchievementSheetState` undefined)

- [ ] **Step 3: Implement `AchievementSheetState` + the sheet**

Create `fe/cmpys/lib/features/plan/presentation/achievement_sheet.dart` with:

```dart
class AchievementSheetState {
  AchievementSheetState({required String initial}) : text = initial;
  String text;
  bool userEdited = false;

  void onUserType(String value) {
    userEdited = true;
    text = value;
  }

  void applySuggestion(String suggestion) {
    if (!userEdited && suggestion.trim().isNotEmpty) text = suggestion;
  }
}
```

Then add `Future<void> showAchievementSheet(...)` below it: a `showModalBottomSheet` that (1) seeds a `TextEditingController` with `item.successMetric`, (2) fires `fetchAchievementSuggestion(item.id)` and on return calls `applySuggestion` + updates the controller only if `!userEdited`, (3) Confirm → `saveAchievement(source: 'plan_item', planItemId: item.id, planId: planId, cycleNumber: cycleNumber, ...)` then closes, (4) Skip → just closes. Follow the styling of existing sheets/cards (`CmpysCardSurface`, `AppTypography`, `AppColors`).

- [ ] **Step 4: Run the presenter test to verify it passes**

Run: `cd fe/cmpys && flutter test test/achievement_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Trigger the sheet on mission-task completion**

In the completion handler that calls `toggleItemComplete`, after awaiting the `ToggleResult`: if the item is a mission task (`item.type` is project/course/reading) AND `result.completed == true`, call `showAchievementSheet(context, item: item, planId: plan.id, cycleNumber: plan.cycleNumber)`. For the plan-complete branch, add `if (result.planComplete) { /* cycle completion — implemented in Task 10 */ }` with an empty body for now; Task 10 fills this exact branch. `showCycleCompletion` is defined in Task 10 (see its Interfaces block).

- [ ] **Step 6: Analyze**

Run: `cd fe/cmpys && flutter analyze lib test/achievement_sheet_test.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add fe/cmpys/lib/features/plan/presentation/achievement_sheet.dart fe/cmpys/test/achievement_sheet_test.dart
git add -u fe/cmpys/lib/features/plan/presentation/
git commit -m "feat(fe): achievement sheet on mission-task completion"
```

---

### Task 10: Frontend — cycle completion form, recap, next-plan CTA

**Files:**
- Create: `fe/cmpys/lib/features/plan/presentation/cycle_completion_screen.dart`
- Modify: `fe/cmpys/lib/features/plan/state/current_plan_provider.dart` (expose `generateNext` via existing job polling)
- Modify: the Task 9 completion handler (the empty `if (result.planComplete) { }` branch)
- Test: `fe/cmpys/test/cycle_completion_test.dart`

**Interfaces:**
- Consumes: `PlanRepository.fetchCycleSummary`, `generateNext`, `saveAchievement`; `CurrentPlanController.onJobIdChanged` (existing).
- Produces: `showCycleCompletion(BuildContext, {required PlanModel plan})`; on CTA, calls `generateNext(plan.id)` then `cmpysStoreProvider.notifier.setPlanJobId(jobId)` so existing polling drives the new cycle.

- [ ] **Step 1: Write the failing test**

Create `fe/cmpys/test/cycle_completion_test.dart` testing a pure presenter `CycleCompletionPresenter` with a fake repo: `start()` loads the summary (falls back to `''`→ shows count text), and `startNextCycle()` returns the job id from `generateNext` and forwards it to a captured `onJobId` callback.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plan/presentation/cycle_completion_screen.dart';

class _FakeRepo implements CycleCompletionRepo {
  @override
  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(String id) async =>
      (narrative: 'You did great', capstoneTitle: 'Shipped MVP');
  @override
  Future<String> generateNext(String id) async => 'job-123';
}

void main() {
  test('startNextCycle forwards the new job id', () async {
    String? captured;
    final p = CycleCompletionPresenter(
      planId: 'p1', repo: _FakeRepo(), onJobId: (j) => captured = j);
    await p.start();
    expect(p.narrative, 'You did great');
    final job = await p.startNextCycle();
    expect(job, 'job-123');
    expect(captured, 'job-123');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd fe/cmpys && flutter test test/cycle_completion_test.dart`
Expected: FAIL (`cycle_completion_screen.dart` undefined)

- [ ] **Step 3: Implement presenter + repo interface**

Create `fe/cmpys/lib/features/plan/presentation/cycle_completion_screen.dart`:

```dart
abstract class CycleCompletionRepo {
  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(String id);
  Future<String> generateNext(String id);
}

class CycleCompletionPresenter {
  CycleCompletionPresenter({
    required this.planId,
    required this.repo,
    required this.onJobId,
  });
  final String planId;
  final CycleCompletionRepo repo;
  final void Function(String jobId) onJobId;

  String narrative = '';
  String? capstoneTitle;

  Future<void> start() async {
    final s = await repo.fetchCycleSummary(planId);
    narrative = s.narrative;
    capstoneTitle = s.capstoneTitle;
  }

  Future<String> startNextCycle() async {
    final job = await repo.generateNext(planId);
    if (job.isNotEmpty) onJobId(job);
    return job;
  }
}
```

- [ ] **Step 4: Run the presenter test to verify it passes**

Run: `cd fe/cmpys && flutter test test/cycle_completion_test.dart`
Expected: PASS

- [ ] **Step 5: Build the screen widget + wire the CTA**

Add a `showCycleCompletion(BuildContext, {required PlanModel plan})` that renders the recap (achievements list grouped, `presenter.narrative`, capstone), with a single CTA "Start your next 12 weeks" calling `presenter.startNextCycle()`. The `onJobId` callback does `ref.read(cmpysStoreProvider.notifier).setPlanJobId(jobId)` — reusing the existing polling path (`onJobIdChanged` → `_startPolling`) so no new polling code is needed. `PlanRepository` satisfies `CycleCompletionRepo` (it already has both methods from Task 8).

- [ ] **Step 6: Fill the Task 9 plan-complete branch**

In the completion handler, fill the empty `if (result.planComplete) { }` branch left in Task 9 Step 5 with: `if (result.planComplete) { await showCycleCompletion(context, plan: plan); }`.

- [ ] **Step 7: Analyze + run the FE plan tests**

Run: `cd fe/cmpys && flutter analyze lib && flutter test test/plan_toggle_complete_test.dart test/achievement_sheet_test.dart test/cycle_completion_test.dart`
Expected: No analyzer issues; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add fe/cmpys/lib/features/plan/presentation/cycle_completion_screen.dart fe/cmpys/lib/features/plan/state/current_plan_provider.dart fe/cmpys/test/cycle_completion_test.dart
git add -u fe/cmpys/lib/features/plan/presentation/
git commit -m "feat(fe): cycle completion recap + progressive next-plan CTA"
```

---

## Final verification

- [ ] Backend: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/ -q` — all pass.
- [ ] Backend import smoke: `python -c "import app.main; print('OK')"`.
- [ ] Migration round-trips: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
- [ ] Frontend: `cd fe/cmpys && flutter analyze lib && flutter test` — clean + green.
- [ ] Manual: complete the last mission task of a plan against a dev backend → achievement sheet appears → confirm → cycle completion recap → "Start your next 12 weeks" generates a cycle-2 plan that `/plans/current` then serves.
