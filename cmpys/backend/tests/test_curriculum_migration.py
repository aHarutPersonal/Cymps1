"""Static and offline-SQL checks for the additive curriculum migration."""

from pathlib import Path
import subprocess
import sys


MIGRATION = Path("migrations/versions/g4h5i6j7k8l9_curriculum_factory_foundation.py")
RI_CONTRACT_MIGRATION = Path(
    "migrations/versions/h5i6j7k8l9m0_fix_curriculum_ri_trigger_contracts.py"
)
DETAIL_JOB_CLOCK_MIGRATION = Path(
    "migrations/versions/h6i7j8k9l0m1_detail_job_wall_clock_epoch.py"
)
CURRICULUM_INTEGRITY_MIGRATION = Path(
    "migrations/versions/h7i8j9k0l1m2_curriculum_integrity_guards.py"
)
CURRICULUM_AUDIT_SHAPE_MIGRATION = Path(
    "migrations/versions/h8i9j0k1l2m3_curriculum_audit_shapes.py"
)
CURRICULUM_H8_CONVERGENCE_MIGRATION = Path(
    "migrations/versions/h9j0k1l2m3n4_curriculum_h8_convergence.py"
)
CURRICULUM_USAGE_LEDGER_INDEX_MIGRATION = Path(
    "migrations/versions/i0j1k2l3m4n5_curriculum_usage_ledger_index.py"
)


def test_curriculum_migration_is_based_on_expected_head_and_additive():
    source = MIGRATION.read_text(encoding="utf-8")
    assert 'revision: str = "g4h5i6j7k8l9"' in source
    assert 'down_revision: Union[str, None] = "f3g4h5i6j7k8"' in source

    upgrade_source = source.split("def upgrade() -> None:", 1)[1].split(
        "def _create_immutability_guards", 1
    )[0]
    assert "op.drop_" not in upgrade_source
    assert "DELETE FROM" not in upgrade_source
    assert "UPDATE " not in upgrade_source

    for table in (
        "curriculum_skills",
        "learning_technique_versions",
        "canonical_modules",
        "canonical_module_versions",
        "module_sessions",
        "curriculum_generation_jobs",
        "module_quality_reports",
        "mentor_evidence_claims",
        "learner_skill_states",
        "personalized_lesson_versions",
        "plan_lesson_assignments",
    ):
        assert f'"{table}"' in upgrade_source


def test_migration_contains_db_level_pinning_and_immutability_guards():
    source = MIGRATION.read_text(encoding="utf-8")
    assert '"fk_canonical_modules_current_published_version"' in source
    assert '["current_published_version_id", "id"]' in source
    assert '["id", "module_id"]' in source
    assert '"fk_canonical_module_versions_supersedes_same_module"' in source
    assert "Vector(1024)" in source
    assert "vector_cosine_ops" in source

    for trigger in (
        "trg_guard_canonical_module_version",
        "trg_guard_canonical_module_current_version",
        "trg_guard_learning_technique_version",
        "trg_guard_published_module_session",
        "trg_guard_ready_personalized_lesson",
        "trg_guard_module_quality_report",
        "trg_guard_mentor_evidence_claim",
        "trg_guard_mentor_claim_skill_binding",
        "trg_guard_mentor_claim_source_owner",
        "trg_guard_plan_lesson_assignment_owner",
    ):
        assert f"CREATE TRIGGER {trigger}" in source

    assert (
        "OLD.source_manifest_json IS DISTINCT FROM NEW.source_manifest_json" in source
    )
    assert "OLD.technique_plan_json IS DISTINCT FROM NEW.technique_plan_json" in source
    assert "OLD.quality_score IS DISTINCT FROM NEW.quality_score" in source
    assert (
        "OLD.retrieval_metadata_json IS DISTINCT FROM NEW.retrieval_metadata_json"
        in source
    )
    assert (
        "OLD.retrieval_metadata_hash IS DISTINCT FROM NEW.retrieval_metadata_hash"
        in source
    )
    assert "BEFORE INSERT OR UPDATE OR DELETE ON module_sessions" in source
    assert "FOR SHARE" in source
    assert "BEFORE UPDATE OR DELETE ON personalized_lesson_versions" in source
    assert "pg_trigger_depth() <= 1" in source
    assert "pg_trigger_depth() > 1" in source
    assert "OLD.learner_state_id IS NOT NULL" in source
    assert "ck_plan_lesson_assignments_personalized_visibility" in source
    assert "fk_plan_lesson_assignments_personalized_session" in source
    assert "uq_plan_lesson_assignments_plan_session" in source
    assert "personalized lesson belongs to another plan user" in source
    assert "plan lesson assignment item belongs to another plan" in source
    assert "UPDATE OF plan_id, plan_item_id, module_session_id" in source
    assert "uq_canonical_modules_compatibility_key" not in source
    assert "uq_mentor_evidence_claims_idol_claim_source" in source
    assert "uq_mentor_evidence_claims_idol_hash" not in source
    assert "content_json IS NOT NULL AND content_hash IS NOT NULL" in source


