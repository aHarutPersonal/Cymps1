# Real Comparison Scores Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Compare screen's seeded dimension scores + milestones with LLM-generated values grounded in the user's interview and the idol's verified facts.

**Architecture:** After the comparison prose persists in `generate-results`, a separate `generate_json` scorer produces structured `{dimensions, milestones}`, normalized server-side to the 5 fixed dimension ids and persisted to a new `intake_sessions.comparison_scores_json` column. The session response surfaces it as `comparisonScores`; the Flutter store converts it to typed dims/milestones and the Compare screen reads real-or-seed via `liveDims()` / `liveMilestones()`.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, Gemini (`app.services.llm`), Flutter/Riverpod, freezed.

## Global Constraints

- Backend tests: `cd cmpys/backend && source .venv/bin/activate && python -m pytest <path> -q`. Style = pure-function unit tests with hand-rolled fakes (see `tests/test_plan_session_trigger.py`).
- Alembic head is `ach_cycle_0001`; the new migration's `down_revision` is `ach_cycle_0001`.
- The 5 fixed dimension ids are EXACTLY: `capital`, `knowledge`, `habits`, `network`, `clarity` (these match the FE radar + `_dimShort` map). The scorer must always emit all 5.
- Dimension scores `you`/`idol` are integers clamped 0–100.
- AI calls use `app.services.llm.get_llm_client()` and MUST degrade: a scorer failure leaves `comparison_scores_json` null and never breaks the results stream.
- New SQLAlchemy enums (none here) would use `values_callable`; not needed this plan.
- New prompt placeholders must be registered in `PROMPT_PLACEHOLDERS` in `app/services/llm/prompt_loader.py`, or strict render raises.
- Flutter: `cd fe/cmpys && flutter analyze lib` stays clean; freezed model changes require `dart run build_runner build --delete-conflicting-outputs`.
- Response/session JSON keys: the session response uses snake_case for existing keys (`comparison_output`); add the new key as `comparisonScores` (the FE reads it as `json['comparisonScores']`).

---

### Task 1: Backend — migration + model column

**Files:**
- Modify: `cmpys/backend/app/models/intake.py` (class `IntakeSession`)
- Create: `cmpys/backend/migrations/versions/cmp_scores_0001_comparison_scores.py`
- Test: `cmpys/backend/tests/test_comparison_scores_column.py`

**Interfaces:**
- Produces: `IntakeSession.comparison_scores_json: dict | None` (JSONB).

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_comparison_scores_column.py`:

```python
"""The comparison_scores_json column exists on IntakeSession."""
from app.models.intake import IntakeSession


def test_intake_session_has_comparison_scores_column():
    assert "comparison_scores_json" in IntakeSession.__table__.columns
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_comparison_scores_column.py -q`
Expected: FAIL (KeyError / assertion — column absent).

- [ ] **Step 3: Add the column**

In `app/models/intake.py`, after the `idol_facts_json` column, add:

```python
    # Structured comparison scores (dimensions + milestones) generated after the
    # prose comparison. Null until generated / if generation fails.
    comparison_scores_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )
```

(`JSONB` and `Mapped`/`mapped_column` are already imported in this file.)

- [ ] **Step 4: Run the model test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_comparison_scores_column.py -q`
Expected: PASS.

- [ ] **Step 5: Write the migration**

Create `cmpys/backend/migrations/versions/cmp_scores_0001_comparison_scores.py`:

```python
"""comparison scores json on intake_sessions

Revision ID: cmp_scores_0001
Revises: ach_cycle_0001
Create Date: 2026-06-29

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "cmp_scores_0001"
down_revision: Union[str, None] = "ach_cycle_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "intake_sessions",
        sa.Column("comparison_scores_json", postgresql.JSONB(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("intake_sessions", "comparison_scores_json")
```

- [ ] **Step 6: Verify migration round-trips**

Run: `cd cmpys/backend && source .venv/bin/activate && alembic upgrade head && alembic downgrade -1 && alembic upgrade head`
Expected: no errors; head ends at `cmp_scores_0001`. (Uses the local dev DB.)

- [ ] **Step 7: Commit**

```bash
git add cmpys/backend/app/models/intake.py cmpys/backend/migrations/versions/cmp_scores_0001_comparison_scores.py cmpys/backend/tests/test_comparison_scores_column.py
git commit -m "feat(backend): add comparison_scores_json column to intake_sessions"
```

---

