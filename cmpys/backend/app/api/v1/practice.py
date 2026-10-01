"""In-app practice. GET never generates. Paid operations are bounded and leased."""

import logging
import math
from datetime import datetime, timedelta, timezone
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.lesson_practice import LessonPractice
from app.models.user import User
from app.services.practice.contracts import (
    DraftRequest,
    SubmitRequest,
    Workbook,
    combine_review,
    grade_fixed,
    lesson_version,
    public_workbook,
    validate_answers,
)
from app.services.practice.generation import (
    PRACTICE_GENERATION_LEASE_SECONDS,
    generate_workbook,
    review_text,
)
from app.services.practice.evidence import (
    activity_answers as _activity_answers,
    passed_activities,
    practice_summary,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/plan-items", tags=["practice"])
DB = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]
Artifact = Annotated[str | None, Query(alias="artifactJobId")]
PREPARATION_ATTEMPT_LIMIT = 3
PREPARATION_RETRY_COOLDOWN = timedelta(minutes=30)


def _busy(row):
    return bool(row.lease_until and row.lease_until > datetime.now(timezone.utc))


def _preparation_retry_at(row):
    if row.generation_attempts < PREPARATION_ATTEMPT_LIMIT or row.workbook_json:
        return None
    if row.state not in {"failed", "preparing"} or _busy(row):
        return None
    updated_at = getattr(row, "updated_at", None)
    if not isinstance(updated_at, datetime):
        return None
    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    # An expired worker may still have held its lease after updated_at.
    failed_after = max(updated_at, row.lease_until) if row.lease_until else updated_at
    return failed_after + PREPARATION_RETRY_COOLDOWN


def _can_retry_preparation(row):
    retry_at = _preparation_retry_at(row)
    return row.generation_attempts < PREPARATION_ATTEMPT_LIMIT or bool(
        retry_at and retry_at <= datetime.now(timezone.utc)
    )


def view(row):
    if row is None:
        return {"state": "not_started"}
    workbook = Workbook.model_validate(row.workbook_json) if row.workbook_json else None
    passed = passed_activities(row, workbook) if workbook else []
    state = row.state
    if state in {"preparing", "reviewing"} and not _busy(row):
        state = "ready" if workbook else "failed"
    retry_at = _preparation_retry_at(row)
    return {
        "state": state,
        "revision": row.revision,
        "lesson_version": row.lesson_version,
        "workbook": public_workbook(workbook) if workbook else None,
        "learning_evidence": practice_summary(row, workbook) if workbook else None,
        "answers": row.answers_json,
        "attempts": row.attempts_json,
        "hints": row.hints_json,
        "passed_activity_ids": passed,
        "complete": bool(workbook and len(passed) == len(workbook.activities)),
        "can_retry_preparation": _can_retry_preparation(row),
        "retry_after_seconds": (
            max(0, math.ceil((retry_at - datetime.now(timezone.utc)).total_seconds()))
            if retry_at else None
        ),
    }


async def _refreshed_practice_view(row, db):
    # SQL-expression onupdate expires this timestamp even when the async
    # session keeps ordinary attributes after commit. Refresh it explicitly
    # before the synchronous cooldown serializer can trigger lazy IO.
    await db.refresh(row, ["updated_at"])
    return view(row)


async def _load(db, user_id, item_id, step_id, artifact, *, lock=False):
    from app.api.v1.plans import (
        _get_item_for_user,
        _validate_expected_artifact,
        _progress_eligible_step_ids,
        _validated_lesson_steps,
    )

    item = await _get_item_for_user(db, item_id, user_id, for_update=lock)
    await _validate_expected_artifact(
        db, item, user_id=user_id, expected_job_id=artifact
    )
    steps = _validated_lesson_steps(item.details_json) or ()
    step = next((s for s in steps if s.get("id") == step_id), None)
    if not step:
        raise HTTPException(404, "Lesson not found")
    if not str(step.get("lesson_content") or "").strip():
        raise HTTPException(
            409, "The lesson needs content before practice can be prepared"
        )
    if ((item.details_json or {}).get("_generation") or {}).get("status") == "revoked":
        raise HTTPException(
            409, "This lesson is no longer available. Refresh your plan."
        )
    if step_id not in _progress_eligible_step_ids(item.details_json):
        raise HTTPException(409, "This lesson is still being prepared")
    from app.services.planning.catalog_lessons import (
        catalog_details_are_ready_in_database,
    )

    if not await catalog_details_are_ready_in_database(
        db, item.details_json, user_id=user_id, plan_item_id=item_id
    ):
        raise HTTPException(
            409, "This lesson is no longer available. Refresh your plan."
        )
    version = lesson_version(item, step)
    row = (
        await db.execute(
            select(LessonPractice)
            .where(
                LessonPractice.user_id == user_id,
                LessonPractice.plan_item_id == item_id,
                LessonPractice.step_id == step_id,
                LessonPractice.lesson_version == version,
            )
            .execution_options(populate_existing=True)
        )
    ).scalar_one_or_none()
    return item, step, row, version


