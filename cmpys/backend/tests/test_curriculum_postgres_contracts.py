"""Live PostgreSQL checks for curriculum invariants that static SQL cannot prove."""

from uuid import uuid4

import psycopg
import pytest
from psycopg.types.json import Jsonb
from sqlalchemy import create_engine, select, text
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.curriculum import (
    CurriculumGenerationJob,
    LearnerSkillState,
    ModuleQualityReport,
    PersonalizedLessonVersion,
)
from app.services.curriculum.budget import (
    _usage_by_curriculum_job_ids_statement,
    _usage_for_curriculum_job_statement,
)
from migrations.versions import (
    h8i9j0k1l2m3_curriculum_audit_shapes as audit_shape_migration,
)
from migrations.versions import (
    h9j0k1l2m3n4_curriculum_h8_convergence as h8_convergence_migration,
)


HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64
HASH_D = "d" * 64


def _postgres_dsn() -> str:
    return settings.database_url.replace("postgresql+psycopg://", "postgresql://", 1)


def _id() -> str:
    return str(uuid4())


def _assert_rejected(conn, cursor, query: str, params: tuple, message: str) -> None:
    """Run expected-invalid DML in a savepoint so the outer fixture stays usable."""

    with pytest.raises(psycopg.Error) as caught:
        with conn.transaction():
            cursor.execute(query, params)
    assert message in str(caught.value)


def test_curriculum_budget_queries_use_usage_ledger_partial_index_on_postgres():
    job_id = "00000000-0000-0000-0000-000000000001"
    statements = (
        _usage_by_curriculum_job_ids_statement([job_id]),
        _usage_for_curriculum_job_statement(job_id),
    )

    with psycopg.connect(_postgres_dsn()) as conn:
        with conn.transaction(force_rollback=True), conn.cursor() as cursor:
            cursor.execute("SET LOCAL enable_seqscan = off")
            cursor.execute("SET LOCAL plan_cache_mode = force_generic_plan")
            for statement in statements:
                compiled = statement.compile(
                    dialect=postgresql.dialect(),
                    compile_kwargs={"render_postcompile": True},
                )
                sql = str(compiled)
                assert "curriculum_job_id" not in compiled.params.values()
                cursor.execute(
                    f"EXPLAIN (COSTS OFF) {sql}",
                    compiled.params,
                    prepare=True,
                )
                plan = "\n".join(str(row[0]) for row in cursor.fetchall())
                assert "ix_llm_usage_events_curriculum_job" in plan, plan


