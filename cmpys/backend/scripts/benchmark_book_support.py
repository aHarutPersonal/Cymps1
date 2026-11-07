"""Offline fixed-delay book/support scheduling benchmark; no provider calls.

Run: python scripts/benchmark_book_support.py --runs 3 --out book-support.json

Both schedules receive identical source/support fixtures and enforce the same
source sufficiency check. Delays are synthetic assumptions, not live measures.
"""
import argparse
import asyncio
import copy
import json
import sys
import time
from pathlib import Path
from statistics import median
from unittest.mock import patch

BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from app.services import content_resources as resources
from app.services import learning_support as support
from app.services.book_fidelity import sufficient_source

SOURCE = {"source_context": "Verified original source words. " * 100,
          "source_url": "https://example.test/book"}
REFERENCE = {"catalog": "Book metadata"}
DELAYS = {"public": .025, "reference": .150, "official": .080,
          "books": .070, "idea": .020, "video": .150}


async def previous_source(**kwargs):
    public, reference = await asyncio.gather(resources.lookup_public_domain_book(**kwargs),
                                            resources.lookup_book_reference_context(**kwargs))
    if public and sufficient_source(str(public.get("source_context") or "")):
        return public
    official = await resources.lookup_gutenberg_book(**kwargs)
    return official or public or reference


async def previous_support(value):
    books = await asyncio.gather(*(support.resolved_companion(book) for book in value["books"]))
    result = {"books": value["books"], "idea": None, "videos": []}
    if any(book.get("status") == "checking" for book in books):
        result["books_pending"] = True
    if value["lesson"]:
        idea, videos = await asyncio.gather(support.match_book_idea(value, books),
                                          support.find_support_video(value), return_exceptions=True)
        result["idea"] = idea if isinstance(idea, dict) else None
        result["videos"] = videos if isinstance(videos, list) else []
    return result


async def measure(mode, profile):
    calls = []
    async def delayed(stage, result):
        calls.append(stage)
        await asyncio.sleep(DELAYS[stage])
        return copy.deepcopy(result)
    if profile == "support":
        value = {"lesson": "One tutorial", "books": [{"title": "Book"}]}
        with patch.object(support, "resolved_companion", lambda book: delayed("books", {"status": "ready"})), \
             patch.object(support, "match_book_idea", lambda *args: delayed("idea", {"id": "idea"})), \
             patch.object(support, "find_support_video", lambda *args: delayed("video", [{"id": "video"}])):
            started = time.perf_counter()
            result = await (previous_support if mode == "before" else support.build_support)(value)
    else:
        public = SOURCE if profile == "full_text" else None
        with patch.object(resources, "lookup_public_domain_book", lambda **kw: delayed("public", public)), \
             patch.object(resources, "lookup_book_reference_context", lambda **kw: delayed("reference", REFERENCE)), \
             patch.object(resources, "lookup_gutenberg_book", lambda **kw: delayed("official", SOURCE)):
            started = time.perf_counter()
            result = await (previous_source if mode == "before" else resources.lookup_book_source)(title="Book", author="Author")
    return {"mode": mode, "profile": profile, "milliseconds": (time.perf_counter() - started) * 1000,
            "calls": calls, "result": result}


async def run(runs):
    measurements, summaries = [], []
    for profile in ("full_text", "official_fallback", "support"):
        for _ in range(runs):
            before, after = await measure("before", profile), await measure("after", profile)
            assert before.pop("result") == after.pop("result"), "Scheduling changed the output"
            assert sorted(before["calls"]) == sorted(after["calls"]), "Extra or missing request"
            measurements.extend((before, after))
        medians = {mode: median(row["milliseconds"] for row in measurements
                               if row["mode"] == mode and row["profile"] == profile)
                   for mode in ("before", "after")}
        summaries.append({"profile": profile, "runs": runs,
                          "before_median_ms": round(medians["before"], 3),
                          "after_median_ms": round(medians["after"], 3),
                          "reduction_percent": round(100 * (1 - medians["after"] / medians["before"]), 1)})
    return {"kind": "offline synthetic delays; identical selected outputs; no live quality or latency claim",
            "assumed_delays_seconds": DELAYS, "summary": summaries, "runs": measurements}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("runs must be positive")
    result = asyncio.run(run(args.runs))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"kind": result["kind"], "summary": result["summary"]}, indent=2))


if __name__ == "__main__":
    main()