async def _canonical_workbook(db, item, step):
    """Load private answers only from the already-authorized immutable catalog row."""
    from app.models.curriculum import ModuleSession
    from app.services.curriculum.hashing import sha256_json

    session_id = step.get("catalog_session_id")
    version_id = ((item.details_json or {}).get("catalog") or {}).get("module_version_id")
    if not session_id or not version_id:
        return None
    session = await db.scalar(select(ModuleSession).where(ModuleSession.id == session_id, ModuleSession.module_version_id == version_id))
    if session is None:
        raise HTTPException(409, "The prepared lesson is no longer available.")
    content = session.content_json or {}
    payload = content.get("practice_workbook")
    if payload is None:
        return None
    if content.get("practice_workbook_hash") != sha256_json(payload):
        raise HTTPException(409, "The prepared practice needs review.")
    try:
        return Workbook.model_validate(payload)
    except ValueError as exc:
        raise HTTPException(409, "The prepared practice needs review.") from exc


def _ready(row):
    if row is None or not row.workbook_json:
        raise HTTPException(409, "Prepare the practice first")
    if _busy(row):
        raise HTTPException(
            409, "A practice operation is already running. Refresh shortly."
        )
    return Workbook.model_validate(row.workbook_json)


def _revision(row, revision):
    if row.revision != revision:
        raise HTTPException(
            409, "Your practice changed on another screen. Reload before saving."
        )


def _activity(row, workbook, activity_id):
    passed = passed_activities(row, workbook)
    for a in workbook.activities:
        if a.id == activity_id:
            return a
        if a.id not in passed:
            raise HTTPException(409, "Complete the earlier exercise first")
    raise HTTPException(404, "Exercise not found")


@router.get("/{item_id}/steps/{step_id}/practice")
async def get_practice(
    item_id: str,
    step_id: str,
    db: DB,
    current_user: CurrentUser,
    artifact_job_id: Artifact = None,
):
    item, step, row, _ = await _load(
        db, str(current_user.id), item_id, step_id, artifact_job_id
    )
    result = view(row)
    if row is None:
        result["prepared_available"] = await _canonical_workbook(db, item, step) is not None
    return result


@router.post("/{item_id}/steps/{step_id}/practice/prepare")
async def prepare_practice(
    item_id: str,
    step_id: str,
    db: DB,
    current_user: CurrentUser,
    artifact_job_id: Artifact = None,
):
    user_id = str(current_user.id)
    item, step, row, version = await _load(
        db, user_id, item_id, step_id, artifact_job_id, lock=True
    )
    if row and (row.workbook_json or _busy(row)):
        return view(row)
    prepared = await _canonical_workbook(db, item, step)
    if prepared is None and row and row.generation_attempts >= PREPARATION_ATTEMPT_LIMIT:
        if not _can_retry_preparation(row):
            retry_at = _preparation_retry_at(row)
            retry_seconds = max(1, math.ceil((retry_at - datetime.now(timezone.utc)).total_seconds())) if retry_at else int(PREPARATION_RETRY_COOLDOWN.total_seconds())
            raise HTTPException(
                429,
                "Practice preparation is temporarily paused after three attempts. Try again later.",
                headers={"Retry-After": str(retry_seconds)},
            )
        # Reset only this immutable lesson's exhausted window, while holding
        # the same lock that claims the new operation. No automatic paid retry.
        row.generation_attempts = 0
    if row is None:
        row = LessonPractice(
            user_id=user_id,
            plan_item_id=item_id,
            step_id=step_id,
            lesson_version=version,
            revision=0,
            generation_attempts=0,
            review_calls=0,
            answers_json={},
            attempts_json=[],
            hints_json=[],
        )
        db.add(row)
    token = str(uuid4())
    row.generation_attempts += 0 if prepared is not None else 1
    row.state, row.lease_token = "preparing", token
    row.lease_until = datetime.now(timezone.utc) + timedelta(
        seconds=PRACTICE_GENERATION_LEASE_SECONDS
    )
    # Mark this immutable lesson version as requiring practice. Other legacy
    # versions retain their old completion semantics until they opt in.
    meta = dict(item.meta_json or {})
    required = dict(meta.get("practice_versions") or {})
    required[step_id] = version
    item.meta_json = {**meta, "practice_versions": required}
    context = {
        "mission": item.title,
        "goal": item.success_metric,
        "mentor_context": meta.get("idol_parallel"),
        "gap": meta.get("primary_gap"),
        "plan_item_id": item_id,
        "step_id": step_id,
    }
    await db.commit()  # No database connection/row lock held during inference.
    generated, failed = None, False
    failure_code = None
    try:
        generated = prepared if prepared is not None else await generate_workbook(step, context)
    except Exception as exc:
        failed = True
        failure_code = "provider_timeout" if isinstance(exc, TimeoutError) else "invalid_practice"
        logger.warning("Practice preparation failed item=%s step=%s type=%s", item_id, step_id, type(exc).__name__)
    item, _, row, current_version = await _load(
        db, user_id, item_id, step_id, artifact_job_id, lock=True
    )
    if current_version != version or row is None or row.lease_token != token:
        raise HTTPException(409, "This lesson changed. Reopen the lesson.")
    row.lease_until = None
    row.lease_token = None
    row.state = "failed" if failed else "ready"
    failures = dict((item.meta_json or {}).get("practice_preparation_failures") or {})
    if failure_code:
        failures[step_id] = {"code": failure_code, "lesson_version": version,
                             "at": datetime.now(timezone.utc).isoformat()}
    else:
        failures.pop(step_id, None)
    item.meta_json = {**(item.meta_json or {}), "practice_preparation_failures": failures}
    if generated is not None:
        row.workbook_json = generated.model_dump()
    row.revision += 1
    await db.commit()
    return await _refreshed_practice_view(row, db)


