"""Content-free pilot monitoring; run on the server with access to private captures."""
import json
import subprocess
from pathlib import Path

def costs(rows):
    return {
        'reported_usd': round(sum(r['charged_usd'] for r in rows if r['status'] == 'finished' and not r.get('usage_unknown')), 9),
        'unknown_reserved_usd': round(sum(r['charged_usd'] for r in rows if r['status'] == 'finished' and r.get('usage_unknown')), 9),
        'pending_reserved_usd': round(sum(r['reserved_usd'] for r in rows if r['status'] == 'reserved'), 9),
        'accounted_usd': round(sum(r.get('charged_usd', r.get('reserved_usd', 0)) for r in rows), 9),
    }

def main():
    root = Path('/opt/cmpys/releases/20261017-001200-structured-solutions/live-batch')
    auth = json.loads((root / 'authorization.json').read_text())
    assert auth['max_tests'] == 6 and auth['shared_cap_usd'] == 1.97
    assert auth['tests_reserved'] == 6 and len(auth['batches']) == 2
    batch = auth['batches'][1]
    assert batch['release'] == '20261017-013000-field-drafts' and batch['label'] == 'corrected'
    lines = (root / 'usage.jsonl').read_text().splitlines()
    rows = []
    for index, line in enumerate(lines):
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            if index != len(lines) - 1:
                raise
    latest = {r['id']: r for r in rows}
    prior = set(batch['prior_request_ids'])
    assert prior <= latest.keys()
    current = [r for key, r in latest.items() if key not in prior]
    state = json.loads(subprocess.check_output(['docker', 'inspect', batch['container']], timeout=30))[0]['State']
    result = {'release': batch['release'], 'running': state['Running'], 'exit_code': state['ExitCode'],
              'cap_usd': auth['shared_cap_usd'], 'tests_reserved': auth['tests_reserved'],
              'prior_completed_accounted_usd': 1.0208688,
              'combined_accounted_usd': round(1.0208688 + costs(list(latest.values()))['accounted_usd'], 9),
              'total_costs': costs(list(latest.values())), 'batch_costs': costs(current),
              'finished_calls': sum(r['status'] == 'finished' for r in current),
              'pending_calls': sum(r['status'] == 'reserved' for r in current), 'cases': []}
    for domain in ('accounting', 'geometry', 'writing'):
        scenario = domain + '_novice_missing'
        calls = [r for r in current if r.get('scenario_id') == scenario]
        case = {'scenario_id': scenario, 'calls': len(calls), **costs(calls)}
        path = root / (scenario + '-corrected-balanced.json')
        try:
            value = json.loads(path.read_text()) if path.exists() else None
        except json.JSONDecodeError:
            value = None  # A case report may be observed during its write.
        if value is not None:
            case.update(status='accepted' if value['accepted'] else 'failed',
                        elapsed_seconds=round(value['elapsed_ms'] / 1000, 3),
                        failure_count=len(value['failures']), adjudicated=value.get('adjudicated', False))
        else:
            case['status'] = 'in_progress' if calls and state['Running'] else 'interrupted' if calls else 'not_started'
        result['cases'].append(case)
    result['recent_responses'] = [
        {key: r.get(key) for key in ('schema', 'scenario_id', 'duration_ms', 'finish_reason', 'thoughts_tokens',
                                    'completion_tokens', 'usage_unknown', 'response_received')}
        for r in current if r['status'] == 'finished'][-3:]
    print(json.dumps(result, sort_keys=True))

if __name__ == '__main__':
    main()
