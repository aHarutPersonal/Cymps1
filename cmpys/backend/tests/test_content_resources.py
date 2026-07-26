import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.content_resource import ContentResourceKind, LicenseStatus
from app.models.idol import CatalogStatus
from app.services.content_resources import (
    BOOK_MODULE_QUALITY_GATE_VERSION,
    BOOK_MODULE_QUALITY_TIMEOUT_SECONDS,
    BOOK_MODULE_TOTAL_TIMEOUT_SECONDS,
    BookModuleGroundingRepairOutput,
    BookModuleMetadataOutput,
    BookModuleOutput,
    _apply_book_grounding_patches,
    _neutralize_unsupported_grounding_markers,
    _unsupported_grounding_markers,
    canonical_book_key,
    canonical_video_query_key,
    canonical_youtube_key,
    generate_book_module,
    get_or_create_book_module_resource,
    get_or_create_video_resource,
    material_to_resource_payload,
    get_or_create_content_resource,
    sync_plan_item_content_resource_links,
)


class ScalarResult:
    def __init__(self, value=None):
        self._value = value

    def scalar_one_or_none(self):
        return self._value

    def scalars(self):
        return self

    def all(self):
        if self._value is None:
            return []
        if isinstance(self._value, list):
            return self._value
        return [self._value]


class LLMResponse:
    def __init__(self, data=None, error=None):
        self.data = data or {}
        self.error = error


def _book_module_markdown(title: str, words: int = 3400) -> str:
    return f"# {title}\n\n" + " ".join(["insight"] * words)


def _valid_book_module(title: str = "Deep Work", author: str = "Cal Newport") -> dict:
    sections = []
    markdown_parts = []
    for index in range(6):
        sections.append(
            {
                "title": f"Framework {index + 1}",
                "summary": " ".join(["mechanism"] * 80),
                "exercise": " ".join(["practice"] * 40),
            }
        )
        markdown_parts.append(
            f"## Framework {index + 1}\n\n"
            + " ".join([f"concept{index}"] * 560)
            + "\n\n### Practice This\n1. Apply the framework.\n2. Record the result."
        )
    markdown_parts.append(
        "## Closing Synthesis\n\nConnect the six frameworks into one practice."
    )
    return {
        "title": title,
        "author_or_creator": author,
        "promise": "Apply the book's central framework.",
        "sections": sections,
        "ideas": [
            {"title": f"Idea {index + 1}", "content": " ".join(["application"] * 40)}
            for index in range(7)
        ],
        "content_markdown": f"# {title}\n\n" + "\n\n".join(markdown_parts),
    }


@pytest.mark.parametrize(
    "patches",
    [
        [
            {
                "old_text": "Unrelated prose that exists exactly once.",
                "replacement_text": "A model should not be allowed to alter it.",
            }
        ],
        [
            {
                "old_text": (
                    'The author writes, "This unsupported quotation is deliberately '
                    'long enough for the grounding detector to inspect."'
                ),
                "replacement_text": "The framework was introduced in 2025.",
            }
        ],
        [
            {
                "old_text": (
                    'The author writes, "This unsupported quotation is deliberately '
                    'long enough for the grounding detector to inspect."'
                ),
                "replacement_text": 'A supposedly safe but "short" quoted claim.',
            }
        ],
        [
            {
                "old_text": (
                    '"This unsupported quotation is deliberately long enough for the '
                    'grounding detector to inspect."'
                ),
                "replacement_text": "A cautious interpretation without attribution.",
            }
        ],
    ],
)
def test_grounding_patches_reject_unrelated_targets_or_new_claims(patches):
    markdown = (
        "Unrelated prose that exists exactly once.\n\n"
        'The author writes, "This unsupported quotation is deliberately long enough '
        'for the grounding detector to inspect."'
    )

    assert (
        _apply_book_grounding_patches(
            markdown,
            patches,
            source_context="Publisher metadata with no direct quotations.",
        )
        is None
    )


def test_grounding_patches_reject_supported_marker_bundled_with_valid_repair():
    supported_quote = (
        '"This supported quotation is deliberately long enough for the grounding '
        'detector to inspect correctly."'
    )
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to require a repair."'
    )
    markdown = (
        f"According to the author, {supported_quote}\n\n"
        f"The author writes, {unsupported_quote}"
    )
    patches = [
        {
            "old_text": f"The author writes, {unsupported_quote}",
            "replacement_text": "A cautious interpretation without attribution.",
        },
        {
            "old_text": f"According to the author, {supported_quote}",
            "replacement_text": "An unrelated alteration to supported material.",
        },
    ]

    assert (
        _apply_book_grounding_patches(
            markdown,
            patches,
            source_context=supported_quote,
        )
        is None
    )


def test_grounding_patches_are_atomic_and_cannot_modify_headings():
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to require a repair."'
    )
    markdown = f"## Protected Heading\n\nThe author writes, {unsupported_quote}"
    patches = [
        {
            "old_text": unsupported_quote,
            "replacement_text": (
                "Illustrative example (not a sourced quotation): A cautious practical "
                "interpretation."
            ),
        },
        {
            "old_text": "## Protected Heading",
            "replacement_text": "## Altered Heading",
        },
    ]

    assert (
        _apply_book_grounding_patches(
            markdown,
            patches,
            source_context="Publisher metadata with no direct quotations.",
        )
        is None
    )
    assert markdown.startswith("## Protected Heading")


def test_deterministic_grounding_neutralization_changes_only_unsupported_markers():
    supported_quote = (
        '"This supported quotation is deliberately long enough for the grounding '
        'detector to verify against source text."'
    )
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to neutralize without claiming support."'
    )
    markdown = (
        "## Framework\n\n"
        f"According to the author, {supported_quote}\n\n"
        f"The book says, {unsupported_quote}\n\n"
        "### Practice This\n1. Preserve the structure."
    )

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context=supported_quote,
    )

    assert neutralized is not None
    assert supported_quote in neutralized
    assert unsupported_quote not in neutralized
    assert "Illustrative example (not a sourced quotation):" in neutralized
    assert neutralized.startswith("## Framework\n\n")
    assert "### Practice This" in neutralized


def test_grounding_neutralization_removes_direct_source_attribution_only():
    direct_quote = (
        '"This alleged author quotation is deliberately long enough for the grounding '
        'detector to require transparent neutralization."'
    )
    scenario_quote = (
        '"This hypothetical customer statement is deliberately long enough for the '
        'grounding detector to inspect as an illustrative scenario."'
    )
    suffix_quote = (
        '"This alleged trailing quotation is deliberately long enough for the '
        'grounding detector to require transparent neutralization."'
    )
    markdown = (
        f"The author writes, {direct_quote}\n\n"
        f"When a customer says, {scenario_quote}\n\n"
        f"{suffix_quote}, the book argues."
    )

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is not None
    assert "The author writes" not in neutralized
    assert "the book argues" not in neutralized
    assert "When a customer says" in neutralized
    assert scenario_quote in neutralized
    assert neutralized.count("not a sourced quotation") == 2
    assert "For illustration," in neutralized


