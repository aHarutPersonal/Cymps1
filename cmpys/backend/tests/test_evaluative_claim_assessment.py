"""The recorded garden exercise confused lacking a measure with asserting nothing."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import SEMANTIC_TOKENS
from app.services.planning.package_preflight import (
    PackageSemanticReview, _SEMANTIC_PROMPT, _text_audit_issues, review_package,
)


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'evaluative_claim_misclassification.json').read_text())
TARGET = 'practice.independent_transfer'
VALID_ALTERNATIVE = (
    'The compost comparison is the strongest empirically testable claim: depot totals '
    'showing no increase would refute it. "The community garden matters to our street" '
    'asserts importance, so it is an evaluative claim, not a topic phrase. Its missing '
    'measure limits testability without erasing the assertion.'
)


def checked_verdict():
    value = copy.deepcopy(RECORDED['recorded_verdict'])
    # Keep the independently valid first activity's complete alternative concise.
    value['text_audits'][0]['alternative_response'] = (
        '"The town swimming pool", "Pool maintenance costs..." and "Local families..." '
        'name subjects only. "Free morning sessions raised..." asserts increased attendance; '
        'unchanged attendance would defeat it. "Free morning sessions cost..." asserts '
        'cafe sales recover costs; revenue below those costs would defeat that claim.'
    )
    transfer = value['text_audits'][1]
    transfer['alternative_response'] = VALID_ALTERNATIVE
    transfer['criteria'][2].update(task_aligned=False, accepts_alternative=False,
        reason='Importance is an evaluative assertion; missing measurement does not erase it.')
    transfer.update(model_answer_valid=False,
        model_answer_reason='It falsely labels a value assertion a topic and imposes impossible alternatives.',
        requires_activity_repair=True)
    return value


def test_exact_recorded_task_rubric_and_solution_require_the_false_classification():
    package = LessonPackage.model_validate(RECORDED['package'])
    transfer = package.workbook.activities[1]
    assert 'why the other candidate is a topic' in transfer.instructions
    assert "is a topic because no stated finding or measure" in transfer.fields[0].criteria[2]
    solution = transfer.worked_solution
    assert isinstance(solution, str)
    assert 'topic dressed as a sentence' in solution
    assert 'shows why the compost sentence fails that test' in solution
    verdict = PackageSemanticReview.model_validate(checked_verdict())
    issues = _text_audit_issues(package, verdict.text_audits)
    assert [issue.target for issue in issues] == [TARGET]
    assert VALID_ALTERNATIVE in issues[0].description


def test_review_and_generation_separate_assertion_from_testability():
    for rule in ('Distinguish assertion from empirical testability', 'evaluative claim',
                 'normative claim', 'lack of a measurable test is not absence of an assertion',
                 'keep a uniquely correct choice and challenge a false secondary premise',
                 'impossible condition for accepting them'):
        assert rule in _SEMANTIC_PROMPT
    for name in ('tutorial_package_seed.txt', 'tutorial_activity_generate.txt'):
        prompt = load_and_render(name, {})
        assert 'factual, evaluative and normative assertions remain claims' in prompt
        assert 'even if accepted or untestable' in prompt
        assert 'Empirical testability and contestability are separate properties' in prompt
    for name in ('lesson_package_seed.txt', 'lesson_activity_generate.txt', 'lesson_package_generate.txt'):
        assert 'without an impossible\nrequirement to disprove another valid option' in load_and_render(name, {})


@pytest.mark.asyncio
async def test_exact_package_cannot_pass_when_its_audit_admits_correct_secondary_classification(monkeypatch):
    package = LessonPackage.model_validate(RECORDED['package'])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=checked_verdict())))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client)
    assert failures and not response.error and not response.semantic_accepted
    assert response.effective_parameters['validated_repair_targets'] == [TARGET]
    assert response.effective_parameters['requested_output_tokens'] == SEMANTIC_TOKENS
    assert client.generate_json.await_count == 1



# Exact v33 failure: the review rejects a false topic key but suggests a false
# exception which the private repair copies into one criterion only.
INVALID_PERMISSION = json.loads((Path(__file__).parent / 'fixtures' / 'invalid_permitted_alternative.json').read_text())
PERMISSION_TARGET = 'practice.guided_practice.labels'


def _corrected_permission_patch():
    patch = copy.deepcopy(INVALID_PERMISSION['recorded_repair'])
    patch['field_patches'][0]['criteria'][0] = 'Labels A as a topic and B, C, and D as claims'
    patch['solution_step_patches'][0]['explanation'] = (
        'A names the reading room without asserting a proposition. B asserts a policy, '
        'C asserts a fact, and D asserts value through "matters to families". '
        'A is the only topic; accepted facts, captions and value assertions remain claims.'
    )
    return patch


def test_exact_repair_copied_a_semantically_false_reviewer_permission():
    from app.services.planning.lesson_package import PrivatePackageRepair, apply_private_package_repair

    original = LessonPackage.model_validate(INVALID_PERMISSION['original_package'])
    suggestion = INVALID_PERMISSION['initial_verdict']['issues'][0]['description']
    assert 'accepting a reasoned alternative for D only if it argues no position is taken' in suggestion
    recorded = apply_private_package_repair(original,
        PrivatePackageRepair.model_validate(INVALID_PERMISSION['recorded_repair']),
        repair_targets=[PERMISSION_TARGET])
    criteria = recorded.workbook.activities[0].fields[0].criteria
    assert 'alternative for D' in criteria[0]
    assert "D's" in criteria[2] and '"matters to families" is a disputable value position' in criteria[2]
    # Its final audit tries to satisfy the false exception rather than remove it.
    alternative = INVALID_PERMISSION['final_verdict']['text_audits'][0]['alternative_response']
    assert 'topic' in alternative and 'caption' in alternative


def test_server_does_not_certify_a_reviewers_proposed_alternative_as_domain_truth():
    package = LessonPackage.model_validate(INVALID_PERMISSION['repaired_package'])
    from app.services.planning.package_preflight import TextFieldAudit
    audit = TextFieldAudit.model_validate(INVALID_PERMISSION['final_verdict']['text_audits'][0])
    issues = _text_audit_issues(package, [audit], required_targets={PERMISSION_TARGET})
    issue = next(issue for issue in issues if issue.target == PERMISSION_TARGET)
    assert 'Reviewer-proposed alternative:' in issue.description
    assert 'Independently validate' in issue.description
    assert 'remove false permissions' in issue.description
    assert ' Valid alternative:' not in issue.description
    assert audit.alternative_response in issue.description


@pytest.mark.asyncio
@pytest.mark.parametrize('public_correction', [False, True])
async def test_private_and_scoped_repairs_independently_check_the_same_reviewer_suggestion(monkeypatch, public_correction):
    from app.services.planning.lesson_package import (
        ASSESSMENT_ALTERNATIVE_VALIDITY_RULE, PrivatePackageRepair,
        apply_private_package_repair, generate_package,
    )
    from tests.section_client_fixture import activity_draft_fixture

    original = LessonPackage.model_validate(INVALID_PERMISSION['original_package'])
    before = original.model_dump(mode='json')
    corrected = _corrected_permission_patch()
    replies = [LLMResponse(data=corrected)]
    if public_correction:
        corrected_package = apply_private_package_repair(original,
            PrivatePackageRepair.model_validate(corrected), repair_targets=[PERMISSION_TARGET])
        replies = [LLMResponse(data={'public_defects': ['The independently rejected field needs a complete owned correction.']}),
            LLMResponse(data=activity_draft_fixture(corrected_package.workbook.activities[0].model_dump(mode='json')))]
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=replies))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    result, response, _ = await generate_package({'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client, prior_package=original,
        defects=[INVALID_PERMISSION['initial_verdict']['issues'][0]['description']],
        repair_targets=[PERMISSION_TARGET])
    assert result is not None and not response.error
    assert client.generate_json.await_count == (2 if public_correction else 1)
    for request in client.generate_json.await_args_list:
        assert ASSESSMENT_ALTERNATIVE_VALIDITY_RULE in request.kwargs['system_prompt']
        assert 'alternative for D' in request.kwargs['user_prompt']
    assert result.workbook.activities[0].fields[0].criteria[0] == 'Labels A as a topic and B, C, and D as claims'
    assert result.workbook.activities[1] == original.workbook.activities[1]
    assert original.model_dump(mode='json') == before
    assert response.semantic_accepted is None  # Correction still requires fresh preflight.


def test_shared_validity_rule_reaches_preflight_and_existing_generation_layers():
    from app.services.planning.lesson_package import ASSESSMENT_ALTERNATIVE_VALIDITY_RULE

    assert _SEMANTIC_PROMPT.startswith(ASSESSMENT_ALTERNATIVE_VALIDITY_RULE)
    assert 'Remove a semantically false permission' in ' '.join(_SEMANTIC_PROMPT.split())
    assert 'different sound justification of the same answer is enough' in _SEMANTIC_PROMPT
    for name in ('tutorial_package_seed.txt', 'tutorial_activity_generate.txt'):
        prompt = load_and_render(name, {})
        assert 'factual, evaluative and normative assertions remain claims' in prompt
        assert 'A permission cannot make a false classification valid' in prompt
        assert 'alphabetic labels' in prompt
    general = load_and_render('lesson_package_generate.txt', {})
    assert 'remove semantically false permissions' in general
    assert 'do not manufacture disagreement' in general


def test_recorded_numeric_tags_are_fixed_by_lettering_without_relaxing_numeric_evidence():
    import re
    from pydantic import ValidationError
    from app.services.planning.activity_draft import TutorialActivityDraft, parse_activity_draft
    from app.services.planning.package_builder import UndeclaredNumbersError, require_declared_numbers

    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(INVALID_PERMISSION['six_criteria_draft'])
    numbered = INVALID_PERMISSION['numbered_draft']
    assert len(numbered['fields'][0]['criteria']) == 5
    with pytest.raises(UndeclaredNumbersError):
        require_declared_numbers(parse_activity_draft(numbered))
    lettered = json.loads(re.sub(r'\(([1-5])\)',
        lambda match: '(' + chr(64 + int(match.group(1))) + ')', json.dumps(numbered)))
    require_declared_numbers(parse_activity_draft(lettered))
    # Only formatting is checked here. The captured draft's semantic false
    # permission is independently covered above, not approved by this test.


@pytest.mark.asyncio
async def test_valid_witness_does_not_override_an_invalid_acceptance_clause(monkeypatch):
    # The recorded first replay found correct alternatives but approved false
    # exceptions because those particular alternatives passed every criterion.
    verdict = copy.deepcopy(INVALID_PERMISSION['valid_witness_only_verdict'])
    assert verdict['acceptable'] and not verdict['issues']
    assert all(row['accepts_alternative'] for audit in verdict['text_audits'] for row in audit['criteria'])
    assert 'D — claim' in verdict['text_audits'][0]['alternative_response']
    for audit in verdict['text_audits']:
        invalid_index = 0 if audit['target'] == PERMISSION_TARGET else 4
        audit['criteria'][invalid_index].update(task_aligned=False,
            reason='The exception permits an explicit assertion to be falsely classified as topic.')
        audit.update(model_answer_valid=False,
            model_answer_reason='Its conditional topic exception contradicts the supplied assertion.',
            requires_activity_repair=False)
    package = LessonPackage.model_validate(INVALID_PERMISSION['repaired_package'])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=verdict)))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client)
    assert failures and not response.error and not response.semantic_accepted
    assert client.generate_json.await_count == 1
    assert set(response.effective_parameters['validated_repair_targets']) == {
        PERMISSION_TARGET, 'practice.transfer_classify.labels_and_reasons',
    }


@pytest.mark.asyncio
async def test_captured_negative_survives_overlong_optional_audit_and_keeps_private_repair_scope(monkeypatch):
    from app.services.planning.lesson_package import PrivatePackageRepair, apply_private_package_repair

    verdict = copy.deepcopy(INVALID_PERMISSION['corrected_verdict'])
    assert len(verdict['text_audits'][1]['alternative_response']) > 500
    original = LessonPackage.model_validate(INVALID_PERMISSION['original_package'])
    package = apply_private_package_repair(original,
        PrivatePackageRepair.model_validate(INVALID_PERMISSION['recorded_repair']),
        repair_targets=[PERMISSION_TARGET])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=verdict)))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client)
    assert failures and not response.error and not response.semantic_accepted
    assert client.generate_json.await_count == 1
    targets = response.effective_parameters['validated_repair_targets']
    assert set(targets) == {PERMISSION_TARGET, 'practice.transfer_classify.labels_and_reasons'}
    assert 'Remove the exception' in ' '.join(failures)
    patch = _corrected_permission_patch()
    transfer = package.workbook.activities[1]
    criteria = list(transfer.fields[0].criteria)
    criteria[4] = 'Labels A and C as factual claims; accepted background facts still assert propositions'
    patch['field_patches'].append({'activity_id': transfer.id, 'field_id': transfer.fields[0].id,
                                  'criteria': criteria})
    patch['solution_step_patches'].append({'activity_id': transfer.id, 'field_id': transfer.fields[0].id,
        'explanation': 'A asserts the branch closure; B asserts value through "deserves"; C asserts a posting; D predicts help. All are claims. E only names diesel cost, so it is a topic. Being accepted background does not erase a factual assertion.'})
    corrected = apply_private_package_repair(package,
        PrivatePackageRepair.model_validate(patch), repair_targets=targets)
    assert corrected.teaching_cases == package.teaching_cases
    for before, after in zip(package.workbook.activities, corrected.workbook.activities):
        assert after.instructions == before.instructions and after.data == before.data
        assert after.hint == before.hint and after.fields[0].label == before.fields[0].label
        assert (after.minutes_min, after.minutes_max) == (before.minutes_min, before.minutes_max)
        assert after.fields[0].criteria != before.fields[0].criteria
        assert after.worked_solution.steps[0].explanation != before.worked_solution.steps[0].explanation
