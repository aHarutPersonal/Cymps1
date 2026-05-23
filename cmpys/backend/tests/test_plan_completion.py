import pytest
from unittest.mock import AsyncMock, MagicMock
from datetime import datetime

from app.models.plan import PlanItem, PlanItemCompletion
from app.api.v1.plans import _compute_item_progress, _parse_item_details

class ResultMock:
    def __init__(self, scalar_val=None, scalars_list=None):
        self._scalar = scalar_val
        self._scalars = scalars_list or []

    def scalar(self):
        return self._scalar

    def scalar_one_or_none(self):
        return self._scalar
        
    def scalars(self):
        m = MagicMock()
        m.all.return_value = self._scalars
        return m

@pytest.mark.asyncio
class TestPlanCompletionLogic:

    async def test_compute_progress_no_steps_not_completed(self):
        """Test progress for item with no steps and not completed."""
        db = AsyncMock()
        
        # Mock completed steps count -> 0
        db.execute.return_value = ResultMock(scalar_val=0)
        
        # Second execute call for item_completion -> None
        db.execute.side_effect = [
            ResultMock(scalar_val=0), # count
            ResultMock(scalar_val=None) # item_completion
        ]
        
        item = PlanItem(id="1", details_json={})
        
        progress, is_completed = await _compute_item_progress(db, "user1", item)
        
        assert progress.total_steps == 0
        assert progress.completed_steps == 0
        assert progress.percent == 0.0
        assert is_completed is False

    async def test_compute_progress_no_steps_completed(self):
        """Test progress for item with no steps but marked completed."""
        db = AsyncMock()
        
        # Mock completed steps count -> 0
        # Mock item_completion -> present
        db.execute.side_effect = [
            ResultMock(scalar_val=0), # count
            ResultMock(scalar_val=PlanItemCompletion(completed_at=datetime.now())) # item_completion
        ]
        
        item = PlanItem(id="1", details_json={})
        
        progress, is_completed = await _compute_item_progress(db, "user1", item)
        
        assert progress.total_steps == 0
        # When manually completed without steps, progress is 100%
        assert progress.percent == 100.0
        assert is_completed is True

    async def test_compute_progress_with_steps_partial(self):
        """Test progress for item with steps partially completed."""
        db = AsyncMock()
        
        details = {
            "steps": [
                {"id": "s1", "title": "Step 1"},
                {"id": "s2", "title": "Step 2"},
                {"id": "s3", "title": "Step 3"},
                {"id": "s4", "title": "Step 4"},
            ]
        }
        item = PlanItem(id="1", details_json=details)
        
        # Mock completed steps count -> 1
        # Mock item_completion -> None
        db.execute.side_effect = [
            ResultMock(scalar_val=1), # count (1 step done)
            ResultMock(scalar_val=None) # item_completion
        ]
        
        progress, is_completed = await _compute_item_progress(db, "user1", item)
        
        assert progress.total_steps == 4
        assert progress.completed_steps == 1
        assert progress.percent == 25.0
        assert is_completed is False

    async def test_compute_progress_with_steps_full(self):
        """Test progress for item with all steps completed."""
        db = AsyncMock()
        
        details = {
            "steps": [
                {"id": "s1", "title": "Step 1"},
                {"id": "s2", "title": "Step 2"}
            ]
        }
        item = PlanItem(id="1", details_json=details)
        
        # Mock completed steps count -> 2
        # Mock item_completion -> None (calculated purely from steps here)
        db.execute.side_effect = [
            ResultMock(scalar_val=2), # count (2 steps done)
            ResultMock(scalar_val=None) # item_completion
        ]
        
        progress, is_completed = await _compute_item_progress(db, "user1", item)
        
        assert progress.total_steps == 2
        assert progress.completed_steps == 2
        assert progress.percent == 100.0
        # Note: In the actual function logic:
        # if total_steps > 0: percent = (completed/total)*100
        # It does NOT auto-set is_completed=True in the return value tuple unless found in DB
        # But `toggle_step_complete` handles the DB update. 
        # `_compute_item_progress` just reports the state.
        assert is_completed is False 

    async def test_parse_item_details(self):
        """Test parsing of details JSON into schema."""
        details_json = {
            "steps": [
                {"id": "1", "title": "S1", "description": "D1", "estimate_minutes": 10}
            ],
            "materials": [
                {
                    "title": "M1",
                    "url": "http://x.com",
                    "type": "article",
                    "content_resource_id": "resource-1",
                    "canonical_key": "article:m1",
                    "author_or_creator": "Creator",
                    "thumbnail_url": "http://x.com/thumb.jpg",
                    "license_status": "external_link",
                    "search_query": "M1 creator",
                }
            ]
        }
        
        parsed = _parse_item_details(details_json)
        
        assert len(parsed.steps) == 1
        assert parsed.steps[0].title == "S1"
        assert parsed.steps[0].description == "D1"
        assert parsed.steps[0].estimate_minutes == 10
        
        assert len(parsed.materials) == 1
        assert parsed.materials[0].title == "M1"
        assert parsed.materials[0].type == "article"
        assert parsed.materials[0].content_resource_id == "resource-1"
        assert parsed.materials[0].canonical_key == "article:m1"
        assert parsed.materials[0].author_or_creator == "Creator"
        assert parsed.materials[0].thumbnail_url == "http://x.com/thumb.jpg"
        assert parsed.materials[0].license_status == "external_link"
        assert parsed.materials[0].search_query == "M1 creator"

    async def test_parse_item_details_empty(self):
        """Test parsing of empty details."""
        parsed = _parse_item_details(None)
        assert parsed is None
        
        parsed = _parse_item_details({})
        assert parsed is None