@pytest.mark.parametrize(
    "attributed_template",
    [
        "According to Rob Fitzpatrick, {quote}",
        "Rob Fitzpatrick said, {quote}",
        "The author writes in the book, {quote}",
        "{quote}, writes the author",
        "{quote}, according to Rob Fitzpatrick",
        "In the book, the author writes, {quote}",
        "According to research by Rob Fitzpatrick, {quote}",
        "According to McKinsey & Company, {quote}",
        "Rob Fitzpatrick famously writes, {quote}",
        "As the book clearly argues, {quote}",
    ],
)
def test_grounding_neutralization_covers_common_direct_source_forms(
    attributed_template,
):
    unsupported_quote = (
        '"This alleged source quotation is deliberately long enough for the grounding '
        'detector to require honest neutralization."'
    )
    markdown = attributed_template.format(quote=unsupported_quote)

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is not None
    assert unsupported_quote not in neutralized
    assert "not a sourced quotation" in neutralized
    assert "Rob Fitzpatrick" not in neutralized
    assert "author writes" not in neutralized.casefold()
    assert "writes the author" not in neutralized.casefold()
    assert "according to" not in neutralized.casefold()
    assert "the book" not in neutralized.casefold()
    assert "famously writes" not in neutralized.casefold()


def test_grounding_patch_rejects_arbitrary_fact_behind_transparency_label():
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to reject an invented replacement fact."'
    )
    markdown = f"The author writes, {unsupported_quote}"

    assert (
        _apply_book_grounding_patches(
            markdown,
            [
                {
                    "old_text": unsupported_quote,
                    "replacement_text": (
                        "*Illustrative example (not a sourced quotation): Paris is "
                        "the capital of Mars according to a definitive study.*"
                    ),
                }
            ],
            source_context="Publisher metadata with no direct quotations.",
        )
        is None
    )


def test_grounding_neutralization_handles_duplicate_and_overlapping_markers():
    repeated_quote = (
        '"This repeated unsupported quotation is deliberately long enough for the grounding '
        'detector to test duplicate and overlapping markers."'
    )
    markdown = (
        f"The author writes, {repeated_quote}\n\nWhen a customer says, {repeated_quote}"
    )

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is not None
    assert repeated_quote not in neutralized
    assert neutralized.count("not a sourced quotation") == 2
    assert "The author writes" not in neutralized
    assert "When a customer says" in neutralized


def test_grounding_neutralization_handles_two_quotes_in_one_attributed_line_atomically():
    first_quote = (
        '"This first unsupported quotation is deliberately long enough for the '
        'grounding detector to exercise atomic line handling."'
    )
    second_quote = (
        '"This second unsupported quotation is deliberately long enough for the '
        'grounding detector to preserve every marker without corruption."'
    )
    markdown = (
        f"According to research by Rob Fitzpatrick, {first_quote} while "
        f"{second_quote} illustrates the contrast."
    )

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is None
    assert "while" in markdown
    assert "illustrates the contrast." in markdown
    assert first_quote in markdown
    assert second_quote in markdown


@pytest.mark.parametrize(
    "markdown",
    [
        (
            "According to Rob Fitzpatrick,\n"
            '"This hard-wrapped unsupported quotation is deliberately long enough '
            'for the grounding detector to reject safely."'
        ),
        (
            '"This hard-wrapped unsupported quotation is deliberately long enough '
            'for the grounding detector to reject safely."\n'
            "according to Rob Fitzpatrick"
        ),
    ],
)
def test_grounding_neutralization_rejects_cross_line_attribution(markdown):
    assert (
        _neutralize_unsupported_grounding_markers(
            markdown,
            source_context="Publisher metadata with no direct quotations.",
        )
        is None
    )


def test_grounding_neutralization_rejects_attributed_line_with_unrelated_prose():
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to protect neighboring instructions."'
    )
    markdown = (
        "1. Keep this safety instruction. According to the author, "
        f"{unsupported_quote} Never skip verification."
    )

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is None
    assert markdown.startswith("1. Keep this safety instruction.")
    assert markdown.endswith("Never skip verification.")


def test_grounding_neutralization_preserves_markdown_prefix_for_pure_attribution():
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to preserve its list structure."'
    )
    markdown = f"1. According to the author, {unsupported_quote}"

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is not None
    assert neutralized.startswith("1. For illustration, ")
    assert "not a sourced quotation" in neutralized


def test_grounding_neutralization_preserves_inner_markdown_without_outer_emphasis():
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough and ends with an '
        'emphasized *warning*"'
    )
    markdown = f"The author writes, {unsupported_quote}"

    neutralized = _neutralize_unsupported_grounding_markers(
        markdown,
        source_context="Publisher metadata with no direct quotations.",
    )

    assert neutralized is not None
    assert neutralized.endswith("emphasized *warning*")
    assert neutralized.count("*") == 2


def test_grounding_neutralization_rejects_ambiguous_curly_single_quote_prose():
    markdown = (
        "The author writes, ‘This unsupported quotation has enough words and ends "
        "with customers’ says the editor, who calls it ‘wrong’."
    )

    assert (
        _neutralize_unsupported_grounding_markers(
            markdown,
            source_context="Publisher metadata with no direct quotations.",
        )
        is None
    )
    assert "says the editor" in markdown
    assert "calls it ‘wrong’" in markdown


def test_grounding_markers_use_exact_known_book_title_credit():
    unsupported_quote = (
        '"This unsupported title-attributed quotation is deliberately long enough for '
        'the grounding detector to require source support."'
    )
    markdown = f"Good to Great: {unsupported_quote}"

    markers = _unsupported_grounding_markers(
        markdown,
        "Publisher metadata with no direct quotations.",
        ("Good to Great", "Jim Collins"),
    )

    assert markers == {unsupported_quote}


@pytest.mark.parametrize(
    "template",
    [
        "**Important Safety Rule:** According to the author, {quote}",
        "CRM Checklist: According to the author, {quote}",
        "Never Skip Verification: According to the author, {quote}",
        "Practice Note: According to the author, {quote}",
        "Never Skip Verification: {quote}",
        "CRM Checklist: {quote}",
        "- [ ] According to the author, {quote}",
        "| According to the author, {quote} |",
        "## According to the author, {quote}",
        "> - According to the author, {quote}",
    ],
)
def test_grounding_neutralization_rejects_structured_or_titled_attribution(template):
    unsupported_quote = (
        '"This unsupported quotation is deliberately long enough for the grounding '
        'detector to preserve all surrounding structure."'
    )
    markdown = template.format(quote=unsupported_quote)

    assert (
        _neutralize_unsupported_grounding_markers(
            markdown,
            source_context="Publisher metadata with no direct quotations.",
        )
        is None
    )
    assert unsupported_quote in markdown


