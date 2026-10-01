"""Offline audit probes: synthetic inputs, no database queries or provider calls.

Run with the backend virtualenv. Passing probes reproduce limitations; they do
not certify lesson quality or bypass the independent publication reviewers.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "cmpys/backend"))

from app.services.curriculum.gates import validate_structure
from app.services.llm.schemas import PlanItemDetailsOutput
from app.services.planning.catalog_lessons import match_catalog_lesson
from app.tasks.plans import normalize_lesson_durations
from tests.test_catalog_personalization import _candidate, _gap, _session
from tests.test_curriculum_pipeline import _draft
from tests.test_plan_detail_output_schema import _valid_payload


def main() -> None:
    probes = []
    payload = _valid_payload(lesson_count=1, material_count=1)
    step = payload["steps"][0]
    step.update(estimate_minutes=120, reading_minutes=13, practice_minutes=20)
    validated = PlanItemDetailsOutput.model_validate(payload)
    probes.append({
        "id": "duration_sum_not_enforced_by_details_schema",
        "reproduced": validated.steps[0].estimate_minutes != 13 + 20,
        "declared_minutes": 120, "component_minutes": 33,
        "scope": "Details schema only; generated output was not sampled.",
    })
    probes.append({
        "id": "repeated_filler_passes_details_schema",
        "reproduced": True,
        "words": len(step["lesson_content"].split()),
        "scope": "Existing synthetic test fixture passes word/heading gates; not a full publication claim.",
    })
    tiny = {"steps": [{"lesson_content": "word " * 600,
                        "practice_minutes": 4, "estimate_minutes": 7}]}
    result = normalize_lesson_durations(tiny, mission_hours=2)["steps"][0]
    probes.append({
        "id": "normalizer_invents_practice_minutes",
        "reproduced": result["practice_minutes"] == 117,
        "original_practice_minutes": 4,
        "normalized_practice_minutes": result["practice_minutes"],
        "normalized_total_minutes": result["estimate_minutes"],
        "scope": "Normalizer in isolation; a short lesson may fail a separate depth gate.",
    })
    canonical = _draft()
    gate = validate_structure(canonical)
    probes.append({
        "id": "canonical_structure_accepts_thin_content",
        "reproduced": gate.passed,
        "declared_minutes": canonical.estimated_minutes,
        "body_words": sum(len(b.content_markdown.split()) for b in canonical.blocks),
        "scope": "Deterministic structure gate only; independent semantic reviews still apply.",
    })
    candidate = _candidate(sessions=(_session(
        content={"lesson_content": "Use price-chart timing as the primary investment decision rule."}
    ),))
    match = match_catalog_lesson(_gap(), [candidate])
    probes.append({
        "id": "matcher_does_not_inspect_method_compatibility",
        "reproduced": match.verdict.value == "exact",
        "verdict": match.verdict.value,
        "scope": "Adversarial candidate with unchanged skill metadata; no claim about a published lesson.",
    })
    prompt_files = sorted(p for p in (ROOT / "cmpys/prompts").iterdir()
                          if p.suffix in {".txt", ".xml"})
    inventory = [{"name": p.name, "words": len(p.read_text().split()),
                  "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                 for p in prompt_files]
    result = {"kind": "offline_adversarial_audit", "live_provider_calls": 0,
              "database_queries": 0, "probes": probes,
              "prompt_count": len(inventory), "prompt_inventory": inventory}
    (OUT / "audit-results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"probes": probes, "prompt_count": len(inventory)}, indent=2))
    assert all(p["reproduced"] for p in probes), "A previously observed limitation changed; update the report."


if __name__ == "__main__":
    main()
