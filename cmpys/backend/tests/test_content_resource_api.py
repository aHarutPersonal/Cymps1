from unittest.mock import AsyncMock, MagicMock

import pytest

from app.api.v1.content_resources import delete_content_highlight


class ScalarResult:
    def __init__(self, value=None):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


@pytest.mark.asyncio
async def test_delete_content_highlight_removes_only_current_users_resource_note():
    db = AsyncMock()
    db.get.return_value = MagicMock(id="resource-1")
    highlight = MagicMock(id="highlight-1", user_id="user-1", content_resource_id="resource-1")
    db.execute.return_value = ScalarResult(highlight)
    current_user = MagicMock(id="user-1")

    await delete_content_highlight(
        resource_id="resource-1",
        highlight_id="highlight-1",
        db=db,
        current_user=current_user,
    )

    resource_lookup = str(db.execute.await_args_list[0].args[0])
    assert "content_resources.status" in resource_lookup
    db.delete.assert_awaited_once_with(highlight)