def test_forward_revision_repairs_ri_actions_without_weakening_direct_guards():
    source = RI_CONTRACT_MIGRATION.read_text(encoding="utf-8")
    assert 'revision: str = "h5i6j7k8l9m0"' in source
    assert 'down_revision: Union[str, None] = "g4h5i6j7k8l9"' in source

    upgrade_source = source.split("def upgrade() -> None:", 1)[1].split(
        "def downgrade() -> None:", 1
    )[0]
    assert "ADD COLUMN IF NOT EXISTS retrieval_metadata_hash" in upgrade_source
    assert "curriculum_canonical_jsonb_for_migration" in upgrade_source
    assert "sha256(" in upgrade_source
    assert "ALTER COLUMN retrieval_metadata_hash SET NOT NULL" in upgrade_source
    assert "ck_canonical_module_version_retrieval_hash_sha256" in upgrade_source
    assert (
        "CREATE OR REPLACE FUNCTION guard_canonical_module_version()" in upgrade_source
    )
    assert (
        "OLD.retrieval_metadata_hash IS DISTINCT FROM NEW.retrieval_metadata_hash"
        in upgrade_source
    )
    assert "CREATE OR REPLACE FUNCTION guard_mentor_evidence_claim()" in upgrade_source
    assert "SELECT 1 FROM idols WHERE id = OLD.idol_id" in upgrade_source
    assert (
        "CREATE OR REPLACE FUNCTION guard_mentor_claim_skill_binding()"
        in upgrade_source
    )
    assert "OLD.claim_id IS DISTINCT FROM NEW.claim_id" in upgrade_source
    assert "ORDER BY id" in upgrade_source
    assert "checked_claim_count = 0" in upgrade_source
    assert "mentor evidence claim does not exist" in upgrade_source
    assert "skill bindings of finalized mentor evidence are immutable" in upgrade_source

    assert "CREATE OR REPLACE FUNCTION guard_module_quality_report()" in upgrade_source
    assert "pg_trigger_depth() > 1" in upgrade_source
    assert "OLD.generation_job_id IS NOT NULL" in upgrade_source
    assert "NEW.generation_job_id IS NULL" in upgrade_source
    assert "WHERE id = OLD.generation_job_id" in upgrade_source
    assert "to_jsonb(OLD) - 'generation_job_id'" in upgrade_source
    assert "to_jsonb(NEW) - 'generation_job_id'" in upgrade_source
    assert "module quality reports are append-only" in upgrade_source

    assert (
        "CREATE OR REPLACE FUNCTION guard_plan_lesson_assignment_owner()"
        in upgrade_source
    )
    assert "IF NOT FOUND THEN\n                RETURN NEW;" in upgrade_source
    for trigger in (
        "trg_guard_canonical_module_version",
        "trg_guard_mentor_evidence_claim",
        "trg_guard_mentor_claim_skill_binding",
        "trg_guard_module_quality_report",
        "trg_guard_plan_lesson_assignment_owner",
    ):
        assert f"tgname = '{trigger}'" in upgrade_source
        assert f"CREATE TRIGGER {trigger}" in upgrade_source
    assert (
        "CREATE INDEX IF NOT EXISTS ix_plan_lesson_assignments_plan_item"
        in upgrade_source
    )
    assert "WHERE plan_item_id IS NOT NULL" in upgrade_source

    downgrade_source = source.split("def downgrade() -> None:", 1)[1]
    assert "DROP INDEX" not in downgrade_source
    assert "guard_plan_lesson_assignment_owner" not in downgrade_source
    assert "DROP COLUMN" not in downgrade_source
    assert "guard_canonical_module_version" not in downgrade_source
    assert downgrade_source.count("CREATE OR REPLACE FUNCTION") == 3