@router.put("/{item_id}/steps/{step_id}/practice/draft")
async def save_draft(
    item_id: str,
    step_id: str,
    data: DraftRequest,
    db: DB,
    current_user: CurrentUser,
    artifact_job_id: Artifact = None,
):
    _, _, row, _ = await _load(
        db, str(current_user.id), item_id, step_id, artifact_job_id, lock=True
    )
    workbook = _ready(row)
    _revision(row, data.revision)
    try:
        validate_answers(workbook, data.answers)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    if row.answers_json != data.answers:
        if view(row).get("complete"):
            raise HTTPException(
                409,
                "Completed practice is preserved. Reopen it to review your saved work.",
            )
        row.answers_json = data.answers
        row.revision += 1
    await db.commit()
    return view(row)


@router.post("/{item_id}/steps/{step_id}/practice/hint")
async def get_hint(
    item_id: str,
    step_id: str,
    data: SubmitRequest,
    db: DB,
    current_user: CurrentUser,
    artifact_job_id: Artifact = None,
    solution: bool = False,
):
    _, _, row, _ = await _load(
        db, str(current_user.id), item_id, step_id, artifact_job_id, lock=True
    )
    workbook = _ready(row)
    _revision(row, data.revision)
    activity = _activity(row, workbook, data.activity_id)
    if solution and not any(a["activity_id"] == activity.id for a in row.attempts_json):
        raise HTTPException(409, "Try the exercise before opening its worked solution")
    kind = "solution" if solution else "hint"
    if not any(
        h["activity_id"] == activity.id and h["kind"] == kind for h in row.hints_json
    ):
        row.hints_json = [
            *row.hints_json,
            {
                "activity_id": activity.id,
                "kind": kind,
                "content": activity.worked_solution if solution else activity.hint,
            },
        ]
        row.revision += 1
    await db.commit()
    return view(row)