def test_h8_repairs_stamped_modern_artifact_progress_on_postgres(monkeypatch):
    user_id = _id()
    repair_plan_id = _id()
    sticky_plan_id = _id()
    successor_plan_id = _id()
    ready_plan_id = _id()
    malformed_item_id = _id()
    partial_item_id = _id()
    skipped_item_id = _id()
    sticky_item_id = _id()
    ready_item_id = _id()
    material_scalar_item_id = _id()
    invalid_step_field_item_id = _id()
    invalid_idea_item_id = _id()
    invalid_top_level_item_id = _id()
    malformed_job_id = _id()
    partial_job_id = _id()
    thin_partial_item_id = _id()
    thin_partial_job_id = _id()
    skipped_job_id = _id()
    sticky_job_id = _id()
    ready_job_id = _id()
    material_scalar_job_id = _id()
    invalid_step_field_job_id = _id()
    invalid_idea_job_id = _id()
    invalid_top_level_job_id = _id()
    invalid_ready_fixtures = (
        ("missing", _id(), _id(), False, None),
        ("scalar", _id(), _id(), True, "one"),
        ("non-string", _id(), _id(), True, [7]),
        ("duplicate", _id(), _id(), True, ["one", "one"]),
        ("untrimmed", _id(), _id(), True, [" one"]),
        ("overlong", _id(), _id(), True, ["x" * 101]),
        ("unknown", _id(), _id(), True, ["not-a-current-step"]),
    )
    substantive_lesson = "evidence\vproof\N{NO-BREAK SPACE}" * 950
    assert len(substantive_lesson.split()) == 1900

    with psycopg.connect(_postgres_dsn()) as conn:
        with conn.transaction(force_rollback=True), conn.cursor() as cursor:
            strip_characters = audit_shape_migration.PYTHON_STRIP_CHARACTERS_SQL
            cursor.execute(
                f"""
                SELECT
                    BTRIM('valuation-step', {strip_characters}),
                    BTRIM(U&'\\000Btrim\\000B', {strip_characters}),
                    BTRIM(U&'\\00A0trim\\00A0', {strip_characters}),
                    BTRIM(E'\\t\\n', {strip_characters})
                """
            )
            assert cursor.fetchone() == ("valuation-step", "trim", "trim", "")

            cursor.execute(
                "INSERT INTO users (id, email, password_hash) VALUES (%s, %s, 'test')",
                (user_id, f"h8-repair-{user_id}@example.test"),
            )
            for plan_id, previous_plan_id in (
                (repair_plan_id, None),
                (sticky_plan_id, None),
                (successor_plan_id, sticky_plan_id),
                (ready_plan_id, None),
            ):
                cursor.execute(
                    """
                    INSERT INTO plans
                        (id, user_id, target_age, duration_weeks, weekly_hours,
                         cycle_number, completed_at, previous_plan_id)
                    VALUES (%s, %s, 40, 12, 5, 1, now(), %s)
                    """,
                    (plan_id, user_id, previous_plan_id),
                )

            items = (
                (
                    malformed_item_id,
                    repair_plan_id,
                    "Malformed current artifact",
                    "COMPLETED",
                    100,
                    {
                        "steps": [{"id": "\vtrim-me"}],
                        "_generation": {
                            "job_id": malformed_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    partial_item_id,
                    repair_plan_id,
                    "Partial current artifact",
                    "COMPLETED",
                    100,
                    {
                        "steps": [
                            {"id": "one", "lesson_content": substantive_lesson},
                            {"id": "two", "lesson_content": substantive_lesson},
                        ],
                        "_generation": {
                            "job_id": partial_job_id,
                            "status": "partial",
                            "ready_step_ids": ["one"],
                        },
                    },
                ),
                (
                    thin_partial_item_id,
                    repair_plan_id,
                    "Partial artifact with a thin exposed step",
                    "COMPLETED",
                    100,
                    {
                        "steps": [
                            {
                                "id": "one",
                                "lesson_content": "evidence " * 1899,
                            }
                        ],
                        "_generation": {
                            "job_id": thin_partial_job_id,
                            "status": "partial",
                            "ready_step_ids": ["one"],
                        },
                    },
                ),
                (
                    skipped_item_id,
                    repair_plan_id,
                    "Skipped malformed history",
                    "SKIPPED",
                    100,
                    {
                        "steps": "not-an-array",
                        "_generation": {
                            "job_id": skipped_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    sticky_item_id,
                    sticky_plan_id,
                    "Malformed artifact with successor",
                    "COMPLETED",
                    100,
                    {
                        "steps": [],
                        "_generation": {
                            "job_id": sticky_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    ready_item_id,
                    ready_plan_id,
                    "Valid ready artifact",
                    "COMPLETED",
                    100,
                    {
                        "steps": [
                            {
                                "id": "valuation-step",
                                "title": "Valid lesson",
                                "resources": ["source-1"],
                                "estimate_minutes": 15,
                            }
                        ],
                        "materials": [
                            {
                                "title": "Valid material",
                                "duration_minutes": 10,
                                "ideas": [
                                    {
                                        "title": "Idea",
                                        "content": "Evidence",
                                        "category": "Mindset",
                                    }
                                ],
                            }
                        ],
                        "generated_at": "2026-07-29T12:00:00Z",
                        "generated_from_prompt_version": "details-v1",
                        "_generation": {
                            "job_id": ready_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    material_scalar_item_id,
                    repair_plan_id,
                    "Scalar materials",
                    "COMPLETED",
                    100,
                    {
                        "steps": [{"id": "material-step"}],
                        "materials": "not-an-array",
                        "_generation": {
                            "job_id": material_scalar_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    invalid_step_field_item_id,
                    repair_plan_id,
                    "Invalid nested step field",
                    "COMPLETED",
                    100,
                    {
                        "steps": [{"id": "nested-step", "resources": "not-an-array"}],
                        "_generation": {
                            "job_id": invalid_step_field_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    invalid_idea_item_id,
                    repair_plan_id,
                    "Invalid nested idea",
                    "COMPLETED",
                    100,
                    {
                        "steps": [{"id": "idea-step"}],
                        "materials": [{"title": "Book", "ideas": [{"title": 7}]}],
                        "_generation": {
                            "job_id": invalid_idea_job_id,
                            "status": "ready",
                        },
                    },
                ),
                (
                    invalid_top_level_item_id,
                    repair_plan_id,
                    "Invalid top-level field",
                    "COMPLETED",
                    100,
                    {
                        "steps": [{"id": "top-level-step"}],
                        "generated_at": 7,
                        "_generation": {
                            "job_id": invalid_top_level_job_id,
                            "status": "ready",
                        },
                    },
                ),
                *(
                    (
                        item_id,
                        repair_plan_id,
                        f"Invalid progressive ready IDs: {label}",
                        "COMPLETED",
                        100,
                        {
                            "steps": [
                                {
                                    "id": "one",
                                    "lesson_content": substantive_lesson,
                                }
                            ],
                            "_generation": {
                                "job_id": job_id,
                                "status": "partial",
                                **(
                                    {"ready_step_ids": ready_value}
                                    if ready_ids_present
                                    else {}
                                ),
                            },
                        },
                    )
                    for (
                        label,
                        item_id,
                        job_id,
                        ready_ids_present,
                        ready_value,
                    ) in invalid_ready_fixtures
                ),
            )
            for item_id, plan_id, title, status, progress, details in items:
                cursor.execute(
                    """
                    INSERT INTO plan_items
                        (id, plan_id, title, type, description, week_start,
                         week_end, success_metric, estimated_hours, status,
                         progress_percent, details_json)
                    VALUES (%s, %s, %s, 'COURSE', 'Migration repair fixture',
                            1, 1, 'Finish it', 1, %s, %s, %s)
                    """,
                    (item_id, plan_id, title, status, progress, Jsonb(details)),
                )

            for item_id, artifact_job_id in (
                (malformed_item_id, malformed_job_id),
                (partial_item_id, partial_job_id),
                (thin_partial_item_id, thin_partial_job_id),
                (skipped_item_id, skipped_job_id),
                (sticky_item_id, sticky_job_id),
                (ready_item_id, ready_job_id),
                (material_scalar_item_id, material_scalar_job_id),
                (invalid_step_field_item_id, invalid_step_field_job_id),
                (invalid_idea_item_id, invalid_idea_job_id),
                (invalid_top_level_item_id, invalid_top_level_job_id),
                *(
                    (item_id, job_id)
                    for _label, item_id, job_id, _present, _value in (
                        invalid_ready_fixtures
                    )
                ),
            ):
                cursor.execute(
                    """
                    INSERT INTO plan_item_completions
                        (id, user_id, plan_item_id, artifact_job_id, completed_at)
                    VALUES (%s, %s, %s, %s, now())
                    """,
                    (_id(), user_id, item_id, artifact_job_id),
                )
            for item_id, step_id, artifact_job_id in (
                (partial_item_id, "one", partial_job_id),
                # This exact completion is still hidden because only "one" is
                # named in ready_step_ids. It must not inflate the cache to 100.
                (partial_item_id, "two", partial_job_id),
                (thin_partial_item_id, "one", thin_partial_job_id),
                (
                    invalid_step_field_item_id,
                    "nested-step",
                    invalid_step_field_job_id,
                ),
                (
                    material_scalar_item_id,
                    "material-step",
                    material_scalar_job_id,
                ),
                *(
                    (item_id, "one", job_id)
                    for _label, item_id, job_id, _present, _value in (
                        invalid_ready_fixtures
                    )
                ),
            ):
                cursor.execute(
                    """
                    INSERT INTO plan_item_step_completions
                        (id, user_id, plan_item_id, step_id, artifact_job_id,
                         completed_at)
                    VALUES (%s, %s, %s, %s, %s, now())
                    """,
                    (_id(), user_id, item_id, step_id, artifact_job_id),
                )

            monkeypatch.setattr(
                audit_shape_migration.op,
                "execute",
                lambda statement: cursor.execute(str(statement)),
            )
            audit_shape_migration._repair_stamped_artifact_progress()

            checked_item_ids = [
                malformed_item_id,
                partial_item_id,
                thin_partial_item_id,
                skipped_item_id,
                sticky_item_id,
                ready_item_id,
                material_scalar_item_id,
                invalid_step_field_item_id,
                invalid_idea_item_id,
                invalid_top_level_item_id,
                *(item_id for _label, item_id, *_rest in invalid_ready_fixtures),
            ]
            cursor.execute(
                """
                SELECT id::text, status::text, progress_percent
                FROM plan_items
                WHERE id = ANY(%s::uuid[])
                """,
                (checked_item_ids,),
            )
            item_states = {row[0]: row[1:] for row in cursor.fetchall()}
            assert item_states[malformed_item_id] == ("NOT_STARTED", 0)
            assert item_states[partial_item_id] == ("IN_PROGRESS", 50)
            assert item_states[thin_partial_item_id] == ("NOT_STARTED", 0)
            assert item_states[skipped_item_id] == ("SKIPPED", 100)
            assert item_states[sticky_item_id] == ("NOT_STARTED", 0)
            assert item_states[ready_item_id] == ("COMPLETED", 100)
            assert item_states[material_scalar_item_id] == ("NOT_STARTED", 0)
            assert item_states[invalid_step_field_item_id] == ("NOT_STARTED", 0)
            assert item_states[invalid_idea_item_id] == ("NOT_STARTED", 0)
            assert item_states[invalid_top_level_item_id] == ("NOT_STARTED", 0)
            for _label, item_id, *_rest in invalid_ready_fixtures:
                assert item_states[item_id] == ("NOT_STARTED", 0)

            cursor.execute(
                """
                SELECT plan_item_id::text, completed_at IS NOT NULL
                FROM plan_item_completions
                WHERE plan_item_id = ANY(%s::uuid[])
                """,
                (checked_item_ids,),
            )
            completion_states = dict(cursor.fetchall())
            assert completion_states[malformed_item_id] is False
            assert completion_states[partial_item_id] is False
            assert completion_states[thin_partial_item_id] is False
            assert completion_states[skipped_item_id] is True
            assert completion_states[sticky_item_id] is False
            assert completion_states[ready_item_id] is True
            assert completion_states[material_scalar_item_id] is False
            assert completion_states[invalid_step_field_item_id] is False
            assert completion_states[invalid_idea_item_id] is False
            assert completion_states[invalid_top_level_item_id] is False
            for _label, item_id, *_rest in invalid_ready_fixtures:
                assert completion_states[item_id] is False

            cursor.execute(
                """
                SELECT count(*), bool_and(completed_at IS NOT NULL)
                FROM plan_item_step_completions
                WHERE plan_item_id = %s AND artifact_job_id = %s
                """,
                (partial_item_id, partial_job_id),
            )
            assert cursor.fetchone() == (2, True)

            cursor.execute(
                """
                SELECT completed_at IS NOT NULL
                FROM plan_item_step_completions
                WHERE plan_item_id = %s AND artifact_job_id = %s
                """,
                (thin_partial_item_id, thin_partial_job_id),
            )
            assert cursor.fetchone() == (True,)

            cursor.execute(
                """
                SELECT id::text, completed_at IS NOT NULL
                FROM plans WHERE id IN (%s, %s, %s)
                """,
                (repair_plan_id, sticky_plan_id, ready_plan_id),
            )
            plan_states = dict(cursor.fetchall())
            assert plan_states[repair_plan_id] is False
            assert plan_states[sticky_plan_id] is True
            assert plan_states[ready_plan_id] is True


def test_h9_converges_broken_artifact_references_on_postgres(monkeypatch):
    owner_id = _id()
    other_user_id = _id()
    repair_plan_id = _id()
    valid_plan_id = _id()
    carrier_item_id = _id()
    missing_item_id = _id()
    wrong_item_id = _id()
    wrong_user_item_id = _id()
    invalid_status_item_id = _id()
    partial_item_id = _id()
    thin_partial_item_id = _id()
    valid_item_id = _id()
    revoked_item_id = _id()
    noncanonical_item_id = _id()
    missing_job_id = _id()
    wrong_item_job_id = _id()
    wrong_user_job_id = _id()
    invalid_status_job_id = _id()
    partial_job_id = _id()
    thin_partial_job_id = _id()
    valid_job_id = _id()
    revoked_job_id = _id()
    noncanonical_job_id = _id()
    invalid_ready_fixtures = (
        ("missing", _id(), _id(), False, None),
        ("scalar", _id(), _id(), True, "step-1"),
        ("non-string", _id(), _id(), True, [7]),
        ("duplicate", _id(), _id(), True, ["step-1", "step-1"]),
        ("untrimmed", _id(), _id(), True, [" step-1"]),
        ("overlong", _id(), _id(), True, ["x" * 101]),
        ("unknown", _id(), _id(), True, ["not-a-current-step"]),
    )
    invalid_ready_by_item = {
        item_id: (ready_ids_present, ready_value)
        for _label, item_id, _job_id, ready_ids_present, ready_value in (
            invalid_ready_fixtures
        )
    }
    substantive_lesson = "evidence\vproof\N{NO-BREAK SPACE}" * 950
    assert len(substantive_lesson.split()) == 1900

    with psycopg.connect(_postgres_dsn()) as conn:
        with conn.transaction(force_rollback=True), conn.cursor() as cursor:
            for user_id, label in ((owner_id, "owner"), (other_user_id, "other")):
                cursor.execute(
                    """
                    INSERT INTO users (id, email, password_hash)
                    VALUES (%s, %s, 'test')
                    """,
                    (user_id, f"h9-{label}-{user_id}@example.test"),
                )
            for plan_id in (repair_plan_id, valid_plan_id):
                cursor.execute(
                    """
                    INSERT INTO plans
                        (id, user_id, target_age, duration_weeks, weekly_hours,
                         cycle_number, completed_at)
                    VALUES (%s, %s, 40, 12, 5, 1, now())
                    """,
                    (plan_id, owner_id),
                )

            items = (
                (
                    carrier_item_id,
                    repair_plan_id,
                    "HABIT",
                    "NOT_STARTED",
                    0,
                    None,
                    None,
                ),
                (
                    missing_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    missing_job_id,
                    "ready",
                ),
                (
                    wrong_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    wrong_item_job_id,
                    "ready",
                ),
                (
                    wrong_user_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    wrong_user_job_id,
                    "ready",
                ),
                (
                    invalid_status_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    invalid_status_job_id,
                    "failed",
                ),
                (
                    partial_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    partial_job_id,
                    "partial",
                ),
                (
                    thin_partial_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    thin_partial_job_id,
                    "partial",
                ),
                (
                    valid_item_id,
                    valid_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    valid_job_id,
                    "ready",
                ),
                (
                    revoked_item_id,
                    valid_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    revoked_job_id,
                    "revoked",
                ),
                (
                    noncanonical_item_id,
                    repair_plan_id,
                    "COURSE",
                    "COMPLETED",
                    100,
                    noncanonical_job_id.upper(),
                    "ready",
                ),
                *(
                    (
                        item_id,
                        repair_plan_id,
                        "COURSE",
                        "COMPLETED",
                        100,
                        job_id,
                        "partial",
                    )
                    for _label, item_id, job_id, _present, _value in (
                        invalid_ready_fixtures
                    )
                ),
            )
            for (
                item_id,
                plan_id,
                item_type,
                status,
                progress,
                artifact_job_id,
                generation_status,
            ) in items:
                details = None
                if artifact_job_id is not None:
                    steps = [{"id": "step-1"}]
                    generation = {
                        "job_id": artifact_job_id,
                        "status": generation_status,
                    }
                    if item_id == partial_item_id:
                        steps = [
                            {
                                "id": "step-1",
                                "lesson_content": substantive_lesson,
                            },
                            {
                                "id": "step-2",
                                "lesson_content": substantive_lesson,
                            },
                        ]
                        generation["ready_step_ids"] = ["step-1"]
                    elif item_id == thin_partial_item_id:
                        steps[0]["lesson_content"] = "evidence " * 1899
                        generation["ready_step_ids"] = ["step-1"]
                    elif item_id in invalid_ready_by_item:
                        steps[0]["lesson_content"] = substantive_lesson
                        ready_ids_present, ready_value = invalid_ready_by_item[item_id]
                        if ready_ids_present:
                            generation["ready_step_ids"] = ready_value
                    details = {
                        "steps": steps,
                        "_generation": generation,
                    }
                cursor.execute(
                    """
                    INSERT INTO plan_items
                        (id, plan_id, title, type, description, week_start,
                         week_end, success_metric, estimated_hours, status,
                         progress_percent, details_json)
                    VALUES (%s, %s, 'h9 convergence item', %s,
                            'Migration repair fixture', 1, 1, 'Finish it', 1,
                            %s, %s, %s)
                    """,
                    (
                        item_id,
                        plan_id,
                        item_type,
                        status,
                        progress,
                        Jsonb(details) if details is not None else None,
                    ),
                )

            for job_id, item_id, user_id, job_status in (
                (wrong_item_job_id, carrier_item_id, owner_id, "completed"),
                (wrong_user_job_id, wrong_user_item_id, other_user_id, "completed"),
                (
                    invalid_status_job_id,
                    invalid_status_item_id,
                    owner_id,
                    "completed",
                ),
                (partial_job_id, partial_item_id, owner_id, "running"),
                (thin_partial_job_id, thin_partial_item_id, owner_id, "running"),
                # Operational status is intentionally irrelevant once a READY
                # artifact has been durably published under the exact owner.
                (valid_job_id, valid_item_id, owner_id, "failed"),
                # Revocation retains exact terminal reader history until a
                # replacement is published.
                (revoked_job_id, revoked_item_id, owner_id, "completed"),
                (noncanonical_job_id, noncanonical_item_id, owner_id, "completed"),
                *(
                    (job_id, item_id, owner_id, "running")
                    for _label, item_id, job_id, _present, _value in (
                        invalid_ready_fixtures
                    )
                ),
            ):
                cursor.execute(
                    """
                    INSERT INTO plan_item_detail_jobs
                        (id, plan_item_id, user_id, status, progress_percent)
                    VALUES (%s, %s, %s, %s, 100)
                    """,
                    (job_id, item_id, user_id, job_status),
                )

            artifact_items = (
                (missing_item_id, missing_job_id),
                (wrong_item_id, wrong_item_job_id),
                (wrong_user_item_id, wrong_user_job_id),
                (invalid_status_item_id, invalid_status_job_id),
                (partial_item_id, partial_job_id),
                (thin_partial_item_id, thin_partial_job_id),
                (valid_item_id, valid_job_id),
                (revoked_item_id, revoked_job_id),
                (noncanonical_item_id, noncanonical_job_id),
                *(
                    (item_id, job_id)
                    for _label, item_id, job_id, _present, _value in (
                        invalid_ready_fixtures
                    )
                ),
            )
            for item_id, artifact_job_id in artifact_items:
                cursor.execute(
                    """
                    INSERT INTO plan_item_completions
                        (id, user_id, plan_item_id, artifact_job_id, completed_at)
                    VALUES (%s, %s, %s, %s, now())
                    """,
                    (_id(), owner_id, item_id, artifact_job_id),
                )
                cursor.execute(
                    """
                    INSERT INTO plan_item_step_completions
                        (id, user_id, plan_item_id, step_id, artifact_job_id,
                         completed_at)
                    VALUES (%s, %s, %s, 'step-1', %s, now())
                    """,
                    (_id(), owner_id, item_id, artifact_job_id),
                )

            # An exact but not-yet-exposed completion must remain durable while
            # being excluded from the progressive cache numerator.
            cursor.execute(
                """
                INSERT INTO plan_item_step_completions
                    (id, user_id, plan_item_id, step_id, artifact_job_id,
                     completed_at)
                VALUES (%s, %s, %s, 'step-2', %s, now())
                """,
                (_id(), owner_id, partial_item_id, partial_job_id),
            )

            monkeypatch.setattr(
                h8_convergence_migration.op,
                "execute",
                lambda statement: cursor.execute(str(statement)),
            )
            h8_convergence_migration._repair_stamped_artifact_progress()

            cursor.execute(
                """
                SELECT id::text, status::text, progress_percent
                FROM plan_items
                WHERE id = ANY(%s::uuid[])
                """,
                ([item_id for item_id, _job_id in artifact_items],),
            )
            item_states = {row[0]: row[1:] for row in cursor.fetchall()}
            for invalid_item_id in (
                missing_item_id,
                wrong_item_id,
                wrong_user_item_id,
                invalid_status_item_id,
                noncanonical_item_id,
                thin_partial_item_id,
                *(item_id for _label, item_id, *_rest in invalid_ready_fixtures),
            ):
                assert item_states[invalid_item_id] == ("NOT_STARTED", 0)
            assert item_states[partial_item_id] == ("IN_PROGRESS", 50)
            assert item_states[valid_item_id] == ("COMPLETED", 100)
            assert item_states[revoked_item_id] == ("COMPLETED", 100)

            cursor.execute(
                """
                SELECT plan_item_id::text, completed_at IS NOT NULL
                FROM plan_item_completions
                WHERE plan_item_id = ANY(%s::uuid[])
                """,
                ([item_id for item_id, _job_id in artifact_items],),
            )
            completion_states = dict(cursor.fetchall())
            for repaired_item_id in (
                missing_item_id,
                wrong_item_id,
                wrong_user_item_id,
                invalid_status_item_id,
                partial_item_id,
                thin_partial_item_id,
                *(item_id for _label, item_id, *_rest in invalid_ready_fixtures),
            ):
                assert completion_states[repaired_item_id] is False
            assert completion_states[valid_item_id] is True
            assert completion_states[revoked_item_id] is True
            # Normalize only syntactically UUID-shaped variants for cleanup;
            # runtime identity remains strict canonical text and the JSON marker
            # is never cast to UUID inside the migration.
            assert completion_states[noncanonical_item_id] is False

            cursor.execute(
                """
                SELECT count(*)
                FROM plan_item_step_completions
                WHERE plan_item_id = ANY(%s::uuid[]) AND completed_at IS NOT NULL
                """,
                ([item_id for item_id, _job_id in artifact_items],),
            )
            assert cursor.fetchone() == (len(artifact_items) + 1,)

            cursor.execute(
                """
                SELECT id::text, completed_at IS NOT NULL
                FROM plans WHERE id IN (%s, %s)
                """,
                (repair_plan_id, valid_plan_id),
            )
            plan_states = dict(cursor.fetchall())
            assert plan_states[repair_plan_id] is False
            assert plan_states[valid_plan_id] is True


def test_orm_generation_job_delete_delegates_report_unlinking_to_postgres():
    """A loaded select-in collection must not make SQLAlchemy emit SET NULL."""

    skill_id = _id()
    module_id = _id()
    version_id = _id()
    generation_job_id = _id()
    report_id = _id()
    input_hash = generation_job_id.replace("-", "") * 2
    engine = create_engine(settings.database_url)

    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            connection.execute(
                text(
                    """
                    INSERT INTO curriculum_skills
                        (id, key, domain, name, description, skill_type)
                    VALUES (:id, :key, 'investing', 'ORM cascade skill',
                            'Exercises the generation-job report contract.',
                            'procedural')
                    """
                ),
                {"id": skill_id, "key": f"test.orm-cascade.{skill_id}"},
            )
            connection.execute(
                text(
                    """
                    INSERT INTO canonical_modules
                        (id, skill_id, key, level, title, learning_outcome,
                         artifact_type, estimated_total_minutes)
                    VALUES (:id, :skill_id, :key, 'beginner', 'ORM cascade module',
                            'Verify database-owned report unlinking.', 'memo', 55)
                    """
                ),
                {
                    "id": module_id,
                    "skill_id": skill_id,
                    "key": f"test.orm-cascade.module.{module_id}",
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO canonical_module_versions
                        (id, module_id, version_number, content_json,
                         source_manifest_json, technique_plan_json, content_hash,
                         source_hash, retrieval_metadata_json,
                         retrieval_metadata_hash, estimated_minutes,
                         prompt_version, model_name)
                    VALUES (:id, :module_id, 1, '{}'::jsonb, '{}'::jsonb,
                            '{}'::jsonb, :content_hash, :source_hash, '{}'::jsonb,
                            :retrieval_hash, 55, 'orm-contract-v1', 'test-model')
                    """
                ),
                {
                    "id": version_id,
                    "module_id": module_id,
                    "content_hash": HASH_A,
                    "source_hash": HASH_B,
                    "retrieval_hash": HASH_C,
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO curriculum_generation_jobs
                        (id, skill_id, module_id, module_version_id, input_hash,
                         input_json, pipeline_version)
                    VALUES (:id, :skill_id, :module_id, :version_id, :input_hash,
                            '{}'::jsonb, 'orm-contract-v1')
                    """
                ),
                {
                    "id": generation_job_id,
                    "skill_id": skill_id,
                    "module_id": module_id,
                    "version_id": version_id,
                    "input_hash": input_hash,
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO module_quality_reports
                        (id, module_version_id, generation_job_id, review_type,
                         verdict, reviewed_content_hash)
                    VALUES (:id, :version_id, :job_id, 'factual', 'passed',
                            :content_hash)
                    """
                ),
                {
                    "id": report_id,
                    "version_id": version_id,
                    "job_id": generation_job_id,
                    "content_hash": HASH_A,
                },
            )

            with Session(bind=connection, expire_on_commit=False) as session:
                job = session.execute(
                    select(CurriculumGenerationJob).where(
                        CurriculumGenerationJob.id == generation_job_id
                    )
                ).scalar_one()
                assert [str(report.id) for report in job.quality_reports] == [report_id]

                session.delete(job)
                session.flush()

                assert (
                    session.execute(
                        select(ModuleQualityReport.generation_job_id).where(
                            ModuleQualityReport.id == report_id
                        )
                    ).scalar_one()
                    is None
                )
        finally:
            if transaction.is_active:
                transaction.rollback()
    engine.dispose()


def test_orm_learner_state_delete_delegates_ready_snapshot_unlinking_to_postgres():
    """A loaded relationship must not bypass the guarded database SET NULL."""

    skill_id = _id()
    module_id = _id()
    version_id = _id()
    session_id = _id()
    user_id = _id()
    learner_state_id = _id()
    lesson_id = _id()
    engine = create_engine(settings.database_url)

    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            connection.execute(
                text(
                    """
                    INSERT INTO curriculum_skills
                        (id, key, domain, name, description, skill_type)
                    VALUES (:id, :key, 'investing', 'ORM learner state skill',
                            'Exercises database-owned snapshot unlinking.',
                            'procedural')
                    """
                ),
                {"id": skill_id, "key": f"test.orm-state.{skill_id}"},
            )
            connection.execute(
                text(
                    """
                    INSERT INTO canonical_modules
                        (id, skill_id, key, level, title, learning_outcome,
                         artifact_type, estimated_total_minutes)
                    VALUES (:id, :skill_id, :key, 'beginner', 'ORM state module',
                            'Verify database-owned learner-state unlinking.',
                            'memo', 55)
                    """
                ),
                {
                    "id": module_id,
                    "skill_id": skill_id,
                    "key": f"test.orm-state.module.{module_id}",
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO canonical_module_versions
                        (id, module_id, version_number, content_json,
                         source_manifest_json, technique_plan_json, content_hash,
                         source_hash, retrieval_metadata_json,
                         retrieval_metadata_hash, estimated_minutes,
                         prompt_version, model_name)
                    VALUES (:id, :module_id, 1, '{}'::jsonb, '{}'::jsonb,
                            '{}'::jsonb, :content_hash, :source_hash, '{}'::jsonb,
                            :retrieval_hash, 55, 'orm-contract-v1', 'test-model')
                    """
                ),
                {
                    "id": version_id,
                    "module_id": module_id,
                    "content_hash": HASH_A,
                    "source_hash": HASH_B,
                    "retrieval_hash": HASH_C,
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO module_sessions
                        (id, module_version_id, position, title,
                         learning_objective, estimated_minutes, content_json,
                         assessment_json, artifact_spec_json,
                         technique_plan_json, content_hash)
                    VALUES (:id, :version_id, 1, 'Apply', 'Produce evidence.', 55,
                            '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
                            :content_hash)
                    """
                ),
                {"id": session_id, "version_id": version_id, "content_hash": HASH_D},
            )
            connection.execute(
                text(
                    """
                    INSERT INTO users (id, email, password_hash)
                    VALUES (:id, :email, 'test')
                    """
                ),
                {"id": user_id, "email": f"orm-state-{user_id}@example.test"},
            )
            connection.execute(
                text(
                    """
                    INSERT INTO learner_skill_states
                        (id, user_id, skill_id, state_version, state_hash)
                    VALUES (:id, :user_id, :skill_id, 1, :state_hash)
                    """
                ),
                {
                    "id": learner_state_id,
                    "user_id": user_id,
                    "skill_id": skill_id,
                    "state_hash": HASH_A,
                },
            )
            connection.execute(
                text(
                    """
                    INSERT INTO personalized_lesson_versions
                        (id, user_id, module_session_id, module_version_id,
                         learner_state_id, version_number, status,
                         learner_state_snapshot_json, learner_state_hash,
                         mentor_evidence_snapshot_json, mentor_evidence_hash,
                         personalization_brief_json, input_hash, content_json,
                         content_hash, estimated_minutes, prompt_version,
                         model_name, ready_at)
                    VALUES (:id, :user_id, :session_id, :version_id, :state_id,
                            1, 'ready', '{}'::jsonb, :state_hash, '{}'::jsonb,
                            :mentor_hash, '{}'::jsonb, :input_hash, '{}'::jsonb,
                            :content_hash, 55, 'personal-v1', 'test-model', now())
                    """
                ),
                {
                    "id": lesson_id,
                    "user_id": user_id,
                    "session_id": session_id,
                    "version_id": version_id,
                    "state_id": learner_state_id,
                    "state_hash": HASH_A,
                    "mentor_hash": HASH_B,
                    "input_hash": HASH_C,
                    "content_hash": HASH_D,
                },
            )

            with Session(bind=connection, expire_on_commit=False) as session:
                learner_state = session.execute(
                    select(LearnerSkillState).where(
                        LearnerSkillState.id == learner_state_id
                    )
                ).scalar_one()
                assert [
                    str(lesson.id) for lesson in learner_state.personalized_lessons
                ] == [lesson_id]

                session.delete(learner_state)
                session.flush()

                assert (
                    session.execute(
                        select(PersonalizedLessonVersion.learner_state_id).where(
                            PersonalizedLessonVersion.id == lesson_id
                        )
                    ).scalar_one()
                    is None
                )
        finally:
            if transaction.is_active:
                transaction.rollback()
    engine.dispose()


def test_curriculum_guards_and_user_privacy_cascade_on_postgres():
    skill_id = _id()
    technique_id = _id()
    direct_technique_id = _id()
    module_id = _id()
    version_id = _id()
    session_id = _id()
    user_id = _id()
    other_user_id = _id()
    plan_id = _id()
    other_plan_id = _id()
    plan_item_id = _id()
    other_plan_item_id = _id()
    learner_state_id = _id()
    lesson_id = _id()
    other_lesson_id = _id()
    assignment_id = _id()
    retry_assignment_id = _id()
    second_retry_assignment_id = _id()
    idol_id = _id()
    cascade_idol_id = _id()
    claim_id = _id()
    cascade_claim_id = _id()
    finalized_cascade_claim_id = _id()
    revised_claim_id = _id()
    generation_job_id = _id()
    report_id = _id()

    with psycopg.connect(_postgres_dsn()) as conn:
        # Every row below is test-only, including rows whose direct deletion is
        # intentionally forbidden by append-only triggers.
        with conn.transaction(force_rollback=True), conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT indexdef
                FROM pg_indexes
                WHERE schemaname = current_schema()
                  AND indexname = 'ix_personalized_lessons_ready_mentor_evidence'
                """
            )
            mentor_index = cursor.fetchone()
            assert mentor_index is not None
            assert "USING gin" in mentor_index[0]
            assert "jsonb_path_ops" in mentor_index[0]
            assert "revoked_at IS NULL" in mentor_index[0]

            cursor.execute(
                """
                INSERT INTO curriculum_skills
                    (id, key, domain, name, description, skill_type, status)
                VALUES (%s, %s, 'investing', 'Margin of safety',
                        'Estimate downside before committing capital.',
                        'procedural', 'draft')
                """,
                (skill_id, f"test.margin_of_safety.{skill_id}"),
            )
            cursor.execute(
                """
                INSERT INTO learning_technique_versions
                    (id, technique_key, version_number, title, summary,
                     evidence_level, implementation_contract_json,
                     source_manifest_json, content_hash, source_hash, status)
                VALUES (%s, %s, 1, 'Test retrieval', 'Recall before review.',
                        'strong', %s, %s, %s, %s, 'draft')
                """,
                (
                    technique_id,
                    f"test_retrieval_{technique_id}",
                    Jsonb({"steps": ["recall", "check"]}),
                    Jsonb({"sources": ["source-1"]}),
                    HASH_A,
                    HASH_B,
                ),
            )
            cursor.execute(
                """
                INSERT INTO learning_technique_versions
                    (id, technique_key, version_number, title, summary,
                     evidence_level, implementation_contract_json,
                     source_manifest_json, content_hash, source_hash, status,
                     published_at, reviewed_at)
                VALUES (%s, %s, 1, 'Direct published technique',
                        'A reviewed technique may be inserted atomically.',
                        'strong', %s, %s, %s, %s, 'published', now(), now())
                """,
                (
                    direct_technique_id,
                    f"test_direct_published_{direct_technique_id}",
                    Jsonb({"steps": ["recall", "check"]}),
                    Jsonb({"sources": ["source-2"]}),
                    HASH_C,
                    HASH_D,
                ),
            )
            cursor.execute(
                """
                SELECT status::text, published_at IS NOT NULL
                FROM learning_technique_versions WHERE id = %s
                """,
                (direct_technique_id,),
            )
            assert cursor.fetchone() == ("published", True)
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO learning_technique_versions
                    (id, technique_key, version_number, title, summary,
                     evidence_level, implementation_contract_json,
                     source_manifest_json, content_hash, source_hash, status,
                     published_at)
                VALUES (%s, %s, 1, 'Ambiguous draft', 'Invalid audit shape.',
                        'strong', %s, %s, %s, %s, 'draft', now())
                """,
                (
                    _id(),
                    f"test_ambiguous_draft_{_id()}",
                    Jsonb({"steps": ["recall"]}),
                    Jsonb({"sources": ["source-3"]}),
                    HASH_A,
                    HASH_B,
                ),
                "ck_learning_technique_versions_audit_shape",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO learning_technique_versions
                    (id, technique_key, version_number, title, summary,
                     evidence_level, implementation_contract_json,
                     source_manifest_json, content_hash, source_hash, status,
                     published_at, revoked_at, revocation_reason)
                VALUES (%s, %s, 1, 'Ambiguous revocation',
                        'Blank reasons are not auditable.', 'strong', %s, %s,
                        %s, %s, 'revoked', now(), now(), U&'\\0009\\00A0')
                """,
                (
                    _id(),
                    f"test_blank_revocation_{_id()}",
                    Jsonb({"steps": ["recall"]}),
                    Jsonb({"sources": ["source-3"]}),
                    HASH_A,
                    HASH_B,
                ),
                "ck_learning_technique_versions_audit_shape",
            )
            cursor.execute(
                """
                UPDATE learning_technique_versions
                SET status = 'published', published_at = now(), reviewed_at = now()
                WHERE id = %s
                """,
                (technique_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE learning_technique_versions
                SET published_at = published_at + interval '1 second'
                WHERE id = %s
                """,
                (technique_id,),
                "lifecycle audit fields are immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE learning_technique_versions
                SET reviewed_at = reviewed_at + interval '1 second'
                WHERE id = %s
                """,
                (technique_id,),
                "lifecycle audit fields are immutable",
            )
            cursor.execute(
                """
                UPDATE learning_technique_versions
                SET status = 'revoked', revoked_at = now(),
                    revocation_reason = 'Evidence superseded'
                WHERE id = %s
                """,
                (technique_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE learning_technique_versions
                SET revocation_reason = 'Rewritten audit history'
                WHERE id = %s
                """,
                (technique_id,),
                "lifecycle audit fields are immutable",
            )
            cursor.execute(
                """
                INSERT INTO canonical_modules
                    (id, skill_id, key, level, language, title,
                     learning_outcome, artifact_type, estimated_total_minutes, status)
                VALUES (%s, %s, %s, 'beginner', 'en', 'Margin of safety',
                        'Produce and defend a downside range.', 'valuation', 55, 'draft')
                """,
                (module_id, skill_id, f"test.module.{module_id}"),
            )
            cursor.execute(
                """
                INSERT INTO canonical_module_versions
                    (id, module_id, version_number, status, content_json,
                     source_manifest_json, technique_plan_json, content_hash,
                     source_hash, retrieval_metadata_json,
                     retrieval_metadata_hash, estimated_minutes, quality_score,
                     prompt_version, gate_version, model_name)
                VALUES (%s, %s, 1, 'draft', %s, %s, %s, %s, %s, %s, %s, 55,
                        0.95, 'module-v1', 'gates-v1', 'quality-model')
                """,
                (
                    version_id,
                    module_id,
                    Jsonb({"title": "Margin of safety"}),
                    Jsonb({"sources": ["source-1"]}),
                    Jsonb({"bindings": ["retrieval-practice-v1"]}),
                    HASH_A,
                    HASH_B,
                    Jsonb({"skill_key": "investing.margin_of_safety"}),
                    HASH_C,
                ),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO canonical_module_versions
                    (id, module_id, version_number, status, content_json,
                     source_manifest_json, technique_plan_json, content_hash,
                     source_hash, retrieval_metadata_json,
                     retrieval_metadata_hash, estimated_minutes,
                     prompt_version, model_name, published_at)
                VALUES (%s, %s, 99, 'draft', %s, %s, %s, %s, %s, %s, %s,
                        55, 'module-v1', 'quality-model', now())
                """,
                (
                    _id(),
                    module_id,
                    Jsonb({"title": "Ambiguous draft"}),
                    Jsonb({"sources": ["source-1"]}),
                    Jsonb({"bindings": []}),
                    HASH_D,
                    HASH_C,
                    Jsonb({}),
                    HASH_B,
                ),
                "ck_canonical_module_versions_audit_shape",
            )
            # Sessions are assembled while the parent is mutable, then the
            # complete version is published in the same transaction.
            cursor.execute(
                """
                INSERT INTO module_sessions
                    (id, module_version_id, position, title, learning_objective,
                     estimated_minutes, content_json, assessment_json,
                     artifact_spec_json, technique_plan_json, content_hash)
                VALUES (%s, %s, 1, 'Apply the method',
                        'Produce a valuation range.', 55, %s, %s, %s, %s, %s)
                """,
                (
                    session_id,
                    version_id,
                    Jsonb({"explanation": "Use evidence."}),
                    Jsonb({"rubric": {}}),
                    Jsonb({"type": "valuation"}),
                    Jsonb({"bindings": []}),
                    HASH_C,
                ),
            )
            cursor.execute(
                """
                UPDATE canonical_module_versions
                SET status = 'published', published_at = now()
                WHERE id = %s
                """,
                (version_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE canonical_module_versions
                SET published_at = published_at + interval '1 second'
                WHERE id = %s
                """,
                (version_id,),
                "lifecycle audit fields are immutable",
            )
            cursor.execute(
                """
                UPDATE canonical_modules
                SET status = 'active', current_published_version_id = %s
                WHERE id = %s
                """,
                (version_id, module_id),
            )

            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO module_sessions
                    (id, module_version_id, position, title, learning_objective,
                     estimated_minutes, content_json, assessment_json,
                     artifact_spec_json, technique_plan_json, content_hash)
                VALUES (%s, %s, 2, 'Late mutation', 'Should fail.', 10,
                        %s, %s, %s, %s, %s)
                """,
                (
                    _id(),
                    version_id,
                    Jsonb({}),
                    Jsonb({}),
                    Jsonb({}),
                    Jsonb({}),
                    HASH_D,
                ),
                "sessions of published module versions are immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                "UPDATE canonical_module_versions SET quality_score = 0.10 WHERE id = %s",
                (version_id,),
                "published canonical module content is immutable",
            )

            generation_job_input_hash = generation_job_id.replace("-", "") * 2
            cursor.execute(
                """
                INSERT INTO curriculum_generation_jobs
                    (id, skill_id, module_id, module_version_id, input_hash,
                     input_json, pipeline_version)
                VALUES (%s, %s, %s, %s, %s, %s, 'contract-v1')
                """,
                (
                    generation_job_id,
                    skill_id,
                    module_id,
                    version_id,
                    generation_job_input_hash,
                    Jsonb({"contract": "quality-report-fk"}),
                ),
            )
            cursor.execute(
                """
                INSERT INTO module_quality_reports
                    (id, module_version_id, generation_job_id, review_type,
                     verdict, score, attempt, reviewed_content_hash, issues_json,
                     evidence_json, deterministic_checks_json)
                VALUES (%s, %s, %s, 'factual', 'passed', 0.95, 1, %s, %s, %s, %s)
                """,
                (
                    report_id,
                    version_id,
                    generation_job_id,
                    HASH_A,
                    Jsonb([]),
                    Jsonb({}),
                    Jsonb({"citations_resolve": True}),
                ),
            )
            _assert_rejected(
                conn,
                cursor,
                "UPDATE module_quality_reports SET score = 0.1 WHERE id = %s",
                (report_id,),
                "module quality reports are append-only",
            )
            _assert_rejected(
                conn,
                cursor,
                "UPDATE module_quality_reports SET generation_job_id = NULL WHERE id = %s",
                (report_id,),
                "module quality reports are append-only",
            )

            cursor.execute(
                """
                SELECT generation_job_id, to_jsonb(report) - 'generation_job_id'
                FROM module_quality_reports AS report
                WHERE id = %s
                """,
                (report_id,),
            )
            job_link_before, report_before = cursor.fetchone()
            assert str(job_link_before) == generation_job_id

            # The database-owned SET NULL action may clear only the provenance
            # link.  The append-only report itself must remain byte-for-byte
            # equivalent in every other persisted field.
            cursor.execute(
                "DELETE FROM curriculum_generation_jobs WHERE id = %s",
                (generation_job_id,),
            )
            cursor.execute(
                """
                SELECT generation_job_id, to_jsonb(report) - 'generation_job_id'
                FROM module_quality_reports AS report
                WHERE id = %s
                """,
                (report_id,),
            )
            job_link_after, report_after = cursor.fetchone()
            assert job_link_after is None
            assert report_after == report_before

            cursor.execute(
                "INSERT INTO idols (id, name, domain, status) VALUES (%s, %s, %s, 'published')",
                (idol_id, f"Test mentor {idol_id}", "investing"),
            )
            ambiguous_claim_id = _id()
            ambiguous_claim_hash = ambiguous_claim_id.replace("-", "") * 2
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO mentor_evidence_claims
                    (id, idol_id, claim_type, claim_text, normalized_hash,
                     source_title, source_url, evidence_excerpt, source_hash,
                     confidence, verification_status, verified_at)
                VALUES (%s, %s, 'principle', 'Ambiguous pending evidence', %s,
                        'Transcript', 'https://example.test/ambiguous',
                        'Pending evidence cannot already be verified.', %s,
                        0.5, 'pending', now())
                """,
                (
                    ambiguous_claim_id,
                    idol_id,
                    ambiguous_claim_hash,
                    ambiguous_claim_hash,
                ),
                "ck_mentor_evidence_claims_audit_shape",
            )
            cursor.execute(
                """
                INSERT INTO mentor_evidence_claims
                    (id, idol_id, claim_type, claim_text, normalized_hash,
                     source_title, source_url, evidence_excerpt, evidence_json,
                     source_hash, skill_tags_json, confidence, verification_status)
                VALUES (%s, %s, 'recommended_book', %s, %s, 'Transcript',
                        'https://example.test/evidence', %s, %s, %s, %s, 0.95, 'pending')
                """,
                (
                    claim_id,
                    idol_id,
                    "Read a foundational value-investing text.",
                    HASH_C,
                    "A source-backed excerpt.",
                    Jsonb({}),
                    HASH_D,
                    Jsonb(["investing"]),
                ),
            )
            cursor.execute(
                "INSERT INTO mentor_evidence_claim_skills (claim_id, skill_id) VALUES (%s, %s)",
                (claim_id, skill_id),
            )
            cursor.execute(
                """
                UPDATE mentor_evidence_claims
                SET verification_status = 'verified', verified_at = now()
                WHERE id = %s
                """,
                (claim_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE mentor_evidence_claims
                SET verified_at = verified_at + interval '1 second'
                WHERE id = %s
                """,
                (claim_id,),
                "lifecycle audit fields are immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                "UPDATE mentor_evidence_claims SET claim_text = 'rewritten' WHERE id = %s",
                (claim_id,),
                "finalized mentor evidence is immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                "DELETE FROM mentor_evidence_claims WHERE id = %s",
                (claim_id,),
                "finalized mentor evidence claims are append-only",
            )
            _assert_rejected(
                conn,
                cursor,
                "DELETE FROM mentor_evidence_claim_skills WHERE claim_id = %s AND skill_id = %s",
                (claim_id, skill_id),
                "skill bindings of finalized mentor evidence are immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE mentor_evidence_claim_skills
                SET skill_id = skill_id
                WHERE claim_id = %s AND skill_id = %s
                """,
                (claim_id, skill_id),
                "skill bindings of finalized mentor evidence are immutable",
            )

            cascade_claim_hash = cascade_claim_id.replace("-", "") * 2
            cursor.execute(
                """
                INSERT INTO mentor_evidence_claims
                    (id, idol_id, claim_type, claim_text, normalized_hash,
                     source_title, source_url, evidence_excerpt, evidence_json,
                     source_hash, skill_tags_json, confidence, verification_status)
                VALUES (%s, %s, 'principle', %s, %s, 'Draft notes',
                        'https://example.test/draft', %s, %s, %s, %s, 0.60, 'pending')
                """,
                (
                    cascade_claim_id,
                    idol_id,
                    "A draft claim may be removed with all of its bindings.",
                    cascade_claim_hash,
                    "Draft evidence.",
                    Jsonb({}),
                    cascade_claim_hash,
                    Jsonb(["investing"]),
                ),
            )
            cursor.execute(
                "INSERT INTO mentor_evidence_claim_skills (claim_id, skill_id) VALUES (%s, %s)",
                (cascade_claim_id, skill_id),
            )
            cursor.execute(
                "DELETE FROM mentor_evidence_claims WHERE id = %s",
                (cascade_claim_id,),
            )
            cursor.execute(
                "SELECT count(*) FROM mentor_evidence_claim_skills WHERE claim_id = %s",
                (cascade_claim_id,),
            )
            assert cursor.fetchone() == (0,)

            # Deleting an idol owns the lifecycle of its claims. The nested
            # database cascade may remove finalized evidence and its bindings,
            # while a direct finalized-claim DELETE remains forbidden.
            cursor.execute(
                "INSERT INTO idols (id, name, domain, status) VALUES (%s, %s, %s, 'published')",
                (
                    cascade_idol_id,
                    f"Cascade mentor {cascade_idol_id}",
                    "investing",
                ),
            )
            finalized_cascade_hash = finalized_cascade_claim_id.replace("-", "") * 2
            cursor.execute(
                """
                INSERT INTO mentor_evidence_claims
                    (id, idol_id, claim_type, claim_text, normalized_hash,
                     source_title, source_url, evidence_excerpt, evidence_json,
                     source_hash, skill_tags_json, confidence,
                     verification_status)
                VALUES (%s, %s, 'principle', %s, %s, 'Verified notes',
                        'https://example.test/finalized-cascade', %s, %s, %s, %s,
                        0.90, 'pending')
                """,
                (
                    finalized_cascade_claim_id,
                    cascade_idol_id,
                    "A finalized claim follows its owning idol privacy lifecycle.",
                    finalized_cascade_hash,
                    "Verified cascade evidence.",
                    Jsonb({}),
                    finalized_cascade_hash,
                    Jsonb(["investing"]),
                ),
            )
            cursor.execute(
                "INSERT INTO mentor_evidence_claim_skills (claim_id, skill_id) VALUES (%s, %s)",
                (finalized_cascade_claim_id, skill_id),
            )
            cursor.execute(
                """
                UPDATE mentor_evidence_claims
                SET verification_status = 'verified', verified_at = now()
                WHERE id = %s
                """,
                (finalized_cascade_claim_id,),
            )
            cursor.execute("DELETE FROM idols WHERE id = %s", (cascade_idol_id,))
            cursor.execute(
                "SELECT count(*) FROM mentor_evidence_claims WHERE id = %s",
                (finalized_cascade_claim_id,),
            )
            assert cursor.fetchone() == (0,)
            cursor.execute(
                "SELECT count(*) FROM mentor_evidence_claim_skills WHERE claim_id = %s",
                (finalized_cascade_claim_id,),
            )
            assert cursor.fetchone() == (0,)

            # A semantic claim may be versioned when its source evidence
            # changes, while an exact semantic+evidence duplicate stays
            # idempotently rejected.
            cursor.execute(
                """
                INSERT INTO mentor_evidence_claims
                    (id, idol_id, claim_type, claim_text, normalized_hash,
                     source_title, source_url, evidence_excerpt, evidence_json,
                     source_hash, skill_tags_json, confidence, verification_status)
                VALUES (%s, %s, 'recommended_book', %s, %s, 'Updated transcript',
                        'https://example.test/evidence-v2', %s, %s, %s, %s, 0.97, 'pending')
                """,
                (
                    revised_claim_id,
                    idol_id,
                    "Read a foundational value-investing text.",
                    HASH_C,
                    "New source evidence for the same semantic claim.",
                    Jsonb({"evidence_version": 2}),
                    HASH_A,
                    Jsonb(["investing"]),
                ),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE mentor_evidence_claim_skills
                SET claim_id = %s
                WHERE claim_id = %s AND skill_id = %s
                """,
                (revised_claim_id, claim_id, skill_id),
                "skill bindings of finalized mentor evidence are immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO mentor_evidence_claims
                    (id, idol_id, claim_type, claim_text, normalized_hash,
                     source_title, source_url, evidence_excerpt, evidence_json,
                     source_hash, skill_tags_json, confidence, verification_status)
                VALUES (%s, %s, 'recommended_book', %s, %s, 'Duplicate',
                        'https://example.test/evidence-v2', %s, %s, %s, %s, 0.97, 'pending')
                """,
                (
                    _id(),
                    idol_id,
                    "Read a foundational value-investing text.",
                    HASH_C,
                    "The exact same evidence.",
                    Jsonb({}),
                    HASH_A,
                    Jsonb(["investing"]),
                ),
                "uq_mentor_evidence_claims_idol_claim_source",
            )

            cursor.execute(
                "INSERT INTO users (id, email, password_hash) VALUES (%s, %s, 'test')",
                (user_id, f"curriculum-{user_id}@example.test"),
            )
            cursor.execute(
                "INSERT INTO users (id, email, password_hash) VALUES (%s, %s, 'test')",
                (other_user_id, f"curriculum-{other_user_id}@example.test"),
            )
            cursor.execute(
                """
                INSERT INTO plans
                    (id, user_id, target_age, duration_weeks, weekly_hours, cycle_number)
                VALUES (%s, %s, 40, 12, 5, 1)
                """,
                (plan_id, user_id),
            )
            cursor.execute(
                """
                INSERT INTO plans
                    (id, user_id, target_age, duration_weeks, weekly_hours, cycle_number)
                VALUES (%s, %s, 40, 12, 5, 1)
                """,
                (other_plan_id, other_user_id),
            )
            for current_item_id, current_plan_id, title in (
                (plan_item_id, plan_id, "Owner item"),
                (other_plan_item_id, other_plan_id, "Other item"),
            ):
                cursor.execute(
                    """
                    INSERT INTO plan_items
                        (id, plan_id, title, type, description, week_start,
                         week_end, success_metric, estimated_hours, status,
                         progress_percent)
                        VALUES (%s, %s, %s, 'COURSE', 'Test item', 1, 1,
                                'Finish it', 1, 'NOT_STARTED', 0)
                    """,
                    (current_item_id, current_plan_id, title),
                )
            cursor.execute(
                """
                INSERT INTO learner_skill_states
                    (id, user_id, skill_id, current_level, mastery_status,
                     state_version, state_hash)
                VALUES (%s, %s, %s, 'beginner', 'developing', 1, %s)
                """,
                (learner_state_id, user_id, skill_id, HASH_A),
            )

            ambiguous_lesson_id = _id()
            ambiguous_lesson_hash = ambiguous_lesson_id.replace("-", "") * 2
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO personalized_lesson_versions
                    (id, user_id, module_session_id, module_version_id,
                     version_number, status, learner_state_snapshot_json,
                     learner_state_hash, mentor_evidence_snapshot_json,
                     mentor_evidence_hash, personalization_brief_json,
                     input_hash, estimated_minutes, prompt_version, ready_at)
                VALUES (%s, %s, %s, %s, 99, 'queued', %s, %s, %s, %s, %s,
                        %s, 55, 'personal-v1', now())
                """,
                (
                    ambiguous_lesson_id,
                    user_id,
                    session_id,
                    version_id,
                    Jsonb({"level": "beginner"}),
                    HASH_A,
                    Jsonb({}),
                    HASH_B,
                    Jsonb({"goal": "Invalid queued audit shape"}),
                    ambiguous_lesson_hash,
                ),
                "ck_personalized_lessons_audit_shape",
            )
            revoked_lesson_id = _id()
            revoked_lesson_hash = revoked_lesson_id.replace("-", "") * 2
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO personalized_lesson_versions
                    (id, user_id, module_session_id, module_version_id,
                     version_number, status, learner_state_snapshot_json,
                     learner_state_hash, mentor_evidence_snapshot_json,
                     mentor_evidence_hash, personalization_brief_json,
                     input_hash, estimated_minutes, prompt_version, ready_at,
                     revoked_at, revocation_reason)
                VALUES (%s, %s, %s, %s, 98, 'revoked', %s, %s, %s, %s, %s,
                        %s, 55, 'personal-v1', now(), now(),
                        'Pinned evidence was revoked')
                """,
                (
                    revoked_lesson_id,
                    user_id,
                    session_id,
                    version_id,
                    Jsonb({"level": "beginner"}),
                    HASH_A,
                    Jsonb({}),
                    HASH_B,
                    Jsonb({"goal": "Missing retained content"}),
                    revoked_lesson_hash,
                ),
                "ck_personalized_lessons_audit_shape",
            )

            for current_lesson_id, current_user_id, input_hash, state_id in (
                (lesson_id, user_id, HASH_A, learner_state_id),
                (other_lesson_id, other_user_id, HASH_B, None),
            ):
                cursor.execute(
                    """
                    INSERT INTO personalized_lesson_versions
                        (id, user_id, module_session_id, module_version_id,
                         learner_state_id, version_number, status,
                         learner_state_snapshot_json,
                         learner_state_hash, mentor_evidence_snapshot_json,
                         mentor_evidence_hash, personalization_brief_json,
                         input_hash, content_json, content_hash,
                         estimated_minutes, prompt_version, model_name, ready_at)
                    VALUES (%s, %s, %s, %s, %s, 1, 'ready', %s, %s, %s, %s,
                            %s, %s, %s, %s, 55, 'personal-v1',
                            'quality-model', now())
                    """,
                    (
                        current_lesson_id,
                        current_user_id,
                        session_id,
                        version_id,
                        state_id,
                        Jsonb({"level": "beginner"}),
                        HASH_A,
                        Jsonb({"claim_ids": [claim_id]}),
                        HASH_B,
                        Jsonb({"goal": "Value a company"}),
                        input_hash,
                        Jsonb({"step": {"title": "Apply"}}),
                        HASH_D,
                    ),
                )

            cursor.execute(
                """
                SELECT count(*)
                FROM personalized_lesson_versions
                WHERE id IN (%s, %s) AND status = 'ready' AND ready_at IS NOT NULL
                """,
                (lesson_id, other_lesson_id),
            )
            assert cursor.fetchone() == (2,)

            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE personalized_lesson_versions
                SET ready_at = ready_at + interval '1 second'
                WHERE id = %s
                """,
                (lesson_id,),
                "lifecycle audit fields are immutable",
            )

            cursor.execute(
                """
                INSERT INTO plan_lesson_assignments
                    (id, plan_id, plan_item_id, module_session_id,
                     personalized_lesson_version_id, week_number, position,
                     allocated_minutes, status, comparison_gap_json,
                     match_reason, available_at)
                VALUES (%s, %s, %s, %s, %s, 1, 1, 55, 'available', %s,
                        'Exact compatible outcome.', now())
                """,
                (
                    assignment_id,
                    plan_id,
                    plan_item_id,
                    session_id,
                    lesson_id,
                    Jsonb({"skill_id": skill_id}),
                ),
            )

            _assert_rejected(
                conn,
                cursor,
                "UPDATE personalized_lesson_versions SET learner_state_id = NULL WHERE id = %s",
                (lesson_id,),
                "ready personalized lesson content is immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                "DELETE FROM personalized_lesson_versions WHERE id = %s",
                (lesson_id,),
                "ready personalized lesson versions are immutable",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO plan_lesson_assignments
                    (id, plan_id, module_session_id,
                     personalized_lesson_version_id, week_number, position,
                     allocated_minutes, status, comparison_gap_json, match_reason)
                VALUES (%s, %s, %s, %s, 2, 1, 55, 'scheduled', %s, 'Wrong owner')
                """,
                (
                    _id(),
                    plan_id,
                    session_id,
                    other_lesson_id,
                    Jsonb({"skill_id": skill_id}),
                ),
                "personalized lesson belongs to another plan user",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO plan_lesson_assignments
                    (id, plan_id, plan_item_id, module_session_id,
                     personalized_lesson_version_id, week_number, position,
                     allocated_minutes, status, comparison_gap_json, match_reason)
                VALUES (%s, %s, %s, %s, %s, 3, 1, 55, 'scheduled', %s,
                        'Wrong plan item')
                """,
                (
                    _id(),
                    plan_id,
                    other_plan_item_id,
                    session_id,
                    lesson_id,
                    Jsonb({"skill_id": skill_id}),
                ),
                "plan lesson assignment item belongs to another plan",
            )
            _assert_rejected(
                conn,
                cursor,
                """
                INSERT INTO plan_lesson_assignments
                    (id, plan_id, module_session_id, week_number, position,
                     allocated_minutes, status, comparison_gap_json, match_reason)
                VALUES (%s, %s, %s, 2, 1, 55, 'scheduled', %s, 'Duplicate session')
                """,
                (_id(), plan_id, session_id, Jsonb({"skill_id": skill_id})),
                "uq_plan_lesson_assignments_plan_session",
            )

            # A terminal status cannot be resurrected, but the retained row no
            # longer prevents the session from receiving a safe replacement.
            cursor.execute(
                """
                UPDATE plan_lesson_assignments
                SET status = 'skipped'
                WHERE id = %s
                """,
                (assignment_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                "UPDATE plan_lesson_assignments SET status = 'scheduled' WHERE id = %s",
                (assignment_id,),
                "terminal plan lesson assignment status is immutable",
            )
            # The terminal-status guard is narrow: deleting the owned plan item
            # may still perform its FK SET NULL without rewriting history.
            cursor.execute("DELETE FROM plan_items WHERE id = %s", (plan_item_id,))
            cursor.execute(
                "SELECT plan_item_id FROM plan_lesson_assignments WHERE id = %s",
                (assignment_id,),
            )
            assert cursor.fetchone() == (None,)
            cursor.execute(
                """
                INSERT INTO plan_lesson_assignments
                    (id, plan_id, module_session_id, week_number, position,
                     allocated_minutes, status, comparison_gap_json, match_reason)
                VALUES (%s, %s, %s, 2, 1, 55, 'scheduled', %s,
                        'Safe retry after skipped pin')
                """,
                (
                    retry_assignment_id,
                    plan_id,
                    session_id,
                    Jsonb({"skill_id": skill_id}),
                ),
            )
            cursor.execute(
                """
                UPDATE plan_lesson_assignments
                SET status = 'replaced'
                WHERE id = %s
                """,
                (retry_assignment_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                "UPDATE plan_lesson_assignments SET status = 'scheduled' WHERE id = %s",
                (retry_assignment_id,),
                "terminal plan lesson assignment status is immutable",
            )
            cursor.execute(
                """
                INSERT INTO plan_lesson_assignments
                    (id, plan_id, module_session_id, week_number, position,
                     allocated_minutes, status, comparison_gap_json, match_reason)
                VALUES (%s, %s, %s, 3, 1, 55, 'scheduled', %s,
                        'Safe retry after replaced pin')
                """,
                (
                    second_retry_assignment_id,
                    plan_id,
                    session_id,
                    Jsonb({"skill_id": skill_id}),
                ),
            )

            cursor.execute(
                """
                UPDATE personalized_lesson_versions
                SET status = 'revoked', revoked_at = now(),
                    revocation_reason = 'Mentor evidence withdrawn'
                WHERE id = %s
                """,
                (other_lesson_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE personalized_lesson_versions
                SET revocation_reason = 'Rewritten audit history'
                WHERE id = %s
                """,
                (other_lesson_id,),
                "lifecycle audit fields are immutable",
            )
            cursor.execute(
                """
                UPDATE mentor_evidence_claims
                SET verification_status = 'revoked', revoked_at = now(),
                    revocation_reason = 'Source withdrawn'
                WHERE id = %s
                """,
                (claim_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE mentor_evidence_claims
                SET revocation_reason = 'Rewritten audit history'
                WHERE id = %s
                """,
                (claim_id,),
                "lifecycle audit fields are immutable",
            )

            # The privacy boundary outranks reader-artifact immutability:
            # deleting the owning user must remove READY lessons and pins.
            cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))
            cursor.execute(
                "SELECT count(*) FROM personalized_lesson_versions WHERE user_id = %s",
                (user_id,),
            )
            assert cursor.fetchone() == (0,)
            cursor.execute(
                "SELECT count(*) FROM learner_skill_states WHERE user_id = %s",
                (user_id,),
            )
            assert cursor.fetchone() == (0,)
            cursor.execute(
                "SELECT count(*) FROM plan_lesson_assignments WHERE plan_id = %s",
                (plan_id,),
            )
            assert cursor.fetchone() == (0,)
            cursor.execute("SELECT count(*) FROM plans WHERE id = %s", (plan_id,))
            assert cursor.fetchone() == (0,)

            cursor.execute(
                """
                UPDATE canonical_modules
                SET status = 'retired', current_published_version_id = NULL
                WHERE id = %s
                """,
                (module_id,),
            )
            cursor.execute(
                """
                UPDATE canonical_module_versions
                SET status = 'revoked', revoked_at = now(),
                    revocation_reason = 'Source withdrawn'
                WHERE id = %s
                """,
                (version_id,),
            )
            _assert_rejected(
                conn,
                cursor,
                """
                UPDATE canonical_module_versions
                SET revocation_reason = 'Rewritten audit history'
                WHERE id = %s
                """,
                (version_id,),
                "lifecycle audit fields are immutable",
            )