def test_detail_artifact_revision_uses_exact_identity_and_wall_clock_order() -> None:
    source = DETAIL_JOB_CLOCK_MIGRATION.read_text(encoding="utf-8")

    assert 'revision: str = "h6i7j8k9l0m1"' in source
    assert 'down_revision: Union[str, None] = "h5i6j7k8l9m0"' in source
    upgrade_source = source.split("def upgrade() -> None:", 1)[1].split(
        "def downgrade() -> None:", 1
    )[0]
    assert '"plan_item_detail_jobs"' in upgrade_source
    assert '"artifact_epoch_at"' in upgrade_source
    assert "op.add_column" in upgrade_source
    assert 'sa.text("clock_timestamp()")' in upgrade_source
    assert 'sa.text("now()")' not in upgrade_source
    assert "detail_job.id::text" in upgrade_source
    assert "plan_item.details_json #>> '{_generation,job_id}'" in upgrade_source
    assert "THEN clock_timestamp()" in upgrade_source
    assert "ELSE detail_job.created_at" in upgrade_source
    assert "ranked_active_replacements" in upgrade_source
    assert "MAX(artifact_epoch_at)" in upgrade_source
    assert "ROW_NUMBER() OVER" in upgrade_source
    assert "detail_job.status IN ('pending', 'queued', 'running')" in upgrade_source
    assert "IS DISTINCT FROM" in upgrade_source
    assert "replacement_rank" in upgrade_source
    assert "INTERVAL '1 microsecond'" in upgrade_source
    assert "FROM plan_item_detail_jobs AS active_replacement" in upgrade_source
    assert "active_replacement.user_id = plan.user_id" in upgrade_source
    assert "active_replacement.status IN" in upgrade_source
    assert '"supersedes_artifact"' in upgrade_source
    assert upgrade_source.count('"artifact_job_id"') >= 4
    assert "ix_plan_item_step_completions_artifact_unique" in upgrade_source
    assert "ix_plan_item_completions_artifact_unique" in upgrade_source
    assert "artifact_job_id IS NULL" in upgrade_source
    assert "artifact_job_id IS NOT NULL" in upgrade_source
    assert upgrade_source.count("SET artifact_job_id = detail_job.id") == 2
    assert "item_completion.completed_at >= detail_job.created_at" in upgrade_source
    assert "step_completion.completed_at >= detail_job.created_at" in upgrade_source
    assert upgrade_source.count("FROM plan_item_detail_jobs AS earlier_job") == 2
    assert "lesson_step.value ->> 'id' = step_completion.step_id" in upgrade_source
    assert "SET supersedes_artifact = FALSE" in upgrade_source
    assert "'false'::jsonb" in upgrade_source
    assert "plan_item.details_json #> '{_generation}'" in upgrade_source
    assert ") ? 'job_id'" in upgrade_source
    assert "jsonb_typeof(" in upgrade_source
    assert "-> 'steps'" in upgrade_source
    assert "IS DISTINCT FROM 'array' THEN 0" in upgrade_source
    assert "COALESCE(plan_item.details_json -> 'steps'" not in upgrade_source
    progress_recalculation = upgrade_source.split(
        "progress_percent = CASE",
        1,
    )[1].split("WHERE plan_item.details_json ? '_generation'", 1)[0]
    assert "jsonb_typeof(step) IS DISTINCT FROM 'object'" in progress_recalculation
    assert "IS DISTINCT FROM 'string'" in progress_recalculation
    python_strip_characters = (
        r"U&'\\0009\\000A\\000B\\000C\\000D"
        r"\\001C\\001D\\001E\\001F\\0020\\0085\\00A0\\1680"
        r"\\2000\\2001\\2002\\2003\\2004\\2005\\2006\\2007"
        r"\\2008\\2009\\200A\\2028\\2029\\202F\\205F\\3000'"
    )
    assert progress_recalculation.count(python_strip_characters) == 2
    assert r"\\000B" in python_strip_characters
    assert r"\\00A0" in python_strip_characters
    assert r"\\v" not in progress_recalculation
    assert "E'" not in progress_recalculation
    assert "BTRIM(step ->> 'id')" not in progress_recalculation
    assert "(step ->> 'id') IS DISTINCT FROM" in progress_recalculation
    assert "CHAR_LENGTH(step ->> 'id') > 100" in progress_recalculation
    assert "jsonb_array_length(" in progress_recalculation
    assert "COUNT(DISTINCT step ->> 'id')" in progress_recalculation
    completion_branch = progress_recalculation.index(
        "FROM plan_item_completions AS item_completion"
    )
    assert (
        progress_recalculation.index("IS DISTINCT FROM 'array' THEN 0")
        < completion_branch
    )
    assert progress_recalculation.index("CHAR_LENGTH(step ->> 'id') > 100") < (
        completion_branch
    )
    assert progress_recalculation.index("COUNT(DISTINCT step ->> 'id')") < (
        completion_branch
    )
    assert "NULLIF(" not in progress_recalculation
    assert "ELSE COALESCE(" not in progress_recalculation
    assert "cannot downgrade h6 without deleting artifact completion history" in source

    downgrade_source = source.split("def downgrade() -> None:", 1)[1]
    assert 'op.drop_column("plan_item_detail_jobs", "artifact_epoch_at")' in (
        downgrade_source
    )


