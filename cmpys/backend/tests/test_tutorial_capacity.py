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
@pytest.mark.parametrize("failure", [None, "transport", "truncated", "unowned", "too_long", "visual", "semantic", "retimed", "out_of_range", "length_recovered", "section_regressed", "undersized_both", "title_echo", "changed_title"])
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
            elif failure == "too_long" or (failure in {"length_recovered", "section_regressed"} and len(requests) == 1): data = {name: _sections(step)[name] for name in data}
            elif failure == "visual": data["core_framework"] = "explanation " * 180
            if failure == "undersized_both" or (failure == "section_regressed" and len(requests) == 2):
                data["why_this_matters"] = "Too short."
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
                               "thinking_level": "low", "allow_fallback": False}]
    assert len(requests) == (2 if failure in {"too_long", "length_recovered", "section_regressed", "undersized_both"} else 1)
    if failure and failure not in {"retimed", "length_recovered", "section_regressed", "title_echo"}:
        assert changed is None and error
        assert review.await_count == (1 if failure in {"semantic", "out_of_range"} else 0)
    else:
        assert not error and changed["reading_minutes"] == 3 and changed["estimate_minutes"] == (7 if failure == "retimed" else 6)
        assert changed["practice_minutes"] == (4 if failure == "retimed" else step["practice_minutes"])
        assert changed["substeps"] == step["substeps"] and changed["resources"] == step["resources"]
        assert _sections(changed).get("guided_practice") == _sections(step).get("guided_practice")
        assert _sections(changed)["references"] == _sections(step)["references"]
        assert 450 <= len(changed["lesson_content"].split()) <= 600
        assert review.await_args.args[0] == changed and len(calls) == (3 if failure in {"length_recovered", "section_regressed"} else 2)
        if failure == "section_regressed":
            assert _sections(changed)["why_this_matters"] == _sections(step)["why_this_matters"]
        if failure in {"length_recovered", "section_regressed"}:
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
    revisions = set()
    payload, calls, error = await _generate_plan_item_details_parallel(
        system_prompt='Teach', task_title='Sequence', mission_hours=2, user_goal='Reason',
        learning_preferences='examples', idol_name='Mentor', idol_domain='writing', idol_evidence={},
        session_context='', active_tier='balanced', routing_reason='test',
        client_factory=lambda **kwargs: pytest.fail('No new lesson generation expected'),
        on_checkpoint=checkpoint, prepared_packages=packages, validation_records=validations,
        existing_checkpoint=saved, capacity_protected_steps=AsyncMock(side_effect=lambda: set(protected)),
        capacity_revised_step_ids=revisions)
    # One-ahead: capacity is corrected only on the tutorial being written.
    # Already-ready tutorials are never rewritten, so a reused over-capacity
    # artifact is passed to publication unchanged (whose mission-capacity guard
    # rejects it) instead of being silently shortened.
    assert not changed_ids and not revisions and not calls
    assert payload['steps'] == steps and saved['steps'] == steps
    assert error is None and len(checkpoints) == 1
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
        pytest.fail('One-ahead never rewrites an already-ready tutorial')
    monkeypatch.setattr('app.services.planning.tutorial_capacity.shorten_tutorial_reading', fail_edit)
    payload, calls, error = await _generate_plan_item_details_parallel(
        system_prompt='Teach', task_title='Sequence', mission_hours=2, user_goal='Reason',
        learning_preferences='examples', idol_name='Mentor', idol_domain='writing', idol_evidence={},
        session_context='', active_tier='balanced', routing_reason='test',
        client_factory=lambda **kwargs: pytest.fail('Reviewed tutorials must be reused'),
        on_checkpoint=checkpoint, prepared_packages=packages, validation_records=validations,
        existing_checkpoint=saved, capacity_protected_steps=AsyncMock(return_value={'step_1'}))
    # The reused reviewed partial is published as-is; the learner's window
    # (T1, T2) is ready, so the job parks without any edit or new tutorial.
    assert error is None and not calls
    assert payload.pop('_tutorial_waiting_for_learner') is True
    assert events == ['outline_ready']


def test_capacity_request_leaves_one_hundred_words_of_counting_margin():
    step = long_tutorial()
    source, targets, _, _ = _request(step)
    retained = len(step["lesson_content"].split()) - sum(len(source[key].split()) for key in targets)
    assert retained + sum(targets.values()) == 500



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
    assert retained + sum(targets.values()) == 500
    assert _request(step)[1] == targets and step == original



