from sqlalchemy import select
from app.models.idol import Idol, CatalogStatus
from app.api.v1.idols import _published_only


def test_published_filter_adds_status_clause():
    compiled = str(_published_only(select(Idol)).compile())
    assert "status" in compiled