@pytest.mark.parametrize(
    "markdown",
    [
        (
            "See [the 2024 report](https://example.com/reports/2024/summary) and "
            "[the 2023 archive](https://example.com/2023/archive)."
        ),
        "Compare SKU-2024 with SKU-2023 before changing inventory records.",
        "Keep `release-2024` distinct from `release-2023` in the command.",
        "<meta data-start=2024 data-end=2023>",
        "```text\nrelease 2024 follows release 2023\n```",
        "[2024]: https://example.com/report\n[2023]: https://example.com/archive",
        "Compare report.2024.pdf with archive.2023.pdf before publishing.",
        "Contact 2024@example.com or 2023@example.com for the archives.",
        "Compare case:2024 with case:2023 before changing identifiers.",
        "\trelease 2024 follows release 2023",
        "````text\n```\nrelease 2024 follows release 2023\n````",
        "The 2024 plan superseded the 2023 plan.",
        "A 2024 study updated a 2023 report.",
        "Its 2024 version replaced its 2023 version.",
    ],
)
def test_grounding_neutralization_never_rewrites_link_code_or_identifier_years(
    markdown,
):
    assert (
        _neutralize_unsupported_grounding_markers(
            markdown,
            source_context="Publisher metadata without dates.",
        )
        is None
    )
    assert "2024" in markdown
    assert "2023" in markdown


@pytest.mark.asyncio
async def test_book_generation_has_an_end_to_end_deadline(monkeypatch):
    from app.services import content_resources as service

    cancelled = asyncio.Event()

    async def never_finishes(**_kwargs):
        try:
            await asyncio.Future()
        finally:
            cancelled.set()

    monkeypatch.setattr(service, "_generate_book_module_unbounded", never_finishes)
    monkeypatch.setattr(service, "BOOK_MODULE_TOTAL_TIMEOUT_SECONDS", 0.01)

    with pytest.raises(RuntimeError, match="overall provider deadline"):
        await service.generate_book_module(
            title="Deep Work",
            author="Cal Newport",
            user_goal="focus better",
        )

    assert cancelled.is_set()
    assert BOOK_MODULE_TOTAL_TIMEOUT_SECONDS < 600


def test_canonical_book_key_is_stable_for_title_and_author_variants():
    assert (
        canonical_book_key("The Intelligent Investor", "Benjamin Graham")
        == "book:benjamin_graham:the_intelligent_investor"
    )
    assert (
        canonical_book_key("  the intelligent investor! ", " Benjamin  Graham ")
        == "book:benjamin_graham:the_intelligent_investor"
    )


def test_canonical_youtube_key_uses_video_id_only():
    assert (
        canonical_youtube_key("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=12s")
        == "youtube:dQw4w9WgXcQ"
    )


def test_canonical_video_query_key_is_stable():
    assert (
        canonical_video_query_key("  Warren Buffett margin of safety interview!! ")
        == "youtube_query:warren_buffett_margin_of_safety_interview"
    )
    assert (
        canonical_youtube_key("https://youtu.be/dQw4w9WgXcQ?si=abc")
        == "youtube:dQw4w9WgXcQ"
    )


def test_material_to_resource_payload_keeps_in_app_lesson_distinct_from_book():
    payload = material_to_resource_payload(
        {
            "title": "The Intelligent Investor",
            "type": "in_app_lesson",
            "author": "Benjamin Graham",
            "content_markdown": "# Defensive Investing\n\nA compact lesson.",
            "duration_minutes": 15,
            "ideas": [{"title": "Margin", "content": "Protect downside."}],
        }
    )

    assert payload is not None
    assert payload["kind"] == ContentResourceKind.IN_APP_LESSON
    assert payload["canonical_key"] == "in_app_lesson:the_intelligent_investor"
    assert payload["summary_json"]["ideas"][0]["title"] == "Margin"


def test_material_to_resource_payload_rejects_short_book_summary():
    assert (
        material_to_resource_payload(
            {
                "title": "Deep Work",
                "type": "book",
                "author": "Cal Newport",
                "content_markdown": "short " * 500,
                "ideas": [{"title": "Depth"}],
            }
        )
        is None
    )


@pytest.mark.asyncio
async def test_generate_book_module_retries_until_prd_minimum(monkeypatch):
    """Book modules below 3,200 words should trigger the stronger retry."""
    calls = []

    class Client:
        async def generate_json(self, **kwargs):
            calls.append(kwargs["user_prompt"])
            if len(calls) == 1:
                return LLMResponse(
                    {
                        "title": "Deep Work",
                        "author_or_creator": "Cal Newport",
                        "content_markdown": "word " * 2000,
                        "sections": [],
                        "ideas": [],
                    }
                )
            return LLMResponse(_valid_book_module())

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        lambda **kwargs: Client(),
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
    )

    assert len(calls) == 2
    assert len(result["content_markdown"].split()) >= 3200
    assert result["duration_minutes"] == 17
    assert result["quality_report"]["passed"] is True


@pytest.mark.asyncio
async def test_generate_book_module_prefers_equal_score_passing_rewrite(monkeypatch):
    """A binary structure repair must win even when its score is unchanged."""
    invalid = _valid_book_module()
    invalid["content_markdown"] = invalid["content_markdown"].replace(
        "## Closing Synthesis",
        "## Seven-Day Integration",
    )
    valid = _valid_book_module()
    calls = 0

    class Client:
        async def generate_json(self, **_kwargs):
            nonlocal calls
            calls += 1
            return LLMResponse(invalid if calls == 1 else valid)

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        lambda **_kwargs: Client(),
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
    )

    assert calls == 2
    assert "## Closing Synthesis" in result["content_markdown"]
    assert result["quality_report"]["passed"] is True


@pytest.mark.asyncio
async def test_generate_book_module_repairs_metadata_without_regenerating_lesson(
    monkeypatch,
):
    draft = _valid_book_module()
    draft["ideas"] = [
        {"title": f"Idea {index + 1}", "content": "Too short.", "category": "Strategy"}
        for index in range(6)
    ]
    calls = []

    class BalancedClient:
        async def generate_json(self, **kwargs):
            calls.append("balanced")
            return LLMResponse(draft)

    class FastClient:
        async def generate_json(self, **kwargs):
            calls.append("fast")
            return LLMResponse(
                {
                    "sections": draft["sections"],
                    "ideas": [
                        {
                            "title": f"Idea {index + 1}",
                            "content": " ".join(["application"] * 40),
                            "category": "Strategy",
                        }
                        for index in range(6)
                    ],
                }
            )

    def client_factory(**kwargs):
        tier = kwargs.get("tier")
        if tier == "balanced":
            return BalancedClient()
        if tier == "fast":
            return FastClient()
        raise AssertionError("quality tier must not rewrite a sound long lesson")

    monkeypatch.setattr("app.services.llm.client.get_llm_client", client_factory)

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="understand focused work",
    )

    assert calls == ["balanced", "fast"]
    assert result["quality_report"]["passed"] is True
    assert result["content_markdown"] == draft["content_markdown"]


