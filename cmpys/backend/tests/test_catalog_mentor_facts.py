from copy import deepcopy
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock

import pytest

from app.services.comparison.mentor_facts import published_mentor_facts, catalog_mentor_facts


def mentor():
    source = NS(id="s1", idol_id="mentor", url="https://example.org/biography", title="Biography",
                full_text="In 1836, Dickens began publishing The Pickwick Papers.")
    event = NS(id="e1", age_at_event=24, confidence=.9, event_date=None, date_precision="year",
               canonical_title="Pickwick", canonical_description=source.full_text,
               evidence=[{"source_id": "s1", "source_url": source.url,
                          "snippet": "Dickens began publishing The Pickwick Papers."}])
    return NS(id="mentor", status="published", sources=[source], timeline_events=[event])


def test_returns_cited_age_appropriate_catalog_facts_without_inventing_score():
    result = published_mentor_facts(mentor(), 24)
    assert result["origin"] == "published_catalog" and result["through_age"] == 24
    assert result["facts"][0]["age"] == 24
    assert result["facts"][0]["evidence"][0]["source_url"] == "https://example.org/biography"
    assert "score" not in result
    assert published_mentor_facts(mentor(), 23) is None


@pytest.mark.parametrize("defect", ["draft", "age_missing", "low_confidence", "missing_source",
    "wrong_mentor", "wrong_url", "invented_snippet", "no_evidence"])
def test_unsupported_or_mismatched_evidence_never_enters_comparison(defect):
    m = deepcopy(mentor())
    e = m.timeline_events[0]
    if defect == "draft": m.status = "draft"
    elif defect == "age_missing": e.age_at_event = None
    elif defect == "low_confidence": e.confidence = .2
    elif defect == "missing_source": m.sources = []
    elif defect == "wrong_mentor": m.sources[0].idol_id = "someone_else"
    elif defect == "wrong_url": e.evidence[0]["source_url"] = "https://example.org/other"
    elif defect == "invented_snippet": e.evidence[0]["snippet"] = "Unsupported claim."
    else: e.evidence = []
    assert published_mentor_facts(m, 24) is None


@pytest.mark.asyncio
async def test_catalog_lookup_uses_selected_id_and_eager_loads_evidence():
    m = mentor()
    db = NS(execute=AsyncMock(return_value=NS(scalar_one_or_none=lambda: m)))
    result = await catalog_mentor_facts(db, idol_id=m.id, user_age=24)
    assert result["facts"]
    statement = db.execute.call_args.args[0]
    assert statement.compile().params == {"id_1": "mentor", "status_1": "published"}
    assert len(statement._with_options) == 2
