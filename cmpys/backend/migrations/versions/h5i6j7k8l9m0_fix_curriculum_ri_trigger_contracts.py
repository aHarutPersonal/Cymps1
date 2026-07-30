"""fix curriculum referential-action trigger contracts

Revision ID: h5i6j7k8l9m0
Revises: g4h5i6j7k8l9

The curriculum foundation intentionally makes evidence and quality reports
immutable after publication. Three guards also intercepted referential actions
declared by their own foreign keys. Keep direct mutation protection while
allowing the narrowly-scoped database cascades.

This revision also reconciles deployments already stamped at the foundation
revision before its retrieval hash, plan-assignment cascade guard, and lookup
index were added.
"""

from typing import Sequence, Union

from alembic import op


revision: str = "h5i6j7k8l9m0"
down_revision: Union[str, None] = "g4h5i6j7k8l9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Some development deployments were stamped at g4 before retrieval hashes
    # were added to the still-unreleased foundation revision. Repair them in a
    # forward migration; a clean g4 install already has this column/constraint.
    op.execute(
        """
        ALTER TABLE canonical_module_versions
        ADD COLUMN IF NOT EXISTS retrieval_metadata_hash varchar(64)
        """
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION curriculum_canonical_jsonb_for_migration(payload jsonb)
        RETURNS text AS $$
            SELECT CASE jsonb_typeof(payload)
                WHEN 'object' THEN COALESCE(
                    (
                        SELECT '{' || string_agg(
                            to_jsonb(entry.key)::text || ':' ||
                            curriculum_canonical_jsonb_for_migration(entry.value),
                            ',' ORDER BY entry.key COLLATE "C"
                        ) || '}'
                        FROM jsonb_each(payload) AS entry(key, value)
                    ),
                    '{}'
                )
                WHEN 'array' THEN COALESCE(
                    (
                        SELECT '[' || string_agg(
                            curriculum_canonical_jsonb_for_migration(element.value),
                            ',' ORDER BY element.position
                        ) || ']'
                        FROM jsonb_array_elements(payload) WITH ORDINALITY
                            AS element(value, position)
                    ),
                    '[]'
                )
                ELSE payload::text
            END
        $$ LANGUAGE SQL IMMUTABLE STRICT;

        UPDATE canonical_module_versions
        SET retrieval_metadata_hash = encode(
            sha256(
                convert_to(
                    curriculum_canonical_jsonb_for_migration(retrieval_metadata_json),
                    'UTF8'
                )
            ),
            'hex'
        )
        WHERE retrieval_metadata_hash IS NULL;

        DROP FUNCTION curriculum_canonical_jsonb_for_migration(jsonb);
        """
    )
    op.execute(
        """
        ALTER TABLE canonical_module_versions
        ALTER COLUMN retrieval_metadata_hash SET NOT NULL
        """
    )
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM pg_constraint
                WHERE conrelid = 'canonical_module_versions'::regclass
                  AND conname = 'ck_canonical_module_version_retrieval_hash_sha256'
            ) THEN
                ALTER TABLE canonical_module_versions
                ADD CONSTRAINT ck_canonical_module_version_retrieval_hash_sha256
                CHECK (retrieval_metadata_hash ~ '^[0-9a-f]{64}$');
            END IF;
        END;
        $$;
        """
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_canonical_module_version()
        RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION 'canonical module versions are append-only';
            END IF;

            IF OLD.status::text IN ('published', 'revoked') AND (
                OLD.module_id IS DISTINCT FROM NEW.module_id OR
                OLD.version_number IS DISTINCT FROM NEW.version_number OR
                OLD.supersedes_version_id IS DISTINCT FROM NEW.supersedes_version_id OR
                OLD.content_json IS DISTINCT FROM NEW.content_json OR
                OLD.source_manifest_json IS DISTINCT FROM NEW.source_manifest_json OR
                OLD.technique_plan_json IS DISTINCT FROM NEW.technique_plan_json OR
                OLD.content_hash IS DISTINCT FROM NEW.content_hash OR
                OLD.source_hash IS DISTINCT FROM NEW.source_hash OR
                OLD.estimated_minutes IS DISTINCT FROM NEW.estimated_minutes OR
                OLD.quality_score IS DISTINCT FROM NEW.quality_score OR
                OLD.prompt_version IS DISTINCT FROM NEW.prompt_version OR
                OLD.gate_version IS DISTINCT FROM NEW.gate_version OR
                OLD.model_name IS DISTINCT FROM NEW.model_name OR
                OLD.retrieval_metadata_json IS DISTINCT FROM NEW.retrieval_metadata_json OR
                OLD.retrieval_metadata_hash IS DISTINCT FROM NEW.retrieval_metadata_hash
            ) THEN
                RAISE EXCEPTION 'published canonical module content is immutable';
            END IF;

            IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
                (OLD.status::text = 'draft' AND NEW.status::text IN ('in_review', 'published')) OR
                (OLD.status::text = 'in_review' AND NEW.status::text IN ('draft', 'published')) OR
                (OLD.status::text = 'published' AND NEW.status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid canonical module version transition';
            END IF;
            IF NEW.status::text = 'revoked' AND EXISTS (
                SELECT 1 FROM canonical_modules
                WHERE current_published_version_id = NEW.id
            ) THEN
                RAISE EXCEPTION 'detach a current module version before revoking it';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_mentor_evidence_claim()
        RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                IF OLD.verification_status::text <> 'pending' AND NOT (
                    pg_trigger_depth() > 1
                    AND NOT EXISTS (
                        SELECT 1 FROM idols WHERE id = OLD.idol_id
                    )
                ) THEN
                    RAISE EXCEPTION
                        'finalized mentor evidence claims are append-only';
                END IF;
                RETURN OLD;
            END IF;

            IF OLD.verification_status::text <> 'pending' AND (
                OLD.idol_id IS DISTINCT FROM NEW.idol_id OR
                OLD.claim_type IS DISTINCT FROM NEW.claim_type OR
                OLD.claim_text IS DISTINCT FROM NEW.claim_text OR
                OLD.normalized_hash IS DISTINCT FROM NEW.normalized_hash OR
                OLD.source_chunk_id IS DISTINCT FROM NEW.source_chunk_id OR
                OLD.source_title IS DISTINCT FROM NEW.source_title OR
                OLD.source_url IS DISTINCT FROM NEW.source_url OR
                OLD.evidence_excerpt IS DISTINCT FROM NEW.evidence_excerpt OR
                OLD.evidence_json IS DISTINCT FROM NEW.evidence_json OR
                OLD.source_hash IS DISTINCT FROM NEW.source_hash OR
                OLD.skill_tags_json IS DISTINCT FROM NEW.skill_tags_json OR
                OLD.confidence IS DISTINCT FROM NEW.confidence OR
                OLD.valid_from IS DISTINCT FROM NEW.valid_from OR
                OLD.valid_to IS DISTINCT FROM NEW.valid_to
            ) THEN
                RAISE EXCEPTION 'finalized mentor evidence is immutable';
            END IF;

            IF OLD.verification_status IS DISTINCT FROM NEW.verification_status AND NOT (
                (OLD.verification_status::text = 'pending' AND
                 NEW.verification_status::text IN ('verified', 'rejected')) OR
                (OLD.verification_status::text = 'verified' AND
                 NEW.verification_status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid mentor evidence transition';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_mentor_claim_skill_binding()
        RETURNS trigger AS $$
        DECLARE
            checked_claim_count integer := 0;
            expected_claim_count integer := 1;
            claim_row record;
        BEGIN
            IF TG_OP = 'UPDATE' AND OLD.claim_id IS DISTINCT FROM NEW.claim_id THEN
                expected_claim_count := 2;
            END IF;

            -- Lock both sides of a reassignment in UUID order. Checking only
            -- NEW.claim_id would allow UPDATE A -> B to remove a binding from
            -- finalized A whenever B was still pending.
            FOR claim_row IN
                SELECT id, verification_status::text AS claim_status
                FROM mentor_evidence_claims
                WHERE id IN (
                    CASE WHEN TG_OP = 'INSERT' THEN NEW.claim_id ELSE OLD.claim_id END,
                    CASE WHEN TG_OP = 'DELETE' THEN OLD.claim_id ELSE NEW.claim_id END
                )
                ORDER BY id
                FOR SHARE
            LOOP
                checked_claim_count := checked_claim_count + 1;
                IF claim_row.claim_status IS DISTINCT FROM 'pending' THEN
                    RAISE EXCEPTION
                        'skill bindings of finalized mentor evidence are immutable';
                END IF;
            END LOOP;

            -- A valid child cannot outlive its FK parent.  Therefore a missing
            -- parent on DELETE is the nested ON DELETE CASCADE action, after the
            -- parent claim has already left the statement snapshot.  Inserts and
            -- updates never receive this exception and remain FK-checked.
            IF TG_OP = 'DELETE' AND checked_claim_count = 0 THEN
                RETURN OLD;
            END IF;
            IF checked_claim_count <> expected_claim_count THEN
                RAISE EXCEPTION 'mentor evidence claim does not exist';
            END IF;
            IF TG_OP = 'DELETE' THEN
                RETURN OLD;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_module_quality_report()
        RETURNS trigger AS $$
        BEGIN
            -- The FK action is the only permitted update: it is nested below
            -- DELETE FROM curriculum_generation_jobs, clears exactly its link,
            -- sees the deleted parent as absent, and leaves every append-only
            -- report field unchanged.  A direct SET generation_job_id = NULL
            -- runs at trigger depth 1 and is still rejected.
            IF TG_OP = 'UPDATE'
               AND pg_trigger_depth() > 1
               AND OLD.generation_job_id IS NOT NULL
               AND NEW.generation_job_id IS NULL
               AND NOT EXISTS (
                   SELECT 1
                   FROM curriculum_generation_jobs
                   WHERE id = OLD.generation_job_id
               )
               AND (to_jsonb(OLD) - 'generation_job_id') IS NOT DISTINCT FROM
                   (to_jsonb(NEW) - 'generation_job_id')
            THEN
                RETURN NEW;
            END IF;

            RAISE EXCEPTION 'module quality reports are append-only';
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    # The foundation revision was still under review when these two additions
    # landed. CREATE OR REPLACE / IF NOT EXISTS makes already-stamped databases
    # converge without disturbing clean installs that already have both objects.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_plan_lesson_assignment_owner()
        RETURNS trigger AS $$
        DECLARE
            plan_user_id uuid;
            item_plan_id uuid;
            lesson_user_id uuid;
            lesson_status text;
            lesson_revoked_at timestamptz;
        BEGIN
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
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgrelid = 'canonical_module_versions'::regclass
                  AND tgname = 'trg_guard_canonical_module_version'
                  AND NOT tgisinternal
            ) THEN
                CREATE TRIGGER trg_guard_canonical_module_version
                BEFORE UPDATE OR DELETE ON canonical_module_versions
                FOR EACH ROW EXECUTE FUNCTION guard_canonical_module_version();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgrelid = 'mentor_evidence_claims'::regclass
                  AND tgname = 'trg_guard_mentor_evidence_claim'
                  AND NOT tgisinternal
            ) THEN
                CREATE TRIGGER trg_guard_mentor_evidence_claim
                BEFORE UPDATE OR DELETE ON mentor_evidence_claims
                FOR EACH ROW EXECUTE FUNCTION guard_mentor_evidence_claim();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgrelid = 'mentor_evidence_claim_skills'::regclass
                  AND tgname = 'trg_guard_mentor_claim_skill_binding'
                  AND NOT tgisinternal
            ) THEN
                CREATE TRIGGER trg_guard_mentor_claim_skill_binding
                BEFORE INSERT OR UPDATE OR DELETE ON mentor_evidence_claim_skills
                FOR EACH ROW EXECUTE FUNCTION guard_mentor_claim_skill_binding();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgrelid = 'module_quality_reports'::regclass
                  AND tgname = 'trg_guard_module_quality_report'
                  AND NOT tgisinternal
            ) THEN
                CREATE TRIGGER trg_guard_module_quality_report
                BEFORE UPDATE OR DELETE ON module_quality_reports
                FOR EACH ROW EXECUTE FUNCTION guard_module_quality_report();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgrelid = 'plan_lesson_assignments'::regclass
                  AND tgname = 'trg_guard_plan_lesson_assignment_owner'
                  AND NOT tgisinternal
            ) THEN
                CREATE TRIGGER trg_guard_plan_lesson_assignment_owner
                BEFORE INSERT OR UPDATE OF plan_id, plan_item_id, module_session_id,
                    personalized_lesson_version_id, status
                ON plan_lesson_assignments
                FOR EACH ROW EXECUTE FUNCTION guard_plan_lesson_assignment_owner();
            END IF;
        END;
        $$;
        """
    )
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_plan_lesson_assignments_plan_item
        ON plan_lesson_assignments (plan_item_id)
        WHERE plan_item_id IS NOT NULL
        """
    )


