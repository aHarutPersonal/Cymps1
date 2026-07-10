from app.models.ingest_job import IngestJob, IngestKind, IngestState


def test_ingest_job_defaults_and_fields():
    job = IngestJob(
        kind=IngestKind.IDOL,
        source="wikidata",
        external_id="Q12345",
        priority=10,
    )
    assert job.state == IngestState.QUEUED
    assert job.attempts == 0
    assert job.kind.value == "idol"
    assert job.source == "wikidata"
    assert job.external_id == "Q12345"
    assert job.payload_json is None
    for column in (
        "next_attempt_at",
        "locked_at",
        "last_started_at",
        "completed_at",
    ):
        assert column in IngestJob.__table__.columns


def test_ingest_job_uses_migration_enum_names():
    assert IngestJob.__table__.c.kind.type.name == "ingest_kind"
    assert IngestJob.__table__.c.state.type.name == "ingest_state"