@pytest.mark.asyncio
async def test_generate_book_module_repairs_live_shaped_mixed_defects_without_pro(
    monkeypatch,
):
    """Keep a sound long core while fixing thin metadata and eight unsafe quotes."""
    draft = _valid_book_module(title="The Mom Test", author="Rob Fitzpatrick")
    draft["sections"][0]["exercise"] = "Too short."
    for idea in draft["ideas"]:
        idea["content"] = "Too short."

    unsupported_claims = [
        (
            f'The author writes, "Unsupported claim number '
            f"{index} contains enough "
            'words to trigger the attributed quotation grounding check."'
        )
        for index in range(1, 9)
    ]
    unsupported_markers = [claim[claim.index('"') :] for claim in unsupported_claims]
    insertion = "\n\n".join(unsupported_claims) + "\n\n"
    draft["content_markdown"] = draft["content_markdown"].replace(
        "## Framework 1\n\n",
        "## Framework 1\n\n" + insertion,
        1,
    )

    repaired_sections = [dict(section) for section in draft["sections"]]
    repaired_sections[0]["exercise"] = " ".join(["practice"] * 40)
    repaired_ideas = [
        {
            **idea,
            "content": " ".join([f"application{index}"] * 40),
            "category": "Strategy",
        }
        for index, idea in enumerate(draft["ideas"], start=1)
    ]
    replacements = [
        f"Illustrative example (not a sourced quotation): {marker[1:-1]}"
        for marker in unsupported_markers
    ]
    client_options = []
    calls = []

    class Client:
        def __init__(self, tier):
            self.tier = tier
            self.model = f"{tier}-model"

        async def generate_json(self, **kwargs):
            output_model = kwargs["output_model"]
            calls.append((self.tier, output_model))
            if output_model is BookModuleOutput:
                if self.tier == "quality":
                    raise AssertionError("targeted repairs should avoid a Pro rewrite")
                return LLMResponse(draft)
            if output_model is BookModuleMetadataOutput:
                return LLMResponse(
                    {
                        "sections": repaired_sections,
                        "ideas": repaired_ideas,
                    }
                )
            if output_model is BookModuleGroundingRepairOutput:
                prompt_payload = json.loads(kwargs["user_prompt"].split("\n\n", 1)[1])
                assert set(prompt_payload["exact_unsupported_markers"]) == set(
                    unsupported_markers
                )
                return LLMResponse(
                    {
                        "patches": [
                            {
                                "old_text": old_text,
                                "replacement_text": replacement_text,
                            }
                            for old_text, replacement_text in zip(
                                unsupported_markers,
                                replacements,
                                strict=True,
                            )
                        ]
                    }
                )
            raise AssertionError(f"unexpected output model: {output_model}")

    def client_factory(**kwargs):
        client_options.append(kwargs)
        return Client(kwargs.get("tier", "balanced"))

    async def choose_balanced(**_kwargs):
        return SimpleNamespace(tier="balanced", reason="test_balanced")

    monkeypatch.setattr("app.services.llm.client.get_llm_client", client_factory)
    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_balanced,
    )

    result = await generate_book_module(
        title="The Mom Test",
        author="Rob Fitzpatrick",
        user_goal="ask better customer questions",
        source_context="Publisher metadata with no direct quotations.",
    )

    assert result["quality_report"]["passed"] is True
    assert result["quality_report"]["metrics"]["unmatched_attributed_quote_count"] == 0
    assert all(claim not in result["content_markdown"] for claim in unsupported_claims)
    assert all(
        replacement in result["content_markdown"] for replacement in replacements
    )
    assert [output_model for _, output_model in calls] == [
        BookModuleOutput,
        BookModuleMetadataOutput,
        BookModuleGroundingRepairOutput,
    ]
    assert [options["tier"] for options in client_options] == [
        "balanced",
        "fast",
        "balanced",
    ]
    assert not any(options["tier"] == "quality" for options in client_options)


@pytest.mark.asyncio
async def test_generate_book_module_uses_bounded_quality_fallback_options(monkeypatch):
    short = _valid_book_module()
    short["content_markdown"] = "word " * 500
    valid = _valid_book_module()
    client_options = []
    generation_count = 0

    class Client:
        def __init__(self, tier):
            self.tier = tier

        async def generate_json(self, **kwargs):
            nonlocal generation_count
            assert kwargs["output_model"] is BookModuleOutput
            generation_count += 1
            return LLMResponse(valid if self.tier == "quality" else short)

    def client_factory(**kwargs):
        client_options.append(kwargs)
        return Client(kwargs.get("tier", "balanced"))

    async def choose_balanced(**_kwargs):
        return SimpleNamespace(tier="balanced", reason="test_balanced")

    monkeypatch.setattr("app.services.llm.client.get_llm_client", client_factory)
    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_balanced,
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
    )

    quality_options = [
        options for options in client_options if options.get("tier") == "quality"
    ]
    assert generation_count == 3
    assert quality_options == [
        {
            "timeout": BOOK_MODULE_QUALITY_TIMEOUT_SECONDS,
            "max_tokens": 16000,
            "tier": "quality",
            "thinking_level": "low",
            "temperature": 0.15,
            "allow_fallback": True,
        }
    ]
    assert result["quality_report"]["passed"] is True


@pytest.mark.asyncio
async def test_invalid_grounding_patch_uses_exact_deterministic_neutralization(
    monkeypatch,
):
    draft = _valid_book_module()
    unsupported_claim = (
        'The author writes, "This unsupported quotation has enough words to trigger '
        'the attributed quotation grounding check in production."'
    )
    draft["content_markdown"] = draft["content_markdown"].replace(
        "## Framework 1\n\n",
        f"## Framework 1\n\n{unsupported_claim}\n\n",
        1,
    )
    calls = []
    book_generation_count = 0

    class Client:
        async def generate_json(self, **kwargs):
            nonlocal book_generation_count
            output_model = kwargs["output_model"]
            calls.append(output_model)
            if output_model is BookModuleGroundingRepairOutput:
                return LLMResponse(
                    {
                        "patches": [
                            {
                                "old_text": "text that is not present",
                                "replacement_text": "A cautious replacement.",
                            }
                        ]
                    }
                )
            assert output_model is BookModuleOutput
            book_generation_count += 1
            return LLMResponse(draft)

    async def choose_balanced(**_kwargs):
        return SimpleNamespace(tier="balanced", reason="test_balanced")

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client", lambda **_kwargs: Client()
    )
    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_balanced,
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_context="Publisher metadata with no direct quotations.",
    )

    assert calls == [
        BookModuleOutput,
        BookModuleGroundingRepairOutput,
    ]
    assert book_generation_count == 1
    assert unsupported_claim not in result["content_markdown"]
    assert (
        "Illustrative example (not a sourced quotation):" in result["content_markdown"]
    )
    assert result["quality_report"]["passed"] is True
    grounding_call = result["quality_report"]["generation"]["calls"][1]
    assert grounding_call["result_status"] == "quality_passed"
    assert grounding_call["repair_mode"] == "deterministic_neutralization"


