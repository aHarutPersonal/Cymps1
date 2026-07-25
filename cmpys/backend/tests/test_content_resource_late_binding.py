from types import SimpleNamespace

import pytest

from app.api.v1 import content_resources as api
from app.models.idol import CatalogStatus
from app.models.ingest_job import IngestState
from app.models.user import User
from app.schemas.content_resource import ContentResourceResolutionStatus


def test_resolve_route_precedes_dynamic_resource_route() -> None:
    paths = [getattr(route, "path", "") for route in api.router.routes]

    assert paths.index("/content-resources/resolve") < paths.index(
        "/content-resources/{resource_id}"
    )


@pytest.mark.asyncio
async def test_resolve_returns_ready_resource_reference() -> None:
    class Result:
        def scalar_one_or_none(self):
            return SimpleNamespace(
                id="resource-1",
                canonical_key="book:author:title",
                status=CatalogStatus.PUBLISHED,
                metadata_json={"quality_report": {"score": 0.94}},
            )

    class Database:
        async def execute(self, _statement):
            return Result()

    response = await api.resolve_content_resource(
        db=Database(),
        current_user=User(
            id="user-1", email="reader@example.com", password_hash="hash"
        ),
        canonicalKey="book:author:title",
    )

    assert response.id == "resource-1"
    assert response.status == ContentResourceResolutionStatus.READY
    assert response.qualityScore == 0.94


@pytest.mark.asyncio
async def test_resolve_reports_processing_without_exposing_partial_module() -> None:
    class Result:
        def __init__(self, value):
            self.value = value

        def scalar_one_or_none(self):
            return self.value

    class Database:
        def __init__(self):
            self.results = iter(
                [
                    None,
                    SimpleNamespace(
                        state=IngestState.RUNNING,
                        next_attempt_at=None,
                    ),
                ]
            )

        async def execute(self, _statement):
            return Result(next(self.results))

    response = await api.resolve_content_resource(
        db=Database(),
        current_user=User(
            id="user-1",
            email="reader@example.com",
            password_hash="hash",
        ),
        canonicalKey="book:author:title",
    )

    assert response.id is None
    assert response.status == ContentResourceResolutionStatus.PROCESSING


@pytest.mark.asyncio
async def test_resolve_reports_terminal_quality_failure() -> None:
    class Result:
        def __init__(self, value):
            self.value = value

        def scalar_one_or_none(self):
            return self.value

    resource = SimpleNamespace(
        status=CatalogStatus.FLAGGED,
        metadata_json={"quality_report": {"score": 0.52}},
    )

    class Database:
        def __init__(self):
            self.results = iter([resource, SimpleNamespace(state=IngestState.FLAGGED)])

        async def execute(self, _statement):
            return Result(next(self.results))

    response = await api.resolve_content_resource(
        db=Database(),
        current_user=User(
            id="user-1",
            email="reader@example.com",
            password_hash="hash",
        ),
        canonicalKey="book:author:title",
    )

    assert response.status == ContentResourceResolutionStatus.FAILED_QUALITY
    assert response.retryable is False
    assert response.qualityScore == 0.52