### Task 2: Backend — scorer service + prompt + normalization

**Files:**
- Create: `cmpys/backend/app/services/comparison/__init__.py`
- Create: `cmpys/backend/app/services/comparison/scoring.py`
- Create: `cmpys/backend/prompts/comparison_scores.txt`
- Modify: `cmpys/backend/app/services/llm/prompt_loader.py` (`PROMPT_PLACEHOLDERS`)
- Test: `cmpys/backend/tests/test_comparison_scoring.py`

**Interfaces:**
- Produces:
  - `FIXED_DIMENSIONS: list[dict]` — the 5 seed-default dims.
  - `normalize_comparison_scores(raw: dict | None) -> dict` — always returns `{"dimensions": [5 dicts in fixed order], "milestones": [<=5 dicts]}`; fills missing dims from seed, clamps you/idol to 0–100, caps milestones at 5.
  - `async generate_comparison_scores(client, idol_name, user_age, user_profile_json, interview_transcript_json, idol_facts_json, comparison_summary) -> dict | None` — renders `comparison_scores.txt`, calls `generate_json` (one retry on error), returns `normalize_comparison_scores(...)` or `None` on failure.

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_comparison_scoring.py`:

```python
"""normalize_comparison_scores always yields the 5 fixed dims, clamped."""
from app.services.comparison.scoring import (
    normalize_comparison_scores,
    FIXED_DIMENSIONS,
)

FIXED_IDS = ["capital", "knowledge", "habits", "network", "clarity"]


def test_fixed_dimensions_are_the_five_ids():
    assert [d["id"] for d in FIXED_DIMENSIONS] == FIXED_IDS


def test_none_returns_full_seed_five_dims():
    out = normalize_comparison_scores(None)
    assert [d["id"] for d in out["dimensions"]] == FIXED_IDS
    assert out["milestones"] == []


def test_clamps_scores_and_fills_missing_dims():
    raw = {
        "dimensions": [
            {"id": "capital", "label": "Capital", "you": 250, "idol": -5,
             "you_note": "a", "idol_note": "b"},
            {"id": "knowledge", "label": "Knowledge", "you": 30, "idol": 80,
             "you_note": "c", "idol_note": "d"},
        ],
        "milestones": [{"text": "Wrote a philosophy", "hit_by_age": 21}],
    }
    out = normalize_comparison_scores(raw)
    assert [d["id"] for d in out["dimensions"]] == FIXED_IDS  # all 5 present
    cap = next(d for d in out["dimensions"] if d["id"] == "capital")
    assert cap["you"] == 100 and cap["idol"] == 0  # clamped
    assert out["milestones"][0]["id"] == "m1"
    assert out["milestones"][0]["label"] == "Wrote a philosophy"


def test_milestones_capped_at_five():
    raw = {"milestones": [{"text": f"m{i}"} for i in range(9)]}
    out = normalize_comparison_scores(raw)
    assert len(out["milestones"]) == 5
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_comparison_scoring.py -q`
Expected: FAIL (`ModuleNotFoundError: app.services.comparison`).

- [ ] **Step 3: Create the scorer service**

Create `cmpys/backend/app/services/comparison/__init__.py` (empty), and `cmpys/backend/app/services/comparison/scoring.py`:

```python
"""Structured comparison scores: a separate JSON scorer with a seed fallback."""
import asyncio
import logging

from app.services.llm.prompt_loader import load_and_render

logger = logging.getLogger(__name__)

# Fixed dimensions — ids MUST match the FE radar (capital/knowledge/habits/
# network/clarity). Seed values fill any dimension the model omits so the radar
# always has 5 axes.
FIXED_DIMENSIONS: list[dict] = [
    {"id": "capital", "label": "Capital at work", "you": 35, "idol": 70,
     "you_note": "", "idol_note": ""},
    {"id": "knowledge", "label": "Knowledge base", "you": 45, "idol": 85,
     "you_note": "", "idol_note": ""},
    {"id": "habits", "label": "Daily discipline", "you": 40, "idol": 80,
     "you_note": "", "idol_note": ""},
    {"id": "network", "label": "Trusted network", "you": 35, "idol": 65,
     "you_note": "", "idol_note": ""},
    {"id": "clarity", "label": "Strategic clarity", "you": 45, "idol": 78,
     "you_note": "", "idol_note": ""},
]

