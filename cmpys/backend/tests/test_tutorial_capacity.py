import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import render_public_package_results, provenance
from app.services.planning.tutorial_capacity import (
    TutorialCapacityError, _render, _request, _sections, protected_tutorial_ids,
    reading_capacity_targets, shorten_tutorial_reading,
)
from app.tasks.plans import (_assemble_parallel_lesson_response, _prepare_current_detail_artifact_publication,
    _generate_plan_item_details_parallel, normalize_lesson_durations)
from tests.test_short_tutorial_pipeline import outline, short_package
from tests.test_tutorial_reading_budget import sections


def long_tutorial():
    base = sections()
    base["core_framework"] += "\n" + " substantive " * 180
    response = LLMResponse(data=render_public_package_results(base, short_package().writer_context()))
    _assemble_parallel_lesson_response(response, step=outline(1)["steps"][0],
        material_titles={"Resource 1"}, target_minutes=7)
    assert not response.error and response.data["reading_minutes"] == 4
    return response.data


def test_reserve_pending_tutorials_and_never_select_saved_work():
    steps = [{**long_tutorial(), "id": f"step_{i}"} for i in range(1, 19)]
    before = copy.deepcopy(steps)
    protected = {f"step_{i}" for i in range(1, 6)}
    assert reading_capacity_targets(steps, 2, protected) == []  # 126 ready minutes fit.
    targets = reading_capacity_targets(steps, 2, protected, pending_count=2)
    assert len(targets) == 4 and not set(targets) & protected
    assert steps == before
    with pytest.raises(ValueError, match="rescheduling"):
        reading_capacity_targets(steps, 2, {s["id"] for s in steps}, pending_count=2)


def test_reading_correction_is_bounded_and_never_pads_short_tutorials():
    steps = [{**long_tutorial(), "id": f"step_{i}"} for i in range(1, 21)]
    with pytest.raises(ValueError, match="rescheduling"):
        reading_capacity_targets(steps, 1, set())
    short = {**steps[0], "lesson_content": "word " * 550, "practice_minutes": 4}
    with pytest.raises(ValueError, match="rescheduling"):
        reading_capacity_targets([short] * 20, 2, set())
    assert reading_capacity_targets([short], 1, set()) == []


def test_only_prose_sections_can_be_assigned_for_capacity_correction():
    step = long_tutorial()
    source, targets, model, prompt = _request(step)
    assert targets and set(model.model_fields) == set(targets)
    assert {"guided_practice", "references", "substeps"}.isdisjoint(targets)
    assert _render(step["title"], source) == step["lesson_content"]
    assert "450-600" in prompt and "every case fact and numerical result" in prompt
    for name, target in targets.items():
        description = model.model_fields[name].description
        assert f"Aim for {target} words" in description
        assert "140-180" not in description and "120-160" not in description
    bad = {**step, "lesson_content": step["lesson_content"] + "\nUnexpected appendix"}
    # An unheaded appendix is part of references; a duplicate canonical heading
    # cannot be silently reinterpreted or shortened by splitting at the first.
    bad["lesson_content"] += "\n## Core Framework\nAnother mechanism."
    with pytest.raises(ValueError):
        _sections(bad)


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [None, "transport", "truncated", "unowned", "too_long", "visual", "semantic", "retimed", "out_of_range", "length_recovered", "title_echo", "changed_title"])
async def test_shortening_requires_complete_scoped_prose_and_independent_review(monkeypatch, failure):
    step = long_tutorial(); before = copy.deepcopy(step)
    package = short_package(); original_package = package.model_dump(mode="json")
    base = render_public_package_results(sections(), package.writer_context())
    requests = []
    client_options = []
    class Client:
        model = "offline"
        async def generate_json(self, **kwargs):
            requests.append(kwargs)
            if failure == "transport": return LLMResponse(data={}, error="Unavailable")
            data = {name: base[name] for name in kwargs["output_model"].model_fields}
            if failure in {"title_echo", "changed_title"}: data["title"] = step["title"] if failure == "title_echo" else "Changed title"
            elif failure == "unowned": data["guided_practice"] = "An unauthorized exercise rewrite"
            elif failure == "too_long" or (failure == "length_recovered" and len(requests) == 1): data = {name: _sections(step)[name] for name in data}
            elif failure == "visual": data["core_framework"] = "explanation " * 180
            return LLMResponse(data=data, finish_reason="length" if failure == "truncated" else "stop")
    review = AsyncMock(return_value=([
        "Missing reasoning"] if failure == "semantic" else [],
        LLMResponse(data={"practice_minutes": 5 if failure == "out_of_range" else 4 if failure == "retimed" else 3}), SimpleNamespace(model="review")))
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    def factory(**kwargs):
        client_options.append(kwargs)
        return Client()
    calls = []
    changed, error = await shorten_tutorial_reading(step, package, {"goal": "Explain motives"},
        client_factory=factory, call_records=calls)
    assert step == before and package.model_dump(mode="json") == original_package
    assert client_options == [{"tier": "balanced", "timeout": 60, "max_tokens": 2600,
                               "thinking_level": "medium", "allow_fallback": False}]
    assert len(requests) == (2 if failure in {"too_long", "length_recovered"} else 1)
    if failure and failure not in {"retimed", "length_recovered", "title_echo"}:
        assert changed is None and error
        assert review.await_count == (1 if failure in {"semantic", "out_of_range"} else 0)
    else:
        assert not error and changed["reading_minutes"] == 3 and changed["estimate_minutes"] == (7 if failure == "retimed" else 6)
        assert changed["practice_minutes"] == (4 if failure == "retimed" else step["practice_minutes"])
        assert changed["substeps"] == step["substeps"] and changed["resources"] == step["resources"]
        assert _sections(changed)["guided_practice"] == _sections(step)["guided_practice"]
        assert _sections(changed)["references"] == _sections(step)["references"]
        assert 450 <= len(changed["lesson_content"].split()) <= 600
        assert review.await_args.args[0] == changed and len(calls) == (3 if failure == "length_recovered" else 2)
        if failure == "length_recovered":
            assert "actual_whole_words" in requests[1]["user_prompt"] and calls[0][1].error
            assert "minimum_words_to_remove" in requests[1]["user_prompt"]
            assert "assigned_sections" not in requests[1]["user_prompt"]
            assert "target_section_words" in requests[1]["user_prompt"]
        assert review.await_args.kwargs["context"]["lesson_package"] == package.review_context()


