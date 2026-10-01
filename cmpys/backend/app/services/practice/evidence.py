"""Read narrowly scoped practice evidence without inferring general mastery."""

from pydantic import ValidationError
from sqlalchemy import select

from app.models.lesson_practice import LessonPractice
from app.models.plan import Plan, PlanItem
from app.services.practice.contracts import Workbook, lesson_version


def activity_answers(activity, answers):
    return {
        field.id: answers.get(f"{activity.id}.{field.id}", "")
        for field in activity.fields
    }


def matching_attempts(row, activity):
    current = activity_answers(activity, row.answers_json or {})
    return [
        attempt
        for attempt in (row.attempts_json or [])
        if attempt.get("activity_id") == activity.id
        and attempt.get("answers") == current
    ]


def passed_activities(row, workbook):
    return [
        activity.id
        for activity in workbook.activities
        if any(
            attempt.get("passed") is True
            for attempt in matching_attempts(row, activity)
        )
    ]


def practice_summary(row, workbook: Workbook) -> dict:
    """Only assessments of the CURRENT answers count; drafts are not failures."""
    activities = []
    for activity in workbook.activities:
        matching = matching_attempts(row, activity)
        passed = [attempt for attempt in matching if attempt.get("passed") is True]
        independent = [
            attempt for attempt in passed if attempt.get("assisted") is False
        ]
        assessed = (independent or passed or matching or [None])[-1]
        if passed:
            status = "passed_without_hint" if independent else "passed_with_support"
        elif assessed and any(f.get("uncertain") for f in assessed.get("feedback", [])):
            status = "needs_review"
        elif assessed:
            status = "needs_practice"
        else:
            status = "not_assessed"
        activities.append(
            {
                "title": activity.title,
                "kind": activity.kind,
                "status": status,
                "checked_at": assessed.get("submitted_at") if assessed else None,
                "assessment": "model_and_fixed_checks"
                if any(f.kind == "text" for f in activity.fields)
                else "fixed_checks",
            }
        )
    transfer = [a for a in activities if a["kind"] == "transfer"]
    if all(a["status"].startswith("passed_") for a in activities):
        status = (
            "transfer_without_hint"
            if all(a["status"] == "passed_without_hint" for a in transfer)
            else "completed_with_support"
        )
    elif any(a["status"] == "needs_review" for a in activities):
        status = "needs_review"
    elif any(a["status"] == "needs_practice" for a in activities):
        status = "needs_practice"
    else:
        status = "in_progress"
    return {
        "status": status,
        "activities": activities,
        "scope": "This lesson and these cases only. No proof of broad mastery or outside assistance being absent.",
    }


async def load_recent_practice_evidence(
    db, *, user_id: str, idol_id: str, session_id: str
) -> list[dict]:
    """Owner + mentor + goal-session scoped, bounded, current artifacts only."""
    if not all((user_id, idol_id, session_id)):
        return []
    from app.api.v1.plans import _progress_eligible_step_ids, _validated_lesson_steps
    from app.services.planning.catalog_lessons import (
        catalog_details_are_ready_in_database,
    )

    result = await db.execute(
        select(LessonPractice, PlanItem)
        .join(PlanItem, PlanItem.id == LessonPractice.plan_item_id)
        .join(Plan, Plan.id == PlanItem.plan_id)
        .where(
            LessonPractice.user_id == user_id,
            Plan.user_id == user_id,
            Plan.idol_id == idol_id,
            Plan.roadmap_json["source_session_id"].as_string() == session_id,
            LessonPractice.state == "ready",
        )
        .order_by(LessonPractice.updated_at.desc(), LessonPractice.id.desc())
        .limit(8)
    )
    evidence = []
    for row, item in result.all():
        details = item.details_json or {}
        if (details.get("_generation") or {}).get("status") == "revoked":
            continue
        step = next(
            (
                step
                for step in (_validated_lesson_steps(details) or [])
                if step.get("id") == row.step_id
            ),
            None,
        )
        if not step or row.step_id not in _progress_eligible_step_ids(details):
            continue
        if row.lesson_version != lesson_version(item, step):
            continue
        if not await catalog_details_are_ready_in_database(
            db, details, user_id=user_id, plan_item_id=str(item.id)
        ):
            continue
        try:
            workbook = Workbook.model_validate(row.workbook_json)
        except (ValidationError, ValueError):
            continue
        summary = practice_summary(row, workbook)
        if all(
            activity["status"] == "not_assessed" for activity in summary["activities"]
        ):
            continue
        evidence.append(
            {"lesson": str(step.get("title") or item.title)[:160], **summary}
        )
        if len(evidence) == 4:
            break
    return evidence


def compact_practice_evidence(evidence: list[dict]) -> list[dict]:
    """A small prompt budget preserves scope and assistance before descriptions."""

    def salient_checks(item):
        activities = item.get("activities", [])
        unresolved = [
            a
            for a in activities
            if a.get("status") in {"needs_practice", "needs_review"}
        ]
        transfer = [a for a in activities if a.get("kind") == "transfer"]
        chosen = unresolved[:1]
        for activity in transfer[-1:] + activities[-2:]:
            if activity not in chosen:
                chosen.append(activity)
        return chosen[:2]

    return [
        {
            "lesson": str(item.get("lesson") or "")[:120],
            "status": item.get("status"),
            "checks": [
                {
                    "title": str(activity.get("title") or "")[:80],
                    "kind": activity.get("kind"),
                    "status": activity.get("status"),
                    "checked_at": activity.get("checked_at"),
                }
                for activity in salient_checks(item)
            ],
            "scope": "Named lesson only; no in-app hint does not exclude outside help.",
        }
        for item in evidence[:2]
    ]
