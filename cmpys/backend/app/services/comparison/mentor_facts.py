"""Reuse published, source-backed mentor milestones before optional research."""
import re
from urllib.parse import urlsplit

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.models.idol import Idol


def _text(value):
    return re.sub(r"\s+", " ", value or "").strip()


def published_mentor_facts(idol, user_age):
    """Only same-mentor, age-bounded evidence still present in its source."""
    if not idol or getattr(idol, "status", None) != "published":
        return None
    if type(user_age) is not int or user_age < 0:
        return None
    sources = {str(source.id): source for source in idol.sources}
    facts = []
    for event in sorted(idol.timeline_events, key=lambda e: (
        e.age_at_event if e.age_at_event is not None else -1, str(e.id))):
        age = event.age_at_event
        if type(age) is not int or not 0 <= age <= user_age or (event.confidence or 0) < 0.55:
            continue
        citations = []
        for item in event.evidence if isinstance(event.evidence, list) else []:
            if not isinstance(item, dict):
                continue
            source = sources.get(str(item.get("source_id")))
            snippet = _text(item.get("snippet"))
            if (not source or str(source.idol_id) != str(idol.id)
                    or item.get("source_url") != source.url or not snippet
                    or snippet not in _text(source.full_text)):
                continue
            parsed = urlsplit(source.url)
            if parsed.scheme not in {"http", "https"} or not parsed.hostname:
                continue
            citations.append({"source_url": source.url, "title": source.title, "snippet": snippet})
        if citations and event.canonical_description:
            facts.append({"title": event.canonical_title, "description": event.canonical_description,
                          "age": age, "date": str(event.event_date) if event.event_date else None,
                          "date_precision": getattr(event.date_precision, "value", event.date_precision),
                          "evidence": citations})
    return {"origin": "published_catalog", "idol_id": str(idol.id), "through_age": user_age,
            "facts": facts} if facts else None


async def catalog_mentor_facts(db, *, idol_id, user_age):
    if not idol_id or type(user_age) is not int:
        return None
    idol = (await db.execute(select(Idol).where(Idol.id == idol_id, Idol.status == "published")
        .options(selectinload(Idol.timeline_events), selectinload(Idol.sources)))).scalar_one_or_none()
    return published_mentor_facts(idol, user_age)