def test_capacity_keeps_reviewed_visual_bytes_before_counting_or_review():
    from app.services.planning.tutorial_capacity import _retain_native_visuals
    visual = "```comparison\nTold motive\n- Names fear\n- Explains a reason\nvs\nShown motive\n- Hands hide paper\n- Eyes follow the door\n```"
    original = "Long original explanation.\n\n" + visual
    rewritten = "Shorter explanation.\n\n" + visual.replace("Hands hide paper", "Hands hide paper; eyes watch")
    assert _retain_native_visuals(original, rewritten) == "Shorter explanation.\n\n" + visual
    for invalid in ["Missing visual", rewritten + "\n" + visual, rewritten.replace("```comparison", "```diagram")]:
        with pytest.raises(ValueError, match="retain every native visual"):
            _retain_native_visuals(original, invalid)



@pytest.mark.asyncio
@pytest.mark.parametrize("recovers", [True, False])
async def test_one_extra_correction_only_for_valid_near_limit_drafts(monkeypatch, recovers):
    step = long_tutorial(); original = copy.deepcopy(step); package = short_package()
    base = render_public_package_results(sections(), package.writer_context())
    source = _sections(step); requests = []
    class Client:
        model = "offline"
        async def generate_json(self, **kwargs):
            requests.append(kwargs)
            data = {name: base[name].strip() for name in kwargs["output_model"].model_fields}
            if len(requests) < 3 or not recovers:
                whole = _render(step["title"], {**source, **data})
                data["core_framework"] += "\n\n" + "substantive " * (610 - len(whole.split()))
            return LLMResponse(data=data, finish_reason="stop")
    review = AsyncMock(return_value=([], LLMResponse(data={"practice_minutes": 3}), SimpleNamespace(model="review")))
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    records = []
    result, error = await shorten_tutorial_reading(step, package, {}, client_factory=lambda **kw: Client(), call_records=records)
    assert len(requests) == 3 and step == original
    assert review.await_count == int(recovers)
    if recovers:
        assert result and not error and 450 <= len(result["lesson_content"].split()) <= 600
    else:
        assert result is None and error


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [None, "still_rejected", "unowned", "private", "unavailable", "unchanged", "extra", "too_long", "undersized", "truncated"])
async def test_capacity_editorial_repair_is_scoped_changed_and_reviewed_once(monkeypatch, failure):
    step = long_tutorial(); original = copy.deepcopy(step); package = short_package()
    base = render_public_package_results(sections(), package.writer_context())
    requests = []
    class Client:
        model = "offline"
        async def generate_json(self, **kwargs):
            requests.append(kwargs)
            data = {name: base[name].strip() for name in kwargs["output_model"].model_fields}
            if len(requests) == 2:
                if failure != "unchanged":
                    data["failure_modes"] = ("Explain the general mistake without repeating the independent case. "
                        "Check observable evidence, remove the unwanted label, and let the learner apply the method.")
                if failure == "extra": data["guided_practice"] = "Unauthorized change"
                if failure == "too_long": data["failure_modes"] += " substantive" * 400
                if failure == "undersized": data["failure_modes"] = "Too short."
            return LLMResponse(data=data, finish_reason="length" if failure == "truncated" and len(requests) == 2 else "stop")
    rejection = (["Leaked transfer answer"], LLMResponse(data={
        "acceptable": False, "issues": ["Leaked transfer answer"],
        "package_issues": ["Private answer is wrong"] if failure == "private" else [],
        "affected_sections": ["guided_practice"] if failure == "unowned" else ["failure_modes"],
        "practice_minutes": 3}, error="Review unavailable" if failure == "unavailable" else None), SimpleNamespace(model="review"))
    acceptance = ([], LLMResponse(data={"practice_minutes": 3}), SimpleNamespace(model="review"))
    review = AsyncMock(side_effect=[rejection, rejection if failure == "still_rejected" else acceptance])
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    records = []
    result, error = await shorten_tutorial_reading(step, package, {}, client_factory=lambda **kw: Client(), call_records=records)
    assert step == original
    eligible = failure not in {"unowned", "private", "unavailable"}
    assert len(requests) == 1 + int(eligible)
    if eligible:
        assert set(requests[1]["output_model"].model_fields) == {"failure_modes"}
        assert "private_workbook" not in requests[1]["user_prompt"]
    assert review.await_count == (2 if failure in {None, "still_rejected"} else 1)
    if failure is None:
        assert result and not error and result["substeps"] == original["substeps"]
        before, after = _sections(original), _sections(result)
        assert before.get("guided_practice") == after.get("guided_practice")
        assert before["references"] == after["references"]
        assert 450 <= len(result["lesson_content"].split()) <= 600
    else:
        assert result is None and error