@pytest.mark.asyncio
async def test_deterministic_neutralization_cannot_bypass_maximum_word_gate(
    monkeypatch,
):
    draft = _valid_book_module()
    unsupported_claim = (
        'The author writes, "This unsupported quotation has enough words to trigger '
        'the attributed quotation grounding check near the maximum length."'
    )
    draft["content_markdown"] = draft["content_markdown"].replace(
        "## Framework 1\n\n",
        f"## Framework 1\n\n{unsupported_claim}\n\n",
        1,
    )
    filler_count = 4499 - len(draft["content_markdown"].split())
    assert filler_count > 0
    draft["content_markdown"] = draft["content_markdown"].replace(
        "\n\n## Closing Synthesis",
        "\n\n" + " ".join(["boundaryword"] * filler_count) + "\n\n## Closing Synthesis",
        1,
    )
    assert len(draft["content_markdown"].split()) == 4499
    valid = _valid_book_module()
    calls = []
    book_generation_count = 0

    class Client:
        async def generate_json(self, **kwargs):
            nonlocal book_generation_count
            output_model = kwargs["output_model"]
            calls.append(output_model)
            if output_model is BookModuleGroundingRepairOutput:
                return LLMResponse(
                    {
                        "patches": [
                            {
                                "old_text": "not an exact marker",
                                "replacement_text": (
                                    "Illustrative example (not a sourced quotation): "
                                    "A cautious interpretation."
                                ),
                            }
                        ]
                    }
                )
            assert output_model is BookModuleOutput
            book_generation_count += 1
            return LLMResponse(draft if book_generation_count == 1 else valid)

    async def choose_balanced(**_kwargs):
        return SimpleNamespace(tier="balanced", reason="test_balanced")

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client", lambda **_kwargs: Client()
    )
    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_balanced,
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_context="Publisher metadata with no direct quotations.",
    )

    assert calls == [
        BookModuleOutput,
        BookModuleGroundingRepairOutput,
        BookModuleOutput,
    ]
    assert result["content_markdown"] == valid["content_markdown"]
    assert result["quality_report"]["passed"] is True
    grounding_call = result["quality_report"]["generation"]["calls"][1]
    assert grounding_call["result_status"] == "patch_validation_failed"


@pytest.mark.asyncio
async def test_pro_fallback_receives_same_bounded_preservation_repairs(monkeypatch):
    short = _valid_book_module()
    short["content_markdown"] = "word " * 500
    pro_draft = _valid_book_module()
    pro_draft["ideas"][0]["content"] = "Too short."
    unsupported_claim = (
        'The author writes, "This unsupported quotation has enough words to trigger '
        'the attributed quotation grounding check after the Pro rewrite."'
    )
    unsupported_marker = unsupported_claim[unsupported_claim.index('"') :]
    replacement = (
        f"Illustrative example (not a sourced quotation): {unsupported_marker[1:-1]}"
    )
    pro_draft["content_markdown"] = pro_draft["content_markdown"].replace(
        "## Framework 1\n\n",
        f"## Framework 1\n\n{unsupported_claim}\n\n",
        1,
    )
    repaired_ideas = [dict(idea) for idea in pro_draft["ideas"]]
    repaired_ideas[0]["content"] = " ".join(["application"] * 40)
    client_options = []
    book_generation_count = 0

    class Client:
        def __init__(self, tier):
            self.tier = tier

        async def generate_json(self, **kwargs):
            nonlocal book_generation_count
            output_model = kwargs["output_model"]
            if output_model is BookModuleMetadataOutput:
                return LLMResponse(
                    {
                        "sections": pro_draft["sections"],
                        "ideas": repaired_ideas,
                    }
                )
            if output_model is BookModuleGroundingRepairOutput:
                return LLMResponse(
                    {
                        "patches": [
                            {
                                "old_text": unsupported_marker,
                                "replacement_text": replacement,
                            }
                        ]
                    }
                )
            assert output_model is BookModuleOutput
            book_generation_count += 1
            return LLMResponse(pro_draft if self.tier == "quality" else short)

    def client_factory(**kwargs):
        client_options.append(kwargs)
        return Client(kwargs.get("tier", "balanced"))

    async def choose_balanced(**_kwargs):
        return SimpleNamespace(tier="balanced", reason="test_balanced")

    monkeypatch.setattr("app.services.llm.client.get_llm_client", client_factory)
    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_balanced,
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_context="Publisher metadata with no direct quotations.",
    )

    stages = [call["stage"] for call in result["quality_report"]["generation"]["calls"]]
    assert stages == [
        "draft",
        "quality_retry",
        "quality_fallback",
        "metadata_repair",
        "grounding_repair",
    ]
    assert book_generation_count == 3
    assert result["quality_report"]["passed"] is True
    assert unsupported_claim not in result["content_markdown"]
    assert replacement in result["content_markdown"]
    quality_options = [
        options for options in client_options if options.get("tier") == "quality"
    ]
    assert quality_options[0]["timeout"] == BOOK_MODULE_QUALITY_TIMEOUT_SECONDS
    assert quality_options[0]["thinking_level"] == "low"


@pytest.mark.asyncio
async def test_fast_book_canary_falls_back_to_balanced_on_quality_failure(monkeypatch):
    from app.services.llm.client import LLMResponse
    from app.services.llm.routing import RoutingDecision, RoutingStats

    calls = []

    class Client:
        def __init__(self, tier):
            self.tier = tier
            self.model = None

        async def generate_json(self, **kwargs):
            calls.append(self.tier)
            if self.tier == "fast":
                return LLMResponse(
                    data={
                        "title": "Deep Work",
                        "author_or_creator": "Cal Newport",
                        "content_markdown": "thin " * 1500,
                        "sections": [],
                        "ideas": [],
                    },
                )
            return LLMResponse(data=_valid_book_module())

    async def choose_canary(**kwargs):
        return RoutingDecision(
            tier="fast",
            reason="fast_canary",
            fast_model="fast-model",
            stats=RoutingStats(),
            exploration_bucket=1,
        )

    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_canary,
    )
    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        lambda **kwargs: Client(kwargs.get("tier", "balanced")),
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="understand focused work",
    )

    assert calls == ["fast", "balanced"]
    assert result["quality_report"]["passed"] is True
    stages = result["quality_report"]["generation"]["calls"]
    assert stages[0]["routing_reason"] == "fast_canary"
    assert stages[0]["quality_score"] < 0.85
    assert stages[1]["routing_reason"] == "fast_quality_fallback"
    assert stages[1]["quality_score"] >= 0.85


def test_material_to_resource_payload_converts_valid_youtube_video():
    payload = material_to_resource_payload(
        {
            "title": "Buffett on Safety",
            "type": "video",
            "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "reason": "Explains margin of safety.",
        }
    )

    assert payload is not None
    assert payload["kind"] == ContentResourceKind.VIDEO
    assert payload["license_status"] == LicenseStatus.EXTERNAL_LINK
    assert payload["canonical_key"] == "youtube:dQw4w9WgXcQ"


def test_material_to_resource_payload_converts_article_material():
    payload = material_to_resource_payload(
        {
            "title": "How to Practice Deliberately",
            "type": "article",
            "url": "https://example.com/deliberate-practice",
            "reason": "Useful guided learning source.",
            "content_markdown": "# Deliberate practice\n\nA complete in-app article.",
        }
    )

    assert payload is not None
    assert payload["kind"] == ContentResourceKind.ARTICLE
    assert payload["license_status"] == LicenseStatus.EXTERNAL_LINK
    assert payload["canonical_key"] == "article:how_to_practice_deliberately"
    assert payload["metadata_json"]["reason"] == "Useful guided learning source."


def test_material_to_resource_payload_rejects_metadata_only_external_course():
    assert (
        material_to_resource_payload(
            {
                "title": "Introduction to Business Analytics",
                "type": "course",
                "url": "https://www.coursera.org/search?query=business+analytics",
                "reason": "A useful external course recommendation.",
                "duration_minutes": 120,
            }
        )
        is None
    )


