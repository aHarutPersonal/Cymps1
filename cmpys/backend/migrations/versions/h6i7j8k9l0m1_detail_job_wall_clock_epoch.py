"""Version plan progress by artifact and order detail jobs by wall-clock time.

Revision ID: h6i7j8k9l0m1
Revises: h5i6j7k8l9m0
"""

from typing import Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "h6i7j8k9l0m1"
down_revision: Union[str, None] = "h5i6j7k8l9m0"
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    op.add_column(
        "plan_item_detail_jobs",
        sa.Column("artifact_epoch_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "plan_item_detail_jobs",
        sa.Column(
            "supersedes_artifact",
            sa.Boolean(),
            server_default=sa.false(),
            nullable=False,
        ),
    )
    op.add_column(
        "plan_item_step_completions",
        sa.Column(
            "artifact_job_id",
            postgresql.UUID(as_uuid=False),
            nullable=True,
        ),
    )
    op.add_column(
        "plan_item_completions",
        sa.Column(
            "artifact_job_id",
            postgresql.UUID(as_uuid=False),
            nullable=True,
        ),
    )

    # PostgreSQL now() is the transaction-start timestamp. New rows use the
    # wall clock below. Start historical terminal jobs at their audit timestamp,
    # then place the currently published artifact and every unreferenced active
    # replacement on a deterministic wall-clock timeline. If multiple active
    # jobs exist, only the last ranked row can pass the runtime publication CAS.
    op.execute(
        sa.text(
            """
            UPDATE plan_item_detail_jobs AS detail_job
            SET artifact_epoch_at = CASE
                WHEN detail_job.id::text =
                     plan_item.details_json #>> '{_generation,job_id}'
                THEN clock_timestamp()
                ELSE detail_job.created_at
            END
            FROM plan_items AS plan_item
            WHERE plan_item.id = detail_job.plan_item_id
            """
        )
    )
    op.execute(
        sa.text(
            """
            WITH migration_clock AS (
                SELECT GREATEST(
                    clock_timestamp(),
                    COALESCE(MAX(artifact_epoch_at), clock_timestamp())
                ) AS epoch
                FROM plan_item_detail_jobs
            ),
            ranked_active_replacements AS (
                SELECT
                    detail_job.id,
                    ROW_NUMBER() OVER (
                        PARTITION BY detail_job.plan_item_id, detail_job.user_id
                        ORDER BY detail_job.created_at ASC, detail_job.id ASC
                    ) AS replacement_rank
                FROM plan_item_detail_jobs AS detail_job
                JOIN plan_items AS plan_item
                  ON plan_item.id = detail_job.plan_item_id
                WHERE detail_job.status IN ('pending', 'queued', 'running')
                  AND detail_job.id::text IS DISTINCT FROM
                      plan_item.details_json #>> '{_generation,job_id}'
            )
            UPDATE plan_item_detail_jobs AS detail_job
            SET artifact_epoch_at = migration_clock.epoch
                + ranked_active_replacements.replacement_rank
                  * INTERVAL '1 microsecond'
            FROM ranked_active_replacements, migration_clock
            WHERE detail_job.id = ranked_active_replacements.id
            """
        )
    )
    # Existing clients did not receive an artifact token. Treat the artifact
    # embedded at migration time as the compatibility baseline; only a
    # replacement published by the new runtime may require a token. This keeps
    # the migration deployable before every installed client has upgraded while
    # preserving strict identity for all future replacements.
    op.execute(
        sa.text(
            """
            UPDATE plan_item_detail_jobs AS detail_job
            SET supersedes_artifact = FALSE
            FROM plan_items AS plan_item
            WHERE plan_item.id = detail_job.plan_item_id
              AND detail_job.id::text =
                  plan_item.details_json #>> '{_generation,job_id}'
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE plan_items AS plan_item
            SET details_json = jsonb_set(
                plan_item.details_json,
                '{_generation,supersedes_artifact}',
                'false'::jsonb,
                TRUE
            )
            FROM plan_item_detail_jobs AS detail_job
            WHERE detail_job.id::text =
                  plan_item.details_json #>> '{_generation,job_id}'
            """
        )
    )
    op.alter_column(
        "plan_item_detail_jobs",
        "artifact_epoch_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
        server_default=sa.text("clock_timestamp()"),
    )

    # Preserve progress only when identity is provable: the embedded artifact is
    # the first detail job for the item/user and the completion happened after
    # that job was created. A row that predates the job, or any item with an
    # earlier detail job, stays NULL as legacy history and cannot leak into a
    # replacement. Step rows additionally have to name a step in the embedded
    # artifact. The production preflight uses the same predicates.
    op.execute(
        sa.text(
            """
            UPDATE plan_item_completions AS item_completion
            SET artifact_job_id = detail_job.id
            FROM plan_items AS plan_item
            JOIN plans AS owner_plan
              ON owner_plan.id = plan_item.plan_id
            JOIN plan_item_detail_jobs AS detail_job
              ON detail_job.plan_item_id = plan_item.id
             AND detail_job.user_id = owner_plan.user_id
             AND detail_job.id::text =
                 plan_item.details_json #>> '{_generation,job_id}'
            WHERE item_completion.plan_item_id = plan_item.id
              AND item_completion.user_id = owner_plan.user_id
              AND item_completion.artifact_job_id IS NULL
              AND item_completion.completed_at IS NOT NULL
              AND item_completion.completed_at >= detail_job.created_at
              AND NOT EXISTS (
                  SELECT 1
                  FROM plan_item_detail_jobs AS earlier_job
                  WHERE earlier_job.plan_item_id = detail_job.plan_item_id
                    AND earlier_job.user_id = detail_job.user_id
                    AND (
                        earlier_job.created_at < detail_job.created_at
                        OR (
                            earlier_job.created_at = detail_job.created_at
                            AND earlier_job.id < detail_job.id
                        )
                    )
              )
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE plan_item_step_completions AS step_completion
            SET artifact_job_id = detail_job.id
            FROM plan_items AS plan_item
            JOIN plans AS owner_plan
              ON owner_plan.id = plan_item.plan_id
            JOIN plan_item_detail_jobs AS detail_job
              ON detail_job.plan_item_id = plan_item.id
             AND detail_job.user_id = owner_plan.user_id
             AND detail_job.id::text =
                 plan_item.details_json #>> '{_generation,job_id}'
            WHERE step_completion.plan_item_id = plan_item.id
              AND step_completion.user_id = owner_plan.user_id
              AND step_completion.artifact_job_id IS NULL
              AND step_completion.completed_at IS NOT NULL
              AND step_completion.completed_at >= detail_job.created_at
              AND jsonb_typeof(plan_item.details_json -> 'steps') = 'array'
              AND EXISTS (
                  SELECT 1
                  FROM jsonb_array_elements(
                      plan_item.details_json -> 'steps'
                  ) AS lesson_step(value)
                  WHERE jsonb_typeof(lesson_step.value) = 'object'
                    AND jsonb_typeof(lesson_step.value -> 'id') = 'string'
                    AND lesson_step.value ->> 'id' = step_completion.step_id
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM plan_item_detail_jobs AS earlier_job
                  WHERE earlier_job.plan_item_id = detail_job.plan_item_id
                    AND earlier_job.user_id = detail_job.user_id
                    AND (
                        earlier_job.created_at < detail_job.created_at
                        OR (
                            earlier_job.created_at = detail_job.created_at
                            AND earlier_job.id < detail_job.id
                        )
                    )
              )
            """
        )
    )

    # Keep one durable legacy row while permitting an append-only row for each
    # modern artifact. Two partial indexes avoid PostgreSQL's distinct-NULL
    # behavior without requiring PostgreSQL 15's NULLS NOT DISTINCT feature.
    op.drop_index(
        "ix_plan_item_step_completions_unique",
        table_name="plan_item_step_completions",
    )
    op.create_index(
        "ix_plan_item_step_completions_unique",
        "plan_item_step_completions",
        ["user_id", "plan_item_id", "step_id"],
        unique=True,
        postgresql_where=sa.text("artifact_job_id IS NULL"),
    )
    op.create_index(
        "ix_plan_item_step_completions_artifact_unique",
        "plan_item_step_completions",
        ["user_id", "plan_item_id", "step_id", "artifact_job_id"],
        unique=True,
        postgresql_where=sa.text("artifact_job_id IS NOT NULL"),
    )
    op.drop_index(
        "ix_plan_item_completions_unique",
        table_name="plan_item_completions",
    )
    op.create_index(
        "ix_plan_item_completions_unique",
        "plan_item_completions",
        ["user_id", "plan_item_id"],
        unique=True,
        postgresql_where=sa.text("artifact_job_id IS NULL"),
    )
    op.create_index(
        "ix_plan_item_completions_artifact_unique",
        "plan_item_completions",
        ["user_id", "plan_item_id", "artifact_job_id"],
        unique=True,
        postgresql_where=sa.text("artifact_job_id IS NOT NULL"),
    )

    # Re-derive cached item state for every modern artifact. Completion rows are
    # authoritative; old terminal flags must not leak from artifact A into B.
    op.execute(
        sa.text(
            """
            UPDATE plan_items AS plan_item
            SET status = CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM plan_item_completions AS item_completion
                        WHERE item_completion.plan_item_id = plan_item.id
                          AND item_completion.user_id = (
                              SELECT owner_plan.user_id
                              FROM plans AS owner_plan
                              WHERE owner_plan.id = plan_item.plan_id
                          )
                          AND item_completion.completed_at IS NOT NULL
                          AND item_completion.artifact_job_id::text =
                              plan_item.details_json #>> '{_generation,job_id}'
                    ) THEN 'COMPLETED'::plan_item_status
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
                              plan_item.details_json #>> '{_generation,job_id}'
                    ) THEN 'IN_PROGRESS'::plan_item_status
                    ELSE 'NOT_STARTED'::plan_item_status
                END,
                progress_percent = CASE
                    -- Progress identity is usable only when the complete
                    -- array has unique, already-trimmed, non-empty string
                    -- IDs. Any malformed entry fails the whole artifact
                    -- closed instead of creating untoggleable progress.
                    WHEN jsonb_typeof(
                        plan_item.details_json -> 'steps'
                    ) IS DISTINCT FROM 'array' THEN 0
                    WHEN jsonb_array_length(
                        plan_item.details_json -> 'steps'
                    ) = 0 THEN 0
                    WHEN EXISTS (
                        SELECT 1
                        FROM jsonb_array_elements(
                            plan_item.details_json -> 'steps'
                        ) AS step
                        WHERE jsonb_typeof(step) IS DISTINCT FROM 'object'
                           OR jsonb_typeof(step -> 'id')
                              IS DISTINCT FROM 'string'
                           OR BTRIM(
                                  step ->> 'id',
                                  U&'\\0009\\000A\\000B\\000C\\000D\\001C\\001D\\001E\\001F\\0020\\0085\\00A0\\1680\\2000\\2001\\2002\\2003\\2004\\2005\\2006\\2007\\2008\\2009\\200A\\2028\\2029\\202F\\205F\\3000'
                              ) = ''
                           OR (step ->> 'id') IS DISTINCT FROM
                              BTRIM(
                                  step ->> 'id',
                                  U&'\\0009\\000A\\000B\\000C\\000D\\001C\\001D\\001E\\001F\\0020\\0085\\00A0\\1680\\2000\\2001\\2002\\2003\\2004\\2005\\2006\\2007\\2008\\2009\\200A\\2028\\2029\\202F\\205F\\3000'
                              )
                           OR CHAR_LENGTH(step ->> 'id') > 100
                    ) THEN 0
                    WHEN jsonb_array_length(
                        plan_item.details_json -> 'steps'
                    ) <> (
                        SELECT COUNT(DISTINCT step ->> 'id')
                        FROM jsonb_array_elements(
                            plan_item.details_json -> 'steps'
                        ) AS step
                    ) THEN 0
                    WHEN EXISTS (
                        SELECT 1
                        FROM plan_item_completions AS item_completion
                        WHERE item_completion.plan_item_id = plan_item.id
                          AND item_completion.user_id = (
                              SELECT owner_plan.user_id
                              FROM plans AS owner_plan
                              WHERE owner_plan.id = plan_item.plan_id
                          )
                          AND item_completion.completed_at IS NOT NULL
                          AND item_completion.artifact_job_id::text =
                              plan_item.details_json #>> '{_generation,job_id}'
                    ) THEN 100
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
                                      plan_item.details_json #>> '{_generation,job_id}'
                            ) / jsonb_array_length(
                                plan_item.details_json -> 'steps'
                            )
                        )::integer
                    )
                END
            WHERE plan_item.details_json ? '_generation'
              AND (
                  jsonb_typeof(plan_item.details_json -> '_generation')
                      <> 'object'
                  OR COALESCE(
                      plan_item.details_json #> '{_generation}',
                      '{}'::jsonb
                  ) ? 'job_id'
              )
              AND plan_item.status <> 'SKIPPED'::plan_item_status
            """
        )
    )

    # Reopen only plans that have no successor and whose current mission
    # artifacts are no longer all complete. Historical rows remain untouched.
    op.execute(
        sa.text(
            """
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
                    AND (
                        NOT EXISTS (
                            SELECT 1
                            FROM plan_item_completions AS item_completion
                            WHERE item_completion.plan_item_id = plan_item.id
                              AND item_completion.user_id = plan.user_id
                              AND item_completion.completed_at IS NOT NULL
                              AND (
                                  (
                                      (
                                          NOT COALESCE(
                                              plan_item.details_json
                                                  ? '_generation',
                                              FALSE
                                          )
                                          OR (
                                              jsonb_typeof(
                                                  plan_item.details_json
                                                      -> '_generation'
                                              ) = 'object'
                                              AND NOT (
                                                  COALESCE(
                                                      plan_item.details_json
                                                          #> '{_generation}',
                                                      '{}'::jsonb
                                                  ) ? 'job_id'
                                              )
                                          )
                                      )
                                      AND item_completion.artifact_job_id IS NULL
                                  )
                                  OR item_completion.artifact_job_id::text =
                                      plan_item.details_json
                                          #>> '{_generation,job_id}'
                              )
                        )
                        OR EXISTS (
                            SELECT 1
                            FROM plan_item_detail_jobs AS active_replacement
                            WHERE active_replacement.plan_item_id = plan_item.id
                              AND active_replacement.user_id = plan.user_id
                              AND active_replacement.status IN (
                                  'pending', 'queued', 'running'
                              )
                              AND active_replacement.id::text IS DISTINCT FROM
                                  plan_item.details_json
                                      #>> '{_generation,job_id}'
                        )
                    )
              )
            """
        )
    )


def downgrade() -> None:
    # Refuse to erase artifact history merely to satisfy the old unique shape.
    # A downgrade is safe only while every old logical key still has one row.
    op.execute(
        sa.text(
            """
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1
                    FROM plan_item_step_completions
                    GROUP BY user_id, plan_item_id, step_id
                    HAVING COUNT(*) > 1
                ) OR EXISTS (
                    SELECT 1
                    FROM plan_item_completions
                    GROUP BY user_id, plan_item_id
                    HAVING COUNT(*) > 1
                ) THEN
                    RAISE EXCEPTION
                        'cannot downgrade h6 without deleting artifact completion history';
                END IF;
            END $$
            """
        )
    )
    op.drop_index(
        "ix_plan_item_step_completions_artifact_unique",
        table_name="plan_item_step_completions",
    )
    op.drop_index(
        "ix_plan_item_step_completions_unique",
        table_name="plan_item_step_completions",
    )
    op.drop_index(
        "ix_plan_item_completions_artifact_unique",
        table_name="plan_item_completions",
    )
    op.drop_index(
        "ix_plan_item_completions_unique",
        table_name="plan_item_completions",
    )
    op.drop_column("plan_item_step_completions", "artifact_job_id")
    op.drop_column("plan_item_completions", "artifact_job_id")
    op.create_index(
        "ix_plan_item_step_completions_unique",
        "plan_item_step_completions",
        ["user_id", "plan_item_id", "step_id"],
        unique=True,
    )
    op.create_index(
        "ix_plan_item_completions_unique",
        "plan_item_completions",
        ["user_id", "plan_item_id"],
        unique=True,
    )
    op.drop_column("plan_item_detail_jobs", "supersedes_artifact")
    op.drop_column("plan_item_detail_jobs", "artifact_epoch_at")
