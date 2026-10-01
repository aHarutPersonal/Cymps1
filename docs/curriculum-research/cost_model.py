"""Illustrative USD sensitivity model, not measured production expenditure.

Only public native Google prices verified on 2026-09-09 are used. All token
counts, reuse, acceptance, escalation, and module preparation costs are explicit
scenario assumptions. Output counts include any billable thinking tokens.
"""
from __future__ import annotations

import json
from math import ceil
from pathlib import Path

OUT = Path(__file__).resolve().parent
RATES = {"flash": (0.75, 3.75), "lite": (0.30, 2.50), "pro": (2.0, 12.0)}


def call(tier: str, input_tokens: int, output_tokens: int) -> float:
    inp, out = RATES[tier]
    return (input_tokens * inp + output_tokens * out) / 1_000_000


def scenario(*, reuse: int, search_overage: bool,
             fallback: float = 0.10, flash_multiplier: float = 1.0,
             canonical_cost: float = 1.0) -> dict:
    assert reuse > 0 and 0 <= fallback <= 1 and flash_multiplier > 0 and canonical_cost >= 0
    flash = lambda i, o: call("flash", i, o) * flash_multiplier
    full = flash(16000, 6000) + call("pro", 8000, 800) + (0.028 if search_overage else 0)
    rewrite = flash(10000, 6000) + call("pro", 8000, 800)
    overlay = flash(4000, 1000) + flash(5000, 500) + 0.10 * call("pro", 8000, 800)
    shared = canonical_cost / reuse
    # A failed overlay incurs its attempted cost AND a full bespoke fallback.
    hybrid = overlay + fallback * full + shared
    return {"reuse_per_module": reuse, "search_overage": search_overage,
            "canonical_preparation_usd": canonical_cost,
            "fallback_rate": fallback, "flash_price_multiplier": flash_multiplier,
            "full_bespoke_per_lesson_usd": round(full, 6),
            "catalog_rewrite_per_lesson_usd": round(rewrite + shared, 6),
            "hybrid_per_lesson_usd": round(hybrid, 6),
            "hybrid_saving_vs_full_percent": round((1 - hybrid / full) * 100, 2),
            "hybrid_break_even_reuse": ceil(canonical_cost / (full - overlay - fallback * full))
                if full > overlay + fallback * full else None}


def main() -> None:
    planning = call("flash", 5000, 1500)
    result = {
        "status": "assumption_based_estimate_not_benchmark",
        "pricing_source": "https://ai.google.dev/gemini-api/docs/pricing",
        "pricing_checked": "2026-09-09",
        "rates_per_million": RATES,
        "flash_rate_validity": "Native Gemini 3.6/3.7/3.8 promotional rates through 2026-12-31; gateway rates not inferred.",
        "assumptions": {"canonical_preparation_usd_per_module": 1.0,
                        "hybrid_quality_escalation_rate": 0.10,
                        "hybrid_fallback_rate": 0.10,
                        "search_queries_per_bespoke_lesson": 2,
                        "search_overage_usd_per_query": 0.014,
                        "planning_usd_per_user": planning,
                        "lessons_per_example_user": 24},
        "excluded": ["human editorial review", "hosting", "retrieval/storage",
                     "audio", "chat", "taxes", "unexpected transport retries",
                     "additional canonical variants", "long-context surcharges"],
        "scenarios": [scenario(reuse=n, search_overage=over)
                      for over in (False, True) for n in (10, 25, 100, 1000)],
        "sensitivity": [scenario(reuse=100, search_overage=False, fallback=f,
                                 flash_multiplier=m)
                        for f in (0, 0.1, 0.3) for m in (1.0, 2.0)],
        "preparation_cost_sensitivity": [
            scenario(reuse=n, search_overage=False, canonical_cost=c)
            for c in (1.0, 10.0, 50.0) for n in (100, 1000)
        ],
    }
    assert abs(call("flash", 4000, 1000) - 0.00675) < 1e-12
    assert scenario(reuse=100, search_overage=False)["hybrid_per_lesson_usd"] > 0
    (OUT / "cost-results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