def test_curriculum_integrity_revision_closes_fail_open_and_history_gaps() -> None:
    source = CURRICULUM_INTEGRITY_MIGRATION.read_text(encoding="utf-8")

    assert 'revision: str = "h7i8j9k0l1m2"' in source
    assert 'down_revision: Union[str, None] = "h6i7j8k9l0m1"' in source
    upgrade_source = source.split("def upgrade() -> None:", 1)[1].split(
        "def downgrade() -> None:", 1
    )[0]
    assert "SET budget_limit_usd = 0" in upgrade_source
    assert "WHERE budget_limit_usd IS NULL" in upgrade_source
    assert '"budget_limit_usd"' in upgrade_source
    assert "nullable=False" in upgrade_source
    assert '"uq_plan_lesson_assignments_plan_session"' in upgrade_source
    assert "status NOT IN ('skipped', 'replaced')" in upgrade_source
    assert '"ix_personalized_lessons_ready_mentor_evidence"' in upgrade_source
    assert 'postgresql_using="gin"' in upgrade_source
    assert '"content_json": "jsonb_path_ops"' in upgrade_source
    assert "status = 'ready' AND revoked_at IS NULL" in upgrade_source
    assert "_replace_ready_personalized_lesson_guard" in upgrade_source
    assert "allow_deleted_state_owner=True" in upgrade_source

    ready_guard_source = source.split(
        "def _replace_ready_personalized_lesson_guard", 1
    )[1].split("def _create_lifecycle_audit_guards", 1)[0]
    assert "SELECT 1 FROM learner_skill_states" in ready_guard_source
    assert "WHERE id = OLD.learner_state_id" in ready_guard_source
    assert "to_jsonb(OLD) - 'learner_state_id'" in ready_guard_source

    guard_source = source.split("def _create_lifecycle_audit_guards() -> None:", 1)[
        1
    ].split("def upgrade() -> None:", 1)[0]
    assert "CREATE FUNCTION guard_curriculum_lifecycle_audit()" in guard_source
    assert "lifecycle audit fields are immutable" in guard_source
    assert "must set revoked_at and revocation_reason exactly when revoked" in (
        guard_source
    )
    assert "old_row ->> 'reviewed_at'" in guard_source
    for table_name in (
        "canonical_module_versions",
        "learning_technique_versions",
        "personalized_lesson_versions",
        "mentor_evidence_claims",
    ):
        assert f'"{table_name}"' in guard_source

    downgrade_source = source.split("def downgrade() -> None:", 1)[1]
    preflight = downgrade_source.index("cannot downgrade h7 with retained terminal")
    first_drop = downgrade_source.index("op.drop_index")
    assert preflight < first_drop
    assert "GROUP BY plan_id, module_session_id" in downgrade_source
    assert "HAVING count(*) > 1" in downgrade_source


