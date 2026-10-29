"""Exercise the actual recovery predicate on PostgreSQL JSON null semantics."""
from uuid import uuid4

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.content_resource import ContentResource, ContentResourceKind, LicenseStatus
from app.models.idol import CatalogStatus
from app.services.book_fidelity import FIDELITY_VERSION
from app.services.content_quality import BOOK_MODULE_QUALITY_GATE_VERSION
from app.tasks.catalog import _obsolete_book_quality_clause


def test_recovery_finds_legacy_fidelity_once_and_preserves_failed_attempt_limits():
    engine = create_engine(settings.database_url)
    quality = {'gate_version': BOOK_MODULE_QUALITY_GATE_VERSION, 'passed': True}
    valid_fidelity = {'version': FIDELITY_VERSION, 'passed': True, 'content_hash': 'a' * 64}
    cases = [
        ('legacy_published', CatalogStatus.PUBLISHED, quality, True),
        ('null_fidelity', CatalogStatus.PUBLISHED, {**quality, 'fidelity': None}, True),
        ('old_fidelity', CatalogStatus.PUBLISHED,
         {**quality, 'fidelity': {**valid_fidelity, 'version': FIDELITY_VERSION - 1}}, True),
        ('current', CatalogStatus.PUBLISHED, {**quality, 'fidelity': valid_fidelity}, False),
        ('quarantined', CatalogStatus.FLAGGED, quality, False),
        ('failed_review', CatalogStatus.FLAGGED,
         {**quality, 'fidelity': {**valid_fidelity, 'passed': False}}, False),
        ('obsolete_gate', CatalogStatus.FLAGGED,
         {'gate_version': BOOK_MODULE_QUALITY_GATE_VERSION - 1}, True),
    ]
    try:
        with engine.connect() as connection, connection.begin() as transaction:
            with Session(bind=connection) as db:
                rows = []
                for label, status, report, _ in cases:
                    row = ContentResource(
                        id=str(uuid4()), kind=ContentResourceKind.LLM_BOOK_SUMMARY,
                        canonical_key='book:recovery-test:' + str(uuid4()), title=label,
                        status=status, license_status=LicenseStatus.LLM_SUMMARY,
                        metadata_json={'quality_report': report}, is_public_domain=False,
                    )
                    db.add(row)
                    rows.append(row)
                db.flush()
                query = select(ContentResource.id).where(
                    ContentResource.id.in_([row.id for row in rows]),
                    _obsolete_book_quality_clause(),
                )
                selected = set(db.scalars(query))
                assert selected == {row.id for row, case in zip(rows, cases) if case[3]}
                # The existing sweep quarantines before enqueueing. A failed
                # current-version fidelity review must not reset retries forever.
                for row, case in zip(rows, cases):
                    if row.id in selected and case[0] != 'obsolete_gate':
                        row.status = CatalogStatus.FLAGGED
                db.flush()
                assert set(db.scalars(query)) == {rows[-1].id}
            transaction.rollback()
    finally:
        engine.dispose()
