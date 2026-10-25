"""Close curriculum retry, budget, history, and audit-integrity gaps.

Revision ID: h7i8j9k0l1m2
Revises: h6i7j8k9l0m1
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "h7i8j9k0l1m2"
down_revision: Union[str, None] = "h6i7j8k9l0m1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _replace_ready_personalized_lesson_guard(
    *,
    allow_deleted_state_owner: bool,
) -> None:
    ri_action_condition = (
        """
               AND NOT EXISTS (
                   SELECT 1 FROM learner_skill_states
                   WHERE id = OLD.learner_state_id
               )
        """
        if allow_deleted_state_owner
        else "AND pg_trigger_depth() > 1"
    )
    op.execute(
        f"""
        CREATE OR REPLACE FUNCTION guard_ready_personalized_lesson()
        RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                IF OLD.status::text IN ('ready', 'revoked')
                   AND pg_trigger_depth() <= 1 THEN
                    RAISE EXCEPTION
                        'ready personalized lesson versions are immutable';
                END IF;
                RETURN OLD;
            END IF;

            -- learner_skill_states owns this nullable live pointer. Permit its
            -- FK action only after the exact parent row has left the statement
            -- snapshot and only when every other persisted value is unchanged.
            IF OLD.status::text IN ('ready', 'revoked')
               {ri_action_condition}
               AND OLD.learner_state_id IS NOT NULL
               AND NEW.learner_state_id IS NULL
               AND (to_jsonb(OLD) - 'learner_state_id') IS NOT DISTINCT FROM
                   (to_jsonb(NEW) - 'learner_state_id') THEN
                RETURN NEW;
            END IF;

            IF OLD.status::text IN ('ready', 'revoked') AND (
                OLD.user_id IS DISTINCT FROM NEW.user_id OR
                OLD.module_session_id IS DISTINCT FROM NEW.module_session_id OR
                OLD.module_version_id IS DISTINCT FROM NEW.module_version_id OR
                OLD.learner_state_id IS DISTINCT FROM NEW.learner_state_id OR
                OLD.version_number IS DISTINCT FROM NEW.version_number OR
                OLD.learner_state_snapshot_json IS DISTINCT FROM NEW.learner_state_snapshot_json OR
                OLD.learner_state_hash IS DISTINCT FROM NEW.learner_state_hash OR
                OLD.mentor_evidence_snapshot_json IS DISTINCT FROM NEW.mentor_evidence_snapshot_json OR
                OLD.mentor_evidence_hash IS DISTINCT FROM NEW.mentor_evidence_hash OR
                OLD.personalization_brief_json IS DISTINCT FROM NEW.personalization_brief_json OR
                OLD.input_hash IS DISTINCT FROM NEW.input_hash OR
                OLD.content_json IS DISTINCT FROM NEW.content_json OR
                OLD.content_hash IS DISTINCT FROM NEW.content_hash OR
                OLD.estimated_minutes IS DISTINCT FROM NEW.estimated_minutes OR
                OLD.prompt_version IS DISTINCT FROM NEW.prompt_version OR
                OLD.model_name IS DISTINCT FROM NEW.model_name
            ) THEN
                RAISE EXCEPTION 'ready personalized lesson content is immutable';
            END IF;

            IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
                (OLD.status::text = 'queued' AND
                 NEW.status::text IN ('generating', 'failed')) OR
                (OLD.status::text = 'generating' AND
                 NEW.status::text IN ('ready', 'failed')) OR
                (OLD.status::text = 'failed' AND
                 NEW.status::text IN ('queued', 'generating')) OR
                (OLD.status::text = 'ready' AND NEW.status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid personalized lesson transition';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )


def _create_lifecycle_audit_guards() -> None:
    op.execute(
        """
        CREATE FUNCTION guard_curriculum_lifecycle_audit() RETURNS trigger AS $$
        DECLARE
            old_row jsonb;
            new_row jsonb;
            status_key text := TG_ARGV[0];
            finalized_at_key text := TG_ARGV[1];
            final_status text := TG_ARGV[2];
            old_status text;
            new_status text;
            old_finalized_at text;
            new_finalized_at text;
            old_revoked_at text;
            new_revoked_at text;
            old_reason text;
            new_reason text;
            valid_finalization boolean;
            valid_revocation boolean;
        BEGIN
            old_row := to_jsonb(OLD);
            new_row := to_jsonb(NEW);
            old_status := old_row ->> status_key;
            new_status := new_row ->> status_key;
            old_finalized_at := old_row ->> finalized_at_key;
            new_finalized_at := new_row ->> finalized_at_key;
            old_revoked_at := old_row ->> 'revoked_at';
            new_revoked_at := new_row ->> 'revoked_at';
            old_reason := old_row ->> 'revocation_reason';
            new_reason := new_row ->> 'revocation_reason';

            valid_finalization := (
                old_status IS DISTINCT FROM new_status
                AND new_status = final_status
                AND old_finalized_at IS NULL
                AND new_finalized_at IS NOT NULL
            );
            IF old_finalized_at IS DISTINCT FROM new_finalized_at
               AND NOT valid_finalization THEN
                RAISE EXCEPTION '% lifecycle audit fields are immutable',
                    TG_TABLE_NAME;
            END IF;
            IF old_status IS DISTINCT FROM new_status
               AND new_status = final_status
               AND NOT valid_finalization THEN
                RAISE EXCEPTION '% must set % exactly when finalized',
                    TG_TABLE_NAME, finalized_at_key;
            END IF;

            IF TG_TABLE_NAME = 'learning_technique_versions'
               AND old_status IN ('published', 'revoked')
               AND (old_row ->> 'reviewed_at') IS DISTINCT FROM
                   (new_row ->> 'reviewed_at') THEN
                RAISE EXCEPTION '% lifecycle audit fields are immutable',
                    TG_TABLE_NAME;
            END IF;

            valid_revocation := (
                old_status = final_status
                AND new_status = 'revoked'
                AND old_revoked_at IS NULL
                AND old_reason IS NULL
                AND new_revoked_at IS NOT NULL
                AND NULLIF(btrim(COALESCE(new_reason, '')), '') IS NOT NULL
            );
            IF (
                old_revoked_at IS DISTINCT FROM new_revoked_at
                OR old_reason IS DISTINCT FROM new_reason
            ) AND NOT valid_revocation THEN
                RAISE EXCEPTION '% lifecycle audit fields are immutable',
                    TG_TABLE_NAME;
            END IF;
            IF old_status IS DISTINCT FROM new_status
               AND new_status = 'revoked'
               AND NOT valid_revocation THEN
                RAISE EXCEPTION
                    '% must set revoked_at and revocation_reason exactly when revoked',
                    TG_TABLE_NAME;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    for table_name, status_key, finalized_at_key, final_status in (
        (
            "canonical_module_versions",
            "status",
            "published_at",
            "published",
        ),
        (
            "learning_technique_versions",
            "status",
            "published_at",
            "published",
        ),
        (
            "personalized_lesson_versions",
            "status",
            "ready_at",
            "ready",
        ),
        (
            "mentor_evidence_claims",
            "verification_status",
            "verified_at",
            "verified",
        ),
    ):
        trigger_name = f"trg_guard_{table_name}_lifecycle_audit"
        op.execute(
            sa.text(
                f"""
                CREATE TRIGGER {trigger_name}
                BEFORE UPDATE ON {table_name}
                FOR EACH ROW EXECUTE FUNCTION guard_curriculum_lifecycle_audit(
                    '{status_key}', '{finalized_at_key}', '{final_status}'
                )
                """
            )
        )


def upgrade() -> None:
    # Legacy/manual rows without a ceiling receive a zero-dollar ceiling rather
    # than silently inheriting permission for unbounded spend.
    op.execute(
        """
        UPDATE curriculum_generation_jobs
        SET budget_limit_usd = 0
        WHERE budget_limit_usd IS NULL
        """
    )
    op.drop_constraint(
        "ck_curriculum_generation_jobs_budget",
        "curriculum_generation_jobs",
        type_="check",
    )
    op.alter_column(
        "curriculum_generation_jobs",
        "budget_limit_usd",
        existing_type=sa.Numeric(12, 6),
        nullable=False,
        server_default=sa.text("0"),
    )
    op.create_check_constraint(
        "ck_curriculum_generation_jobs_budget",
        "curriculum_generation_jobs",
        "budget_limit_usd >= 0",
    )

    op.drop_constraint(
        "uq_plan_lesson_assignments_plan_session",
        "plan_lesson_assignments",
        type_="unique",
    )
    op.create_index(
        "uq_plan_lesson_assignments_plan_session",
        "plan_lesson_assignments",
        ["plan_id", "module_session_id"],
        unique=True,
        postgresql_where=sa.text("status NOT IN ('skipped', 'replaced')"),
    )
    op.create_index(
        "ix_personalized_lessons_ready_mentor_evidence",
        "personalized_lesson_versions",
        ["content_json"],
        unique=False,
        postgresql_using="gin",
        postgresql_ops={"content_json": "jsonb_path_ops"},
        postgresql_where=sa.text("status = 'ready' AND revoked_at IS NULL"),
    )
    _replace_ready_personalized_lesson_guard(allow_deleted_state_owner=True)
    _create_lifecycle_audit_guards()


def downgrade() -> None:
    # The forward schema intentionally permits multiple terminal historical rows
    # for one plan/session. Never remove guards or indexes and only then discover
    # that the old unconditional constraint can no longer be restored.
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM plan_lesson_assignments
                GROUP BY plan_id, module_session_id
                HAVING count(*) > 1
            ) THEN
                RAISE EXCEPTION
                    'cannot downgrade h7 with retained terminal assignment history';
            END IF;
        END;
        $$;
        """
    )
    for table_name in (
        "mentor_evidence_claims",
        "personalized_lesson_versions",
        "learning_technique_versions",
        "canonical_module_versions",
    ):
        op.execute(
            f"DROP TRIGGER IF EXISTS "
            f"trg_guard_{table_name}_lifecycle_audit ON {table_name}"
        )
    op.execute("DROP FUNCTION IF EXISTS guard_curriculum_lifecycle_audit()")
    _replace_ready_personalized_lesson_guard(allow_deleted_state_owner=False)

    op.drop_index(
        "ix_personalized_lessons_ready_mentor_evidence",
        table_name="personalized_lesson_versions",
    )
    op.drop_index(
        "uq_plan_lesson_assignments_plan_session",
        table_name="plan_lesson_assignments",
    )
    op.create_unique_constraint(
        "uq_plan_lesson_assignments_plan_session",
        "plan_lesson_assignments",
        ["plan_id", "module_session_id"],
    )

    op.drop_constraint(
        "ck_curriculum_generation_jobs_budget",
        "curriculum_generation_jobs",
        type_="check",
    )
    op.alter_column(
        "curriculum_generation_jobs",
        "budget_limit_usd",
        existing_type=sa.Numeric(12, 6),
        nullable=True,
        server_default=None,
    )
    op.create_check_constraint(
        "ck_curriculum_generation_jobs_budget",
        "curriculum_generation_jobs",
        "budget_limit_usd IS NULL OR budget_limit_usd >= 0",
    )