def test_curriculum_audit_shape_revision_is_additive_and_repairs_stamped_rows():
    source = CURRICULUM_AUDIT_SHAPE_MIGRATION.read_text(encoding="utf-8")

    assert 'revision: str = "h8i9j0k1l2m3"' in source
    assert 'down_revision: Union[str, None] = "h7i8j9k0l1m2"' in source
    assert "autocommit_block" not in source

    upgrade_source = source.split("def upgrade() -> None:", 1)[1].split(
        "def downgrade() -> None:", 1
    )[0]
    first_upgrade_call = next(
        line.strip()
        for line in upgrade_source.splitlines()
        if line.strip() and not line.strip().startswith("#")
    )
    assert first_upgrade_call == "_preflight_lifecycle_shapes()"
    assert upgrade_source.index("_preflight_lifecycle_shapes()") < (
        upgrade_source.index("_create_audit_shape_constraints()")
    )
    assert "_repair_stamped_artifact_progress()" in upgrade_source
    assert "protect_terminal_history=True" in upgrade_source

    for constraint_name in (
        "ck_learning_technique_versions_audit_shape",
        "ck_canonical_module_versions_audit_shape",
        "ck_mentor_evidence_claims_audit_shape",
        "ck_personalized_lessons_audit_shape",
    ):
        assert constraint_name in source
    assert "WHERE ({expression}) IS NOT TRUE" in source
    assert "cannot upgrade h8:" in source
    assert "published_at IS NULL" in source
    assert "published_at IS NOT NULL" in source
    assert "verified_at IS NULL" in source
    assert "verified_at IS NOT NULL" in source
    assert "ready_at IS NULL" in source
    assert "ready_at IS NOT NULL" in source
    assert "NULLIF(btrim(COALESCE(revocation_reason, '')," in source
    assert r"U&'\\0009\\000A\\000B\\000C\\000D" in source
    assert r"\\00A0" in source
    assert r"\\3000'" in source
    assert r"\\v" not in source
    assert "content_json IS NOT NULL AND content_hash IS NOT NULL" in source

    repair_source = source.split("def _repair_stamped_artifact_progress() -> None:", 1)[
        1
    ].split("def _replace_plan_assignment_guard", 1)[0]
    assert "UPDATE plan_item_completions AS item_completion" in repair_source
    assert "SET completed_at = NULL" in repair_source
    assert "UPDATE plan_item_step_completions" not in repair_source
    assert "jsonb_typeof(step) IS DISTINCT FROM 'object'" in source
    assert "jsonb_typeof(step -> 'id')" in source
    assert "IS DISTINCT FROM 'string' THEN TRUE" in source
    assert "PYTHON_STRIP_CHARACTERS_SQL = (" in source
    assert source.count("{PYTHON_STRIP_CHARACTERS_SQL}") >= 6
    assert "(step ->> 'id') IS DISTINCT FROM" in source
    assert "CHAR_LENGTH(step ->> 'id') > 100" in source
    assert "COUNT(DISTINCT step ->> 'id')" in source
    for field_name in (
        "generated_at",
        "generated_from_prompt_version",
        "description",
        "expected_output",
        "lesson_content",
        "resources",
        "substeps",
        "order",
        "estimate_minutes",
        "estimateMinutes",
        "reading_minutes",
        "readingMinutes",
        "practice_minutes",
        "practiceMinutes",
        "materials",
        "duration_minutes",
        "ideas",
        "content_resource_id",
        "contentResourceId",
        "canonical_key",
        "canonicalKey",
        "title",
        "content",
        "category",
    ):
        assert f'"{field_name}"' in source or f"'{field_name}'" in source
    assert "NOT IN ('array', 'null')" in source
    assert "NOT IN ('string', 'null')" in source
    assert "IS DISTINCT FROM 'number'" in source
    assert "!~ '^-?(0|[1-9][0-9]*)$'" in source
    assert repair_source.count("WHEN ({MALFORMED_STEPS})") == 2
    assert "IN ('partial', 'generating')" in source
    assert "INVALID_PROGRESSIVE_READY_STEP_IDS" in source
    assert "jsonb_array_length(" in source
    assert "COUNT(DISTINCT ready_step_id #>> '{{}}')" in source
    assert "current_step ->> 'id' = ready_step_id #>> '{{}}'" in source
    assert "CHAR_LENGTH(ready_step_id #>> '{{}}') > 100" in source
    assert "ELIGIBLE_PROGRESSIVE_STEP_COMPLETION" in source
    assert "TRANSLATE(" in source
    assert "REGEXP_SPLIT_TO_ARRAY(" in source
    assert ") >= 1900" in source
    assert repair_source.count("({ELIGIBLE_PROGRESSIVE_STEP_COMPLETION})") == 2
    assert repair_source.count("({INVALID_PROGRESSIVE_READY_STEP_IDS})") == 2
    assert "THEN 'NOT_STARTED'::plan_item_status" in repair_source
    assert "THEN 'IN_PROGRESS'::plan_item_status" in repair_source
    assert "LEAST(" in repair_source
    assert "99," in repair_source
    assert "UPDATE plans AS plan" in repair_source
    assert "successor.previous_plan_id = plan.id" in repair_source
    assert "'PROJECT'::plan_item_type" in repair_source
    assert "'COURSE'::plan_item_type" in repair_source
    assert "'READING'::plan_item_type" in repair_source

    guard_source = source.split("def _replace_plan_assignment_guard", 1)[1].split(
        "def upgrade() -> None:", 1
    )[0]
    assert "OLD.status::text IN ('skipped', 'replaced')" in guard_source
    assert "OLD.status IS DISTINCT FROM NEW.status" in guard_source
    assert "terminal plan lesson assignment status is immutable" in guard_source
    assert "IF NEW.plan_item_id IS NOT NULL" in guard_source

    downgrade_source = source.split("def downgrade() -> None:", 1)[1]
    assert "protect_terminal_history=False" in downgrade_source
    assert "op.drop_constraint(constraint_name, table_name" in downgrade_source
    assert "op.drop_index" not in downgrade_source
    assert "op.drop_column" not in downgrade_source
    assert "op.create_check_constraint" not in downgrade_source
    for legacy_constraint_name in (
        "ck_learning_technique_version_lifecycle",
        "ck_canonical_module_version_lifecycle",
        "ck_mentor_evidence_claims_lifecycle",
        "ck_personalized_lessons_lifecycle",
    ):
        assert legacy_constraint_name not in source


