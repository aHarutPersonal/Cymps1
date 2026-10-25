"""Compare blind synthetic run JSONL files; performs no model or database calls.

PYTHONPATH=. python scripts/evaluate_generation.py candidate.jsonl baseline.jsonl
"""
import argparse
import json
from pathlib import Path
from app.services.llm.evaluation import summarize_runs, promotion_decision


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("baseline", type=Path)
    args = parser.parse_args()
    scenarios = json.loads((Path(__file__).parents[1] / "tests/fixtures/generation_scenarios.json").read_text())
    reports = [summarize_runs([json.loads(line) for line in path.read_text().splitlines() if line.strip()], scenarios)
               for path in (args.candidate, args.baseline)]
    print(json.dumps({"candidate": reports[0], "baseline": reports[1],
                      "decision": promotion_decision(*reports)}, indent=2))


if __name__ == "__main__":
    main()
