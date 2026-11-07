"""Explicit positive review fixtures for the synthetic argument timing tests."""


def argument_text_audits(package):
    audits = []
    for activity in package.workbook.activities:
        assert activity.id in {'guided', 'transfer'}
        for field in activity.fields:
            if field.kind != 'text':
                continue
            assert field.id == 'argument'
            audits.append({
                'target': 'practice.' + activity.id + '.' + field.id,
                'alternative_response': ('A bounded claim holds under its stated conditions. '
                    'An objection tests the supporting reason; a justified revision narrows '
                    'those conditions rather than merely changing the wording.'),
                'criteria': [{'criterion_index': index, 'required_by_task': True,
                    'accepts_alternative': True,
                    'reason': 'The response makes the claim, reasoned objection and revision explicit.'}
                    for index in range(len(field.criteria))],
                'model_answer_valid': True,
                'model_answer_reason': 'The synthetic response demonstrates the same requested argument skills.',
                'requires_activity_repair': False,
            })
    return audits



def public_notice_teaching_audits(package):
    """Explicit review of the shared library notice, never arbitrary case approval."""
    assert len(package.teaching_cases) == 1
    case = package.teaching_cases[0]
    assert case.id == 'public_notice'
    assert 'Please return library books by Friday' in case.assumptions
    return [{'target': 'teaching.public_notice',
        'core_inference': 'Returning books by Friday names action and deadline.',
        'quantities_and_units': 'Qualitative action and a deadline; no arithmetic comparison.',
        'decision_rule': 'The reader can identify the required action and timing.',
        'semantically_valid': True,
        'reason': 'The stated action and deadline support the claimed clarity.'}]
