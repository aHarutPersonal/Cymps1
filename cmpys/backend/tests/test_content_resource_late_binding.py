from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.api.v1 import content_resources as api
from app.models.user import User


def test_resolve_route_precedes_dynamic_resource_route() -> None:
    paths = [getattr(route, "path", "") for route in api.router.routes]

    assert paths.index("/content-resources/resolve") < paths.index(
        "/content-resources/{resource_id}"
    )


@pytest.mark.asyncio
async def test_resolve_returns_ready_resource_reference() -> None:
    class Result:
        def one_or_none(self):
            return SimpleNamespace(
                id="resource-1",
                canonical_key="book:author:title",
            )

    class Database:
        async def execute(self, _statement):
            return Result()

    response = await api.resolve_content_resource(
        db=Database(),
        current_user=User(id="user-1", email="reader@example.com", password_hash="hash"),
        canonicalKey="book:author:title",
    )

    assert response.id == "resource-1"


@pytest.mark.asyncio
async def test_resolve_reports_not_ready_without_exposing_partial_module() -> None:
    class Result:
        def one_or_none(self):
            return None

    class Database:
        async def execute(self, _statement):
            return Result()

    with pytest.raises(HTTPException) as exc:
        await api.resolve_content_resource(
            db=Database(),
            current_user=User(
                id="user-1",
                email="reader@example.com",
                password_hash="hash",
            ),
            canonicalKey="book:author:title",
        )

    assert exc.value.status_code == 404