def test_h9_converges_early_stamped_h8_without_reviving_bad_state():
    source = CURRICULUM_H8_CONVERGENCE_MIGRATION.read_text(encoding="utf-8")

    assert 'revision: str = "h9j0k1l2m3n4"' in source
    assert 'down_revision: Union[str, None] = "h8i9j0k1l2m3"' in source
    assert "from migrations.versions" not in source
    assert "autocommit_block" not in source
    assert "cannot upgrade h9:" in source
    assert r"U&'\\0009\\000A\\000B\\000C\\000D" in source
    assert r"\\00A0" in source
    assert r"\\v" not in source

    upgrade_source = source.split("def upgrade() -> None:", 1)[1].split(
        "def downgrade() -> None:", 1
    )[0]
    first_upgrade_call = next(
        line.strip()
        for line in upgrade_source.splitlines()
        if line.strip() and not line.strip().startswith("#")
    )
    assert first_upgrade_call == "_preflight_lifecycle_shapes()"
    assert upgrade_source.index("_preflight_lifecycle_shapes()") < (
        upgrade_source.index("_repair_stamped_artifact_progress()")
    )
    assert upgrade_source.index("_repair_stamped_artifact_progress()") < (
        upgrade_source.index("_replace_audit_shape_constraints()")
    )
    assert "protect_terminal_history=True" in upgrade_source

    assert "NOT EXISTS (" in source
    assert "FROM plan_item_detail_jobs AS referenced_job" in source
    assert "referenced_job.id::text" in source
    assert "referenced_job.plan_item_id = plan_item.id" in source
    assert "referenced_job.user_id = referenced_owner.user_id" in source
    assert "UUID_TEXT_VARIANT_PATTERN" in source
    assert "REGEXP_REPLACE(" in source
    assert "INVALID_GENERATION_STATUS" in source
    assert "IS DISTINCT FROM 'ready'" in source
    assert "IS DISTINCT FROM 'partial'" in source
    assert "IS DISTINCT FROM 'generating'" in source
    assert "IS DISTINCT FROM 'revoked'" in source
    assert "INVALID_PROGRESSIVE_READY_STEP_IDS" in source
    assert "jsonb_array_length(" in source
    assert "COUNT(DISTINCT ready_step_id #>> '{{}}')" in source
    assert "current_step ->> 'id' = ready_step_id #>> '{{}}'" in source
    assert "CHAR_LENGTH(ready_step_id #>> '{{}}') > 100" in source
    assert "ELIGIBLE_PROGRESSIVE_STEP_COMPLETION" in source
    assert "TRANSLATE(" in source
    assert "REGEXP_SPLIT_TO_ARRAY(" in source
    assert ") >= 1900" in source
    repair_source = source.split("def _repair_stamped_artifact_progress() -> None:", 1)[
        1
    ].split("def _replace_plan_assignment_guard", 1)[0]
    assert repair_source.count("WHEN ({INVALID_CURRENT_ARTIFACT})") == 2
    assert repair_source.count("({ELIGIBLE_PROGRESSIVE_STEP_COMPLETION})") == 2
    assert "::uuid" not in repair_source
    assert "SET completed_at = NULL" in repair_source
    assert "UPDATE plan_item_step_completions" not in repair_source
    assert "successor.previous_plan_id = plan.id" in repair_source

    constraint_helper = source.split(
        "def _replace_audit_shape_constraints() -> None:", 1
    )[1].split("def _affected_artifact_predicate", 1)[0]
    assert "op.drop_constraint" in constraint_helper
    assert "op.create_check_constraint" in constraint_helper
    for constraint_name in (
        "ck_learning_technique_versions_audit_shape",
        "ck_canonical_module_versions_audit_shape",
        "ck_mentor_evidence_claims_audit_shape",
        "ck_personalized_lessons_audit_shape",
    ):
        assert constraint_name in source

    downgrade_source = source.split("def downgrade() -> None:", 1)[1]
    assert "_repair_stamped_artifact_progress()" not in downgrade_source
    assert "_replace_audit_shape_constraints()" in downgrade_source
    assert "protect_terminal_history=True" in downgrade_source
    assert "protect_terminal_history=False" not in downgrade_source