_SCORES_SCHEMA = {
    "type": "object",
    "properties": {
        "dimensions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "label": {"type": "string"},
                    "you": {"type": "integer"},
                    "idol": {"type": "integer"},
                    "you_note": {"type": "string"},
                    "idol_note": {"type": "string"},
                },
                "required": ["id", "you", "idol"],
            },
        },
        "milestones": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "hit_by_age": {"type": "integer"},
                },
                "required": ["text"],
            },
        },
    },
    "required": ["dimensions", "milestones"],
}


def _clamp(v, lo=0, hi=100) -> int:
    try:
        return max(lo, min(hi, int(v)))
    except (TypeError, ValueError):
        return lo


def normalize_comparison_scores(raw: dict | None) -> dict:
    """Always return {dimensions:[5 fixed, in order], milestones:[<=5]}.

    Fills any missing dimension from FIXED_DIMENSIONS, clamps you/idol to
    0-100, and assigns positional milestone ids (m1..m5) so the FE claim map
    stays stable.
    """
    raw = raw or {}
    by_id = {}
    for d in raw.get("dimensions") or []:
        if isinstance(d, dict) and d.get("id") in {x["id"] for x in FIXED_DIMENSIONS}:
            by_id[d["id"]] = d

    dimensions = []
    for seed in FIXED_DIMENSIONS:
        d = by_id.get(seed["id"])
        if d:
            dimensions.append({
                "id": seed["id"],
                "label": (d.get("label") or seed["label"]),
                "you": _clamp(d.get("you", seed["you"])),
                "idol": _clamp(d.get("idol", seed["idol"])),
                "you_note": (d.get("you_note") or "").strip(),
                "idol_note": (d.get("idol_note") or "").strip(),
            })
        else:
            dimensions.append(dict(seed))

    milestones = []
    for i, m in enumerate((raw.get("milestones") or [])[:5]):
        if not isinstance(m, dict):
            continue
        text = (m.get("text") or "").strip()
        if not text:
            continue
        milestones.append({
            "id": f"m{i + 1}",
            "label": text,
            "hit_by_age": _clamp(m.get("hit_by_age", 0), 0, 200),
        })

    return {"dimensions": dimensions, "milestones": milestones}


async def generate_comparison_scores(
    client,
    *,
    idol_name: str,
    user_age,
    user_profile_json: str,
    interview_transcript_json: str,
    idol_facts_json: str,
    comparison_summary: str,
    timeout_s: float = 25.0,
) -> dict | None:
    """Generate structured scores. Returns normalized dict, or None on failure
    (caller falls back to the FE seed). Never raises."""
    try:
        prompt = load_and_render(
            "comparison_scores.txt",
            {
                "idol_name": idol_name,
                "user_age": str(user_age),
                "user_profile_json": user_profile_json,
                "interview_transcript_json": interview_transcript_json,
                "idol_facts_json": idol_facts_json,
                "comparison_summary": comparison_summary[:2000],
            },
            strict=True,
        )
        resp = await asyncio.wait_for(
            client.generate_json(
                system_prompt="You output ONLY valid JSON comparison scores.",
                user_prompt=prompt,
                json_schema=_SCORES_SCHEMA,
            ),
            timeout=timeout_s,
        )
        if resp.error:
            # one fresh retry — Gemini JSON is non-deterministic
            resp = await asyncio.wait_for(
                client.generate_json(
                    system_prompt="You output ONLY valid, minified JSON.",
                    user_prompt=prompt,
                    json_schema=_SCORES_SCHEMA,
                ),
                timeout=timeout_s,
            )
        if resp.error or not resp.data:
            logger.warning(f"[CMP_SCORES] scorer failed: {resp.error}")
            return None
        return normalize_comparison_scores(resp.data)
    except Exception as e:  # noqa: BLE001 — fallback is the contract
        logger.warning(f"[CMP_SCORES] scorer exception: {e}")
        return None
```

- [ ] **Step 4: Create the prompt**

Create `cmpys/backend/prompts/comparison_scores.txt`:

```
You are scoring how this person compares to {idol_name} at age {user_age}, on five fixed dimensions. Output ONLY JSON.

THE PERSON (profile): {user_profile_json}

WHAT THEY SAID IN THE INTERVIEW:
{interview_transcript_json}

VERIFIED FACTS ABOUT {idol_name} BY AGE {user_age}:
{idol_facts_json}

THE HONEST COMPARISON ALREADY DELIVERED (for grounding):
{comparison_summary}

