"""The local school-start tutorial confused attendance evidence with learning."""
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import _SEMANTIC_PROMPT, review_package
from tests.lesson_package_fixtures import package_payload


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'school_start_proxy_activity.json').read_text())
TARGET = 'practice.new_claim_rescue.checklist_and_rewrite'


def test_model_answer_review_requires_exact_outcome_and_claim_strength():
    explanation = RECORDED['worked_solution']['steps'][0]['explanation']
    assert "'tired students cannot learn'" in explanation
    assert 'real attendance records or a sourced study' in explanation
    for requirement in (
        'EVERY private model answer', 'exact claimed outcome, population, comparison and strength',
        'Attendance measures attendance', 'Neither by itself demonstrates learning',
        'association from causation', 'a group tendency from an absolute',
        'A rewrite may openly narrow its outcome', 'remaining evidence gap',
    ):
        assert requirement in _SEMANTIC_PROMPT


@pytest.mark.asyncio
async def test_captured_proxy_mismatch_remains_a_blocking_private_model_answer_defect(monkeypatch):
    payload = package_payload()
    payload['teaching_cases'] = [{
        'id': 'public_notice', 'data': [], 'results': [],
        'assumptions': ('Original fictional notice: "Garden helpers welcome." A clearer request '
                        'names a cleanup and asks volunteers to reply to its coordinator; '
                        'the revision makes the action and response path explicit.'),
    }]
    payload['workbook']['activities'][0].update(minutes_min=1, minutes_max=2)
    payload['workbook']['activities'][1] = RECORDED
    package = LessonPackage.model_validate(payload)
    verdict = {'acceptable': False, 'issues': [{'target': TARGET, 'description': (
        'The private model answer recommends attendance records to support tired students '
        'cannot learn. Attendance does not measure learning, and a generic sourced study '
        'does not establish that absolute claim. Narrow the claim or name relevant learning '
        'evidence and its comparison; explain that attendance and alertness test only the '
        'rewritten operational outcomes.'
    )}]}
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=verdict)))
    telemetry = AsyncMock(return_value=True)
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', telemetry)
    snapshots = []

    async def save(state):
        snapshots.append(state)

    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client, on_review=save)

    assert failures and not response.error and not response.semantic_accepted
    assert response.effective_parameters['validated_repair_targets'] == [TARGET]
    assert client.generate_json.await_count == 1  # No extra audit or retry overrides the rejection.
    assert snapshots[-1]['semantic']['issues'] == [dict(issue, severity='blocking') for issue in verdict['issues']]
    request = client.generate_json.await_args.kwargs
    assert 'real attendance records or a sourced study' in request['user_prompt']
    assert 'Check evidence-to-claim fit in EVERY private model answer' in request['system_prompt']

