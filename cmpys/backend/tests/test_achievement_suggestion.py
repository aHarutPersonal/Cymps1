"""Achievement suggestion falls back to success_metric + mapped category."""
from types import SimpleNamespace

from app.services.achievements.suggestion import fallback_suggestion, category_for_item
from app.models.plan import PlanItemType


def _item(success_metric, type_, domain=None):
    return SimpleNamespace(
        success_metric=success_metric, type=type_, title="t", description="d",
        meta_json={"domain": domain} if domain else None,
    )


def test_fallback_uses_success_metric_as_title():
    item = _item("Wrote a 2-page company teardown", PlanItemType.READING)
    out = fallback_suggestion(item)
    assert out["title"] == "Wrote a 2-page company teardown"
    assert out["category"] == "learning"


def test_category_mapping_for_each_type():
    assert category_for_item(_item("x", PlanItemType.READING)) == "learning"
    assert category_for_item(_item("x", PlanItemType.COURSE)) == "learning"
    assert category_for_item(_item("x", PlanItemType.PROJECT)) == "career"


def test_fallback_handles_empty_success_metric():
    item = _item("", PlanItemType.PROJECT)
    out = fallback_suggestion(item)
    assert out["title"]  # non-empty
    assert out["category"] == "career"
