"""Real local SQL coverage for bounded library reads and lean job polling.

SQLite executes the ORM queries in memory; JSONB uses SQLite's JSON storage.
No application database, network, or provider is used.
"""
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import DateTime, Integer, String, create_engine, event, func, inspect, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column

from app.api.v1.content_resources import list_library_resources
from app.api.v1.jobs import get_job_status
from app.api.v1.sessions import _build_refreshed_session_response
from app.models.content_resource import ContentResource, ContentResourceKind, LicenseStatus, UserContentProgress, UserContentSave
from app.models.idol import CatalogStatus
from app.models.plan import Plan, PlanItem, PlanItemContentResource
from app.models.plan_job import PlanGenerationJob
from app.models.item_detail_job import PlanItemDetailJob
from app.services.book_fidelity import FIDELITY_VERSION
from app.services.content_resources import BOOK_MODULE_QUALITY_GATE_VERSION, MIN_BOOK_MODULE_WORDS


@compiles(JSONB, "sqlite")
def _sqlite_json_storage(element, compiler, **kwargs):
    return "JSON"


class LocalDatabase:
    """Expose the handler's async execute API over an in-memory SQL session."""
    def __init__(self, session):
        self.session = session
        self.statements = []

    async def execute(self, statement):
        self.statements.append(statement)
        return self.session.execute(statement)


def make_library_database():
    engine = create_engine("sqlite:///:memory:")
    for model in (ContentResource, UserContentSave, UserContentProgress, Plan, PlanItem, PlanItemContentResource):
        model.__table__.create(engine)
    return engine


def resource(title, *, kind=ContentResourceKind.ARTICLE, duration=10, **overrides):
    return ContentResource(
        id=str(uuid4()), canonical_key="test:" + title, title=title,
        author_or_creator="Author " + title, kind=kind,
        license_status=LicenseStatus.EXTERNAL_LINK, duration_minutes=duration,
        status=CatalogStatus.PUBLISHED, content_markdown="large unchanged reader content " * 50,
        metadata_json={"quality_report": {
            "passed": True, "gate_version": BOOK_MODULE_QUALITY_GATE_VERSION,
            "metrics": {"word_count": MIN_BOOK_MODULE_WORDS},
            "fidelity": {"passed": True, "version": FIDELITY_VERSION},
        }}, **overrides)


def seed_library(session, shared_count=2):
    owner, other = str(uuid4()), str(uuid4())
    ours = resource("A saved")
    theirs = resource("B other private")
    linked = resource("C linked", kind=ContentResourceKind.VIDEO, duration=4)
    other_linked = resource("D other linked")
    pending = resource("E pending")
    pending.status = CatalogStatus.PENDING
    private_progress = resource("F progress alone")
    shared = [resource(f"Shared {i:05}", kind=(ContentResourceKind.PUBLIC_DOMAIN_BOOK if i % 2 == 0 else ContentResourceKind.LLM_BOOK_SUMMARY), duration=20 + i) for i in range(shared_count)]
    hidden = [resource(f"Hidden {i}", kind=ContentResourceKind.LLM_BOOK_SUMMARY) for i in range(4)]
    hidden[0].metadata_json["quality_report"]["passed"] = False
    hidden[1].metadata_json["quality_report"]["gate_version"] = BOOK_MODULE_QUALITY_GATE_VERSION - 1
    hidden[2].metadata_json["quality_report"]["fidelity"]["passed"] = False
    hidden[3].metadata_json["quality_report"]["metrics"]["word_count"] = MIN_BOOK_MODULE_WORDS - 1
    session.add_all([ours, theirs, linked, other_linked, pending, private_progress, *shared, *hidden])
    plans = [Plan(id=str(uuid4()), user_id=user, target_age=30) for user in (owner, other)]
    session.add_all(plans)
    items = [PlanItem(id=str(uuid4()), plan_id=plan.id, title="Item", description="Details", success_metric="Done") for plan in plans]
    session.add_all(items)
    session.flush()
    session.add_all([
        UserContentSave(user_id=owner, content_resource_id=ours.id),
        UserContentSave(user_id=other, content_resource_id=theirs.id),
        UserContentSave(user_id=owner, content_resource_id=pending.id),
        UserContentSave(user_id=owner, content_resource_id=shared[0].id),
        UserContentSave(user_id=other, content_resource_id=shared[1].id),
        UserContentProgress(user_id=owner, content_resource_id=shared[0].id, progress_percent=35, cursor_json={"chapter": "ours"}),
        UserContentProgress(user_id=other, content_resource_id=shared[0].id, progress_percent=89, cursor_json={"chapter": "theirs"}),
        UserContentProgress(user_id=owner, content_resource_id=private_progress.id, progress_percent=10),
        PlanItemContentResource(plan_item_id=items[0].id, content_resource_id=linked.id),
        PlanItemContentResource(plan_item_id=items[1].id, content_resource_id=other_linked.id),
        # The same resource is shared, saved and linked twice; it still has one row.
        PlanItemContentResource(plan_item_id=items[0].id, content_resource_id=shared[0].id, material_index=1),
        PlanItemContentResource(plan_item_id=items[0].id, content_resource_id=shared[0].id, material_index=2),
    ])
    session.commit()
    return SimpleNamespace(owner=owner, other=other, ours=ours, theirs=theirs, linked=linked,
                           other_linked=other_linked, pending=pending, shared=shared,
                           hidden=hidden, private_progress=private_progress)


