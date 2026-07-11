import pytest

from app.api.v1 import sessions as sessions_api
from app.models.idol import Idol
from app.models.idol_external_id import IdolExternalId
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.models.intake import IntakeSession, SessionPhase
from app.models.user import User


def test_current_session_route_is_registered_before_dynamic_session_route():
    paths = [
        getattr(route, "path", "")
        for route in sessions_api.router.routes
        if "GET" in getattr(route, "methods", set())
    ]

    assert paths.index("/sessions/current") < paths.index("/sessions/{session_id}")


def test_session_response_does_not_lazy_load_unloaded_idol_profile():
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.INTERVIEW,
        user_age=25,
        user_financial_status="student",
        user_interests=["Science"],
        interview_thread_id="thread-1",
    )
    session.idol = Idol(id="idol-1", name="Bill Gates", domain="technology")

    response = sessions_api._build_session_response(session)

    assert response["selected_idol"] == {
        "id": "idol-1",
        "name": "Bill Gates",
        "era": None,
    }


def test_session_response_normalizes_profile_era_tags_to_one_string():
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.COMPLETED,
        user_age=24,
        user_financial_status="employed",
        user_interests=["Technology"],
    )
    idol = Idol(id="idol-1", name="Elon Musk", domain="technology")
    idol.profile = IdolProfile(
        idol_id=idol.id,
        display_name=idol.name,
        nationality=[],
        domains=["technology"],
        primary_roles=["entrepreneur"],
        era_tags=["modern_era"],
        notable_themes=[],
        confidence=0.9,
        evidence=[],
    )
    session.idol = idol

    response = sessions_api._build_session_response(session)

    assert response["selected_idol"]["era"] == "modern_era"


@pytest.mark.asyncio
async def test_suggest_idols_returns_fallback_suggestions_when_llm_fails(monkeypatch):
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.IDOL_SELECTION,
        user_age=24,
        user_financial_status="student",
        user_interests=["Technology", "Business", "Science"],
    )
    user = User(id="user-1", email="coder@example.com", password_hash="hash")

    async def fake_get_session(session_id, user_id, db):
        return session

    async def failing_generate(*args, **kwargs):
        raise RuntimeError("Gemini unavailable")

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions_api, "generate_with_grounding", failing_generate)

    response = await sessions_api.suggest_idols(
        session_id=session.id,
        db=None,
        current_user=user,
    )

    assert len(response.suggestions) == 3
    assert response.suggestions[0].name
    assert all(s.relevance_summary for s in response.suggestions)


@pytest.mark.asyncio
async def test_suggest_idols_prefers_age_grounded_published_catalog(monkeypatch):
    session = IntakeSession(
        id="session-catalog",
        user_id="user-1",
        phase=SessionPhase.IDOL_SELECTION,
        user_age=30,
        user_financial_status="employed",
        user_interests=["technology", "science", "business"],
        user_goal="build a technology company",
    )
    user = User(id="user-1", email="catalog@example.com", password_hash="hash")

    def make_idol(index: int, name: str, domain: str) -> Idol:
        idol = Idol(
            id=f"00000000-0000-0000-0000-00000000000{index}",
            name=name,
            domain=domain,
            status="published",
            quality_score=0.9,
        )
        idol.profile = IdolProfile(
            idol_id=idol.id,
            display_name=name,
            domains=[domain],
            primary_roles=[],
            era_tags=[],
            notable_themes=[],
            nationality=[],
            confidence=0.9,
            evidence=[],
        )
        idol.timeline_events = [
            IdolTimelineEvent(
                idol_id=idol.id,
                canonical_title=f"Milestone {index}",
                canonical_description=f"{name} completed a documented {domain} milestone.",
                age_at_event=28,
                category=domain,
                importance_score=0.9,
                confidence=0.9,
                evidence=[],
            )
        ]
        idol.external_ids = [
            IdolExternalId(
                idol_id=idol.id,
                provider="wikidata",
                external_id=f"Q{index}",
            )
        ]
        idol.tag_links = []
        return idol

    idols = [
        make_idol(1, "Technology Mentor", "technology"),
        make_idol(2, "Science Mentor", "science"),
        make_idol(3, "Business Mentor", "business"),
    ]

    async def fake_get_session(session_id, user_id, db):
        return session

    class _Scalars:
        def unique(self):
            return self

        def all(self):
            return idols

    class _Result:
        def scalars(self):
            return _Scalars()

    class _Db:
        committed = False

        async def execute(self, stmt):
            return _Result()

        async def commit(self):
            self.committed = True

    async def should_not_call_llm(*args, **kwargs):
        raise AssertionError("published catalog should satisfy this request")

    db = _Db()
    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions_api, "generate_with_grounding", should_not_call_llm)

    response = await sessions_api.suggest_idols(
        session_id=session.id,
        db=db,
        current_user=user,
    )

    assert [item.name for item in response.suggestions] == [
        "Technology Mentor",
        "Science Mentor",
        "Business Mentor",
    ]
    assert all("By age 28" in item.relevance_summary for item in response.suggestions)
    assert db.committed is True
    assert len(session.idol_suggestions_json) == 3

@pytest.mark.asyncio
async def test_select_idol_returns_response_without_expiring_session_scalars(monkeypatch):
    """Regression: relationship-only refresh expired updated_at and caused MissingGreenlet."""
    from datetime import datetime, timezone

    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.IDOL_SELECTION,
        user_age=25,
        user_financial_status="student",
        user_interests=["Science"],
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        updated_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    user = User(id="user-1", email="coder@example.com", password_hash="hash")

    async def fake_get_session(session_id, user_id, db):
        return session

    class _EmptyScalars:
        def all(self):
            return []

    class _EmptyResult:
        def scalar_one_or_none(self):
            return None

        def scalars(self):
            return _EmptyScalars()

    class _Db:
        async def execute(self, stmt):
            return _EmptyResult()

        def add(self, item):
            pass

        async def flush(self):
            pass

        async def commit(self):
            pass

        async def refresh(self, item, attrs=None):
            raise AssertionError("select_idol should not refresh only a relationship after commit")

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)

    response = await sessions_api.select_idol(
        session_id=session.id,
        data=sessions_api.SelectIdolRequest(idol_name="Isaac Newton"),
        db=_Db(),
        current_user=user,
    )

    assert response["phase"] == "interview"
    assert response["selected_idol"]["name"] == "Isaac Newton"
    assert response["interview_thread_id"]
