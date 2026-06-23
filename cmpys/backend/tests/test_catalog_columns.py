from app.models.idol import Idol, CatalogStatus
from app.models.content_resource import ContentResource


def test_idol_has_catalog_fields():
    idol = Idol(name="Test", domain="science")
    assert idol.status == CatalogStatus.PENDING
    assert "embedding" in Idol.__table__.columns
    assert "quality_score" in Idol.__table__.columns
    assert "published_at" in Idol.__table__.columns


def test_content_resource_has_catalog_fields():
    for col in ("status", "embedding", "is_public_domain", "source_provider",
                "source_external_id", "read_minutes"):
        assert col in ContentResource.__table__.columns
