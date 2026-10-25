"""Converge databases stamped by pre-final curriculum audit hardening.

Revision ID: h9j0k1l2m3n4
Revises: h8i9j0k1l2m3
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "h9j0k1l2m3n4"
down_revision: Union[str, None] = "h8i9j0k1l2m3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


PYTHON_STRIP_CHARACTERS_SQL = (
    "U&'\\0009\\000A\\000B\\000C\\000D\\001C\\001D\\001E\\001F\\0020"
    "\\0085\\00A0\\1680\\2000\\2001\\2002"
    "\\2003\\2004\\2005\\2006\\2007\\2008\\2009\\200A\\2028\\2029"
    "\\202F\\205F\\3000'"
)
UUID_TEXT_VARIANT_PATTERN = (
    r"^([0-9A-Fa-f]{32}|"
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|"
    r"\{[0-9A-Fa-f]{32}\}|"
    r"\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\})$"
)

STEP_OPTIONAL_STRING_FIELDS = (
    "description",
    "expected_output",
    "lesson_content",
)
STEP_OPTIONAL_STRING_ARRAY_FIELDS = ("resources", "substeps")
STEP_OPTIONAL_INTEGER_FIELDS = (
    "order",
    "estimate_minutes",
    "estimateMinutes",
    "reading_minutes",
    "readingMinutes",
    "practice_minutes",
    "practiceMinutes",
)
MATERIAL_OPTIONAL_STRING_FIELDS = (
    "url",
    "type",
    "content_resource_id",
    "contentResourceId",
    "canonical_key",
    "canonicalKey",
    "author_or_creator",
    "authorOrCreator",
    "thumbnail_url",
    "thumbnailUrl",
    "license_status",
    "licenseStatus",
    "search_query",
    "searchQuery",
    "url_resolution_status",
    "urlResolutionStatus",
    "url_provider",
    "urlProvider",
    "content_markdown",
    "reason",
)
IDEA_STRING_FIELDS = ("title", "content", "category")


def _invalid_nullable_string_fields(container: str, fields: tuple[str, ...]) -> str:
    return " OR\n".join(
        f"""({container} ? '{field}' AND
               jsonb_typeof({container} -> '{field}')
                   NOT IN ('string', 'null'))"""
        for field in fields
    )


def _invalid_required_string_if_present(container: str, field: str) -> str:
    return f"""({container} ? '{field}' AND
               jsonb_typeof({container} -> '{field}')
                   IS DISTINCT FROM 'string')"""


def _invalid_nullable_string_array_cases(
    container: str,
    fields: tuple[str, ...],
) -> str:
    return "\n".join(
        f"""WHEN {container} ? '{field}' AND
             jsonb_typeof({container} -> '{field}')
                 NOT IN ('array', 'null') THEN TRUE
        WHEN jsonb_typeof({container} -> '{field}') = 'array' AND EXISTS (
            SELECT 1
            FROM jsonb_array_elements({container} -> '{field}') AS entry
            WHERE jsonb_typeof(entry) IS DISTINCT FROM 'string'
        ) THEN TRUE"""
        for field in fields
    )


def _invalid_nullable_integer_fields(
    container: str,
    fields: tuple[str, ...],
) -> str:
    return " OR\n".join(
        f"""({container} ? '{field}' AND
               jsonb_typeof({container} -> '{field}')
                   IS DISTINCT FROM 'null' AND (
                   jsonb_typeof({container} -> '{field}')
                       IS DISTINCT FROM 'number'
                   OR ({container} ->> '{field}') !~ '^-?(0|[1-9][0-9]*)$'
               ))"""
        for field in fields
    )


AUDIT_SHAPE_CONSTRAINTS = (
    (
        "learning_technique_versions",
        "ck_learning_technique_versions_audit_shape",
        f"""
        ((status IN ('draft', 'in_review') AND published_at IS NULL) OR
         (status IN ('published', 'revoked') AND published_at IS NOT NULL)) AND
        ((status <> 'revoked' AND revoked_at IS NULL AND
         revocation_reason IS NULL) OR
         (status = 'revoked' AND revoked_at IS NOT NULL AND
          NULLIF(btrim(COALESCE(revocation_reason, ''),
                 {PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL))
        """,
    ),
    (
        "canonical_module_versions",
        "ck_canonical_module_versions_audit_shape",
        f"""
        ((status IN ('draft', 'in_review') AND published_at IS NULL) OR
         (status IN ('published', 'revoked') AND published_at IS NOT NULL)) AND
        ((status <> 'revoked' AND revoked_at IS NULL AND
         revocation_reason IS NULL) OR
         (status = 'revoked' AND revoked_at IS NOT NULL AND
          NULLIF(btrim(COALESCE(revocation_reason, ''),
                 {PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL))
        """,
    ),
    (
        "mentor_evidence_claims",
        "ck_mentor_evidence_claims_audit_shape",
        f"""
        ((verification_status IN ('pending', 'rejected') AND
          verified_at IS NULL) OR
         (verification_status IN ('verified', 'revoked') AND
          verified_at IS NOT NULL)) AND
        ((verification_status <> 'revoked' AND revoked_at IS NULL AND
          revocation_reason IS NULL) OR
         (verification_status = 'revoked' AND revoked_at IS NOT NULL AND
          NULLIF(btrim(COALESCE(revocation_reason, ''),
                 {PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL))
        """,
    ),
    (
        "personalized_lesson_versions",
        "ck_personalized_lessons_audit_shape",
        f"""
        ((status IN ('queued', 'generating', 'failed') AND ready_at IS NULL) OR
         (status IN ('ready', 'revoked') AND ready_at IS NOT NULL)) AND
        ((status <> 'revoked' AND revoked_at IS NULL AND
          revocation_reason IS NULL) OR
         (status = 'revoked' AND revoked_at IS NOT NULL AND
          NULLIF(btrim(COALESCE(revocation_reason, ''),
                 {PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL AND
          content_json IS NOT NULL AND content_hash IS NOT NULL))
        """,
    ),
)


CURRENT_MODERN_ARTIFACT = """
plan_item.details_json ? '_generation'
AND (
    jsonb_typeof(plan_item.details_json -> '_generation') <> 'object'
    OR COALESCE(
        plan_item.details_json #> '{_generation}',
        '{}'::jsonb
    ) ? 'job_id'
)
"""


INVALID_TOP_LEVEL_STRINGS = _invalid_nullable_string_fields(
    "plan_item.details_json",
    ("generated_at", "generated_from_prompt_version"),
)
INVALID_STEP_TITLE = _invalid_required_string_if_present("step", "title")
INVALID_STEP_STRINGS = _invalid_nullable_string_fields(
    "step",
    STEP_OPTIONAL_STRING_FIELDS,
)
INVALID_STEP_STRING_ARRAY_CASES = _invalid_nullable_string_array_cases(
    "step",
    STEP_OPTIONAL_STRING_ARRAY_FIELDS,
)
INVALID_STEP_INTEGERS = _invalid_nullable_integer_fields(
    "step",
    STEP_OPTIONAL_INTEGER_FIELDS,
)
INVALID_MATERIAL_TITLE = _invalid_required_string_if_present("material", "title")
INVALID_MATERIAL_STRINGS = _invalid_nullable_string_fields(
    "material",
    MATERIAL_OPTIONAL_STRING_FIELDS,
)
INVALID_MATERIAL_DURATION = _invalid_nullable_integer_fields(
    "material",
    ("duration_minutes",),
)
INVALID_IDEA_STRINGS = " OR\n".join(
    _invalid_required_string_if_present("idea", field) for field in IDEA_STRING_FIELDS
)


# This mirrors every persisted structural precondition of
# validated_lesson_steps(), validated_lesson_materials(), and ItemDetails. The
# stricter non-empty step rule is also the completion-readiness invariant.
MALFORMED_STEPS = f"""
CASE
    WHEN jsonb_typeof(plan_item.details_json)
         IS DISTINCT FROM 'object' THEN TRUE
    WHEN ({INVALID_TOP_LEVEL_STRINGS}) THEN TRUE
    WHEN jsonb_typeof(plan_item.details_json -> 'steps')
         IS DISTINCT FROM 'array' THEN TRUE
    WHEN jsonb_array_length(plan_item.details_json -> 'steps') = 0 THEN TRUE
    WHEN EXISTS (
        SELECT 1
        FROM jsonb_array_elements(plan_item.details_json -> 'steps') AS step
        WHERE CASE
            WHEN jsonb_typeof(step) IS DISTINCT FROM 'object' THEN TRUE
            WHEN jsonb_typeof(step -> 'id')
                 IS DISTINCT FROM 'string' THEN TRUE
            WHEN BTRIM(
                step ->> 'id', {PYTHON_STRIP_CHARACTERS_SQL}
            ) = '' THEN TRUE
            WHEN (step ->> 'id') IS DISTINCT FROM BTRIM(
                step ->> 'id', {PYTHON_STRIP_CHARACTERS_SQL}
            ) THEN TRUE
            WHEN CHAR_LENGTH(step ->> 'id') > 100 THEN TRUE
            WHEN ({INVALID_STEP_TITLE}) THEN TRUE
            WHEN ({INVALID_STEP_STRINGS}) THEN TRUE
            {INVALID_STEP_STRING_ARRAY_CASES}
            WHEN ({INVALID_STEP_INTEGERS}) THEN TRUE
            ELSE FALSE
        END
    ) THEN TRUE
    WHEN jsonb_array_length(plan_item.details_json -> 'steps') <> (
        SELECT COUNT(DISTINCT step ->> 'id')
        FROM jsonb_array_elements(plan_item.details_json -> 'steps') AS step
    ) THEN TRUE
    WHEN plan_item.details_json ? 'materials' AND
         jsonb_typeof(plan_item.details_json -> 'materials')
             NOT IN ('array', 'null') THEN TRUE
    WHEN jsonb_typeof(plan_item.details_json -> 'materials') = 'array' THEN EXISTS (
        SELECT 1
        FROM jsonb_array_elements(
            plan_item.details_json -> 'materials'
        ) AS material
        WHERE CASE
            WHEN jsonb_typeof(material) IS DISTINCT FROM 'object' THEN TRUE
            WHEN ({INVALID_MATERIAL_TITLE}) THEN TRUE
            WHEN ({INVALID_MATERIAL_STRINGS}) THEN TRUE
            WHEN ({INVALID_MATERIAL_DURATION}) THEN TRUE
            WHEN material ? 'ideas' AND
                 jsonb_typeof(material -> 'ideas')
                     NOT IN ('array', 'null') THEN TRUE
            WHEN jsonb_typeof(material -> 'ideas') = 'array' THEN EXISTS (
                SELECT 1
                FROM jsonb_array_elements(material -> 'ideas') AS idea
                WHERE jsonb_typeof(idea) IS DISTINCT FROM 'object'
                   OR ({INVALID_IDEA_STRINGS})
            )
            ELSE FALSE
        END
    )
    ELSE FALSE
END
"""

PARTIAL_ARTIFACT = """
plan_item.details_json #>> '{_generation,status}' IN ('partial', 'generating')
"""

# Progressive caches are authoritative only for explicitly exposed checkpoints.
# The identity rules mirror validated_ready_step_ids(); membership additionally
# prevents a stale producer marker from naming a step outside the current strict
# artifact.  This predicate is deliberately scoped to partial/generating rows so
# ready and revoked terminal history is unchanged.
INVALID_PROGRESSIVE_READY_STEP_IDS = f"""
CASE
    WHEN NOT ({PARTIAL_ARTIFACT}) THEN FALSE
    WHEN jsonb_typeof(
        plan_item.details_json #> '{{_generation,ready_step_ids}}'
    ) IS DISTINCT FROM 'array' THEN TRUE
    WHEN jsonb_array_length(
        plan_item.details_json #> '{{_generation,ready_step_ids}}'
    ) = 0 THEN TRUE
    WHEN jsonb_typeof(plan_item.details_json -> 'steps')
         IS DISTINCT FROM 'array' THEN TRUE
    WHEN EXISTS (
        SELECT 1
        FROM jsonb_array_elements(
            plan_item.details_json #> '{{_generation,ready_step_ids}}'
        ) AS ready_step_id
        WHERE jsonb_typeof(ready_step_id) IS DISTINCT FROM 'string'
           OR BTRIM(
               ready_step_id #>> '{{}}', {PYTHON_STRIP_CHARACTERS_SQL}
           ) = ''
           OR (ready_step_id #>> '{{}}') IS DISTINCT FROM BTRIM(
               ready_step_id #>> '{{}}', {PYTHON_STRIP_CHARACTERS_SQL}
           )
           OR CHAR_LENGTH(ready_step_id #>> '{{}}') > 100
    ) THEN TRUE
    WHEN jsonb_array_length(
        plan_item.details_json #> '{{_generation,ready_step_ids}}'
    ) <> (
        SELECT COUNT(DISTINCT ready_step_id #>> '{{}}')
        FROM jsonb_array_elements(
            plan_item.details_json #> '{{_generation,ready_step_ids}}'
        ) AS ready_step_id
    ) THEN TRUE
    WHEN EXISTS (
        SELECT 1
        FROM jsonb_array_elements(
            plan_item.details_json #> '{{_generation,ready_step_ids}}'
        ) AS ready_step_id
        WHERE NOT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(
                plan_item.details_json -> 'steps'
            ) AS current_step
            WHERE current_step ->> 'id' = ready_step_id #>> '{{}}'
        )
    ) THEN TRUE
    ELSE FALSE
END
"""

# Python str.split() separates exactly the same whitespace set used by
# str.strip(). Translate those 29 code points to ordinary spaces before the SQL
# split so an exposed step must meet the runtime 1,900-word content threshold.
SUBSTANTIVE_EXPOSED_STEP = f"""
CARDINALITY(
    REGEXP_SPLIT_TO_ARRAY(
        BTRIM(
            TRANSLATE(
                current_step ->> 'lesson_content',
                {PYTHON_STRIP_CHARACTERS_SQL},
                REPEAT(
                    ' ',
                    CHAR_LENGTH({PYTHON_STRIP_CHARACTERS_SQL})
                )
            ),
            ' '
        ),
        ' +'
    )
) >= 1900
"""

ELIGIBLE_PROGRESSIVE_STEP_COMPLETION = f"""
step_completion.step_id IN (
    SELECT current_step ->> 'id'
    FROM jsonb_array_elements(
        plan_item.details_json -> 'steps'
    ) AS current_step
    WHERE current_step ->> 'id' IN (
        SELECT ready_step_id #>> '{{}}'
        FROM jsonb_array_elements(
            plan_item.details_json #> '{{_generation,ready_step_ids}}'
        ) AS ready_step_id
    )
      AND ({SUBSTANTIVE_EXPOSED_STEP})
)
"""

# Catalog revocation intentionally retains an exact completed reader artifact;
# its completion history remains authoritative until a replacement is published.
INVALID_GENERATION_STATUS = """
plan_item.details_json #>> '{_generation,status}'
    IS DISTINCT FROM 'ready'
AND plan_item.details_json #>> '{_generation,status}'
    IS DISTINCT FROM 'partial'
AND plan_item.details_json #>> '{_generation,status}'
    IS DISTINCT FROM 'generating'
AND plan_item.details_json #>> '{_generation,status}'
    IS DISTINCT FROM 'revoked'
"""

BROKEN_ARTIFACT_REFERENCE = """
NOT EXISTS (
    SELECT 1
    FROM plan_item_detail_jobs AS referenced_job
    JOIN plans AS referenced_owner
      ON referenced_owner.id = plan_item.plan_id
    WHERE referenced_job.id::text =
          plan_item.details_json #>> '{_generation,job_id}'
      AND referenced_job.plan_item_id = plan_item.id
      AND referenced_job.user_id = referenced_owner.user_id
)
"""

INVALID_CURRENT_ARTIFACT = (
    f"(({MALFORMED_STEPS}) OR ({BROKEN_ARTIFACT_REFERENCE}) OR "
    f"({INVALID_GENERATION_STATUS}) OR "
    f"({INVALID_PROGRESSIVE_READY_STEP_IDS}))"
)


def _preflight_lifecycle_shapes() -> None:
    """Refuse to guess audit history for already-incoherent terminal rows."""

    for table_name, _constraint_name, expression in AUDIT_SHAPE_CONSTRAINTS:
        op.execute(
            sa.text(
                f"""
                DO $$
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM {table_name}
                        WHERE ({expression}) IS NOT TRUE
                    ) THEN
                        RAISE EXCEPTION
                            'cannot upgrade h9: {table_name} contains ambiguous lifecycle audit data';
                    END IF;
                END;
                $$;
                """
            )
        )


def _replace_audit_shape_constraints() -> None:
    for table_name, constraint_name, expression in AUDIT_SHAPE_CONSTRAINTS:
        op.drop_constraint(constraint_name, table_name, type_="check")
        op.create_check_constraint(
            constraint_name,
            table_name,
            expression,
        )


def _affected_artifact_predicate() -> str:
    return f"(({INVALID_CURRENT_ARTIFACT}) OR ({PARTIAL_ARTIFACT}))"


def _repair_stamped_artifact_progress() -> None:
    """Converge rows accepted before strict artifact completion gates existed."""

    affected = _affected_artifact_predicate()

    # Keep the append-only completion row but withdraw its current completion
    # claim. Step checkpoints remain durable and can be reused once a valid,
    # ready artifact is published under the same exact identity.
    op.execute(
        sa.text(
            f"""
            UPDATE plan_item_completions AS item_completion
            SET completed_at = NULL
            FROM plan_items AS plan_item
            JOIN plans AS owner_plan ON owner_plan.id = plan_item.plan_id
            WHERE item_completion.plan_item_id = plan_item.id
              AND item_completion.user_id = owner_plan.user_id
              AND item_completion.completed_at IS NOT NULL
              AND (
                  item_completion.artifact_job_id::text =
                      plan_item.details_json #>> '{{_generation,job_id}}'
                  OR (
                      plan_item.details_json #>> '{{_generation,job_id}}'
                          ~ '{UUID_TEXT_VARIANT_PATTERN}'
                      AND REPLACE(
                          item_completion.artifact_job_id::text,
                          '-', ''
                      ) = LOWER(REGEXP_REPLACE(
                          plan_item.details_json
                              #>> '{{_generation,job_id}}',
                          '[{{}}-]', '', 'g'
                      ))
                  )
              )
              AND plan_item.status <> 'SKIPPED'::plan_item_status
              AND ({CURRENT_MODERN_ARTIFACT})
              AND {affected}
            """
        )
    )

    # Malformed step identity fails fully closed. A well-shaped progressive
    # artifact may expose completed checkpoints, but cannot claim 100% or a
    # terminal item status until its generation status becomes ready.
    op.execute(
        sa.text(
            f"""
            UPDATE plan_items AS plan_item
            SET status = CASE
                    WHEN ({INVALID_CURRENT_ARTIFACT})
                    THEN 'NOT_STARTED'::plan_item_status
                    WHEN EXISTS (
                        SELECT 1
                        FROM plan_item_step_completions AS step_completion
                        WHERE step_completion.plan_item_id = plan_item.id
                          AND step_completion.user_id = (
                              SELECT owner_plan.user_id
                              FROM plans AS owner_plan
                              WHERE owner_plan.id = plan_item.plan_id
                          )
                          AND step_completion.completed_at IS NOT NULL
                          AND step_completion.artifact_job_id::text =
                              plan_item.details_json
                                  #>> '{{_generation,job_id}}'
                          AND ({ELIGIBLE_PROGRESSIVE_STEP_COMPLETION})
                    ) THEN 'IN_PROGRESS'::plan_item_status
                    ELSE 'NOT_STARTED'::plan_item_status
                END,
                progress_percent = CASE
                    WHEN ({INVALID_CURRENT_ARTIFACT}) THEN 0
                    ELSE LEAST(
                        99,
                        ROUND(
                            100.0 * (
                                SELECT COUNT(DISTINCT step_completion.step_id)
                                FROM plan_item_step_completions AS step_completion
                                WHERE step_completion.plan_item_id = plan_item.id
                                  AND step_completion.user_id = (
                                      SELECT owner_plan.user_id
                                      FROM plans AS owner_plan
                                      WHERE owner_plan.id = plan_item.plan_id
                                  )
                                  AND step_completion.completed_at IS NOT NULL
                                  AND step_completion.artifact_job_id::text =
                                      plan_item.details_json
                                          #>> '{{_generation,job_id}}'
                                  AND ({ELIGIBLE_PROGRESSIVE_STEP_COMPLETION})
                            ) / jsonb_array_length(
                                plan_item.details_json -> 'steps'
                            )
                        )::integer
                    )
                END
            WHERE plan_item.status <> 'SKIPPED'::plan_item_status
              AND ({CURRENT_MODERN_ARTIFACT})
              AND {affected}
            """
        )
    )

    # Mission completion is sticky only after a successor cycle exists. A
    # current malformed/progressive artifact cannot complete its source plan.
    op.execute(
        sa.text(
            f"""
            UPDATE plans AS plan
            SET completed_at = NULL
            WHERE plan.completed_at IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM plans AS successor
                  WHERE successor.previous_plan_id = plan.id
              )
              AND EXISTS (
                  SELECT 1
                  FROM plan_items AS plan_item
                  WHERE plan_item.plan_id = plan.id
                    AND plan_item.type IN (
                        'PROJECT'::plan_item_type,
                        'COURSE'::plan_item_type,
                        'READING'::plan_item_type
                    )
                    AND plan_item.status <>
                        'SKIPPED'::plan_item_status
                    AND ({CURRENT_MODERN_ARTIFACT})
                    AND {affected}
              )
            """
        )
    )


def _replace_plan_assignment_guard(*, protect_terminal_history: bool) -> None:
    terminal_history_guard = (
        """
            IF TG_OP = 'UPDATE'
               AND OLD.status::text IN ('skipped', 'replaced')
               AND OLD.status IS DISTINCT FROM NEW.status THEN
                RAISE EXCEPTION
                    'terminal plan lesson assignment status is immutable';
            END IF;
        """
        if protect_terminal_history
        else ""
    )
    op.execute(
        f"""
        CREATE OR REPLACE FUNCTION guard_plan_lesson_assignment_owner()
        RETURNS trigger AS $$
        DECLARE
            plan_user_id uuid;
            item_plan_id uuid;
            lesson_user_id uuid;
            lesson_status text;
            lesson_revoked_at timestamptz;
        BEGIN
            {terminal_history_guard}

            SELECT user_id INTO plan_user_id
            FROM plans WHERE id = NEW.plan_id
            FOR SHARE;

            IF NOT FOUND THEN
                RETURN NEW;
            END IF;

            IF NEW.personalized_lesson_version_id IS NOT NULL THEN
                SELECT user_id, status::text, revoked_at
                INTO lesson_user_id, lesson_status, lesson_revoked_at
                FROM personalized_lesson_versions
                WHERE id = NEW.personalized_lesson_version_id
                  AND module_session_id = NEW.module_session_id
                FOR SHARE;
                IF plan_user_id IS DISTINCT FROM lesson_user_id THEN
                    RAISE EXCEPTION
                        'personalized lesson belongs to another plan user';
                END IF;
            END IF;

            IF NEW.plan_item_id IS NOT NULL THEN
                SELECT plan_id INTO item_plan_id
                FROM plan_items
                WHERE id = NEW.plan_item_id
                FOR SHARE;
                IF item_plan_id IS DISTINCT FROM NEW.plan_id THEN
                    RAISE EXCEPTION
                        'plan lesson assignment item belongs to another plan';
                END IF;
            END IF;

            IF NEW.status::text IN ('available', 'in_progress', 'completed') AND (
                NEW.personalized_lesson_version_id IS NULL OR
                lesson_status IS DISTINCT FROM 'ready' OR
                lesson_revoked_at IS NOT NULL
            ) THEN
                RAISE EXCEPTION
                    'visible assignment requires a ready personalized lesson';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )


def upgrade() -> None:
    # Early h8 was applied before its final whitespace and parser contract was
    # frozen. Preflight first, then converge its data and database objects in one
    # PostgreSQL transaction.
    _preflight_lifecycle_shapes()
    _repair_stamped_artifact_progress()
    _replace_audit_shape_constraints()
    _replace_plan_assignment_guard(protect_terminal_history=True)


def downgrade() -> None:
    # The final h8 contract has the same definitions. Recreate them explicitly
    # so a downgrade never revives an early-stamped check or trigger body. The
    # data repair intentionally remains fail-closed; old completion timestamps
    # cannot be reconstructed without fabricating audit history.
    _replace_audit_shape_constraints()
    _replace_plan_assignment_guard(protect_terminal_history=True)