def test_h10_converges_curriculum_usage_index_and_matches_model_metadata():
    from app.models.llm_usage_event import LLMUsageEvent

    source = CURRICULUM_USAGE_LEDGER_INDEX_MIGRATION.read_text(encoding="utf-8")
    assert 'revision: str = "i0j1k2l3m4n5"' in source
    assert 'down_revision: Union[str, None] = "h9j0k1l2m3n4"' in source
    assert "CREATE INDEX IF NOT EXISTS ix_llm_usage_events_curriculum_job" in source
    assert "metadata_json ->> 'curriculum_job_id'" in source
    assert "metadata_json ? 'curriculum_job_id'" in source

    downgrade_source = source.split("def downgrade() -> None:", 1)[1]
    assert "drop_index" not in downgrade_source
    assert "DROP INDEX" not in downgrade_source

    index = next(
        candidate
        for candidate in LLMUsageEvent.__table__.indexes
        if candidate.name == "ix_llm_usage_events_curriculum_job"
    )
    assert str(next(iter(index.expressions))) == (
        "(metadata_json ->> 'curriculum_job_id')"
    )
    assert str(index.dialect_options["postgresql"]["where"]) == (
        "metadata_json ? 'curriculum_job_id'"
    )


def test_alembic_offline_sql_contains_curriculum_schema():
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head", "--sql"],
        cwd=".",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    sql = result.stdout
    assert "CREATE TABLE curriculum_generation_jobs" in sql
    assert "CREATE TABLE personalized_lesson_versions" in sql
    assert "CONSTRAINT fk_canonical_modules_current_published_version" in sql
    assert "CREATE TRIGGER trg_guard_canonical_module_version" in sql
    assert "ADD COLUMN IF NOT EXISTS retrieval_metadata_hash" in sql
    assert "curriculum_canonical_jsonb_for_migration" in sql
    assert "CREATE OR REPLACE FUNCTION guard_mentor_claim_skill_binding()" in sql
    assert "CREATE OR REPLACE FUNCTION guard_module_quality_report()" in sql
    assert "CREATE INDEX IF NOT EXISTS ix_plan_lesson_assignments_plan_item" in sql
    assert "ADD COLUMN artifact_epoch_at TIMESTAMP WITH TIME ZONE" in sql
    assert "ADD COLUMN supersedes_artifact BOOLEAN DEFAULT false NOT NULL" in sql
    assert sql.count("ADD COLUMN artifact_job_id UUID") == 2
    assert "UPDATE plan_item_detail_jobs AS detail_job" in sql
    assert "THEN clock_timestamp()" in sql
    assert (
        "ALTER TABLE plan_item_detail_jobs ALTER COLUMN artifact_epoch_at "
        "SET NOT NULL" in sql
    )
    assert (
        "ALTER TABLE plan_item_detail_jobs ALTER COLUMN artifact_epoch_at "
        "SET DEFAULT clock_timestamp()" in sql
    )
    assert "ix_plan_item_step_completions_artifact_unique" in sql
    assert "ix_plan_item_completions_artifact_unique" in sql
    assert "UPDATE curriculum_generation_jobs" in sql
    assert "SET budget_limit_usd = 0" in sql
    assert "CREATE UNIQUE INDEX uq_plan_lesson_assignments_plan_session" in sql
    assert "status NOT IN ('skipped', 'replaced')" in sql
    assert "ix_personalized_lessons_ready_mentor_evidence" in sql
    assert "jsonb_path_ops" in sql
    assert "CREATE FUNCTION guard_curriculum_lifecycle_audit()" in sql
    assert "h8i9j0k1l2m3" in sql
    assert "ck_learning_technique_versions_audit_shape" in sql
    assert "ck_canonical_module_versions_audit_shape" in sql
    assert "ck_mentor_evidence_claims_audit_shape" in sql
    assert "ck_personalized_lessons_audit_shape" in sql
    assert "cannot upgrade h8:" in sql
    assert "terminal plan lesson assignment status is immutable" in sql
    assert "UPDATE plan_item_completions AS item_completion" in sql
    assert "UPDATE plans AS plan" in sql
    assert "h9j0k1l2m3n4" in sql
    assert "cannot upgrade h9:" in sql
    assert "FROM plan_item_detail_jobs AS referenced_job" in sql
    assert "referenced_job.user_id = referenced_owner.user_id" in sql
    assert "i0j1k2l3m4n5" in sql
    assert "CREATE INDEX IF NOT EXISTS ix_llm_usage_events_curriculum_job" in sql


def test_alembic_offline_full_downgrade_compiles_and_cleans_base_types():
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "alembic",
            "downgrade",
            "i0j1k2l3m4n5:base",
            "--sql",
        ],
        cwd=".",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    sql = result.stdout
    assert (
        "ALTER TABLE intake_sessions DROP CONSTRAINT "
        "intake_sessions_learning_thread_id_fkey" in sql
    )
    assert (
        "ALTER TABLE intake_sessions DROP CONSTRAINT "
        "intake_sessions_interview_thread_id_fkey" in sql
    )
    for enum_name in (
        "date_precision",
        "date_precision_enum",
        "message_role",
        "plan_item_status",
        "plan_item_type",
        "user_achievement_category",
    ):
        assert f"DROP TYPE {enum_name}" in sql