@pytest.mark.asyncio
async def test_protection_includes_every_kind_of_saved_work_and_completed_tutorials():
    rows = [SimpleNamespace(step_id=name, answers_json=answers, attempts_json=attempts,
        hints_json=hints, state=state) for name, answers, attempts, hints, state in [
            ("answer", {"draft": "text"}, [], [], "ready"),
            ("attempt", {}, [{"reviewed": True}], [], "ready"),
            ("hint", {}, [], ["used"], "ready"),
            ("reviewing", {}, [], [], "reviewing"), ("untouched", {}, [], [], "ready")]]
    results = [SimpleNamespace(scalars=lambda: SimpleNamespace(all=lambda: rows)),
               SimpleNamespace(scalars=lambda: SimpleNamespace(all=lambda: ["completed"]))]
    db = SimpleNamespace(execute=AsyncMock(side_effect=results))
    protected = await protected_tutorial_ids(db, user_id="owner", item_id="mission", lock=True)
    assert protected == {"answer", "attempt", "hint", "reviewing", "completed"}
    query = db.execute.await_args_list[0].args[0]
    assert "FOR UPDATE" in str(query)
    assert query.get_execution_options()["populate_existing"] is True


@pytest.mark.asyncio
async def test_last_moment_saved_work_blocks_publication_before_progress_reset(monkeypatch):
    item = SimpleNamespace(details_json={"_generation": {"job_id": "job", "lesson_validation": {
        "step_1": {"content_hash": "old"}}}})
    lock = AsyncMock(return_value=(SimpleNamespace(), item, SimpleNamespace(id="job")))
    mutation = Mock(return_value=False)
    monkeypatch.setattr("app.tasks.plans._lock_current_detail_artifact_publication", lock)
    monkeypatch.setattr("app.tasks.plans._approved_readable_step_ids", lambda details: frozenset({"step_1"}))
    monkeypatch.setattr("app.tasks.plans._prepare_detail_artifact_publish", mutation)
    protected = AsyncMock(return_value={"step_1"})
    monkeypatch.setattr("app.services.planning.tutorial_capacity.protected_tutorial_ids", protected)
    with pytest.raises(TutorialCapacityError, match="Started tutorials"):
        await _prepare_current_detail_artifact_publication(SimpleNamespace(), plan_id="plan", item_id="item",
            user_id="owner", job_id="job", candidate_approved_step_ids=frozenset({"step_1"}),
            candidate_validations={"step_1": {"content_hash": "new"}})
    mutation.assert_not_called()
    assert protected.await_args.kwargs["lock"] is True