@pytest.mark.asyncio
async def test_get_or_create_content_resource_reuses_existing_record():
    existing = AsyncMock()
    existing.id = "resource-1"
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    result = await get_or_create_content_resource(
        db,
        kind=ContentResourceKind.VIDEO,
        canonical_key="youtube:dQw4w9WgXcQ",
        title="Buffett on Safety",
        license_status=LicenseStatus.EXTERNAL_LINK,
    )

    assert result is existing
    db.add.assert_not_called()
    db.flush.assert_not_called()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_reuses_existing_without_generation():
    existing = MagicMock()
    existing.id = "book-resource-1"
    existing.content_markdown = "word " * 3400
    existing.status = CatalogStatus.PUBLISHED
    existing.metadata_json = {
        "quality_report": {
            "passed": True,
            "gate_version": BOOK_MODULE_QUALITY_GATE_VERSION,
        }
    }
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    async def factory(**kwargs):
        raise AssertionError("factory should not run when the book module exists")

    result = await get_or_create_book_module_resource(
        db,
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        module_factory=factory,
    )

    assert result is existing
    db.add.assert_not_called()
    db.flush.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("old_passed", [False, True])
async def test_get_or_create_book_module_resource_revalidates_sound_flagged_cache(
    old_passed,
):
    module = _valid_book_module("The Mom Test", "Rob Fitzpatrick")
    existing = MagicMock()
    existing.id = "book-resource-1"
    existing.title = "The Mom Test"
    existing.author_or_creator = "Rob Fitzpatrick"
    existing.content_markdown = module["content_markdown"]
    existing.summary_json = {
        "sections": module["sections"],
        "ideas": module["ideas"],
    }
    existing.metadata_json = {
        "quality_report": {
            "passed": old_passed,
            "generation": {"call_count": 3},
        }
    }
    existing.status = CatalogStatus.FLAGGED
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    async def source_lookup(**_kwargs):
        return {
            "title": "The Mom Test",
            "author_or_creator": "Rob Fitzpatrick",
            "source_context": "Verified catalog metadata without direct quotations.",
            "metadata_json": {"provider": "catalog"},
        }

    async def factory(**_kwargs):
        raise AssertionError("a sound cached module should not be regenerated")

    result = await get_or_create_book_module_resource(
        db,
        title="The Mom Test",
        author="Rob Fitzpatrick",
        user_goal="ask better customer questions",
        source_lookup=source_lookup,
        module_factory=factory,
    )

    assert result is existing
    assert existing.status == CatalogStatus.PUBLISHED
    assert existing.metadata_json["quality_report"]["passed"] is True
    assert existing.metadata_json["quality_report"]["score"] == 1.0
    assert existing.metadata_json["quality_report"]["generation"] == {"call_count": 3}
    assert existing.metadata_json["quality_revalidated"] is True
    db.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_revalidates_stale_published_cache():
    stale = _valid_book_module("The Mom Test", "Rob Fitzpatrick")
    unsupported_claim = (
        'The author writes, "This stale unsupported quotation contains enough words '
        'for the current grounding gate to reject it safely."'
    )
    stale["content_markdown"] = stale["content_markdown"].replace(
        "## Framework 1\n\n",
        f"## Framework 1\n\n{unsupported_claim}\n\n",
        1,
    )
    replacement = _valid_book_module("The Mom Test", "Rob Fitzpatrick")
    existing = MagicMock()
    existing.id = "book-resource-1"
    existing.title = stale["title"]
    existing.author_or_creator = stale["author_or_creator"]
    existing.content_markdown = stale["content_markdown"]
    existing.summary_json = {
        "sections": stale["sections"],
        "ideas": stale["ideas"],
    }
    existing.metadata_json = {"quality_report": {"passed": True}}
    existing.status = CatalogStatus.PUBLISHED
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)
    factory_calls = []

    async def source_lookup(**_kwargs):
        return {
            "title": "The Mom Test",
            "author_or_creator": "Rob Fitzpatrick",
            "source_context": "Verified catalog metadata without direct quotations.",
            "metadata_json": {"provider": "catalog"},
        }

    async def factory(**kwargs):
        factory_calls.append(kwargs)
        return replacement

    result = await get_or_create_book_module_resource(
        db,
        title="The Mom Test",
        author="Rob Fitzpatrick",
        user_goal="ask better customer questions",
        source_lookup=source_lookup,
        module_factory=factory,
    )

    assert result is existing
    assert len(factory_calls) == 1
    assert unsupported_claim not in existing.content_markdown
    assert existing.status == CatalogStatus.PUBLISHED
    assert (
        existing.metadata_json["quality_report"]["gate_version"]
        == BOOK_MODULE_QUALITY_GATE_VERSION
    )


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_generates_and_saves_once_when_missing():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)
    factory_calls = []

    async def factory(**kwargs):
        factory_calls.append(kwargs)
        return _valid_book_module()

    async def no_source(**kwargs):
        return None

    result = await get_or_create_book_module_resource(
        db,
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_context="Catalog overview supplied during idle discovery.",
        source_lookup=no_source,
        module_factory=factory,
    )

    assert len(factory_calls) == 1
    assert factory_calls[0]["title"] == "Deep Work"
    assert factory_calls[0]["author"] == "Cal Newport"
    assert factory_calls[0]["source_context"] == (
        "Catalog overview supplied during idle discovery."
    )
    assert result.canonical_key == "book:cal_newport:deep_work"
    assert result.kind == ContentResourceKind.LLM_BOOK_SUMMARY
    assert result.license_status == LicenseStatus.LLM_SUMMARY
    assert result.is_public_domain is False
    assert result.duration_minutes == 17
    assert result.content_markdown.startswith("# Deep Work")
    assert result.summary_json["ideas"][0]["title"] == "Idea 1"
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_caller_plan_prose_cannot_serve_as_book_grounding_evidence():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)
    quotation = "A fabricated quotation copied from recommendation prose"
    module = _valid_book_module("Deep Work", "Cal Newport")
    module["content_markdown"] = module["content_markdown"].replace(
        "## Framework 1\n\n",
        f'## Framework 1\n\nThe author writes, "{quotation}."\n\n',
        1,
    )

    async def no_source(**_kwargs):
        return None

    async def factory(**kwargs):
        assert quotation in kwargs["source_context"]
        return module

    resource = await get_or_create_book_module_resource(
        db,
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_context=f'Recommendation reason: "{quotation}."',
        source_lookup=no_source,
        module_factory=factory,
    )

    quality = resource.metadata_json["quality_report"]
    assert resource.status == CatalogStatus.FLAGGED
    assert quality["passed"] is False
    assert quality["metrics"]["unmatched_attributed_quote_count"] == 1


@pytest.mark.asyncio
async def test_long_source_text_still_requires_a_quality_checked_book_module():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)
    factory_calls = []

    async def source_lookup(**_kwargs):
        return {
            "title": "Meditations",
            "author_or_creator": "Marcus Aurelius",
            "source_url": "https://www.gutenberg.org/ebooks/2680",
            "license_status": "public_domain",
            "content_markdown": "raw source word " * 1200,
            "metadata_json": {"provider": "gutenberg"},
        }

    async def factory(**kwargs):
        factory_calls.append(kwargs)
        return _valid_book_module("Meditations", "Marcus Aurelius")

    resource = await get_or_create_book_module_resource(
        db,
        title="Meditations",
        author="Marcus Aurelius",
        user_goal="practice resilience",
        source_lookup=source_lookup,
        module_factory=factory,
    )

    assert len(factory_calls) == 1
    assert resource.content_markdown.startswith("# Meditations")
    assert resource.content_markdown != "raw source word " * 1200
    assert resource.metadata_json["quality_report"]["passed"] is True
    assert (
        resource.metadata_json["quality_report"]["gate_version"]
        == BOOK_MODULE_QUALITY_GATE_VERSION
    )


