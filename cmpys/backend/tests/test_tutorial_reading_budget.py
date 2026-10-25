from app.services.content_quality import lesson_sections_word_count
from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialLessonSectionsOutput
from app.services.planning.lesson_package import render_public_package_results
from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _prompt, _tokens, _validated_group
from app.tasks.plans import _assemble_plan_detail_lesson_content
from tests.test_tutorial_workload_profile import short_package
import pytest
from app.services.planning.lesson_writer import _tutorial_word_targets, _group_model, generate_lesson_sections


def sections():
    values = {"why_this_matters": 30, "core_framework": 140, "worked_example": 120,
              "failure_modes": 30, "guided_practice": 70, "check_your_understanding": 35,
              "references": 20}
    data = {key: "meaningful " * count for key, count in values.items()}
    data["core_framework"] += "\n```comparison\nBefore\n- Hidden motive\n- Unclear action\nvs\nAfter\n- Visible motive\n- Purposeful action\n```"
    data["guided_practice"] += " [[practice:guided.argument]] [[practice:transfer.argument]]"
    data["substeps"] = ["Use the supplied case to state your claim and save its supporting reason in the app."]
    return data


def validate(data, context):
    return _validated_group(LLMResponse(data=data), _TUTORIAL_GROUP,
        PlanTutorialLessonSectionsOutput, *_tokens(context), package_context=context,
        allotted_lesson_minutes=6, lesson_title="Read the motive")


def test_reading_budget_counts_exact_rendered_labels_and_canonical_headings():
    context = short_package().writer_context()
    data = sections()
    rendered = render_public_package_results(data, context)
    expected = _assemble_plan_detail_lesson_content(title="Read the motive",
        sections=PlanTutorialLessonSectionsOutput.model_validate(rendered))
    assert lesson_sections_word_count("Read the motive", rendered) == len(expected.split())
    assert validate(data, context)[0] is not None
    # The draft's own word count still fits, but expanded labels can make it too
    # long. Reject before checkpointing or final paid semantic review.
    for activity in context["practice"]["activities"]:
        activity["fields"][0]["label"] = "required response " * 40
    result, issues = validate(data, context)
    assert result is None
    assert any("Rendered reading" in issue and "450-600" in issue for issue in issues)


def test_writer_receives_allocation_specific_budget_without_changing_practice():
    context = short_package().writer_context()
    prompt = _prompt(_TUTORIAL_GROUP, "Teach motive", context, [], allotted_lesson_minutes=6)
    assert "EXACT READING BUDGET: 450-600" in prompt
    assert "expanded practice/result bindings" in prompt
    assert "550-650" not in prompt
    longer = _prompt(_TUTORIAL_GROUP, "Teach motive", context, [], allotted_lesson_minutes=8)
    assert "EXACT READING BUDGET: 601-800" in longer


@pytest.mark.asyncio
@pytest.mark.parametrize("correction", ["valid", "still_missing", "unknown", "unowned_section"])
async def test_missing_practice_links_use_one_scoped_correction_and_keep_other_sections(correction):
    import copy
    context = short_package().writer_context()
    original = sections()
    original["guided_practice"] = original["guided_practice"].replace(
        " [[practice:guided.argument]] [[practice:transfer.argument]]", "")
    before = copy.deepcopy(original)
    requests = []
    class Client:
        model = "offline"
        async def generate_json(self, **kwargs):
            requests.append(kwargs)
            if len(requests) == 1:
                return LLMResponse(data=original)
            value = {"guided_practice": sections()["guided_practice"]}
            if correction == "still_missing": value["guided_practice"] = original["guided_practice"]
            elif correction == "unknown": value["guided_practice"] += " [[practice:other.hidden]]"
            elif correction == "unowned_section": value["core_framework"] = "Unrelated rewrite"
            return LLMResponse(data=value)
    result, calls = await generate_lesson_sections(system_prompt="Teach", lesson_prompt="Motive",
        package_context=context, lesson_format="tutorial_v1", client_factory=lambda **kwargs: Client())
    assert len(requests) == len(calls) == 2
    assert requests[1]["output_model"].__name__ == "TutorialBindingCorrection"
    assert set(requests[1]["output_model"].model_fields) == {"guided_practice"}
    assert "display_token" in requests[0]["user_prompt"]
    assert "[[practice:guided.argument]]" in requests[1]["user_prompt"]
    assert original == before
    if correction == "valid":
        assert not result.error and result.semantic_accepted is None
        assert all(result.data[name] == value for name, value in before.items() if name != "guided_practice")
        assert result.data["guided_practice"] == sections()["guided_practice"]
    else:
        assert result.error and result.data == {}


def test_binding_correction_does_not_grant_unrelated_or_numeric_repair_authority():
    from app.services.planning.lesson_writer import _tutorial_binding_correction
    context = short_package().writer_context()
    missing = "guided_practice must include [[practice:guided.argument]]"
    assert _tutorial_binding_correction(sections(), [missing, "Unknown case/answer bindings"], context) is None
    assert _tutorial_binding_correction(sections(), [missing, "Missing native visual"], context) is None


def test_label_overhead_reduces_prose_targets_and_schema_guidance():
    context = short_package().writer_context()
    before, _ = _tutorial_word_targets(context, "Read the motive", 6)
    for activity in context["practice"]["activities"]:
        activity["fields"][0]["label"] = "required response " * 20
    targets, overhead = _tutorial_word_targets(context, "Read the motive", 6)
    assert sum(targets.values()) < sum(before.values())
    assert sum(targets.values()) + overhead == 510
    model = _group_model(_TUTORIAL_GROUP, targets)
    assert "140-180" not in model.model_fields["core_framework"].description
    assert f"Aim for {targets['core_framework']} draft words" in model.model_fields["core_framework"].description


