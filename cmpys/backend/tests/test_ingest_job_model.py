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