@pytest.mark.asyncio
@pytest.mark.parametrize('started_during_edit', [False, True])
@pytest.mark.parametrize('estimate_drift', [False, True])
async def test_generation_reconciles_before_publication_and_preserves_started_work(monkeypatch, started_during_edit, estimate_drift):
    scaffold = outline(20)
    steps = [{**long_tutorial(), 'id': s['id']} for s in scaffold['steps']]
    packages = {s['id']: short_package() for s in steps}
    validations = {s['id']: provenance(s, packages[s['id']]) for s in steps}
    saved = {**scaffold, 'steps': copy.deepcopy(steps), '_generation': {
        'outline': scaffold, 'outline_contract_version': 3, 'lesson_validation': copy.deepcopy(validations)}}
    protected = {s['id'] for s in steps[:5]}
    changed_ids = []
    async def shorten(step, package, context, *, client_factory, call_records):
        changed_ids.append(step['id'])
        if started_during_edit:
            protected.add(step['id'])
        prose = render_public_package_results(sections(), package.writer_context())
        candidate = {**step, 'lesson_content': _render(step['title'], prose), 'reading_minutes': 3,
                     'estimate_minutes': 6}
        if estimate_drift:
            minutes = 4 if len(changed_ids) == 1 else 2 if len(changed_ids) == 2 else 3
            candidate.update(practice_minutes=minutes, estimate_minutes=3 + minutes)
        call_records.append(('offline-capacity-call', LLMResponse(data={}), 'balanced', 'test', 'offline'))
        return candidate, None
    monkeypatch.setattr('app.services.planning.tutorial_capacity.shorten_tutorial_reading', shorten)
    checkpoints = []
    async def checkpoint(payload, stage):
        checkpoints.append(copy.deepcopy(payload))
        assert sum(s['estimate_minutes'] for s in payload['steps']) <= 132
    revisions = set()
    payload, calls, error = await _generate_plan_item_details_parallel(
        system_prompt='Teach', task_title='Sequence', mission_hours=2, user_goal='Reason',
        learning_preferences='examples', idol_name='Mentor', idol_domain='writing', idol_evidence={},
        session_context='', active_tier='balanced', routing_reason='test',
        client_factory=lambda **kwargs: pytest.fail('No new lesson generation expected'),
        on_checkpoint=checkpoint, prepared_packages=packages, validation_records=validations,
        existing_checkpoint=saved, capacity_protected_steps=AsyncMock(side_effect=lambda: set(protected)),
        capacity_revised_step_ids=revisions)
    assert payload['steps'][:5] == steps[:5]
    assert saved['steps'] == steps
    if started_during_edit:
        assert 'started during' in error and not checkpoints and not revisions
        assert payload['steps'] == steps and len(calls) == 1
    else:
        assert error is None and len(checkpoints) == 1 and len(calls) == 8
        assert len(revisions) == 8 and revisions == set(changed_ids) and not revisions & protected
        assert normalize_lesson_durations(copy.deepcopy(payload), mission_hours=2)['workload']['required_minutes'] == 132
        assert all(validations[s['id']] == provenance(s, packages[s['id']]) for s in payload['steps'])


@pytest.mark.asyncio
async def test_already_published_shortening_can_keep_newly_started_work(monkeypatch):
    item = SimpleNamespace(details_json={'_generation': {'job_id': 'job', 'lesson_validation': {
        'step_1': {'content_hash': 'same'}}}})
    monkeypatch.setattr('app.tasks.plans._lock_current_detail_artifact_publication',
        AsyncMock(return_value=(SimpleNamespace(), item, SimpleNamespace(id='job'))))
    monkeypatch.setattr('app.tasks.plans._approved_readable_step_ids', lambda details: frozenset({'step_1'}))
    mutation = Mock(return_value=False)
    monkeypatch.setattr('app.tasks.plans._prepare_detail_artifact_publish', mutation)
    protected = AsyncMock(return_value={'step_1'})
    monkeypatch.setattr('app.services.planning.tutorial_capacity.protected_tutorial_ids', protected)
    await _prepare_current_detail_artifact_publication(SimpleNamespace(), plan_id='plan', item_id='item',
        user_id='owner', job_id='job', candidate_approved_step_ids=frozenset({'step_1'}),
        candidate_validations={'step_1': {'content_hash': 'same'}}, capacity_revised_step_ids={'step_1'})
    mutation.assert_called_once()
    protected.assert_not_awaited()


def test_capacity_saves_the_same_minute_with_the_least_prose_change():
    # 18 ready at seven minutes plus two pending require four one-minute edits.
    steps = [{**long_tutorial(), 'id': f'step_{i}', 'lesson_content': 'word ' * words}
             for i, words in enumerate([780, 640, 625, 610, 650, 700] + [750] * 12, 1)]
    assert reading_capacity_targets(steps, 2, {'step_4'}, pending_count=2) == [
        'step_3', 'step_2', 'step_5', 'step_6']