@pytest.mark.asyncio
async def test_book_module_upgrade_never_writes_null_public_domain_flag():
    existing = MagicMock()
    existing.id = "legacy-book-resource"
    existing.content_markdown = "thin"
    existing.status = CatalogStatus.PENDING
    existing.metadata_json = {}
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    async def factory(**kwargs):
        return _valid_book_module(kwargs["title"], kwargs["author"])

    async def no_source(**kwargs):
        return None

    result = await get_or_create_book_module_resource(
        db,
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_lookup=no_source,
        module_factory=factory,
    )

    assert result is existing
    assert existing.is_public_domain is False
    db.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_grounds_public_domain_source_before_llm():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def source_lookup(**kwargs):
        assert kwargs["title"] == "Meditations"
        assert kwargs["author"] == "Marcus Aurelius"
        return {
            "title": "Meditations",
            "author_or_creator": "Marcus Aurelius",
            "source_url": "https://www.gutenberg.org/ebooks/2680",
            "license_status": "public_domain",
            "content_markdown": None,
            "source_context": "A sampled passage from the public-domain source.",
            "summary_json": {"source": "project_gutenberg"},
            "duration_minutes": 15,
            "metadata_json": {"provider": "gutenberg"},
        }

    async def factory(**kwargs):
        assert "sampled passage" in kwargs["source_context"]
        return _valid_book_module("Meditations", "Marcus Aurelius")

    result = await get_or_create_book_module_resource(
        db,
        title="Meditations",
        author="Marcus Aurelius",
        user_goal="practice resilience",
        source_lookup=source_lookup,
        module_factory=factory,
    )

    assert result.kind == ContentResourceKind.PUBLIC_DOMAIN_BOOK
    assert result.license_status == LicenseStatus.PUBLIC_DOMAIN
    assert result.source_url == "https://www.gutenberg.org/ebooks/2680"
    assert result.content_markdown.startswith("# Meditations")
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_attach_content_resources_generates_missing_book_module():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def factory(**kwargs):
        return _valid_book_module(kwargs["title"], kwargs["author"])

    async def no_source(**kwargs):
        return None

    materials = await attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "kind": "book",
                "author_or_creator": "James Clear",
                "search_query": "Atomic Habits James Clear",
            }
        ],
        user_goal="build better routines",
        book_source_lookup=no_source,
        book_module_factory=factory,
    )

    assert materials[0]["content_resource_id"] == db.add.call_args.args[0].id
    assert materials[0]["canonical_key"] == "book:james_clear:atomic_habits"
    assert materials[0]["content_markdown"].startswith("# Atomic Habits")
    assert materials[0]["duration_minutes"] == 17
    assert materials[0]["ideas"][0]["title"] == "Idea 1"


@pytest.mark.asyncio
async def test_attach_content_resources_does_not_serve_failed_book_module():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def no_source(**kwargs):
        return None

    async def thin_factory(**kwargs):
        return {
            "title": kwargs["title"],
            "author_or_creator": kwargs["author"],
            "sections": [],
            "ideas": [],
            "content_markdown": "thin " * 200,
        }

    materials = await attach_content_resources_to_materials(
        db,
        [{"title": "Thin Book", "type": "book", "author": "A. Author"}],
        book_source_lookup=no_source,
        book_module_factory=thin_factory,
    )

    assert "content_resource_id" not in materials[0]
    assert materials[0]["resource_unavailable"] is True
    assert materials[0]["quality_status"] == "flagged"


@pytest.mark.asyncio
async def test_attach_content_resources_prefers_public_domain_book_source():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def source_lookup(**kwargs):
        return {
            "title": "Meditations",
            "author_or_creator": "Marcus Aurelius",
            "source_url": "https://www.gutenberg.org/ebooks/2680",
            "license_status": "public_domain",
            "content_markdown": None,
            "source_context": "Sampled public-domain source text.",
            "summary_json": {"source": "project_gutenberg"},
            "duration_minutes": 15,
        }

    async def factory(**kwargs):
        assert kwargs["source_context"] == "Sampled public-domain source text."
        return _valid_book_module("Meditations", "Marcus Aurelius")

    materials = await attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Meditations",
                "type": "book",
                "author_or_creator": "Marcus Aurelius",
            }
        ],
        book_source_lookup=source_lookup,
        book_module_factory=factory,
    )

    resource = db.add.call_args.args[0]
    assert resource.kind == ContentResourceKind.PUBLIC_DOMAIN_BOOK
    assert materials[0]["content_resource_id"] == resource.id
    assert materials[0]["canonical_key"] == "book:marcus_aurelius:meditations"
    assert materials[0]["url"] == "https://www.gutenberg.org/ebooks/2680"
    assert materials[0]["license_status"] == "public_domain"
    assert materials[0]["content_markdown"].startswith("# Meditations")