def test_rendered_budget_does_not_impose_conflicting_raw_word_floor():
    context = short_package().writer_context()
    for activity in context["practice"]["activities"]:
        activity["fields"][0]["label"] = "required response " * 20
    data = sections()
    data["core_framework"] = "meaningful " * 100 + "\n" + data["core_framework"][data["core_framework"].index("```comparison"):]
    data["worked_example"] = "meaningful " * 90
    assert sum(len(v.split()) for k,v in data.items() if k != "substeps") < 430
    count = lesson_sections_word_count("Read the motive", render_public_package_results(data, context))
    assert 450 <= count <= 600
    assert validate(data, context)[0] is not None
    from app.services.planning.lesson_writer import validate_completed_sections
    assert validate_completed_sections(data, context, lesson_format="tutorial_v1",
        allotted_lesson_minutes=6, lesson_title="Read the motive") == data


@pytest.mark.asyncio
async def test_length_retry_edits_prior_draft_and_retains_two_call_bound():
    context = short_package().writer_context()
    overlong = sections()
    overlong["core_framework"] += "\n" + " redundant " * 180
    prompts = []
    class Client:
        model = "test"
        async def generate_json(self, *, user_prompt, **kwargs):
            prompts.append(user_prompt)
            return LLMResponse(data=overlong if len(prompts)==1 else {
                key: sections()[key] for key in kwargs['output_model'].model_fields})
    result, calls = await generate_lesson_sections(system_prompt="Teach", lesson_prompt="Motive",
        package_context=context, lesson_format="tutorial_v1", allotted_lesson_minutes=6,
        lesson_title="Read the motive", client_factory=lambda **kwargs: Client())
    assert not result.error and len(calls) == 2
    assert "Shorten ONLY the assigned prose sections" in prompts[1]
    assert "redundant" in prompts[1]
    assert "Do not shorten a valid section" not in prompts[1]
    assert result.data['guided_practice'] == overlong['guided_practice']
    assert result.data['worked_example'] == overlong['worked_example']


@pytest.mark.asyncio
async def test_only_excessive_prose_gets_one_final_bounded_edit():
    context = short_package().writer_context()
    overlong = sections()
    overlong['core_framework'] += '\n' + ' redundant ' * 200
    seen = []
    class Client:
        model = 'test'
        async def generate_json(self, *, output_model, **kwargs):
            seen.append(output_model.__name__)
            data = sections() if len(seen) == 3 else overlong
            return LLMResponse(data={key:data[key] for key in output_model.model_fields})
    result, calls = await generate_lesson_sections(system_prompt='Teach', lesson_prompt='Motive',
        package_context=context, lesson_format='tutorial_v1', allotted_lesson_minutes=6,
        lesson_title='Read the motive', client_factory=lambda **kwargs: Client())
    assert not result.error and len(calls) == 3
    assert seen[1:] == ['TutorialProseCompression', 'TutorialProseCompression']


@pytest.mark.asyncio
async def test_nonlength_tutorial_failure_never_uses_extra_edit():
    context = short_package().writer_context()
    invalid = sections()
    invalid['core_framework'] = 'meaningful ' * 140  # missing the required visual
    count = 0
    class Client:
        model = 'test'
        async def generate_json(self, **kwargs):
            nonlocal count
            count += 1
            return LLMResponse(data=invalid)
    result, calls = await generate_lesson_sections(system_prompt='Teach', lesson_prompt='Motive',
        package_context=context, lesson_format='tutorial_v1', allotted_lesson_minutes=6,
        lesson_title='Read the motive', client_factory=lambda **kwargs: Client())
    assert result.error and count == len(calls) == 2


def test_inline_native_fence_is_repaired_only_by_boundary_whitespace():
    context = short_package().writer_context()
    data = sections()
    data['core_framework'] = data['core_framework'].replace('\n```comparison', ' ```comparison')
    before = data['core_framework']
    result, issues = validate(data, context)
    assert not issues and result is not None
    assert result['core_framework'].split() == before.split()
    assert '\n\n```comparison\n' in result['core_framework']
    assert data['core_framework'] == before


def test_whitespace_normalization_does_not_accept_invalid_visual_body():
    context = short_package().writer_context()
    data = sections()
    data['core_framework'] = data['core_framework'].replace('\n```comparison', ' ```comparison').replace('\nvs\n', '\nambiguous separator\n')
    result, issues = validate(data, context)
    assert result is None and any('native comparison' in issue for issue in issues)


@pytest.mark.asyncio
@pytest.mark.parametrize("near_miss", [True, False])
async def test_final_length_edit_is_bounded_to_sixty_words_of_overflow(near_miss):
    context = short_package().writer_context()
    valid = sections()
    overlong = sections()
    count = lesson_sections_word_count("Read the motive", render_public_package_results(valid, context))
    overlong["core_framework"] += "\n" + "surplus " * ((625 if near_miss else 700) - count)
    seen = []
    class Client:
        model = "test"
        async def generate_json(self, *, output_model, **kwargs):
            seen.append(output_model.__name__)
            data = valid if len(seen) == 4 else overlong
            return LLMResponse(data={key: data[key] for key in output_model.model_fields})
    result, calls = await generate_lesson_sections(system_prompt="Teach", lesson_prompt="Motive",
        package_context=context, lesson_format="tutorial_v1", allotted_lesson_minutes=6,
        lesson_title="Read the motive", client_factory=lambda **kwargs: Client())
    assert len(calls) == (4 if near_miss else 3)
    assert bool(result.error) is not near_miss
