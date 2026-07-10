from unittest.mock import AsyncMock

import pytest
from fastapi import Response, status

from app.core import health as health_module


@pytest.mark.asyncio
async def test_ready_returns_200_only_when_database_and_redis_are_ready(monkeypatch):
    monkeypatch.setattr(health_module, "_database_ready", AsyncMock(return_value=True))
    monkeypatch.setattr(health_module, "_redis_ready", AsyncMock(return_value=True))
    response = Response()

    result = await health_module.ready(response)

    assert response.status_code == status.HTTP_200_OK
    assert result == {
        "status": "ready",
        "checks": {"database": True, "redis": True},
    }


@pytest.mark.asyncio
async def test_ready_returns_503_when_dependency_is_unavailable(monkeypatch):
    monkeypatch.setattr(health_module, "_database_ready", AsyncMock(return_value=True))
    monkeypatch.setattr(health_module, "_redis_ready", AsyncMock(return_value=False))
    response = Response()

    result = await health_module.ready(response)

    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert result["status"] == "not_ready"
    assert result["checks"]["redis"] is False