@pytest.mark.asyncio
async def test_attach_content_resources_resolves_video_query_material():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def resolver(query: str):
        return "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    materials = await attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Margin of Safety",
                "type": "video",
                "search_query": "Warren Buffett margin of safety interview",
                "reason": "A useful video.",
            }
        ],
        video_resolver=resolver,
    )

    assert materials[0]["content_resource_id"] == db.add.call_args.args[0].id
    assert materials[0]["canonical_key"] == "youtube:dQw4w9WgXcQ"
    assert materials[0]["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"


@pytest.mark.asyncio
async def test_get_or_create_video_resource_resolves_query_and_saves_youtube_resource():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def resolver(query: str):
        assert query == "Warren Buffett margin of safety interview"
        return "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    result = await get_or_create_video_resource(
        db,
        title="Margin of Safety",
        search_query="Warren Buffett margin of safety interview",
        resolver=resolver,
    )

    assert result.canonical_key == "youtube:dQw4w9WgXcQ"
    assert result.kind == ContentResourceKind.VIDEO
    assert result.source_url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    assert result.license_status == LicenseStatus.EXTERNAL_LINK
    assert (
        result.metadata_json["search_query"]
        == "Warren Buffett margin of safety interview"
    )
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_get_or_create_video_resource_caches_unavailable_query_without_researching():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def resolver(query: str):
        return None

    result = await get_or_create_video_resource(
        db,
        title="Obscure Mentor Clip",
        search_query="very obscure unavailable mentor clip",
        resolver=resolver,
    )

    assert result.canonical_key == "youtube_query:very_obscure_unavailable_mentor_clip"
    assert result.kind == ContentResourceKind.VIDEO
    assert result.source_url is None
    assert result.license_status == LicenseStatus.UNKNOWN
    assert result.metadata_json["unavailable"] is True
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_attach_content_resources_defers_uncached_book_generation(monkeypatch):
    from app.services import content_resources as svc

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)
    enqueued = []

    monkeypatch.setattr(
        svc,
        "enqueue_book_module_generation",
        lambda **kwargs: enqueued.append(kwargs),
    )

    async def source_lookup(**kwargs):
        raise AssertionError("source lookup must not run inline when deferred")

    async def factory(**kwargs):
        raise AssertionError("book generation must not run inline when deferred")

    materials = await svc.attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "type": "book",
                "author_or_creator": "James Clear",
                "reason": "Habit design.",
            }
        ],
        user_goal="build better routines",
        book_source_lookup=source_lookup,
        book_module_factory=factory,
        defer_book_generation=True,
    )

    assert "content_resource_id" not in materials[0]
    assert materials[0]["canonical_key"] == "book:james_clear:atomic_habits"
    assert enqueued == [
        {
            "title": "Atomic Habits",
            "author": "James Clear",
            "user_goal": "build better routines",
            "source_context": None,
        }
    ]
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_attach_content_resources_attaches_cached_book_without_enqueue(
    monkeypatch,
):
    from app.services import content_resources as svc

    cached = MagicMock()
    cached.id = "book-resource-1"
    cached.canonical_key = "book:james_clear:atomic_habits"
    cached.source_url = "https://example.com/atomic-habits"
    cached.thumbnail_url = None
    cached.license_status = LicenseStatus.LLM_SUMMARY
    cached.content_markdown = _valid_book_module("Atomic Habits", "James Clear")[
        "content_markdown"
    ]
    cached.duration_minutes = 15
    cached.summary_json = {
        "ideas": [],
        "promise": "Small habits compound.",
        "sections": [],
    }
    cached.status = CatalogStatus.PUBLISHED
    cached.kind = ContentResourceKind.LLM_BOOK_SUMMARY
    cached.metadata_json = {
        "quality_report": {
            "passed": True,
            "gate_version": BOOK_MODULE_QUALITY_GATE_VERSION,
        }
    }

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult([cached])

    def fail_enqueue(**kwargs):
        raise AssertionError("cached book must not be enqueued")

    monkeypatch.setattr(svc, "enqueue_book_module_generation", fail_enqueue)

    materials = await svc.attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "type": "book",
                "author_or_creator": "James Clear",
                "resource_unavailable": True,
                "quality_status": "flagged",
                "quality_word_count": 1200,
            }
        ],
        defer_book_generation=True,
    )

    # Cached materials only need the single batched IN lookup.
    assert db.execute.await_count == 1
    assert materials[0]["content_resource_id"] == "book-resource-1"
    assert materials[0]["canonical_key"] == "book:james_clear:atomic_habits"
    assert materials[0]["content_markdown"].startswith("# Atomic Habits")
    assert materials[0]["license_status"] == "llm_summary"
    assert materials[0]["book_quality_gate_version"] == BOOK_MODULE_QUALITY_GATE_VERSION
    assert "resource_unavailable" not in materials[0]
    assert "quality_status" not in materials[0]
    assert "quality_word_count" not in materials[0]
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_inline_long_book_payload_cannot_reuse_stale_generic_cache(monkeypatch):
    from app.services import content_resources as svc

    stale = MagicMock()
    stale.id = "stale-inline"
    stale.canonical_key = "book:james_clear:atomic_habits"
    stale.kind = ContentResourceKind.LLM_BOOK_SUMMARY
    stale.status = CatalogStatus.PUBLISHED
    stale.license_status = LicenseStatus.LLM_SUMMARY
    stale.content_markdown = _valid_book_module("Atomic Habits", "James Clear")[
        "content_markdown"
    ]
    stale.metadata_json = {"quality_report": {"passed": True}}
    db = AsyncMock()
    db.execute.return_value = ScalarResult([stale])
    enqueued = []
    monkeypatch.setattr(
        svc,
        "enqueue_book_module_generation",
        lambda **kwargs: enqueued.append(kwargs),
    )

    inline = _valid_book_module("Atomic Habits", "James Clear")
    materials = await svc.attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "kind": "book",
                "author_or_creator": "James Clear",
                "content_markdown": inline["content_markdown"],
                "sections": inline["sections"],
                "ideas": inline["ideas"],
            }
        ],
        defer_book_generation=True,
    )

    assert "content_resource_id" not in materials[0]
    assert materials[0]["canonical_key"] == stale.canonical_key
    assert "content_markdown" not in materials[0]
    assert "ideas" not in materials[0]
    assert "sections" not in materials[0]
    assert len(enqueued) == 1
    assert enqueued[0]["source_context"] is None


@pytest.mark.asyncio
async def test_attach_content_resources_runs_independent_book_prep_concurrently():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    started = {"Deep Work": asyncio.Event(), "Atomic Habits": asyncio.Event()}

    async def no_source(**kwargs):
        return None

    async def factory(**kwargs):
        title = kwargs["title"]
        other = "Atomic Habits" if title == "Deep Work" else "Deep Work"
        started[title].set()
        # Each factory only completes once the other has started, which
        # deadlocks (and times out) unless the prep work runs concurrently.
        await asyncio.wait_for(started[other].wait(), timeout=1.0)
        return _valid_book_module(title, kwargs["author"])

    materials = await attach_content_resources_to_materials(
        db,
        [
            {"title": "Deep Work", "type": "book", "author_or_creator": "Cal Newport"},
            {
                "title": "Atomic Habits",
                "type": "book",
                "author_or_creator": "James Clear",
            },
        ],
        user_goal="focus better",
        book_source_lookup=no_source,
        book_module_factory=factory,
    )

    assert materials[0]["canonical_key"] == "book:cal_newport:deep_work"
    assert materials[1]["canonical_key"] == "book:james_clear:atomic_habits"
    assert materials[0]["content_markdown"].startswith("# Deep Work")
    assert materials[1]["content_markdown"].startswith("# Atomic Habits")
    assert db.add.call_count == 2


@pytest.mark.asyncio
async def test_sync_plan_item_content_resource_links_replaces_existing_links():
    db = AsyncMock()
    db.add = MagicMock()

    await sync_plan_item_content_resource_links(
        db,
        plan_item_id="plan-item-1",
        materials=[
            {
                "title": "Deep Work",
                "type": "book",
                "content_resource_id": "resource-book",
                "canonical_key": "book:cal_newport:deep_work",
                "reason": "Focus training.",
                "license_status": "llm_summary",
            },
            {
                "title": "Local note",
                "type": "tool",
            },
            {
                "title": "Buffett Interview",
                "type": "video",
                "content_resource_id": "resource-video",
                "canonical_key": "youtube:dQw4w9WgXcQ",
                "search_query": "Warren Buffett interview",
            },
        ],
    )

    db.execute.assert_awaited_once()
    assert db.add.call_count == 2
    first = db.add.call_args_list[0].args[0]
    second = db.add.call_args_list[1].args[0]
    assert first.plan_item_id == "plan-item-1"
    assert first.content_resource_id == "resource-book"
    assert first.material_index == 0
    assert first.canonical_key == "book:cal_newport:deep_work"
    assert first.metadata_json["reason"] == "Focus training."
    assert second.content_resource_id == "resource-video"
    assert second.material_index == 2
    assert second.metadata_json["search_query"] == "Warren Buffett interview"
    db.flush.assert_awaited_once()
