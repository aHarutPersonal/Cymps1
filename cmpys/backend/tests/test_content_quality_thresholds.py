"""Tests for PRD-aligned content depth thresholds."""

from app.api.v1.plans import _lesson_details_meet_quality
from app.services.content_resources import MIN_BOOK_MODULE_WORDS
from app.services.content_quality import evaluate_book_module
from app.tasks.plans import (
    MIN_PLAN_DETAIL_LESSON_WORDS,
    MIN_PLAN_DETAIL_MATERIAL_WORDS,
    normalize_lesson_durations,
)


def _quality_ready_book_module(*, templated: bool = False) -> dict:
    sections = [
        {
            "title": f"Framework {index + 1}",
            "summary": " ".join(f"summary{index}_{word}" for word in range(70)),
            "exercise": " ".join(f"exercise{index}_{word}" for word in range(35)),
        }
        for index in range(6)
    ]
    markdown_parts = []
    for index in range(6):
        if templated:
            body = " ".join(f"shared{word}" for word in range(520))
            body = f"{body} variation{index}"
        else:
            body = " ".join(f"section{index}term{word}" for word in range(520))
        markdown_parts.append(
            f"## Framework {index + 1}\n\n{body}\n\n"
            "### Practice This\n1. Apply one step.\n2. Record one result."
        )
    closing = " ".join(f"synthesis{word}" for word in range(180))
    markdown_parts.append(f"## Closing Synthesis\n\n{closing}")
    return {
        "content_markdown": "\n\n".join(markdown_parts),
        "sections": sections,
        "ideas": [
            {
                "title": f"Idea {index + 1}",
                "content": " ".join(
                    f"application{index}_{word}" for word in range(40)
                ),
            }
            for index in range(7)
        ],
    }


def test_content_quality_thresholds_match_prd_minimums():
    assert MIN_BOOK_MODULE_WORDS == 3200
    assert MIN_PLAN_DETAIL_LESSON_WORDS == 1200
    assert MIN_PLAN_DETAIL_MATERIAL_WORDS == 350


def test_lesson_duration_is_derived_from_reading_and_practice():
    details = {
        "steps": [
            {
                "lesson_content": "word " * 1600,
                "estimate_minutes": 45,
                "practice_minutes": 35,
            }
        ]
    }

    normalized = normalize_lesson_durations(details)
    step = normalized["steps"][0]

    assert step["reading_minutes"] == 8
    assert step["practice_minutes"] == 35
    assert step["estimate_minutes"] == 43


def test_legacy_short_lesson_is_upgraded_when_opened():
    assert not _lesson_details_meet_quality(
        {"steps": [{"lesson_content": "word " * 500}]}
    )
    assert not _lesson_details_meet_quality(
        {"steps": [{"lesson_content": "word " * 1200}]}
    )
    assert _lesson_details_meet_quality({
        "steps": [
            {"lesson_content": "word " * 1200},
            {"lesson_content": "word " * 1200},
            {"lesson_content": "word " * 1200},
        ]
    })


def test_book_quality_gate_requires_structure_not_only_length():
    report = evaluate_book_module(
        {
            "content_markdown": "word " * 3000,
            "sections": [],
            "ideas": [],
        }
    )

    assert report.passed is False
    assert any("sections" in issue for issue in report.issues)
    assert any("Practice This" in issue for issue in report.issues)


def test_book_grounding_gate_rejects_attributed_quote_missing_from_source():
    invented = (
        'The author writes, "This entirely invented sentence contains enough words '
        'to qualify as a direct attributed quotation in the generated lesson."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": invented + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="source material " * 500,
    )

    assert report.metrics["source_grounding_eligible"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1
    assert any("quotation" in issue for issue in report.issues)


def test_book_grounding_gate_accepts_quote_present_in_source():
    quotation = (
        "This sentence appears exactly in the supplied source and therefore may be "
        "attributed safely in the generated lesson."
    )
    report = evaluate_book_module(
        {
            "content_markdown": f'The author writes, "{quotation}"\n\n' + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context=("source material " * 500) + quotation,
    )

    assert report.metrics["unmatched_attributed_quote_count"] == 0


def test_book_quality_gate_hard_fails_canned_filler_in_otherwise_valid_module():
    module = _quality_ready_book_module()
    module["content_markdown"] = module["content_markdown"].replace(
        "section0term0",
        "Let's dive in before section0term0",
        1,
    )

    report = evaluate_book_module(module)

    assert report.passed is False
    assert report.metrics["filler_phrase_count"] == 1
    assert any("canned" in issue for issue in report.issues)


def test_book_quality_gate_rejects_near_duplicate_section_templates():
    report = evaluate_book_module(_quality_ready_book_module(templated=True))

    assert report.passed is False
    assert report.metrics["near_duplicate_paragraph_ratio"] > 0.10
    assert any("templated paragraph" in issue for issue in report.issues)


def test_book_quality_gate_rejects_repeated_sentence_openings():
    module = _quality_ready_book_module()
    repeated_stems = " ".join(
        f"The practical result becomes visible through distinct application {index}."
        for index in range(14)
    )
    module["content_markdown"] += f"\n\n{repeated_stems}"

    report = evaluate_book_module(module)

    assert report.passed is False
    assert report.metrics["repeated_sentence_opening_count"] >= 4
    assert any("sentence opening" in issue for issue in report.issues)


def test_book_grounding_gate_checks_short_source_contexts():
    module = _quality_ready_book_module()
    invented = (
        'The author writes, "This invented quotation is deliberately long enough '
        'to be treated as an attributed factual quotation by the quality gate."'
    )
    module["content_markdown"] = invented + "\n\n" + module["content_markdown"]

    report = evaluate_book_module(
        module,
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["source_grounding_eligible"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1
    assert report.passed is False


def test_book_quality_gate_requires_one_closing_synthesis_heading():
    module = _quality_ready_book_module()
    module["content_markdown"] = module["content_markdown"].replace(
        "## Closing Synthesis",
        "## Final Integration",
    )

    report = evaluate_book_module(module)

    assert report.passed is False
    assert report.metrics["heading_count"] == 7
    assert report.metrics["closing_synthesis_count"] == 0
    assert any("Closing Synthesis" in issue for issue in report.issues)