async def library(db, user, **kwargs):
    return await list_library_resources(db, SimpleNamespace(id=user),
        **{"kind": None, "q": None, "sort": "title", "limit": 50, "offset": 0, **kwargs})


@pytest.fixture
def shelf():
    engine = make_library_database()
    with Session(engine, expire_on_commit=False) as session:
        seed = seed_library(session)
        session.expunge_all()
        yield LocalDatabase(session), seed
    engine.dispose()


@pytest.mark.asyncio
async def test_library_uses_two_queries_without_leaking_another_users_private_state(shelf):
    db, seed = shelf
    result = await library(db, seed.owner)
    assert result.total == 4
    assert {row.id for row in result.resources} == {seed.ours.id, seed.linked.id, *[row.id for row in seed.shared]}
    assert len(db.statements) == 2
    state = {row.id: row for row in result.resources}
    assert state[seed.shared[0].id].isSaved is True
    assert state[seed.shared[0].id].progressPercent == 35
    assert state[seed.shared[0].id].cursorJson == {"chapter": "ours"}
    assert state[seed.shared[1].id].isSaved is False
    assert state[seed.shared[1].id].progressPercent == 0
    assert all(row.contentMarkdown is None for row in result.resources)
    columns = str(db.statements[1].compile()).split(" FROM ")[0]
    assert "content_resources.content_markdown" not in columns
    assert "content_resources.embedding" not in columns
    # Reusing the session for a second user does not reuse membership or joins.
    db.statements.clear()
    other = await library(db, seed.other)
    assert {row.id for row in other.resources} == {seed.theirs.id, seed.other_linked.id, *[row.id for row in seed.shared]}
    assert next(row for row in other.resources if row.id == seed.shared[0].id).progressPercent == 89
    assert len(db.statements) == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("kwargs,expected", [
    ({"kind": "video"}, ["C linked"]),
    ({"q": "AUTHOR a SAVED"}, ["A saved"]),
    ({"sort": "duration"}, ["C linked", "A saved", "Shared 00000", "Shared 00001"]),
    ({"sort": "duration_desc"}, ["Shared 00001", "Shared 00000", "A saved", "C linked"]),
    ({"offset": 1, "limit": 2}, ["C linked", "Shared 00000"]),
    ({"offset": 500}, []),
    ({"q": "missing"}, []),
])
async def test_library_filters_sort_and_pagination_keep_exact_membership(shelf, kwargs, expected):
    db, seed = shelf
    result = await library(db, seed.owner, **kwargs)
    assert [row.title for row in result.resources] == expected
    assert result.total == (1 if "kind" in kwargs or kwargs.get("q") == "AUTHOR a SAVED" else 0 if "q" in kwargs else 4)
    assert len(db.statements) == 2


@pytest.mark.asyncio
async def test_invalid_library_kind_fails_without_database_work(shelf):
    db, seed = shelf
    with pytest.raises(HTTPException) as exc:
        await library(db, seed.owner, kind="invalid")
    assert exc.value.status_code == 400
    assert db.statements == []


@pytest.mark.asyncio
async def test_empty_library_uses_constant_queries():
    engine = make_library_database()
    with Session(engine) as session:
        db = LocalDatabase(session)
        result = await library(db, str(uuid4()))
        assert result.total == 0 and result.resources == []
        assert len(db.statements) == 2
    engine.dispose()


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["plan", "plan_detail"])
async def test_job_poll_excludes_large_private_and_unneeded_columns(kind):
    if kind == "plan":
        job = PlanGenerationJob(id="job", user_id="user", idol_id=None, target_age=30,
            status="running", step="queued", progress_percent=0, duration_weeks=12,
            weekly_hours=5, thinking_text="Preparing", focus="private" * 100000,
            generation_checkpoint_json={"large": "private" * 100000})
    else:
        plan = Plan(id="plan", user_id="user", target_age=30, roadmap_json={"large": "private" * 100000})
        plan.idol = None
        item = PlanItem(id="item", plan_id="plan", title="Read", description="Read", success_metric="Done",
            details_json={"large": "private" * 100000}, meta_json={"large": "private" * 100000})
        item.plan = plan
        job = PlanItemDetailJob(id="job", user_id="user", plan_item_id="item", status="running",
            step="queued", progress_percent=0, thinking_text="Preparing", result_json={"ready_step_count": 1})
        job.plan_item = item
    class Database:
        async def execute(self, statement):
            self.statement = statement
            return SimpleNamespace(scalar_one_or_none=lambda: job)
    db = Database()
    response = await get_job_status("job", db, SimpleNamespace(id="user"), job_type=kind)
    assert response.status == "running" and response.thinkingText.message == "Preparing"
    sql = str(db.statement)
    for name in ("generation_checkpoint_json", "private_checkpoint_json", "details_json", "meta_json", "roadmap_json"):
        assert name not in sql
    if kind == "plan":
        assert "plan_generation_jobs.focus" not in sql
    else:
        assert response.results == {"ready_step_count": 1}
    assert "user" in db.statement.compile().params.values()