# ---------------------------------------------------------------------------
# Published legacy tutorials (with Guided Practice) keep their reviewed shape
# ---------------------------------------------------------------------------

LEGACY_STEPS_FENCE = ("```steps\ntitle: Invented block\nOne | | A step the lesson never had.\n"
                      "Two | | Another step the lesson never had.\n```")
LEGACY_CHECK_FENCE = "```check\nQ: Invented?\n- [ ] No\n- [x] Yes\nWhy: Added by the model.\n```"


def legacy_long_tutorial():
    from tests.test_tutorial_reading_budget import legacy_sections
    base = legacy_sections()
    base["core_framework"] += "\n" + " substantive " * 180
    response = LLMResponse(data=render_public_package_results(base, short_package().writer_context()))
    _assemble_parallel_lesson_response(response, step=outline(1)["steps"][0],
        material_titles={"Resource 1"}, target_minutes=7)
    assert not response.error and response.data["reading_minutes"] == 4
    assert "## Guided Practice" in response.data["lesson_content"]
    return response.data


def test_legacy_capacity_request_never_asks_for_new_blocks():
    legacy_source, legacy_targets, legacy_model, _ = _request(legacy_long_tutorial())
    assert "guided_practice" in legacy_source and "guided_practice" not in legacy_targets
    new_targets, new_model = _request(long_tutorial())[1:3]
    for name in ("worked_example", "check_your_understanding"):
        assert name in legacy_targets and name in new_targets
        legacy_description = legacy_model.model_fields[name].description
        assert "steps fence" not in legacy_description and "check fence" not in legacy_description
    assert "steps fence" in new_model.model_fields["worked_example"].description
    assert "check fence" in new_model.model_fields["check_your_understanding"].description


@pytest.mark.asyncio
async def test_legacy_tutorial_shortening_succeeds_when_the_model_follows_its_descriptions(monkeypatch):
    """A literal model adds whatever block a description asks for; legacy text never asks."""
    from tests.test_tutorial_reading_budget import legacy_sections
    step = legacy_long_tutorial(); before = copy.deepcopy(step); package = short_package()
    base = render_public_package_results(legacy_sections(), package.writer_context())
    descriptions = []

    class Client:
        model = "offline"
        async def generate_json(self, **kwargs):
            data = {}
            for name, field in kwargs["output_model"].model_fields.items():
                descriptions.append(field.description)
                data[name] = base[name].strip()
                if "steps fence" in field.description:
                    data[name] += "\n\n" + LEGACY_STEPS_FENCE
                if "check fence" in field.description:
                    data[name] += "\n\n" + LEGACY_CHECK_FENCE
            return LLMResponse(data=data, finish_reason="stop")

    review = AsyncMock(return_value=([], LLMResponse(data={"practice_minutes": 3}), SimpleNamespace(model="review")))
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    changed, error = await shorten_tutorial_reading(step, package, {"goal": "Explain motives"},
        client_factory=lambda **kwargs: Client(), call_records=[])
    assert error is None and changed is not None
    assert step == before and descriptions
    assert "## Guided Practice" in changed["lesson_content"]
    assert "```steps" not in changed["lesson_content"] and "```check" not in changed["lesson_content"]
    assert _sections(changed)["guided_practice"] == _sections(step)["guided_practice"]
    assert _sections(changed)["references"] == _sections(step)["references"]
    assert 450 <= len(changed["lesson_content"].split()) <= 600
    assert changed["reading_minutes"] == 3 and review.await_count == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("legacy", [True, False])
async def test_capacity_review_describes_guided_practice_replacement_only_for_new_lessons(legacy):
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review
    step = legacy_long_tutorial() if legacy else long_tutorial()
    response = SimpleNamespace(error=None, data=_review(practice_minutes=3))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    await review_lesson(step, client_factory=lambda **kwargs: client,
                        context={"lesson_format": "tutorial_v1", "lesson_package": short_package().review_context()})
    system_prompt = client.generate_json.call_args.kwargs["system_prompt"]
    assert "This is tutorial_v1" in system_prompt
    assert ("replace the former Guided Practice section" in system_prompt) is not legacy