Score these EXACT five dimension ids (do not rename or add any):
- "capital"  (Capital at work — money/assets actually compounding)
- "knowledge" (Knowledge base — depth in the idol's domain)
- "habits"   (Daily discipline — consistency of the right daily actions)
- "network"  (Trusted network — mentors/peers compounding their growth)
- "clarity"  (Strategic clarity — a written, statable philosophy/system)

For EACH dimension give:
- "you": integer 0-100, grounded in what the person revealed. Be fair, not harsh.
- "idol": integer 0-100, grounded in the verified facts at the same age.
- "you_note": one concrete sentence (max 18 words) about the person's current state.
- "idol_note": one concrete sentence (max 18 words) about the idol at that age, factual.

Also give "milestones": 5 SPECIFIC things {idol_name} had achieved by age {user_age} (from the verified facts), each as {"text": "...", "hit_by_age": <int>}. Each text is a short, claimable accomplishment (max 12 words).

OUTPUT (strict JSON, no markdown, no commentary):
{
  "dimensions": [
    {"id":"capital","label":"Capital at work","you":0,"idol":0,"you_note":"","idol_note":""},
    {"id":"knowledge","label":"Knowledge base","you":0,"idol":0,"you_note":"","idol_note":""},
    {"id":"habits","label":"Daily discipline","you":0,"idol":0,"you_note":"","idol_note":""},
    {"id":"network","label":"Trusted network","you":0,"idol":0,"you_note":"","idol_note":""},
    {"id":"clarity","label":"Strategic clarity","you":0,"idol":0,"you_note":"","idol_note":""}
  ],
  "milestones": [
    {"text":"...","hit_by_age":0}
  ]
}
```

- [ ] **Step 5: Register the prompt placeholders**

In `app/services/llm/prompt_loader.py`, add to the `PROMPT_PLACEHOLDERS` dict:

```python
    "comparison_scores.txt": [
        "idol_name",
        "user_age",
        "user_profile_json",
        "interview_transcript_json",
        "idol_facts_json",
        "comparison_summary",
    ],
```

- [ ] **Step 6: Run the scorer tests to verify they pass**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_comparison_scoring.py -q`
Expected: PASS (4 tests).

- [ ] **Step 7: Verify import wiring**

Run: `cd cmpys/backend && source .venv/bin/activate && python -c "from app.services.comparison.scoring import generate_comparison_scores, normalize_comparison_scores; print('OK')"`
Expected: `OK`.

- [ ] **Step 8: Commit**

```bash
git add cmpys/backend/app/services/comparison/ cmpys/backend/prompts/comparison_scores.txt cmpys/backend/app/services/llm/prompt_loader.py cmpys/backend/tests/test_comparison_scoring.py
git commit -m "feat(backend): comparison scores scorer + prompt + normalization"
```

---

### Task 3: Backend — wire scorer into generate-results + persist + SSE

**Files:**
- Modify: `cmpys/backend/app/api/v1/sessions.py` (`generate_results` → `generate_stream`, after the blueprint persists)
- Test: covered by Task 2's pure tests + the import/smoke check here (no new HTTP test, per project convention).

**Interfaces:**
- Consumes: `generate_comparison_scores` (Task 2); `IntakeSession.comparison_scores_json` (Task 1).
- Produces: `session.comparison_scores_json` populated after a completed results run; SSE `{"type":"comparison_scores","ready":true}`.

- [ ] **Step 1: Add the import**

At the top of `app/api/v1/sessions.py`, with the other service imports:

```python
from app.services.comparison.scoring import generate_comparison_scores
```

- [ ] **Step 2: Wire the scorer after the blueprint persists**

In `generate_stream`, immediately AFTER the blueprint success block (`session.blueprint_output = full_blueprint` … `session.transition_to(SessionPhase.COMPLETED)` … `await db.commit()`) and BEFORE "Part 3: Kick off 12-week plan generation", insert:

```python
        # =====================================================================
        # Part 2.5: Structured comparison scores (best-effort)
        # =====================================================================
        # The prose comparison is the mirror; these are the numbers behind the
        # Compare screen's gauges/radar. Best-effort: a failure leaves
        # comparison_scores_json null and the client falls back to seed data.
        try:
            scores = await generate_comparison_scores(
                get_llm_client(),
                idol_name=idol_name,
                user_age=session.user_age,
                user_profile_json=json_lib.dumps(user_profile),
                interview_transcript_json=interview_transcript,
                idol_facts_json=json_lib.dumps(session.idol_facts_json or {}),
                comparison_summary=full_comparison,
            )
            if scores:
                session.comparison_scores_json = scores
                await db.commit()
                yield f"data: {json_lib.dumps({'type': 'comparison_scores', 'ready': True})}\n\n"
        except Exception as e:
            logger.error(f"[SESSION] comparison scores failed: {e}")
```

Confirm `get_llm_client` is imported in `sessions.py` (it is used for comparison/blueprint streams; if only the stream helpers are imported, add `from app.services.llm import get_llm_client`).

- [ ] **Step 3: Verify import + full backend suite**

Run: `cd cmpys/backend && source .venv/bin/activate && python -c "import app.api.v1.sessions; print('OK')" && python -m pytest tests/ -q`
Expected: `OK`; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add cmpys/backend/app/api/v1/sessions.py
git commit -m "feat(backend): generate + persist comparison scores in generate-results"
```

---

### Task 4: Backend — surface comparisonScores in the session response

**Files:**
- Modify: `cmpys/backend/app/api/v1/sessions.py` (`_build_session_response`)
- Test: `cmpys/backend/tests/test_session_response_scores.py`

**Interfaces:**
- Produces: session response dict key `comparisonScores` (the dict, or null).

- [ ] **Step 1: Write the failing test**

Create `cmpys/backend/tests/test_session_response_scores.py`:

```python
"""_build_session_response surfaces comparison_scores_json as comparisonScores."""
from types import SimpleNamespace
from datetime import datetime, timezone

from app.api.v1.sessions import _build_session_response


def _session(scores):
    return SimpleNamespace(
        id="s1", phase=None, user_age=24, user_financial_status=None,
        user_interests=[], idol=None, interview_turn_count=0,
        comparison_output=None, blueprint_output=None,
        interview_thread_id=None,
        comparison_scores_json=scores,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


def test_includes_scores_when_present():
    s = _session({"dimensions": [], "milestones": []})
    out = _build_session_response(s)
    assert out["comparisonScores"] == {"dimensions": [], "milestones": []}


def test_null_when_absent():
    out = _build_session_response(_session(None))
    assert out["comparisonScores"] is None
```

> Note: if `_build_session_response` accesses `session.idol.profile` or similar, the fake may need those attributes. Inspect the function and extend the `SimpleNamespace` minimally so it runs; do not change production behavior to suit the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_session_response_scores.py -q`
Expected: FAIL (`KeyError: 'comparisonScores'`).

- [ ] **Step 3: Add the field**

In `_build_session_response`, add to the returned dict (after `"blueprint_output": session.blueprint_output,`):

```python
        "comparisonScores": getattr(session, "comparison_scores_json", None),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/test_session_response_scores.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cmpys/backend/app/api/v1/sessions.py cmpys/backend/tests/test_session_response_scores.py
git commit -m "feat(backend): surface comparisonScores in session response"
```

---

### Task 5: Frontend — Session model carries comparisonScores

**Files:**
- Modify: `fe/cmpys/lib/features/session/models/session_models.dart`
- Regenerate: `session_models.freezed.dart` (via build_runner)
- Test: `fe/cmpys/test/session_comparison_scores_test.dart`

**Interfaces:**
- Produces: `Session.comparisonScores: Map<String, dynamic>?` (raw, parsed from `json['comparisonScores']`).

- [ ] **Step 1: Write the failing test**

Create `fe/cmpys/test/session_comparison_scores_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/session/models/session_models.dart';

void main() {
  test('Session.fromJson reads comparisonScores map', () {
    final s = Session.fromJson({
      'id': 's1',
      'phase': 'completed',
      'user_age': 24,
      'user_interests': <String>[],
      'comparisonScores': {
        'dimensions': [
          {'id': 'capital', 'label': 'Capital at work', 'you': 30, 'idol': 70,
           'you_note': 'a', 'idol_note': 'b'}
        ],
        'milestones': [{'id': 'm1', 'label': 'Did a thing', 'hit_by_age': 22}],
      },
    });
    expect(s.comparisonScores?['dimensions'], isA<List>());
    expect((s.comparisonScores!['dimensions'] as List).first['id'], 'capital');
  });

  test('Session.fromJson tolerates missing comparisonScores', () {
    final s = Session.fromJson({
      'id': 's1', 'phase': 'intake', 'user_age': 0, 'user_interests': <String>[],
    });
    expect(s.comparisonScores, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd fe/cmpys && flutter test test/session_comparison_scores_test.dart`
Expected: FAIL (`comparisonScores` getter undefined).

- [ ] **Step 3: Add the freezed field**

In `session_models.dart`, in the `@freezed`/`Session` factory constructor (alongside `comparisonOutput`/`blueprintOutput`), add:

```dart
    Map<String, dynamic>? comparisonScores,
```

In the hand-written `Session.fromJson`, add (after `blueprintOutput: ...`):

```dart
      comparisonScores: json['comparisonScores'] is Map
          ? (json['comparisonScores'] as Map).cast<String, dynamic>()
          : null,
```

- [ ] **Step 4: Regenerate freezed code**

Run: `cd fe/cmpys && dart run build_runner build --delete-conflicting-outputs`
Expected: completes; `session_models.freezed.dart` updated, no errors.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd fe/cmpys && flutter test test/session_comparison_scores_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Analyze + commit**

Run: `cd fe/cmpys && flutter analyze lib`
Expected: No issues.

```bash
git add fe/cmpys/lib/features/session/models/session_models.dart fe/cmpys/lib/features/session/models/session_models.freezed.dart fe/cmpys/test/session_comparison_scores_test.dart
git commit -m "feat(fe): Session model carries comparisonScores"
```

---

### Task 6: Frontend — store conversion + real-or-seed dims/milestones + screen swap

**Files:**
- Modify: `fe/cmpys/lib/features/cmpys/state/cmpys_store.dart` (state fields, `syncFromSession`, `liveDims`, new `liveMilestones`)
- Modify: `fe/cmpys/lib/features/cmpys/presentation/compare_screen.dart` (milestone source + age)
- Test: `fe/cmpys/test/live_comparison_test.dart`

**Interfaces:**
- Consumes: `Session.comparisonScores` (Task 5); seed `cmpysComparison`, `CmpysDimension`, `CmpysMilestone`.
- Produces: `CmpysStore` state field `liveComparisonScores: Map<String, dynamic>?`; `liveDims()` returns real dims when present else seed; `liveMilestones() -> List<CmpysMilestone>` real-or-seed.

- [ ] **Step 1: Write the failing test**

Create `fe/cmpys/test/live_comparison_test.dart` (pure conversion helpers — no widget pump):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';

void main() {
  test('dimsFromScores maps the raw map to CmpysDimension list', () {
    final dims = dimsFromScores({
      'dimensions': [
        {'id': 'capital', 'label': 'Capital at work', 'you': 30, 'idol': 70,
         'you_note': 'small savings', 'idol_note': 'compounded'},
      ],
    });
    expect(dims, isNotNull);
    expect(dims!.first.id, 'capital');
    expect(dims.first.you, 30);
    expect(dims.first.idolNote, 'compounded');
  });

  test('dimsFromScores returns null for null/empty', () {
    expect(dimsFromScores(null), isNull);
    expect(dimsFromScores({'dimensions': []}), isNull);
  });

  test('milestonesFromScores maps to CmpysMilestone with stable ids', () {
    final ms = milestonesFromScores({
      'milestones': [
        {'id': 'm1', 'label': 'Wrote a philosophy'},
        {'label': 'Saved a base'},
      ],
    });
    expect(ms, isNotNull);
    expect(ms!.first.id, 'm1');
    expect(ms.first.label, 'Wrote a philosophy');
    expect(ms[1].id, 'm2'); // positional fallback
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd fe/cmpys && flutter test test/live_comparison_test.dart`
Expected: FAIL (`dimsFromScores` undefined).

- [ ] **Step 3: Add top-level conversion helpers**

In `cmpys_store.dart` (top level, after imports), add:

```dart
/// Convert a raw `comparisonScores` map (from the session) into seed-shaped
/// dimensions. Returns null when absent/empty so callers fall back to seed.
List<CmpysDimension>? dimsFromScores(Map<String, dynamic>? scores) {
  final raw = scores?['dimensions'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <CmpysDimension>[];
  for (final d in raw) {
    if (d is! Map) continue;
    out.add(CmpysDimension(
      id: (d['id'] ?? '').toString(),
      label: (d['label'] ?? '').toString(),
      you: (d['you'] as num?)?.toInt() ?? 0,
      idol: (d['idol'] as num?)?.toInt() ?? 0,
      youNote: (d['you_note'] ?? '').toString(),
      idolNote: (d['idol_note'] ?? '').toString(),
    ));
  }
  return out.isEmpty ? null : out;
}

/// Convert raw milestones into seed-shaped CmpysMilestone with stable ids
/// (`m1`..). Returns null when absent so callers fall back to seed.
List<CmpysMilestone>? milestonesFromScores(Map<String, dynamic>? scores) {
  final raw = scores?['milestones'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <CmpysMilestone>[];
  for (var i = 0; i < raw.length; i++) {
    final m = raw[i];
    if (m is! Map) continue;
    final label = (m['label'] ?? m['text'] ?? '').toString();
    if (label.isEmpty) continue;
    out.add(CmpysMilestone((m['id'] ?? 'm${i + 1}').toString(), label));
  }
  return out.isEmpty ? null : out;
}
```

- [ ] **Step 4: Run the conversion test to verify it passes**

Run: `cd fe/cmpys && flutter test test/live_comparison_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Store the scores on sync + use them in liveDims/liveMilestones**

In `CmpysState`, add a field `final Map<String, dynamic>? liveComparisonScores;` (constructor param + `copyWith` support, matching the class's existing pattern; default null).

In `syncFromSession`, where it builds `next = next.copyWith(...)` with `comparisonMd`/`blueprintMd`, also pass:

```dart
      liveComparisonScores: session.comparisonScores,
```

Change `liveDims()` to prefer real dims:

```dart
  List<({String id, String label, int you, int idol, String youNote, String idolNote})>
      liveDims() {
    final base = dimsFromScores(state.liveComparisonScores) ??
        cmpysComparison.dimensions;
    return base
        .map((d) => (
              id: d.id,
              label: d.label,
              you: (d.you + (dimShift[d.id] ?? 0)).clamp(0, 100),
              idol: d.idol,
              youNote: d.youNote,
              idolNote: d.idolNote,
            ))
        .toList();
  }
```

Add `liveMilestones()`:

```dart
  /// Real milestones from the session when present, else the seed list.
  List<CmpysMilestone> liveMilestones() =>
      milestonesFromScores(state.liveComparisonScores) ??
      cmpysComparison.milestones;
```

> Note: `liveDims`/`liveMilestones` are instance methods on the store notifier that read `state`; match how the existing `liveDims` accesses `state`/`dimShift`.

- [ ] **Step 6: Swap the Compare screen's seed reads**

In `compare_screen.dart`, the screen currently does `final c = cmpysComparison;` then uses `c.milestones` and `c.age`. Replace the milestone list and the age:

- Replace every `c.milestones` with `ms` where `final ms = ref.read(cmpysStoreProvider.notifier).liveMilestones();` is computed in `build` (near `final dims = st.liveDims();`). Specifically:
  - `final hitCount = ms.where((m) => st.milestones[m.id] ?? false).length;`
  - `_milestonesSection` / `_milestoneRow` iterate `ms` instead of `c.milestones` (pass `ms` in, or read it inside).
- For the "Both at age N" kicker and the "MILESTONES … HIT BY {age}" header, use the user's real age when available: `final cmpAge = st.user.age > 0 ? st.user.age : c.age;` and use `cmpAge` in those two strings.

Keep `c` for `headline`/`summary`/`strengths` (still seeded, per scope).

- [ ] **Step 7: Analyze + run FE comparison tests**

Run: `cd fe/cmpys && flutter analyze lib && flutter test test/live_comparison_test.dart test/session_comparison_scores_test.dart`
Expected: No analyzer issues; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add fe/cmpys/lib/features/cmpys/state/cmpys_store.dart fe/cmpys/lib/features/cmpys/presentation/compare_screen.dart fe/cmpys/test/live_comparison_test.dart
git commit -m "feat(fe): Compare screen uses real dimension scores + milestones"
```

---

## Final verification

- [ ] Backend: `cd cmpys/backend && source .venv/bin/activate && python -m pytest tests/ -q` — all pass; `python -c "import app.main"` OK; migration round-trips.
- [ ] Frontend: `cd fe/cmpys && flutter analyze lib && flutter test` — clean + green.
- [ ] Manual (against dev/live backend): complete a fresh onboarding → open Compare → the indices, 53%, radar, dimension bars/notes, and milestones reflect the chosen idol and the user's interview (not the Buffett-flavored seed). An onboarding done before this change still shows seed (null scores) — expected.