@pytest.mark.asyncio
async def test_clean_session_response_skips_refresh_but_expired_timestamp_refreshes():
    class ProbeBase(DeclarativeBase):
        pass
    class Probe(ProbeBase):
        __tablename__ = "timestamp_probe"
        id: Mapped[int] = mapped_column(Integer, primary_key=True)
        comparison_scores_status: Mapped[str] = mapped_column(String)
        updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())
    engine = create_engine("sqlite:///:memory:")
    ProbeBase.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as session:
        row = Probe(id=1, comparison_scores_status="queued")
        session.add(row); session.commit()
        row.idol = row.phase = row.user_goal = row.comparison_output = row.blueprint_output = None
        row.comparison_scores_json = row.interview_thread_id = row.created_at = None
        row.user_age = 24; row.user_financial_status = ""; row.user_interests = []; row.interview_turn_count = 0
        class Database:
            refreshes = 0
            async def flush(self):
                session.flush()
            async def refresh(self, entity, **kwargs):
                self.refreshes += 1
                session.refresh(entity, **kwargs)
        db = Database()
        response = await _build_refreshed_session_response(row, db)
        assert response["updated_at"] and db.refreshes == 0
        row.comparison_scores_status = "ready"
        response = await _build_refreshed_session_response(row, db)
        assert response["comparisonScoresStatus"] == "ready" and db.refreshes == 1
        assert "updated_at" not in inspect(row).unloaded
        repeat = await _build_refreshed_session_response(row, db)
        assert repeat == response and db.refreshes == 1
    engine.dispose()


@pytest.mark.asyncio
async def test_library_keeps_the_existing_single_plan_selection(shelf):
    db, seed = shelf
    extra_plan = Plan(id=str(uuid4()), user_id=seed.owner, target_age=30)
    extra_item = PlanItem(id=str(uuid4()), plan_id=extra_plan.id, title="Later item", description="Details", success_metric="Done")
    extra_resource = resource("Later plan private")
    db.session.add_all([extra_plan, extra_item, extra_resource]); db.session.flush()
    db.session.add(PlanItemContentResource(plan_item_id=extra_item.id, content_resource_id=extra_resource.id))
    db.session.commit()
    chosen = db.session.execute(select(Plan.id).where(Plan.user_id == seed.owner).limit(1)).scalar_one()
    response = await library(db, seed.owner)
    linked_ids = {seed.linked.id, extra_resource.id} & {row.id for row in response.resources}
    assert linked_ids == {extra_resource.id if chosen == extra_plan.id else seed.linked.id}
    assert len(db.statements) == 2


@pytest.mark.asyncio
async def test_detail_job_poll_executes_one_query_and_never_loads_the_whole_plan():
    from app.models.idol import Idol
    engine = create_engine("sqlite:///:memory:")
    for model in (Idol, Plan, PlanItem, PlanItemDetailJob):
        model.__table__.create(engine)
    owner = str(uuid4())
    with Session(engine, expire_on_commit=False) as session:
        idol = Idol(id=str(uuid4()), name="Mentor", domain="Science")
        plan = Plan(id=str(uuid4()), user_id=owner, target_age=30, idol_id=idol.id, roadmap_json={"secret": "large" * 20000})
        item = PlanItem(id=str(uuid4()), plan_id=plan.id, title="Learn", description="Details", success_metric="Done",
            details_json={"private": "large" * 20000}, meta_json={"large": "large" * 20000})
        job = PlanItemDetailJob(id=str(uuid4()), user_id=owner, plan_item_id=item.id,
            artifact_epoch_at=datetime.now(timezone.utc), status="running", step="queued",
            thinking_text="Preparing", result_json={"ready_step_count": 1})
        session.add_all([idol, plan, item, job]); session.commit()
        job_id = job.id
        session.expunge_all()
        emitted, loaded = [], []
        event.listen(session, "loaded_as_persistent", lambda session, instance: loaded.append(instance))
        event.listen(engine, "before_cursor_execute", lambda connection, cursor, statement, parameters, context, many: emitted.append(statement))
        db = LocalDatabase(session)
        response = await get_job_status(job_id, db, SimpleNamespace(id=owner), job_type="plan_detail")
        assert response.idolName == "Mentor" and response.results == {"ready_step_count": 1}
        assert len(emitted) == 1  # No default select-in of every Plan.items/User.
        loaded_job = next(row for row in loaded if isinstance(row, PlanItemDetailJob))
        assert "details_json" in inspect(loaded_job.plan_item).unloaded
        assert "roadmap_json" in inspect(loaded_job.plan_item.plan).unloaded
        with pytest.raises(HTTPException) as raised:
            await get_job_status(job_id, db, SimpleNamespace(id=str(uuid4())), job_type="plan_detail")
        assert raised.value.status_code == 404
    engine.dispose()
