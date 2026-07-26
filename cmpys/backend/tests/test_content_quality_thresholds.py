"""Tests for PRD-aligned content depth thresholds."""

import pytest

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
                "content": " ".join(f"application{index}_{word}" for word in range(40)),
            }
            for index in range(7)
        ],
    }


def test_content_quality_thresholds_match_prd_minimums():
    assert MIN_BOOK_MODULE_WORDS == 3200
    assert MIN_PLAN_DETAIL_LESSON_WORDS == 1900
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


def test_weekly_lesson_bundle_fills_the_mission_hour_budget():
    details = {
        "steps": [
            {
                "lesson_content": "word " * 2600,
                "estimate_minutes": 60,
                "practice_minutes": 47,
            }
            for _ in range(3)
        ]
    }

    normalized = normalize_lesson_durations(details, mission_hours=5)

    assert [step["reading_minutes"] for step in normalized["steps"]] == [13, 13, 13]
    assert [step["estimate_minutes"] for step in normalized["steps"]] == [100, 100, 100]
    assert [step["practice_minutes"] for step in normalized["steps"]] == [87, 87, 87]
    assert sum(step["estimate_minutes"] for step in normalized["steps"]) == 5 * 60


def test_short_lessons_are_upgraded_and_variable_long_lesson_counts_are_ready():
    assert not _lesson_details_meet_quality(
        {"steps": [{"lesson_content": "word " * 500}]}
    )
    assert _lesson_details_meet_quality({"steps": [{"lesson_content": "word " * 1900}]})
    assert _lesson_details_meet_quality(
        {"steps": [{"lesson_content": "word " * 1900} for _ in range(5)]}
    )


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
            "content_markdown": f'The author writes, "{quotation}"\n\n'
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context=("source material " * 500) + quotation,
    )

    assert report.metrics["unmatched_attributed_quote_count"] == 0