def downgrade() -> None:
    # The retrieval hash/guard and plan-assignment function/index belong to the
    # current definition of the foundation revision, so they intentionally
    # remain when stepping back to g4h5i6j7k8l9. Restore only the three RI
    # contracts introduced here.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_module_quality_report()
        RETURNS trigger AS $$
        BEGIN
            RAISE EXCEPTION 'module quality reports are append-only';
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_mentor_evidence_claim()
        RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                IF OLD.verification_status::text <> 'pending' THEN
                    RAISE EXCEPTION
                        'finalized mentor evidence claims are append-only';
                END IF;
                RETURN OLD;
            END IF;

            IF OLD.verification_status::text <> 'pending' AND (
                OLD.idol_id IS DISTINCT FROM NEW.idol_id OR
                OLD.claim_type IS DISTINCT FROM NEW.claim_type OR
                OLD.claim_text IS DISTINCT FROM NEW.claim_text OR
                OLD.normalized_hash IS DISTINCT FROM NEW.normalized_hash OR
                OLD.source_chunk_id IS DISTINCT FROM NEW.source_chunk_id OR
                OLD.source_title IS DISTINCT FROM NEW.source_title OR
                OLD.source_url IS DISTINCT FROM NEW.source_url OR
                OLD.evidence_excerpt IS DISTINCT FROM NEW.evidence_excerpt OR
                OLD.evidence_json IS DISTINCT FROM NEW.evidence_json OR
                OLD.source_hash IS DISTINCT FROM NEW.source_hash OR
                OLD.skill_tags_json IS DISTINCT FROM NEW.skill_tags_json OR
                OLD.confidence IS DISTINCT FROM NEW.confidence OR
                OLD.valid_from IS DISTINCT FROM NEW.valid_from OR
                OLD.valid_to IS DISTINCT FROM NEW.valid_to
            ) THEN
                RAISE EXCEPTION 'finalized mentor evidence is immutable';
            END IF;

            IF OLD.verification_status IS DISTINCT FROM NEW.verification_status AND NOT (
                (OLD.verification_status::text = 'pending' AND
                 NEW.verification_status::text IN ('verified', 'rejected')) OR
                (OLD.verification_status::text = 'verified' AND
                 NEW.verification_status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid mentor evidence transition';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION guard_mentor_claim_skill_binding()
        RETURNS trigger AS $$
        DECLARE
            target_claim_id uuid;
            claim_status text;
        BEGIN
            IF TG_OP = 'DELETE' THEN
                target_claim_id := OLD.claim_id;
            ELSE
                target_claim_id := NEW.claim_id;
            END IF;
            SELECT verification_status::text INTO claim_status
            FROM mentor_evidence_claims
            WHERE id = target_claim_id
            FOR SHARE;
            IF claim_status IS DISTINCT FROM 'pending' THEN
                RAISE EXCEPTION
                    'skill bindings of finalized mentor evidence are immutable';
            END IF;
            IF TG_OP = 'DELETE' THEN
                RETURN OLD;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