@pytest.mark.asyncio
async def test_negative_revalidation_never_rewrites_started_tutorial(monkeypatch):
    scaffold = outline(1);step = long_tutorial();package = short_package()
    saved = {**scaffold, 'steps': [copy.deepcopy(step)], '_generation': {
        'outline': scaffold, 'outline_contract_version': 3, 'lesson_validation': {}}}
    monkeypatch.setattr('app.services.planning.lesson_review.review_lesson', AsyncMock(return_value=(
        ['A new reviewer requires attention'], LLMResponse(data={'practice_minutes': 3}), SimpleNamespace(model='offline'))))
    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt='Teach', task_title='Sequence', mission_hours=7/60, user_goal='Reason',
        learning_preferences='examples', idol_name='Mentor', idol_domain='writing', idol_evidence={},
        session_context='', active_tier='balanced', routing_reason='test',
        client_factory=lambda **kwargs: pytest.fail('Started tutorial must not reach a writer'),
        prepared_packages={'step_1': package}, validation_records={}, existing_checkpoint=saved,
        capacity_protected_steps=AsyncMock(return_value={'step_1'}))
    assert 'Started tutorial requires attention' in error and len(calls) == 1
    assert saved['steps'] == [step]


def test_four_minute_practice_is_preferred_without_manipulating_its_estimate():
    short = {**long_tutorial(), 'id': 'step_1', 'lesson_content': 'word ' * 610}
    longer = {**short, 'id': 'step_2', 'lesson_content': 'word ' * 650, 'practice_minutes': 4}
    # Capacity is 19 + five-minute tolerance; pending tutorials reserve ten.
    assert reading_capacity_targets([short, longer], 19/60, set(), pending_count=2)[0] == 'step_2'


@pytest.mark.asyncio
async def test_reviewed_partial_is_checkpointed_before_a_failed_capacity_edit(monkeypatch):
    scaffold = outline(20)
    steps = [{**long_tutorial(), 'id': f'step_{i}'} for i in range(1, 19)]
    packages = {s['id']: short_package() for s in steps}
    validations = {s['id']: provenance(s, packages[s['id']]) for s in steps}
    saved = {**scaffold, 'steps': steps + scaffold['steps'][18:], '_generation': {
        'outline': scaffold, 'outline_contract_version': 3, 'lesson_validation': copy.deepcopy(validations)}}
    events = []
    async def checkpoint(payload, stage):
        events.append(stage)
        assert sum(s['estimate_minutes'] for s in payload['steps'] if s.get('lesson_content')) == 126
        assert all(validations[s['id']] == provenance(s, packages[s['id']]) for s in payload['steps'] if s.get('lesson_content'))
    async def fail_edit(*args, **kwargs):
        assert events == ['capacity_pending']
        return None, 'Offline synthetic edit rejection'
    monkeypatch.setattr('app.services.planning.tutorial_capacity.shorten_tutorial_reading', fail_edit)
    _, calls, error = await _generate_plan_item_details_parallel(
        system_prompt='Teach', task_title='Sequence', mission_hours=2, user_goal='Reason',
        learning_preferences='examples', idol_name='Mentor', idol_domain='writing', idol_evidence={},
        session_context='', active_tier='balanced', routing_reason='test',
        client_factory=lambda **kwargs: pytest.fail('Reviewed tutorials must be reused'),
        on_checkpoint=checkpoint, prepared_packages=packages, validation_records=validations,
        existing_checkpoint=saved, capacity_protected_steps=AsyncMock(return_value={'step_1'}))
    assert 'Offline synthetic edit rejection' in error and not calls
    assert events == ['capacity_pending']


def test_capacity_request_leaves_eighty_words_of_counting_margin():
    step = long_tutorial()
    source, targets, _, _ = _request(step)
    retained = len(step["lesson_content"].split()) - sum(len(source[key].split()) for key in targets)
    assert retained + sum(targets.values()) == 520



def test_capacity_distributes_cuts_across_editable_prose_without_changing_practice():
    step = long_tutorial()
    body = _sections(step)
    for name in ("why_this_matters", "failure_modes", "check_your_understanding"):
        body[name] += " removable framing" * 15
    step = {**step, "lesson_content": _render(step["title"], body)}
    original = copy.deepcopy(step)
    source, targets, _, _ = _request(step)
    assert set(targets) == {"why_this_matters", "core_framework", "worked_example",
                            "failure_modes", "check_your_understanding"}
    from app.services.llm.schemas import TUTORIAL_SECTION_MIN_WORDS
    for name, target in targets.items():
        assert TUTORIAL_SECTION_MIN_WORDS[name] <= target < len(source[name].split())
    retained = len(step["lesson_content"].split()) - sum(len(source[k].split()) for k in targets)
    assert retained + sum(targets.values()) == 520
    assert _request(step)[1] == targets and step == original