def test_book_grounding_gate_does_not_treat_hypothetical_dialogue_as_author_quote():
    dialogue = (
        'When a customer says, "This hypothetical customer statement contains enough '
        'words to exercise the grounding detector without becoming a source claim," '
        "the interviewer asks for a concrete example."
    )
    report = evaluate_book_module(
        {
            "content_markdown": dialogue + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


def test_book_grounding_gate_pairs_short_and_long_quotes_without_bridging_prose():
    markdown = (
        'When a customer says, "Not now," preserve this unrelated safety instruction. '
        'Then ask, "This longer hypothetical question contains enough words to exercise '
        'the quote-pairing logic without swallowing the prose between examples?"'
    )
    report = evaluate_book_module(
        {
            "content_markdown": markdown + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


@pytest.mark.parametrize(
    "template",
    [
        "The author warns that {quote}",
        "The author asks readers to remember: {quote}",
        "Fitzpatrick explains that {quote}",
        "As Rob Fitzpatrick puts it, {quote}",
        "In Rob Fitzpatrick's words, {quote}",
        "Rob Fitzpatrick: {quote}",
        "A line from the book reads, {quote}",
        "{quote} — Rob Fitzpatrick",
        "According to\nRob Fitzpatrick, {quote}",
        "According to Rob\nFitzpatrick, {quote}",
        "The author\nwrites, {quote}",
    ],
)
def test_book_grounding_gate_catches_common_and_hard_wrapped_attribution(template):
    quotation = (
        '"This unsupported source quotation contains enough words for the strict '
        'grounding classifier to reject it safely."'
    )
    report = evaluate_book_module(
        {
            "author_or_creator": "Rob Fitzpatrick",
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "template",
    [
        "When Alice says, {quote}",
        "If Alice says, {quote}",
        "Imagine Alice says, {quote}",
        "Suppose Alice says, {quote}",
        "Customer Alice says, {quote}",
    ],
)
def test_book_grounding_gate_excludes_named_hypothetical_dialogue(template):
    quotation = (
        '"This hypothetical dialogue contains enough words for the grounding classifier '
        'to distinguish it from a sourced quotation."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


def test_book_grounding_gate_excludes_multi_quote_interview_scenario():
    markdown = (
        'The manager offers a compliment ("This proposed workflow looks excellent and '
        'would certainly transform our entire sales organization"), delivers fluff '
        '("We always record every customer call immediately after each meeting without '
        'ever missing one"), and proposes an idea ("You should build automatic voice '
        'transcription for every mobile note our salespeople create").'
    )
    report = evaluate_book_module(
        {
            "content_markdown": markdown + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


@pytest.mark.parametrize(
    "template",
    [
        "A customer asks a question, then Rob Fitzpatrick writes, {quote}",
        "When a buyer hesitates, Rob Fitzpatrick explains, {quote}",
        'When a customer says "Not now," Fitzpatrick writes, {quote}',
    ],
)
def test_book_grounding_gate_keeps_named_source_after_hypothetical_role(template):
    quotation = (
        '"This unsupported named-source quotation contains enough words for the '
        'grounding classifier to reject after a hypothetical example."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "template",
    [
        "Write: {quote}",
        "Note: {quote}",
        "Explain: {quote}",
        "Describe the situation: {quote}",
        "Define the problem as: {quote}",
        "In your journal, write: {quote}",
        "For practice, ask yourself: {quote}",
        "Read aloud: {quote}",
        "Ask your partner: {quote}",
        "Ask the customer: {quote}",
        "Call it: {quote}",
        "State your hypothesis: {quote}",
        "Tell yourself: {quote}",
        "Remind yourself: {quote}",
        "Try This: {quote}",
        "Observe: {quote}",
        "Record: {quote}",
        "List: {quote}",
        "Draft: {quote}",
        "Imagine: {quote}",
        "Suppose: {quote}",
        "Ask Your Partner: {quote}",
        "Read Aloud: {quote}",
        "State Your Hypothesis: {quote}",
        "Practice Drill: {quote}",
        "Talk Track: {quote}",
        "Words To Use: {quote}",
        "What To Ask: {quote}",
        "Use Instead: {quote}",
    ],
)
def test_book_grounding_gate_excludes_imperative_practice_prompts(template):
    quotation = (
        '"This practice prompt contains enough words for the grounding classifier to '
        'keep it available as an exercise."'
    )
    report = evaluate_book_module(
        {
            "author_or_creator": "Rob Fitzpatrick",
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


@pytest.mark.parametrize(
    "template",
    [
        "According to your notes, {quote}",
        "According to the customer, {quote}",
        "According to a prospect, {quote}",
        "According to your role-play partner, {quote}",
        "According to the example response, {quote}",
    ],
)
def test_book_grounding_gate_excludes_instructional_according_to_cues(template):
    quotation = (
        '"This instructional dialogue contains enough words for the grounding gate '
        'to preserve it as an exercise."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


@pytest.mark.parametrize(
    "label",
    [
        "Question",
        "Prompt",
        "Example",
        "Practice Note",
        "CRM Checklist",
        "Sample Answer",
        "Example Response",
        "Suggested Script",
        "Practice Dialogue",
        "Model Response",
        "Sample Language",
        "Interview Script",
        "Conversation Starter",
        "Opening Line",
    ],
)
def test_book_grounding_gate_excludes_educational_colon_labels(label):
    quotation = (
        '"This labeled learning example contains enough words for the grounding '
        'classifier to keep it as instructional content."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": f"{label}: {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0


def test_book_grounding_gate_accepts_book_title_as_source_credit():
    quotation = (
        '"This title-attributed quotation contains enough words for the grounding '
        'classifier to require support from source text."'
    )
    report = evaluate_book_module(
        {
            "title": "The Mom Test",
            "content_markdown": f"The Mom Test: {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "template",
    [
        "**The Mom Test:** {quote}",
        "*The Mom Test:* {quote}",
        "> **The Mom Test:** {quote}",
        "- **The Mom Test:** {quote}",
        "**The Mom Test**: {quote}",
    ],
)
def test_book_grounding_gate_accepts_markdown_wrapped_known_title_credit(template):
    quotation = (
        '"This decorated title quotation contains enough words for the grounding '
        'classifier to require supporting source text."'
    )
    report = evaluate_book_module(
        {
            "title": "The Mom Test",
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "template",
    [
        "{quote} — **Rob Fitzpatrick**",
        "{quote} — *Rob Fitzpatrick*",
        "{quote} (**Rob Fitzpatrick**)",
        "{quote} — [Rob Fitzpatrick](https://example.com/rob)",
        "{quote} — **Rob Fitzpatrick**.",
        "{quote} — *Rob Fitzpatrick*.",
        "{quote} — [Rob Fitzpatrick](https://example.com/rob).",
        "{quote} — `Rob Fitzpatrick`.",
    ],
)
def test_book_grounding_gate_accepts_markdown_wrapped_known_author_credit(template):
    quotation = (
        '"This decorated author quotation contains enough words for the grounding '
        'classifier to require supporting source text."'
    )
    report = evaluate_book_module(
        {
            "author_or_creator": "Rob Fitzpatrick",
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "template",
    [
        "> {text}\n> — Rob Fitzpatrick",
        "> **{text}**\n> — **Rob Fitzpatrick**",
        "> {text}\n> (Rob Fitzpatrick)",
        "*{text}*\n\n— **Rob Fitzpatrick**",
        "**{text}**\n\n(Rob Fitzpatrick)",
        "_Rob Fitzpatrick:_\n\n_{text}_",
    ],
)
def test_book_grounding_gate_catches_delimiter_free_known_author_epigraph(template):
    quotation = (
        "This delimiter free epigraph contains enough words for the grounding "
        "classifier to require supporting source text."
    )
    report = evaluate_book_module(
        {
            "author_or_creator": "Rob Fitzpatrick",
            "content_markdown": template.format(text=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "epigraph",
    [
        "*Protect your attention.*\n\n— Cal Newport",
        "> Protect attention.\n> — Cal Newport",
    ],
)
def test_book_grounding_gate_catches_short_credited_epigraph(epigraph):
    report = evaluate_book_module(
        {
            "author_or_creator": "Cal Newport",
            "content_markdown": epigraph + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A catalog description with no quotation transcript.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "epigraph",
    [
        (
            "> This quote starts here with six words\n"
            "> and continues with six more useful words\n"
            "> — Rob Fitzpatrick"
        ),
        (
            "> This delimiter free quotation contains enough words for source verification.\n"
            ">\n"
            "> — Rob Fitzpatrick"
        ),
        (
            "> This first line contains enough words to require source verification now.\n"
            "> Continued briefly.\n"
            "> — Rob Fitzpatrick"
        ),
        (
            "> This quote starts here with six useful words\n"
            "and continues lazily with six more useful words\n"
            "> — Rob Fitzpatrick"
        ),
        (
            "> This delimiter free quotation contains enough words for source verification.\n"
            "— Rob Fitzpatrick"
        ),
        (
            "**The Mom Test:**\n"
            "> This delimiter free quotation contains enough words for source verification."
        ),
    ],
)
def test_book_grounding_gate_groups_multiline_blockquote_epigraph(epigraph):
    report = evaluate_book_module(
        {
            "title": "The Mom Test",
            "author_or_creator": "Rob Fitzpatrick",
            "content_markdown": epigraph + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "quotation",
    [
        '"Use a "Mom Test" question to learn about actual behavior"',
        '"This direct quotation calls it "The Mom Test" and ends briefly"',
        "“Use a “Mom Test” question to learn about actual behavior”",
        (
            '"This outer quotation contains more than eight preliminary words before '
            '"The Mom Test" and then finishes."'
        ),
        "‘This isn’t a simple quote because it calls this ‘The Mom Test’ before ending safely.’",
        "‘Customers’ needs are explained by calling this ‘The Mom Test’ before ending safely.’",
        "'This isn't a simple quote because it calls this 'The Mom Test' before ending safely.'",
    ],
)
def test_book_grounding_gate_conservatively_catches_nested_same_style_quotes(
    quotation,
):
    report = evaluate_book_module(
        {
            "content_markdown": f"The author writes, {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "credit",
    ["Who Moved My Cheese?", "**Who Moved My Cheese?:**"],
)
def test_book_grounding_gate_matches_known_title_ending_in_punctuation(credit):
    quotation = (
        '"This title quotation contains enough words to require source support now."'
    )
    separator = ":" if not credit.endswith(":**") else ""
    report = evaluate_book_module(
        {
            "title": "Who Moved My Cheese?",
            "content_markdown": f"{credit}{separator} {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "quotation",
    [
        "‘This curly single quotation contains enough words for the grounding gate to reject it safely.’",
        "'This straight single quotation contains enough words for the grounding gate to reject it safely.'",
        "«This guillemet quotation contains enough words for the grounding gate to reject it safely.»",
        "‘This isn’t a sourced quotation but it contains enough words for rejection.’",
        "‘Customers’ needs reveal an unsupported quotation with enough words for rejection.’",
        "'Customers' needs reveal an unsupported quotation with enough words for rejection.'",
        "'James' advice reveals an unsupported quotation with enough words for rejection.'",
    ],
)
def test_book_grounding_gate_catches_common_alternate_quote_delimiters(quotation):
    report = evaluate_book_module(
        {
            "content_markdown": f"The author writes, {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize("quotation", ['"focus"', '"deep work"'])
def test_book_grounding_gate_catches_short_directly_attributed_quotes(quotation):
    report = evaluate_book_module(
        {
            "content_markdown": f"The author writes, {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A catalog description with no quotation transcript.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize("term", ['"focus"', '"deep work"'])
def test_book_grounding_gate_ignores_unattributed_short_terms(term):
    report = evaluate_book_module(
        {
            "content_markdown": f"Practice {term} deliberately each morning.\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="No source transcript is available.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


def test_book_grounding_gate_ignores_short_term_in_numbered_practice_step():
    markdown = (
        "### Practice This\n"
        '1. Write down three consecutive "slices" of the customer segment.\n\n'
    )
    report = evaluate_book_module(
        {
            "content_markdown": markdown + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="No source transcript is available.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


@pytest.mark.parametrize(
    "source_noun",
    ["source", "chapter", "preface", "publisher", "study", "research"],
)
def test_book_grounding_gate_recognizes_source_noun_attribution(source_noun):
    report = evaluate_book_module(
        {
            "content_markdown": (
                f'The {source_noun} says, "Protect your attention."\n\n'
                + "word " * 2800
            ),
            "sections": [],
            "ideas": [],
        },
        source_context="No source transcript is available.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "credit_line",
    ["{surname}: {quote}", "{quote} — {surname}"],
)
@pytest.mark.parametrize(
    ("author", "surname"),
    [
        ("Cal Newport", "Newport"),
        ("Martin Luther King Jr.", "King"),
        ("Nassim Nicholas Taleb II", "Taleb"),
        ("Jane Doe Sr.", "Doe"),
        ("Robert Cialdini Ph.D.", "Cialdini"),
        ("Newport, Cal", "Newport"),
        ("Cal Newport; Adam Grant", "Newport"),
        ("Cal Newport; Adam Grant", "Grant"),
    ],
)
def test_book_grounding_gate_recognizes_author_surname_credits(
    credit_line,
    author,
    surname,
):
    report = evaluate_book_module(
        {
            "title": "Deep Work",
            "author_or_creator": author,
            "content_markdown": credit_line.format(
                surname=surname,
                quote='"Protect your attention"',
            )
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A catalog description with no quotation transcript.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "verb",
    [
        "added",
        "argued",
        "believes",
        "claimed",
        "commented",
        "concluded",
        "continued",
        "declared",
        "defined",
        "described",
        "emphasized",
        "explained",
        "insisted",
        "mentioned",
        "noted",
        "observed",
        "offered",
        "proposed",
        "recalled",
        "recommended",
        "remarked",
        "reminded",
        "shared",
        "stated",
        "suggested",
        "warned",
    ],
)
def test_book_grounding_gate_recognizes_common_named_source_verbs(verb):
    report = evaluate_book_module(
        {
            "content_markdown": (
                f'Rob Fitzpatrick {verb}, "This fabricated claim needs source support."\n\n'
                + "word " * 2800
            ),
            "sections": [],
            "ideas": [],
        },
        source_context="A catalog description with no quotation transcript.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize("coordinator", ["and", "or", "&", "as well as"])
def test_book_grounding_gate_checks_each_coordinated_quote_against_shared_credit(
    coordinator,
):
    first = "This first supported quotation contains enough words to require source evidence."
    second = "This second supported quotation also contains enough words to require source evidence."
    markdown = f'"{first}" {coordinator} "{second}" — Rob Fitzpatrick'
    source = f'An excerpt says "{first}". Another passage says "{second}".'

    report = evaluate_book_module(
        {
            "author_or_creator": "Rob Fitzpatrick",
            "content_markdown": markdown + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context=source,
    )

    assert report.metrics["attributed_quote_count"] == 2
    assert report.metrics["unmatched_attributed_quote_count"] == 0


@pytest.mark.parametrize(
    "markdown",
    [
        'Instead of asking, "Would you buy this?"',
        'A precise problem interview asks, "What happened last time?"',
        'Sit beside the customer and simply ask, "How do you handle it?"',
        'The interviewer asks, "What happened the last time?"',
        'Your interviewer asks, "What happened the last time?"',
        'As the interviewer, ask: "What happened the last time?"',
        'A Mom Test practitioner asks, "What happened the last time?"',
        'The exercise asks, "What happened the last time?"',
        'The prompt says, "What happened the last time?"',
        'The example says, "What happened the last time?"',
        'The worksheet says, "What happened the last time?"',
        'The script reads, "What happened the last time?"',
        'In this exercise, ask: "What happened the last time?"',
        'For this exercise, write: "What happened the last time?"',
        'During the exercise, ask: "What happened the last time?"',
        'The following exercise asks, "What happened the last time?"',
        'This practice activity asks, "What happened the last time?"',
        'In your worksheet, write: "What happened the last time?"',
        'Now ask: "What happened the last time?"',
        'Next, ask: "What happened the last time?"',
    ],
)
def test_book_grounding_gate_does_not_treat_instructional_dialogue_as_source_quote(
    markdown,
):
    report = evaluate_book_module(
        {
            "content_markdown": markdown + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="No source transcript is available.",
    )

    assert report.metrics["attributed_quote_count"] == 0
    assert report.metrics["unmatched_attributed_quote_count"] == 0


def test_book_grounding_gate_does_not_overcapture_curly_single_quote_prose():
    markdown = (
        "The author writes, ‘This unsupported quotation has enough words and ends "
        "with customers’ says the editor, who calls it ‘wrong’."
    )
    report = evaluate_book_module(
        {
            "content_markdown": markdown + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "quotation",
    [
        (
            '"This direct quotation starts with six useful words\n'
            'and continues with six more before safely closing."'
        ),
        (
            "“This direct quotation starts with six useful words\n"
            "and continues with six more before safely closing.”"
        ),
        (
            "«This direct quotation starts with six useful words\n"
            "and continues with six more before safely closing.»"
        ),
        '"' + ("unsupported evidence " * 30) + '"',
    ],
)
def test_book_grounding_gate_catches_wrapped_and_long_attributed_quotes(quotation):
    assert len(quotation) > 400 or "\n" in quotation
    report = evaluate_book_module(
        {
            "content_markdown": f"The author writes, {quotation}\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    ("identity_field", "identity", "credit"),
    [
        ("title", "The Checklist Manifesto", "The Checklist Manifesto"),
        ("title", "The Practice", "The Practice"),
        ("title", "The Goal", "The Goal"),
        ("title", "Good to Great", "Good to Great"),
        (
            "title",
            "How to Win Friends and Influence People",
            "How to Win Friends and Influence People",
        ),
        (
            "title",
            "The 7 Habits of Highly Effective People",
            "The 7 Habits of Highly Effective People",
        ),
        ("title", "Thinking, Fast and Slow", "Thinking, Fast and Slow"),
        ("title", "Start with Why", "Start with Why"),
        ("title", "Zero to One", "Zero to One"),
        ("author_or_creator", "bell hooks", "bell hooks"),
        ("author_or_creator", "e. e. cummings", "e. e. cummings"),
        ("author_or_creator", "danah boyd", "danah boyd"),
    ],
)
def test_book_grounding_gate_uses_exact_known_title_or_author_credit(
    identity_field,
    identity,
    credit,
):
    quotation = (
        '"This exact source-credit quotation contains enough words for the grounding '
        'classifier to require supporting source text."'
    )
    module = {
        "title": "A Different Book",
        "content_markdown": f"{credit}: {quotation}\n\n" + "word " * 2800,
        "sections": [],
        "ideas": [],
    }
    module[identity_field] = identity
    report = evaluate_book_module(
        module,
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1


@pytest.mark.parametrize(
    "template",
    [
        "{quote}, says the customer.",
        "{quote}, says Alice in this role-play.",
        "In this role-play, {quote}, says Alice.",
        "{quote} — Practice Note",
        "{quote} — Example",
        "{quote} — CRM Checklist",
        "{quote} — Practice Drill",
        "{quote} — Talk Track",
        "{quote} — Words To Use",
        "{quote} — What To Ask",
        "{quote} — Use Instead",
        "{quote} — Next Move",
        "{quote} — Ask Your Partner",
        "{quote} — Read Aloud",
        "{quote} — State Your Hypothesis",
    ],
)
def test_book_grounding_gate_excludes_hypothetical_or_label_suffixes(template):
    quotation = (
        '"This hypothetical suffix dialogue contains enough words for the grounding '
        'classifier to keep it as instructional content."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": template.format(quote=quotation)
            + "\n\n"
            + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="A short catalog description with no direct quotation.",
    )

    assert report.metrics["attributed_quote_count"] == 0
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


@pytest.mark.parametrize("year", ["1492", "2024", "2101", "’83", "'83", "’80s"])
def test_book_grounding_gate_rejects_one_unsupported_specific_year(year):
    report = evaluate_book_module(
        {
            "content_markdown": (
                f"In {year}, the author founded the company and launched its first product.\n\n"
                + "word " * 2800
            ),
            "sections": [],
            "ideas": [],
        },
        source_context="Publisher metadata without dates.",
    )

    assert report.metrics["unmatched_year_count"] == 1
    assert any("date" in issue for issue in report.issues)


def test_book_grounding_gate_does_not_use_unrelated_bare_year_as_claim_support():
    report = evaluate_book_module(
        {
            "content_markdown": (
                "In 2024, the author founded the company and launched its first product.\n\n"
                + "word " * 2800
            ),
            "sections": [],
            "ideas": [],
        },
        source_context="Publisher: Example Press. Published date: 2024.",
    )

    assert report.metrics["unmatched_year_count"] == 1


def test_book_grounding_gate_accepts_year_with_matching_claim_context():
    report = evaluate_book_module(
        {
            "content_markdown": "The book was published in 2024.\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="Catalog record. The book was published in 2024.",
    )

    assert report.metrics["unmatched_year_count"] == 0


@pytest.mark.parametrize(
    ("output_year", "source_year"),
    [
        ("’83", "1983"),
        ("'83", "1983"),
        ("’80s", "1980s"),
        ("'80s", "1980s"),
        ("1983", "’83"),
        ("1983", "'83"),
        ("1980s", "’80s"),
        ("1980s", "'80s"),
    ],
)
def test_book_grounding_gate_matches_abbreviated_year_to_explicit_source_year(
    output_year,
    source_year,
):
    report = evaluate_book_module(
        {
            "content_markdown": (
                f"In {output_year}, the author founded the company.\n\n"
                + "word " * 2800
            ),
            "sections": [],
            "ideas": [],
        },
        source_context=f"In {source_year}, the author founded the company.",
    )

    assert report.metrics["unmatched_year_count"] == 0


@pytest.mark.parametrize(
    ("claim", "source_claim"),
    [
        (
            "Revenue rose in 2024 after customer demand increased.",
            "Revenue fell in 2024 after customer demand slowed.",
        ),
        (
            "The company earned no profit in 2024.",
            "The company earned record profit in 2024.",
        ),
        (
            "The team did not launch in 2024.",
            "The team did launch in 2024.",
        ),
        (
            "The iPhone launched in 2024.",
            "The Vision Pro launched in 2024.",
        ),
    ],
)
def test_book_grounding_gate_rejects_contradictory_same_year_claims(
    claim,
    source_claim,
):
    report = evaluate_book_module(
        {
            "content_markdown": claim + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context=source_claim,
    )

    assert report.metrics["unmatched_year_count"] == 1


@pytest.mark.parametrize(
    "claim", ["The company will launch in 2200.", "The 1990s changed the market."]
)
def test_book_grounding_gate_covers_future_years_and_decades(claim):
    report = evaluate_book_module(
        {
            "content_markdown": claim + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="Publisher metadata without dates.",
    )

    assert report.metrics["unmatched_year_count"] == 1


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