@router.post("/{item_id}/steps/{step_id}/practice/submit")
async def submit_practice(
    item_id: str,
    step_id: str,
    data: SubmitRequest,
    db: DB,
    current_user: CurrentUser,
    artifact_job_id: Artifact = None,
):
    user_id = str(current_user.id)
    item, step, row, version = await _load(
        db, user_id, item_id, step_id, artifact_job_id, lock=True
    )
    if row:
        previous = next(
            (a for a in row.attempts_json if a["request_id"] == data.request_id), None
        )
        if previous:
            if previous["activity_id"] != data.activity_id:
                raise HTTPException(409, "Submission identifier already used")
            return view(row)
    workbook = _ready(row)
    _revision(row, data.revision)
    activity = _activity(row, workbook, data.activity_id)
    try:
        fixed = grade_fixed(activity, row.answers_json)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    answers = dict(row.answers_json)
    # Rechecking an unchanged answer does not incur another model call.
    if any(
        a["activity_id"] == activity.id
        and a["answers"] == _activity_answers(activity, answers)
        for a in row.attempts_json
    ):
        return view(row)
    if row.review_calls >= 40:
        raise HTTPException(429, "This workbook has reached its review limit.")
    recovery = None
    if all(field["passed"] for field in fixed) and any(f.kind == "text" for f in activity.fields):
        try:
            recovery = await _practice_pilot_recovery(db, item, user_id)
        except ValueError as exc:
            raise HTTPException(503, "Your answers are saved. Review is unavailable; please try again.") from exc
    token = str(uuid4())
    row.review_calls += 1
    row.state, row.lease_token = "reviewing", token
    row.lease_until = datetime.now(timezone.utc) + timedelta(seconds=60)
    await db.commit()
    review, failed = None, False
    try:
        if any(not field["passed"] for field in fixed):
            # Give immediate, deterministic corrections before paying to judge
            # reasoning based on calculations that already failed. Pending is
            # not a grade of the learner's explanation and can never pass.
            feedback = fixed + [
                {"field_id": field.id, "passed": False, "pending": True,
                 "feedback": "Correct the calculation or choice above first; your explanation is saved and will be reviewed after that."}
                for field in activity.fields if field.kind == "text"
            ]
        else:
            if any(f.kind == "text" for f in activity.fields):
                kwargs = {"recovery_response": recovery} if recovery is not None else {}
                review = await review_text(activity, answers, step.get("lesson_content", ""), **kwargs)
            feedback = combine_review(activity, fixed, review)
    except Exception:
        failed = True
        feedback = []
    _, _, row, current_version = await _load(
        db, user_id, item_id, step_id, artifact_job_id, lock=True
    )
    if current_version != version or row is None or row.lease_token != token:
        raise HTTPException(409, "This lesson changed. Reopen the lesson.")
    row.state, row.lease_token, row.lease_until = "ready", None, None
    if not failed:
        row.attempts_json = [
            *row.attempts_json,
            {
                "request_id": data.request_id,
                "activity_id": activity.id,
                "answers": _activity_answers(activity, answers),
                "feedback": feedback,
                "passed": all(f["passed"] for f in feedback),
                "assisted": any(
                    h["activity_id"] == activity.id for h in row.hints_json
                ),
                "submitted_at": datetime.now(timezone.utc).isoformat(),
            },
        ]
    row.revision += 1
    await db.commit()
    if failed:
        raise HTTPException(
            503, "Your answers are saved. Review is unavailable; please try again."
        )
    return view(row)


async def _practice_pilot_recovery(db, item, user_id):
    """Carry only the owned, audited pilot outage into its text assessments."""
    from app.models.plan import Plan
    from app.models.plan_job import PlanGenerationJob
    from app.tasks.plans import _validated_plan_recovery

    if not getattr(item, "plan_id", None):
        return None
    plan = await db.get(Plan, item.plan_id)
    pilot_id = (plan.roadmap_json or {}).get("operator_catalog_pilot_job_id") if plan else None
    if not pilot_id:
        return None
    job = await db.get(PlanGenerationJob, pilot_id)
    if plan.user_id != user_id or job is None or job.user_id != user_id or job.plan_id != plan.id:
        raise ValueError("Practice recovery does not belong to this plan")
    response = await _validated_plan_recovery(db, job)
    if response is None:
        # Do not silently spend again through the failing gateway when the
        # operator's bounded pilot authorization has expired.
        raise ValueError("Practice pilot recovery has expired")
    return response


async def require_practice_complete(db, item, user_id, selected_step=None):
    """Called under existing completion locks; block both step and bulk bypass."""
    required = (item.meta_json or {}).get("practice_versions") or {}
    all_required = ((item.details_json or {}).get("_generation") or {}).get(
        "practice_required"
    ) is True
    if not required and not all_required:
        return
    steps = (
        [selected_step] if selected_step else (item.details_json or {}).get("steps", [])
    )
    for step in steps:
        version = lesson_version(item, step)
        if not all_required and required.get(step.get("id")) != version:
            continue
        row = (
            await db.execute(
                select(LessonPractice).where(
                    LessonPractice.user_id == user_id,
                    LessonPractice.plan_item_id == item.id,
                    LessonPractice.step_id == step["id"],
                    LessonPractice.lesson_version == version,
                )
            )
        ).scalar_one_or_none()
        if row is None or not view(row).get("complete"):
            raise HTTPException(
                409, "Complete the in-app practice before finishing this lesson."
            )
