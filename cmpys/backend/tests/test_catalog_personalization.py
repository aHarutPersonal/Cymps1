from __future__ import annotations

import hashlib
from dataclasses import replace
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from sqlalchemy.dialects import postgresql

from app.models.curriculum import (
    AssignmentStatus,
    CurriculumSkillStatus,
    PersonalizedLessonStatus,
    VersionStatus,
)
from app.models.plan import PlanItemType
from app.services.curriculum.hashing import sha256_json
from app.services.planning import catalog_lessons as catalog
from app.tasks import plans as plan_tasks


class _Scalars:
    def __init__(self, values):
        self._values = list(values)

    def all(self):
        return list(self._values)

    def __iter__(self):
        return iter(self._values)


class _Result:
    def __init__(self, values=(), *, scalar=None):
        self._values = list(values)
        self._scalar = scalar

    def scalars(self):
        return _Scalars(self._values)

    def scalar_one_or_none(self):
        return self._scalar

    def all(self):
        return list(self._values)


class _FakeDB:
    def __init__(self, results=()):
        self._results = list(results)
        self.added = []
        self.flush = AsyncMock()

    async def execute(self, _statement):
        if not self._results:
            raise AssertionError("unexpected database query")
        return self._results.pop(0)

    def add(self, value):
        if getattr(value, "id", None) is None:
            value.id = f"new-{len(self.added) + 1}"
        self.added.append(value)


class _CapturingFakeDB(_FakeDB):
    def __init__(self, results=()):
        super().__init__(results)
        self.statements = []

    async def execute(self, statement):
        self.statements.append(statement)
        return await super().execute(statement)


class _NoAutoflushContext:
    def __init__(self, db):
        self.db = db

    def __enter__(self):
        self.db.no_autoflush_depth += 1

    def __exit__(self, *_args):
        self.db.no_autoflush_depth -= 1


class _GuardedCapturingFakeDB(_CapturingFakeDB):
    def __init__(self, results=()):
        super().__init__(results)
        self.no_autoflush_depth = 0

    @property
    def no_autoflush(self):
        return _NoAutoflushContext(self)

    async def execute(self, statement):
        assert self.no_autoflush_depth > 0
        return await super().execute(statement)


def _session(
    session_id: str = "session-1",
    *,
    position: int = 1,
    minutes: int = 50,
    content=None,
    technique_plan=None,
) -> catalog.CatalogSession:
    return catalog.CatalogSession(
        session_id=session_id,
        position=position,
        title=f"Session {position}",
        learning_objective="Produce a defensible downside analysis",
        estimated_minutes=minutes,
        content=content or {"lesson_content": "canonical reference"},
        assessment={"criterion": "reasoning is explicit"},
        artifact_spec={"type": "investment_memo"},
        technique_plan=technique_plan or {},
    )


def _material(
    *,
    source_id: str | None = "source-db-1",
    url: str | None = "https://www.berkshirehathaway.com/letters/letters.html",
) -> catalog.CatalogMaterial:
    return catalog.CatalogMaterial(
        title="Berkshire shareholder letters",
        author_or_creator="Warren Buffett",
        url=url,
        source_id=source_id,
    )


def _technique_manifest() -> tuple[dict, ...]:
    return (
        {
            "technique_key": "retrieval_practice",
            "version_id": "technique-version-1",
            "version_number": 1,
            "content_hash": "a" * 64,
            "source_hash": "b" * 64,
        },
    )


def _technique_row(**changes) -> SimpleNamespace:
    values = {
        **_technique_manifest()[0],
        "id": "technique-version-1",
        "status": VersionStatus.PUBLISHED,
        "revoked_at": None,
    }
    values.update(changes)
    return SimpleNamespace(**values)


def _retrieval_metadata(**changes) -> dict:
    manifest = list(_technique_manifest())
    metadata = {
        "technique_version_manifest": manifest,
        "technique_version_manifest_hash": sha256_json(manifest),
    }
    metadata.update(changes)
    return metadata


def _candidate(**changes) -> catalog.CatalogModuleCandidate:
    manifest = _technique_manifest()
    retrieval = _retrieval_metadata()
    candidate = catalog.CatalogModuleCandidate(
        module_id="module-db-1",
        module_version_id="module-version-db-1",
        title="Downside-first valuation",
        skill_id="investing.valuation",
        outcome_ids=frozenset({"estimate.downside"}),
        outcome_aliases=frozenset({"bound.downside"}),
        level="beginner",
        prerequisite_skill_ids=frozenset({"finance.basics"}),
        locale="en-US",
        artifact_types=frozenset({"investment_memo"}),
        sessions=(_session(),),
        materials=(_material(),),
        quality_score=0.95,
        published=True,
        version_number=2,
        retrieval_metadata_hash=sha256_json(retrieval),
        technique_version_manifest=manifest,
        technique_version_manifest_hash=sha256_json(list(manifest)),
    )
    return replace(candidate, **changes)


def _gap(**changes) -> catalog.StructuredLearningGap:
    gap = catalog.StructuredLearningGap(
        skill_id="investing.valuation",
        outcome_id="estimate.downside",
        target_level="beginner",
        satisfied_prerequisite_ids=frozenset({"finance.basics"}),
        locale="en-US",
        artifact_type="investment_memo",
        available_minutes=60,
        semantic_query="I need a more rigorous downside estimate",
    )
    return replace(gap, **changes)


def _brief(*, mentor_evidence=()) -> catalog.LearnerLessonBrief:
    gap = _gap()
    facts = (
        catalog.BriefFact("goal", "goal", "build an investment memo"),
        catalog.BriefFact("gap.skill", "gap", "investing valuation"),
        catalog.BriefFact("gap.outcome", "gap", "estimate downside"),
        catalog.BriefFact(
            "learner.plan_item",
            "learner",
            "Analyze the Acme annual report",
        ),
        catalog.BriefFact(
            "comparison.context",
            "comparison",
            "needs stronger downside analysis",
        ),
        *(
            catalog.BriefFact(
                f"mentor.evidence.{row['evidence_id']}",
                "mentor",
                str(row["claim"]),
            )
            for row in mentor_evidence
        ),
    )
    return catalog.LearnerLessonBrief(
        user_id="user-private-id",
        plan_id="plan-private-id",
        plan_item_id="item-private-id",
        source_session_id="intake-private-id",
        goal="build an investment memo",
        gap=gap,
        current_capability="can read a balance sheet",
        learning_preferences=("worked examples",),
        constraints=("one hour",),
        achievements=(),
        comparison_context="needs stronger downside analysis",
        weekly_minutes=180,
        mentor_id="idol-private-id",
        mentor_name="Warren Buffett",
        mentor_evidence=tuple(mentor_evidence),
        facts=facts,
    )


def _draft(*, source_ids=None) -> catalog.PersonalizedSessionDraft:
    filler = " Explain the mechanism, make a decision, inspect evidence, and revise."
    return catalog.PersonalizedSessionDraft.model_validate(
        {
            "title": "A downside-first memo",
            "description": "Build a real decision artifact.",
            "why_this_matters": "Your goal is to build an investment memo." + filler,
            "core_framework": "Use evidence, assumptions, ranges, and a decision rule."
            + filler,
            "worked_example": "Use the Acme annual report for the worked example."
            + filler,
            "failure_modes": "Avoid false precision and unsupported certainty."
            + filler,
            "guided_practice": "Practice the needs stronger downside analysis gap."
            + filler,
            "artifact_spec": "Submit an investment memo with a downside table."
            + filler,
            "check_your_understanding": "Explain why the range could be wrong."
            + filler,
            "success_rubric": "The Acme annual report evidence is traceable." + filler,
            "substeps": [
                "Set a ten minute timer, write one assumption, save it, and verify its source."
            ],
            "reference_source_ids": source_ids or ["source-db-1"],
            "bindings": {
                "explanation": [{"fact_id": "goal", "anchor": "investment memo"}],
                "example": [
                    {
                        "fact_id": "learner.plan_item",
                        "anchor": "Acme annual report",
                    }
                ],
                "practice": [
                    {
                        "fact_id": "comparison.context",
                        "anchor": "downside analysis",
                    }
                ],
                "artifact": [{"fact_id": "goal", "anchor": "investment memo"}],
                "rubric": [
                    {
                        "fact_id": "learner.plan_item",
                        "anchor": "Acme annual report",
                    }
                ],
            },
            "used_mentor_evidence_ids": [],
        }
    )


def _disable_word_count_gate(monkeypatch):
    monkeypatch.setattr(catalog, "MIN_PLAN_DETAIL_LESSON_WORDS", 1)
    monkeypatch.setattr(catalog, "MAX_PLAN_DETAIL_LESSON_WORDS", 20_000)


def test_matcher_returns_exact_and_strong_but_never_waives_hard_fields():
    exact = catalog.match_catalog_lesson(_gap(), [_candidate()])
    assert exact.verdict is catalog.MatchVerdict.EXACT

    strong_gap = _gap(outcome_id="bound.downside", locale="en-GB")
    strong = catalog.match_catalog_lesson(
        strong_gap,
        [_candidate()],
        semantic_candidate_hook=lambda _gap, candidates: {
            candidates[0].module_version_id: 0.91
        },
    )
    assert strong.verdict is catalog.MatchVerdict.STRONG

    incompatible = [
        (_gap(skill_id="writing"), _candidate()),
        (_gap(outcome_id="unknown"), _candidate()),
        (_gap(target_level="advanced"), _candidate()),
        (_gap(satisfied_prerequisite_ids=frozenset()), _candidate()),
        (_gap(locale="fr-FR"), _candidate()),
        (_gap(artifact_type="spreadsheet"), _candidate()),
        (_gap(available_minutes=40), _candidate(sessions=(_session(minutes=50),))),
        (_gap(), _candidate(materials=(_material(source_id=None),))),
    ]
    for gap, candidate in incompatible:
        result = catalog.match_catalog_lesson(
            gap,
            [candidate],
            semantic_candidate_hook=lambda _gap, rows: {rows[0].module_version_id: 1.0},
        )
        assert result.verdict is catalog.MatchVerdict.ABSTAIN
        assert result.candidate is None


@pytest.mark.asyncio
async def test_free_form_gap_resolution_pages_beyond_first_hundred_modules():
    modules = []
    for index in range(101):
        is_target = index == 100
        modules.append(
            SimpleNamespace(
                key=("zz.relevant.module" if is_target else f"aa.module.{index:03d}"),
                skill=SimpleNamespace(
                    key=(
                        "investing.valuation" if is_target else f"other.skill.{index}"
                    ),
                    name=("Valuation" if is_target else f"Other skill {index}"),
                ),
                level="beginner",
                learning_outcome=(
                    "estimate.downside" if is_target else f"other.outcome.{index}"
                ),
                artifact_type=("investment_memo" if is_target else "worksheet"),
                language="en-US",
                title=("Downside-first valuation" if is_target else f"Module {index}"),
            )
        )
    db = _CapturingFakeDB([_Result(modules), _Result(())])
    item = SimpleNamespace(
        id="item-1",
        title="Build a downside memo",
        description="Turn uncertainty into a valuation range.",
        success_metric="Defend the downside estimate.",
        estimated_hours=1,
        meta_json={},
    )
    pages: list[list[str]] = []

    async def classifier(_context, candidates):
        keys = [str(candidate["module_key"]) for candidate in candidates]
        pages.append(keys)
        if "zz.relevant.module" in keys:
            return {
                "module_key": "zz.relevant.module",
                "confidence": 0.99,
                "evidence_quotes": ["needs stronger downside analysis"],
                "reason": "direct comparison evidence",
            }
        return {
            "module_key": None,
            "confidence": 0.0,
            "evidence_quotes": [],
            "reason": "no match in this page",
        }

    gap = await catalog.resolve_structured_gap_from_catalog(
        db,
        user_id="user-1",
        item=item,
        session_context={
            "comparison_summary": "The learner needs stronger downside analysis."
        },
        locale="en-US",
        classifier=classifier,
    )

    assert gap is not None
    assert gap.skill_id == "investing.valuation"
    assert gap.outcome_id == "estimate.downside"
    assert len(pages) == 2
    assert len(pages[0]) == catalog.CLOSED_WORLD_GAP_PAGE_SIZE
    assert pages[1] == ["zz.relevant.module"]
    assert "LIMIT" not in str(db.statements[0]).upper()
    assert item.meta_json["structured_gap"]["resolver_version"] == (
        "closed-world-paged-v2"
    )


def test_spacing_claim_hard_abstains_with_explicit_reason():
    spacing_session = _session(
        content={
            "blocks": [
                {
                    "follow_up_day": 3,
                    "technique_ids": ["spaced_practice"],
                }
            ],
            "follow_up_days": [3],
        },
        technique_plan={
            "applications": [{"technique_id": "spaced_practice"}],
            "spacing_follow_up_days": [3],
        },
    )
    result = catalog.match_catalog_lesson(
        _gap(),
        [_candidate(sessions=(spacing_session,))],
    )
    assert result.verdict is catalog.MatchVerdict.ABSTAIN
    assert "spacing_not_schedulable" in result.reason


def test_packer_skips_empty_weeks_and_never_repeats_sessions():
    module = _candidate(
        sessions=tuple(
            _session(f"session-{index}", position=index) for index in range(1, 4)
        )
    )
    schedule = catalog.pack_catalog_sessions(
        [module],
        weekly_minutes={1: 0, 2: 20, 3: 100, 4: 60},
        start_week=1,
        max_week=4,
    )
    assert [row.week_number for row in schedule] == [3, 3, 4]
    assert len({row.session.session_id for row in schedule}) == 3

    with pytest.raises(ValueError, match="exceeds the scalar weekly capacity"):
        catalog.pack_catalog_sessions(
            [_candidate(sessions=(_session(minutes=60),))],
            weekly_minutes=40,
        )


def test_personalization_requires_user_context_in_every_dimension(monkeypatch):
    _disable_word_count_gate(monkeypatch)
    valid = _draft()
    catalog.validate_personalized_session(
        valid,
        canonical_session=_session(),
        brief=_brief(),
        allowed_materials={"source-db-1": _material()},
    )

    payload = valid.model_dump(mode="python")
    for dimension in ("example", "practice", "artifact", "rubric"):
        payload["bindings"][dimension] = [
            {"fact_id": "gap.skill", "anchor": "investing valuation"}
        ]
    payload["worked_example"] += " investing valuation"
    payload["guided_practice"] += " investing valuation"
    payload["artifact_spec"] += " investing valuation"
    payload["success_rubric"] += " investing valuation"
    generic = catalog.PersonalizedSessionDraft.model_validate(payload)
    with pytest.raises(catalog.PersonalizationQualityError, match="must bind"):
        catalog.validate_personalized_session(
            generic,
            canonical_session=_session(),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )


def test_binding_and_source_gates_reject_punctuation_unknown_ids_and_urls(monkeypatch):
    _disable_word_count_gate(monkeypatch)
    base = _draft()

    punctuation_payload = base.model_dump(mode="python")
    punctuation_payload["bindings"]["explanation"] = [
        {"fact_id": "goal", "anchor": "---"}
    ]
    punctuation_payload["why_this_matters"] += " ---"
    with pytest.raises(catalog.PersonalizationQualityError, match="meaningful"):
        catalog.validate_personalized_session(
            catalog.PersonalizedSessionDraft.model_validate(punctuation_payload),
            canonical_session=_session(),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )

    with pytest.raises(
        catalog.PersonalizationQualityError, match="unknown catalog source"
    ):
        catalog.validate_personalized_session(
            _draft(source_ids=["invented-source"]),
            canonical_session=_session(),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )

    url_payload = base.model_dump(mode="python")
    url_payload["worked_example"] += " https://evil.invalid/fake-source"
    with pytest.raises(catalog.PersonalizationQualityError, match="free-form URLs"):
        catalog.validate_personalized_session(
            catalog.PersonalizedSessionDraft.model_validate(url_payload),
            canonical_session=_session(),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )

    rendered = catalog.assemble_personalized_lesson_content(
        base,
        approved_materials={"source-db-1": _material()},
    )
    assert "https://www.berkshirehathaway.com/letters/letters.html" in rendered
    assert "evil.invalid" not in rendered

    injected_material = replace(
        _material(),
        title="Trusted](https://evil.invalid)[label\nnext",
        author_or_creator="Author](https://evil.invalid)",
        reason="Read this](https://evil.invalid) now",
    )
    escaped = catalog.assemble_personalized_lesson_content(
        base,
        approved_materials={"source-db-1": injected_material},
    )
    assert "](https://evil.invalid)" not in escaped
    assert "\\]\\(https://evil.invalid\\)" in escaped
    assert "label next" in escaped


@pytest.mark.parametrize(
    ("field_name", "attack"),
    (
        ("title", "![tracking](//evil.example/pixel)"),
        (
            "worked_example",
            "![tracking][pixel]\n\n[pixel]: &#47;&#47;evil.example/pixel",
        ),
        ("failure_modes", "Contact <attacker@example.com> for the answer."),
        (
            "guided_practice",
            '<img src="&#47;&#47;evil.example/pixel" alt="tracking">',
        ),
        (
            "worked_example",
            r"\` ![tracking](//evil.example/pixel) \`",
        ),
        (
            "failure_modes",
            '<img title="`" src="//evil.example/pixel" data-end="`">',
        ),
        (
            "guided_practice",
            '<img alt=">" src="/tracking">',
        ),
        ("check_your_understanding", "Contact <foo@bar> for the answer."),
        (
            "worked_example",
            "Paragraph starts here\n    [tracking](//evil.example/pixel)",
        ),
        (
            "failure_modes",
            'Paragraph starts here\n    <img src="/tracking">',
        ),
        (
            "guided_practice",
            "- item\n    [tracking](//evil.example/pixel)",
        ),
        (
            "artifact_spec",
            "- item\n\n    [tracking](//evil.example/pixel)",
        ),
        (
            "check_your_understanding",
            "> [foo]:\n>   /tracking\n>\n> [foo]",
        ),
        (
            "failure_modes",
            "<div>\nhttps://evil.example/pixel\n</div>",
        ),
        (
            "guided_practice",
            '<div title="https://evil.example/pixel">visible text</div>',
        ),
        ("description", "[unused-reference]: /tracking"),
        ("failure_modes", '<div style="color: red">styled text</div>'),
        ("worked_example", "<!--><img src=/tracking>-->"),
        (
            "failure_modes",
            "<!--><script src=/tracking></script>-->",
        ),
        ("guided_practice", "<!--><svg onload=alert(1)>-->"),
        (
            "artifact_spec",
            "<!---><iframe src=/tracking></iframe>-->",
        ),
        (
            "worked_example",
            "<![CDATA[><img src=/tracking>]]>",
        ),
        (
            "failure_modes",
            "<![CDATA[x><script src=/tracking></script>]]>",
        ),
    ),
)
def test_personalization_rejects_active_markdown_destination_bypasses(
    monkeypatch,
    field_name,
    attack,
):
    _disable_word_count_gate(monkeypatch)
    payload = _draft().model_dump(mode="python")
    if field_name == "title":
        payload[field_name] = attack
    else:
        payload[field_name] += f"\n\n{attack}"

    with pytest.raises(catalog.PersonalizationQualityError, match="free-form URLs"):
        catalog.validate_personalized_session(
            catalog.PersonalizedSessionDraft.model_validate(payload),
            canonical_session=_session(),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )


def test_personalization_allows_ordinary_data_prose_and_inert_code(monkeypatch):
    _disable_word_count_gate(monkeypatch)
    payload = _draft().model_dump(mode="python")
    payload["core_framework"] += (
        " Input data: revenue, margin, and cash flow are decision inputs. "
        "Entity examples &#91;label&#93;&#40;/destination&#41; and "
        "&lt;attacker@example.com&gt; remain plain text."
    )
    payload["failure_modes"] += (
        "\n\n```markdown\n"
        "![inert example](https://example.invalid/pixel)\n"
        "[reference]: data:text/plain,example\n"
        "```"
    )
    payload["check_your_understanding"] += (
        " Treat `mailto:example@example.invalid` and "
        '``<img title="`" src="/tracking" data-end="`">`` '
        "as literal code samples."
    )
    payload["worked_example"] += (
        "\n\n    ![indented inert example](//evil.example/pixel)"
    )
    payload["guided_practice"] += (
        "\n\n> ```markdown\n"
        "> ![blockquote inert example](//evil.example/pixel)\n"
        "> [reference]: data:text/plain,example\n"
        "> ```"
    )
    payload["artifact_spec"] += (
        '\n\nEscaped raw text \\<img src="/tracking"> stays inert. '
        '<!-- <img src="/tracking"> https://evil.example/pixel -->'
    )
    payload["description"] += (
        "\n\n- ```markdown\n"
        "  [tracking](//evil.example/pixel)\n"
        "  ```\n\n"
        "1. ```markdown\n"
        "   [tracking](//evil.example/pixel)\n"
        "   ```"
    )
    payload["why_this_matters"] += (
        "\n\n> Paragraph\n>\n>     [tracking](//evil.example/pixel)"
        "\n\n<div>\n[tracking](/destination)\n</div>"
        "\n\nThis is [ordinary prose]("
    )
    payload["success_rubric"] += (
        "\n\n<?instruction https://evil.example/pi?>\n\n"
        "<!DOCTYPE https://evil.example/declaration>"
    )

    catalog.validate_personalized_session(
        catalog.PersonalizedSessionDraft.model_validate(payload),
        canonical_session=_session(),
        brief=_brief(),
        allowed_materials={"source-db-1": _material()},
    )


def test_commonmark_safety_parser_fails_closed(monkeypatch):
    def fail_parse(*_args, **_kwargs):
        raise RuntimeError("synthetic parser failure")

    monkeypatch.setattr(catalog._COMMONMARK_PARSER, "parse", fail_parse)
    assert catalog._has_forbidden_link("otherwise harmless lesson prose")


def test_canonical_containment_is_unicode_aware_and_padding_resistant(monkeypatch):
    from time import monotonic

    from app.services.curriculum.gates import (
        MAX_CANONICAL_SHINGLE_CONTAINMENT,
        shingle_containment,
        shingle_similarity,
    )

    multilingual_source = (
        "инвестор проверяет денежный поток риски допущения и решение "
        "ներդրողը ստուգում է կանխիկ հոսքերը ռիսկերը և ենթադրությունները"
    )
    assert (
        shingle_containment(
            multilingual_source,
            f"{multilingual_source} լրացուցիչ բացատրություն",
        )
        == 1.0
    )
    for unspaced_source, addition in (
        ("投资者检查现金流风险假设并做出稳健决策", "新的解释"),
        ("นักลงทุนตรวจสอบกระแสเงินสดความเสี่ยงและสมมติฐาน", "คำอธิบายใหม่"),
    ):
        assert (
            shingle_containment(
                unspaced_source,
                f"{unspaced_source}{addition}",
            )
            == 1.0
        )
        interleaved_characters = []
        for index in range(0, len(unspaced_source), 6):
            interleaved_characters.append(unspaced_source[index : index + 6])
            interleaved_characters.append("x")
        assert (
            shingle_containment(
                unspaced_source,
                "".join(interleaved_characters),
            )
            == 1.0
        )
    assert (
        shingle_containment(
            "cash flow risk",
            "cash flow risk followed by a much longer independent explanation",
        )
        == 1.0
    )

    source_tokens = [f"canonicaltoken{index}" for index in range(84)]
    interleaved_tokens = []
    for index in range(0, len(source_tokens), 6):
        interleaved_tokens.extend(source_tokens[index : index + 6])
        interleaved_tokens.append(f"noveltoken{index // 6}")
    interleaved_source = " ".join(source_tokens)
    interleaved_candidate = " ".join(interleaved_tokens)
    assert shingle_similarity(interleaved_source, interleaved_candidate) == 0.0
    assert shingle_containment(interleaved_source, interleaved_candidate) == 1.0

    repeated_source_tokens = (
        "the investor checks the cash flow and the risk before the decision ".split()
        * 8
    )[:84]
    repeated_candidate_tokens = []
    for index in range(0, len(repeated_source_tokens), 6):
        repeated_candidate_tokens.extend(repeated_source_tokens[index : index + 6])
        repeated_candidate_tokens.append("the")
    assert (
        shingle_containment(
            " ".join(repeated_source_tokens),
            " ".join(repeated_candidate_tokens),
        )
        == 1.0
    )

    long_reference_tokens = [f"referenceword{index}" for index in range(200)]
    copied_subsection = long_reference_tokens[40:120]
    assert (
        shingle_containment(
            " ".join(long_reference_tokens),
            " ".join(copied_subsection),
        )
        == 1.0
    )
    assert (
        shingle_containment(
            " ".join(long_reference_tokens),
            " ".join(reversed(long_reference_tokens)),
        )
        < MAX_CANONICAL_SHINGLE_CONTAINMENT
    )
    topical_source = (
        "Investors compare cash flow debt margins and risk before making a decision. "
        "A careful review tests assumptions and records evidence."
    )
    topical_rewrite = (
        "Before a careful decision investors review evidence and test risk assumptions. "
        "Cash flow margins and debt records make the comparison."
    )
    assert (
        shingle_containment(topical_source, topical_rewrite)
        < MAX_CANONICAL_SHINGLE_CONTAINMENT
    )

    large_source_tokens = (repeated_source_tokens * 50)[:4_200]
    large_candidate_tokens = []
    for index in range(0, len(large_source_tokens), 6):
        large_candidate_tokens.extend(large_source_tokens[index : index + 6])
        large_candidate_tokens.append("the")
    started = monotonic()
    large_containment = shingle_containment(
        " ".join(large_source_tokens),
        " ".join(large_candidate_tokens),
    )
    elapsed = monotonic() - started
    assert large_containment == 1.0
    assert elapsed < 2.0

    _disable_word_count_gate(monkeypatch)
    base = _draft()
    compared_fields = (
        "why_this_matters",
        "core_framework",
        "worked_example",
        "failure_modes",
        "guided_practice",
        "artifact_spec",
        "check_your_understanding",
        "success_rubric",
    )
    copied_canonical = " ".join(
        str(getattr(base, field_name)) for field_name in compared_fields
    )
    canonical_session = _session(
        content={"blocks": [{"content_markdown": copied_canonical}]},
    )
    payload = base.model_dump(mode="python")
    payload["failure_modes"] += " " + " ".join(
        f"independentpadding{index}" for index in range(2_000)
    )
    padded_draft = catalog.PersonalizedSessionDraft.model_validate(payload)
    canonical_text = catalog._fold_text(catalog._canonical_prose(canonical_session))
    personalized_text = catalog._fold_text(
        " ".join(
            str(getattr(padded_draft, field_name)) for field_name in compared_fields
        )
    )
    assert shingle_similarity(canonical_text, personalized_text) < 0.10
    assert (
        shingle_containment(canonical_text, personalized_text)
        > MAX_CANONICAL_SHINGLE_CONTAINMENT
    )

    with pytest.raises(
        catalog.PersonalizationQualityError,
        match="canonical content was returned without personal composition",
    ):
        catalog.validate_personalized_session(
            padded_draft,
            canonical_session=canonical_session,
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )

    subsection_payload = base.model_dump(mode="python")
    subsection_payload.update(
        {
            "title": "Lesson",
            "description": "Brief",
            "why_this_matters": "investment memo",
            "core_framework": "Framework",
            "worked_example": "Acme annual report",
            "failure_modes": " ".join(copied_subsection),
            "guided_practice": "downside analysis",
            "artifact_spec": "investment memo",
            "check_your_understanding": "Question",
            "success_rubric": "Acme annual report",
            "substeps": [
                "Review each assumption carefully and record one decision before checking the final evidence source."
            ],
        }
    )
    with pytest.raises(
        catalog.PersonalizationQualityError,
        match="canonical content was returned without personal composition",
    ):
        catalog.validate_personalized_session(
            catalog.PersonalizedSessionDraft.model_validate(subsection_payload),
            canonical_session=_session(
                content={
                    "blocks": [{"content_markdown": " ".join(long_reference_tokens)}]
                }
            ),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )


def test_canonical_prose_uses_published_schema_narrative_fields():
    session = replace(
        _session(
            content={
                "blocks": [
                    {
                        "title": "Canonical block title",
                        "content_markdown": "Canonical teaching explanation",
                        "learner_instructions": ["Inspect the evidence carefully"],
                        "success_criteria": ["State a defensible decision rule"],
                    }
                ]
            }
        ),
        assessment={
            "blocks": [
                {
                    "title": "Assessment title",
                    "content_markdown": "Explain the transfer decision",
                    "learner_instructions": ["Answer without notes"],
                    "success_criteria": ["Name the decisive assumption"],
                }
            ]
        },
        artifact_spec={
            "description": "Produce a downside investment memo",
            "rubric": [
                {
                    "criterion": "Evidence quality",
                    "evidence_required": "Cite a primary filing",
                    "passing_standard": "Every key assumption is traceable",
                }
            ],
        },
        technique_plan={
            "learning_outcome": "Apply a downside-first decision process",
            "assessment_strategy": "Defend the decision against a counterexample",
            "applications": [
                {
                    "technique_id": "worked_examples",
                    "rationale": "A concrete example exposes hidden assumptions",
                    "implementation_steps": [
                        "Compare the example with the learner artifact",
                        "Remove one scaffold before the second attempt",
                    ],
                    "limitations": [
                        "The example cannot substitute for independent transfer"
                    ],
                }
            ],
        },
    )

    prose = catalog._canonical_prose(session)
    for expected in (
        session.title,
        session.learning_objective,
        "Canonical block title",
        "Canonical teaching explanation",
        "Inspect the evidence carefully",
        "State a defensible decision rule",
        "Assessment title",
        "Explain the transfer decision",
        "Answer without notes",
        "Name the decisive assumption",
        "Produce a downside investment memo",
        "Evidence quality",
        "Cite a primary filing",
        "Every key assumption is traceable",
        "Apply a downside-first decision process",
        "Defend the decision against a counterexample",
        "A concrete example exposes hidden assumptions",
        "Compare the example with the learner artifact",
        "Remove one scaffold before the second attempt",
        "The example cannot substitute for independent transfer",
    ):
        assert expected in prose


def test_reference_urls_are_encoded_as_markdown_link_destinations():
    malicious_url = (
        "https://www.berkshirehathaway.com/report) draft>notes\nnext?section=(one)"
    )
    encoded_url = (
        "https://www.berkshirehathaway.com/report%29%20draft%3Enotes%0A"
        "next?section=%28one%29"
    )
    rendered = catalog.assemble_personalized_lesson_content(
        _draft(),
        approved_materials={"source-db-1": replace(_material(), url=malicious_url)},
    )
    assert encoded_url in rendered
    assert f"]({malicious_url})" not in rendered

    mentor_draft_payload = _draft().model_dump(mode="python")
    mentor_draft_payload["used_mentor_evidence_ids"] = ["mentor-db-1"]
    mentor_rendered = catalog.assemble_personalized_lesson_content(
        catalog.PersonalizedSessionDraft.model_validate(mentor_draft_payload),
        approved_materials={"source-db-1": _material()},
        mentor_evidence={
            "mentor-db-1": {
                "source_title": "Verified source",
                "source_url": malicious_url,
            }
        },
    )
    assert f"[Verified source]({encoded_url})" in mentor_rendered
    assert f"]({malicious_url})" not in mentor_rendered


def test_mentor_reference_is_rendered_only_from_verified_brief_provenance(monkeypatch):
    _disable_word_count_gate(monkeypatch)
    evidence = {
        "evidence_id": "mentor-db-1",
        "claim": "Use primary company filings before making a decision.",
        "source_title": "Berkshire shareholder letter",
        "source_url": "https://www.berkshirehathaway.com/letters/letters.html",
        "confidence": 0.95,
    }
    brief = _brief(mentor_evidence=(evidence,))
    payload = _draft().model_dump(mode="python")
    payload["why_this_matters"] += " Warren Buffett: use primary company filings."
    payload["bindings"]["explanation"].append(
        {
            "fact_id": "mentor.evidence.mentor-db-1",
            "anchor": "primary company filings",
        }
    )
    payload["used_mentor_evidence_ids"] = ["mentor-db-1"]
    draft = catalog.PersonalizedSessionDraft.model_validate(payload)
    catalog.validate_personalized_session(
        draft,
        canonical_session=_session(),
        brief=brief,
        allowed_materials={"source-db-1": _material()},
    )
    rendered = catalog.assemble_personalized_lesson_content(
        draft,
        approved_materials={"source-db-1": _material()},
        mentor_evidence={"mentor-db-1": evidence},
    )
    assert "### Mentor context sources" in rendered
    assert "Berkshire shareholder letter" in rendered
    assert evidence["source_url"] in rendered


@pytest.mark.asyncio
async def test_composition_requires_relevant_verified_mentor_evidence(monkeypatch):
    _disable_word_count_gate(monkeypatch)
    evidence = {
        "evidence_id": "mentor-db-1",
        "claim": "Use primary company filings before making a decision.",
        "source_title": "Berkshire shareholder letter",
        "source_url": "https://www.berkshirehathaway.com/letters/letters.html",
        "confidence": 0.95,
    }

    async def composer_without_mentor(_module, _session, _brief):
        return _draft()

    with pytest.raises(
        catalog.PersonalizationQualityError,
        match="relevant verified mentor evidence",
    ):
        await catalog.compose_personalized_lesson(
            _candidate(),
            _brief(mentor_evidence=(evidence,)),
            session_composer=composer_without_mentor,
        )

    mentor_payload = _draft().model_dump(mode="python")
    mentor_payload["why_this_matters"] += (
        " Warren Buffett: use primary company filings."
    )
    mentor_payload["bindings"]["explanation"].append(
        {
            "fact_id": "mentor.evidence.mentor-db-1",
            "anchor": "primary company filings",
        }
    )
    mentor_payload["used_mentor_evidence_ids"] = ["mentor-db-1"]

    async def composer_with_mentor(_module, _session, _brief):
        return mentor_payload

    personalized = await catalog.compose_personalized_lesson(
        _candidate(),
        _brief(mentor_evidence=(evidence,)),
        session_composer=composer_with_mentor,
    )
    assert personalized.mentor_evidence_ids == ("mentor-db-1",)

    no_evidence = await catalog.compose_personalized_lesson(
        _candidate(),
        _brief(),
        session_composer=composer_without_mentor,
    )
    assert no_evidence.mentor_evidence_ids == ()


def test_unsourced_mentor_name_in_lesson_narrative_is_rejected(monkeypatch):
    _disable_word_count_gate(monkeypatch)
    payload = _draft().model_dump(mode="python")
    payload["worked_example"] += " Warren Buffett would evaluate this downside."

    with pytest.raises(
        catalog.PersonalizationQualityError,
        match="mentor name appears.*without verified mentor evidence",
    ):
        catalog.validate_personalized_session(
            catalog.PersonalizedSessionDraft.model_validate(payload),
            canonical_session=_session(),
            brief=_brief(),
            allowed_materials={"source-db-1": _material()},
        )


def test_prompt_payload_omits_internal_ids_and_uses_request_scoped_aliases():
    evidence = {
        "evidence_id": "mentor-db-uuid",
        "claim": "He recommends reading primary company filings.",
        "source_title": "Berkshire shareholder letter",
        "source_url": "https://www.berkshirehathaway.com/letters/letters.html",
        "source_chunk_id": "chunk-db-uuid",
        "confidence": 0.95,
    }
    brief = _brief(mentor_evidence=(evidence,))
    payload = brief.as_prompt_payload()
    serialized = str(payload)
    for private_id in (
        brief.user_id,
        brief.plan_id,
        brief.plan_item_id,
        brief.source_session_id,
        brief.mentor_id,
    ):
        assert private_id not in serialized

    prompt_session = _session(
        content={
            "blocks": [
                {
                    "source_ids": ["source-db-1"],
                    "content_markdown": "Grounded by source-db-1",
                }
            ]
        },
        technique_plan={"applications": [{"evidence_source_ids": ["source-db-1"]}]},
    )
    bundle = catalog._composition_prompt(_candidate(), prompt_session, brief)
    for private_id in (
        "module-db-1",
        "module-version-db-1",
        "session-1",
        "mentor-db-uuid",
        "chunk-db-uuid",
        "source-db-1",
    ):
        assert private_id not in bundle.text
    assert "mentor_1" in bundle.text
    assert "source_1" in bundle.text


@pytest.mark.asyncio
async def test_brief_ignores_spoofed_mentor_payload_and_bounds_prompt_context():
    db = _FakeDB([_Result(), _Result()])
    plan = SimpleNamespace(
        id="plan-private-id",
        weekly_hours=3,
        roadmap_json={},
    )
    item = SimpleNamespace(
        id="item-private-id",
        title="Write a valuation memo",
        success_metric="One reviewed memo",
    )
    profile = SimpleNamespace(
        goals=["build a robust investment process"],
        skills={},
        learning_preferences=["worked examples"] * 20,
        constraints=["one hour per week"] * 20,
    )
    spoofed = {
        "claims": [
            {
                "id": "attacker-claim",
                "claim_text": "Invented Buffett preference",
                "verification_status": "verified",
                "source_url": "https://attacker.invalid/fake",
            }
        ]
    }
    brief = await catalog.build_learner_lesson_brief(
        db,
        user_id="user-private-id",
        plan=plan,
        item=item,
        gap=_gap(),
        user_profile=profile,
        session_context={"comparison_summary": "comparison " * 10_000},
        idol=SimpleNamespace(id="idol-private-id", name="Warren Buffett"),
        idol_evidence=spoofed,
    )
    assert brief.mentor_evidence == ()
    assert "attacker-claim" not in str(brief.as_prompt_payload())
    assert "mentor" not in brief.as_prompt_payload()
    assert "Warren Buffett" not in str(brief.as_prompt_payload())
    prompt_candidate = _candidate(
        materials=(replace(_material(), author_or_creator="Berkshire Hathaway"),)
    )
    provider_prompt = catalog._composition_prompt(
        prompt_candidate,
        _session(),
        brief,
    ).text
    assert "Warren Buffett" not in provider_prompt
    assert len(brief.comparison_context) <= catalog.MAX_BRIEF_COMPARISON_CHARS
    assert sum(len(fact.value) for fact in brief.facts) <= (
        catalog.MAX_BRIEF_FACT_VALUE_CHARS
    )
    assert brief.truncation_metadata["truncated_fields"]


@pytest.mark.asyncio
async def test_brief_fetches_only_non_revoked_verified_mentor_claims():
    db = _CapturingFakeDB([_Result(), _Result()])
    await catalog.build_learner_lesson_brief(
        db,
        user_id="user-private-id",
        plan=SimpleNamespace(id="plan-private-id", weekly_hours=3, roadmap_json={}),
        item=SimpleNamespace(
            id="item-private-id",
            title="Write a valuation memo",
            success_metric="One reviewed memo",
        ),
        gap=_gap(),
        user_profile=None,
        session_context={},
        idol=SimpleNamespace(id="idol-private-id", name="Warren Buffett"),
        idol_evidence=None,
    )

    mentor_query = str(db.statements[1])
    assert "mentor_evidence_claims.verification_status" in mentor_query
    assert "mentor_evidence_claims.revoked_at IS NULL" in mentor_query


def test_composer_version_is_part_of_cache_identity(monkeypatch):
    original = catalog._composition_input_hash("version", [_session()], "brief")
    monkeypatch.setattr(catalog, "PERSONAL_COMPOSER_VERSION", "composer-next")
    upgraded = catalog._composition_input_hash("version", [_session()], "brief")
    assert upgraded != original


def test_rendered_session_prompt_digest_is_part_of_default_cache_identity(monkeypatch):
    module = _candidate()
    sessions = (_session(),)
    brief = _brief()
    original_prompt_hashes = catalog._composition_session_prompt_hashes(
        module,
        sessions,
        brief,
    )
    original = catalog._composition_input_hash(
        module.module_version_id,
        sessions,
        brief.input_hash,
        session_prompt_hashes=original_prompt_hashes,
    )
    custom_original = catalog._composition_input_hash(
        module.module_version_id,
        sessions,
        brief.input_hash,
        using_default_composer=False,
        session_prompt_hashes=original_prompt_hashes,
    )
    render = catalog._composition_prompt

    def changed_prompt(module, session, brief):
        bundle = render(module, session, brief)
        return replace(bundle, text=bundle.text + "\nNew deterministic instruction.")

    monkeypatch.setattr(catalog, "_composition_prompt", changed_prompt)
    changed_prompt_hashes = catalog._composition_session_prompt_hashes(
        module,
        sessions,
        brief,
    )
    changed = catalog._composition_input_hash(
        module.module_version_id,
        sessions,
        brief.input_hash,
        session_prompt_hashes=changed_prompt_hashes,
    )
    custom_changed = catalog._composition_input_hash(
        module.module_version_id,
        sessions,
        brief.input_hash,
        using_default_composer=False,
        session_prompt_hashes=changed_prompt_hashes,
    )

    assert changed_prompt_hashes != original_prompt_hashes
    assert changed != original
    assert custom_changed == custom_original
    assert brief.user_id not in str(changed_prompt_hashes)


def test_default_composer_cache_identity_tracks_resolved_llm_route(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "yunwu-secret-a")
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-secret-a")
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", True)
    monkeypatch.setattr(settings, "yunwu_base_url", "https://gateway-a.invalid/v1")
    monkeypatch.setattr(settings, "yunwu_model", "yunwu-balanced-a")
    monkeypatch.setattr(settings, "yunwu_quality_model", "yunwu-quality-a")
    monkeypatch.setattr(settings, "gemini_model", "gemini-balanced-a")

    provenance = catalog._default_composer_route_provenance()
    assert provenance["attempts"][0]["route"] == {
        "primary": {
            "provider": "yunwu",
            "model": "yunwu-balanced-a",
            "endpoint_fingerprint": hashlib.sha256(
                b"https://gateway-a.invalid/v1"
            ).hexdigest(),
        },
        "fallback": {
            "provider": "gemini",
            "model": "gemini-balanced-a",
            "endpoint_fingerprint": None,
        },
    }
    assert provenance["attempts"][1]["route"] == {
        "primary": {
            "provider": "yunwu",
            "model": "yunwu-quality-a",
            "endpoint_fingerprint": hashlib.sha256(
                b"https://gateway-a.invalid/v1"
            ).hexdigest(),
        },
        "fallback": None,
    }
    assert "yunwu-secret-a" not in str(provenance)
    assert "gemini-secret-a" not in str(provenance)
    assert "https://gateway-a.invalid/v1" not in str(provenance)

    base = catalog._composition_input_hash("version", [_session()], "brief")
    monkeypatch.setattr(settings, "yunwu_model", "yunwu-balanced-b")
    assert catalog._composition_input_hash("version", [_session()], "brief") != base
    monkeypatch.setattr(settings, "yunwu_model", "yunwu-balanced-a")
    monkeypatch.setattr(settings, "yunwu_quality_model", "yunwu-quality-b")
    assert catalog._composition_input_hash("version", [_session()], "brief") != base
    monkeypatch.setattr(settings, "yunwu_quality_model", "yunwu-quality-a")
    monkeypatch.setattr(settings, "gemini_model", "gemini-balanced-b")
    assert catalog._composition_input_hash("version", [_session()], "brief") != base
    monkeypatch.setattr(settings, "gemini_model", "gemini-balanced-a")
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", False)
    assert catalog._composition_input_hash("version", [_session()], "brief") != base
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", True)
    monkeypatch.setattr(settings, "gemini_api_key", None)
    assert catalog._composition_input_hash("version", [_session()], "brief") != base
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-secret-a")
    monkeypatch.setattr(settings, "yunwu_base_url", "https://gateway-b.invalid/v1")
    assert catalog._composition_input_hash("version", [_session()], "brief") != base

    monkeypatch.setattr(settings, "llm_provider", "openai")
    monkeypatch.setattr(settings, "openai_api_key", "openai-secret")
    monkeypatch.setattr(settings, "openai_model", "shared-model-name")
    openai_hash = catalog._composition_input_hash("version", [_session()], "brief")
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-secret-b")
    monkeypatch.setattr(settings, "gemini_model", "shared-model-name")
    gemini_hash = catalog._composition_input_hash("version", [_session()], "brief")
    assert openai_hash != gemini_hash


def test_default_composer_cache_identity_tracks_system_prompt(monkeypatch):
    from app.services.llm import prompt_loader

    monkeypatch.setattr(
        prompt_loader,
        "load_and_render",
        lambda *_args, **_kwargs: "system prompt v1",
    )
    first = catalog._composition_input_hash("version", [_session()], "brief")
    monkeypatch.setattr(
        prompt_loader,
        "load_and_render",
        lambda *_args, **_kwargs: "system prompt v2",
    )
    second = catalog._composition_input_hash("version", [_session()], "brief")
    assert first != second


def test_custom_composer_cache_identity_ignores_default_provider_route(monkeypatch):
    from app.core.config import settings

    custom_hash = catalog._composition_input_hash(
        "version",
        [_session()],
        "brief",
        using_default_composer=False,
    )
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_model", "unrelated-new-default")
    assert (
        catalog._composition_input_hash(
            "version",
            [_session()],
            "brief",
            using_default_composer=False,
        )
        == custom_hash
    )


def _composition(*, model_name="gpt-test") -> catalog.PersonalizedComposition:
    details = {
        "steps": [
            {
                "id": "step_1",
                "estimate_minutes": 50,
                "lesson_content": "personalized content",
            }
        ],
        "materials": [],
        "catalog": {"module_version_id": "module-version-db-1"},
        "personalization": {"status": "ready"},
        "retrieval_follow_ups": [],
    }
    return catalog.PersonalizedComposition(
        details=details,
        input_hash="a" * 64,
        content_hash=catalog._content_hash(details),
        estimated_minutes=50,
        mentor_evidence_ids=(),
        model_names=(model_name,),
    )


@pytest.mark.asyncio
async def test_ready_cache_mismatch_and_revoked_rows_are_never_mutated():
    brief = _brief()
    ready = SimpleNamespace(
        id="ready-1",
        status=PersonalizedLessonStatus.READY,
        content_json={"corrupt": True},
        content_hash="0" * 64,
        model_name="gpt-old",
    )
    db = _FakeDB([_Result(scalar=ready)])
    with pytest.raises(catalog.PersonalizationQualityError, match="immutable"):
        await catalog._persist_personalized_versions(
            db,
            brief=brief,
            module=_candidate(),
            composition=_composition(),
            sessions=(_session(),),
        )
    assert ready.status is PersonalizedLessonStatus.READY

    revoked = SimpleNamespace(
        id="revoked-1",
        status=PersonalizedLessonStatus.REVOKED,
        content_json={},
        content_hash=catalog._content_hash({}),
        model_name="gpt-old",
    )
    db = _FakeDB([_Result(scalar=revoked)])
    with pytest.raises(catalog.PersonalizationQualityError, match="explicitly revoked"):
        await catalog._persist_personalized_versions(
            db,
            brief=brief,
            module=_candidate(),
            composition=_composition(),
            sessions=(_session(),),
        )
    assert revoked.status is PersonalizedLessonStatus.REVOKED


@pytest.mark.asyncio
async def test_new_personalized_version_pins_exact_model_name():
    db = _FakeDB([_Result(scalar=None), _Result(scalar=0)])
    await catalog._persist_personalized_versions(
        db,
        brief=_brief(),
        module=_candidate(),
        composition=_composition(model_name="gpt-quality-2026-07"),
        sessions=(_session(),),
    )
    assert db.added[0].model_name == "gpt-quality-2026-07"
    assert db.added[0].prompt_version == catalog.PERSONAL_COMPOSER_VERSION


@pytest.mark.asyncio
async def test_route_change_appends_version_without_overwriting_existing_pin(
    monkeypatch,
):
    from app.core.config import settings

    monkeypatch.setattr(settings, "llm_provider", "openai")
    monkeypatch.setattr(settings, "openai_api_key", "test-key")
    monkeypatch.setattr(settings, "openai_model", "balanced-v1")
    old_hash = catalog._composition_input_hash(
        "module-version-db-1",
        [_session()],
        _brief().input_hash,
    )
    monkeypatch.setattr(settings, "openai_model", "balanced-v2")
    new_hash = catalog._composition_input_hash(
        "module-version-db-1",
        [_session()],
        _brief().input_hash,
    )
    assert new_hash != old_hash

    version_db = _FakeDB([_Result(scalar=None), _Result(scalar=1)])
    await catalog._persist_personalized_versions(
        version_db,
        brief=_brief(),
        module=_candidate(),
        composition=replace(_composition(), input_hash=new_hash),
        sessions=(_session(),),
    )
    appended = version_db.added[0]
    assert appended.version_number == 2
    assert appended.input_hash == catalog._session_input_hash(new_hash, "session-1")

    pinned = SimpleNamespace(
        module_session_id="session-1",
        plan_item_id="item-1",
        personalized_lesson_version_id="old-personalized-version",
        week_number=1,
        position=1,
        allocated_minutes=50,
        status=AssignmentStatus.AVAILABLE,
        available_at=datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
        comparison_gap_json={},
    )
    plan_rows = [
        SimpleNamespace(
            plan_id="plan-1",
            week_start=1,
            week_end=1,
            type=PlanItemType.PROJECT,
            estimated_hours=3,
        )
    ]
    assignment_db = _FakeDB([_Result(plan_rows)])
    monkeypatch.setattr(
        catalog,
        "lock_catalog_assignments_for_mutation",
        AsyncMock(return_value=[pinned]),
    )
    scheduled = catalog.ScheduledCatalogSession(
        week_number=1,
        position_in_week=1,
        allocated_minutes=50,
        module_id="module-db-1",
        module_version_id="module-version-db-1",
        session=_session(),
        is_continuation=False,
    )
    with pytest.raises(catalog.PersonalizationQualityError, match="already pinned"):
        await catalog._persist_plan_assignments(
            assignment_db,
            plan=SimpleNamespace(id="plan-1", weekly_hours=3, duration_weeks=1),
            item=SimpleNamespace(id="item-1", week_start=1),
            gap=_gap(),
            match=catalog.CatalogMatch(
                verdict=catalog.MatchVerdict.EXACT,
                candidate=_candidate(),
                reason="exact",
            ),
            schedule=[scheduled],
            personalized_ids={"session-1": str(appended.id)},
        )
    assert pinned.personalized_lesson_version_id == "old-personalized-version"


def _cached_personalized_row(
    *,
    brief: catalog.LearnerLessonBrief,
    evidence_ids: tuple[str, ...] = (),
) -> SimpleNamespace:
    composition_hash = catalog._composition_input_hash(
        "module-version-db-1",
        [_session()],
        brief.input_hash,
        using_default_composer=False,
    )
    step = {
        "id": "stored-step",
        "lesson_content": "complete personalized lesson content",
        "estimate_minutes": 50,
        "used_mentor_evidence_ids": list(evidence_ids),
    }
    content = {
        "step": step,
        "materials": [],
        "retrieval_follow_ups": [],
        "personalization": {"mentor_evidence_ids": list(evidence_ids)},
    }
    return SimpleNamespace(
        id="personalized-version-1",
        input_hash=catalog._session_input_hash(composition_hash, "session-1"),
        content_json=content,
        content_hash=catalog._content_hash(content),
        model_name="gpt-quality-2026-07",
        mentor_evidence_snapshot_json={
            "mentor_id": brief.mentor_id,
            "claims": [{"evidence_id": evidence_id} for evidence_id in evidence_ids],
        },
    )


@pytest.mark.asyncio
async def test_assignment_mutation_helper_locks_every_dependency_in_global_order():
    personalized = SimpleNamespace(
        id="personalized-1",
        status=PersonalizedLessonStatus.READY,
        revoked_at=None,
    )
    plan = SimpleNamespace(id="plan-1", user_id="user-1")
    assignment = SimpleNamespace(
        id="assignment-1",
        plan_id="plan-1",
        plan_item_id="item-1",
        personalized_lesson_version_id="personalized-1",
    )
    item = SimpleNamespace(id="item-1")
    probe = SimpleNamespace(
        assignment_id=assignment.id,
        assignment_plan_id=assignment.plan_id,
        assignment_plan_item_id=assignment.plan_item_id,
        assignment_personalized_id=assignment.personalized_lesson_version_id,
    )
    db = _GuardedCapturingFakeDB(
        [
            _Result([probe]),
            _Result([personalized]),
            _Result([plan]),
            _Result([assignment]),
            _Result([item]),
        ]
    )

    locked = await catalog.lock_catalog_assignments_for_mutation(
        db,
        plan_id="plan-1",
        assignment_ids=("assignment-1",),
        require_ready_personalized_version_ids=("personalized-1",),
        expected_user_id="user-1",
    )

    assert locked == [assignment]
    assert db.no_autoflush_depth == 0
    sql = [
        str(statement.compile(dialect=postgresql.dialect()))
        for statement in db.statements
    ]
    assert "FOR UPDATE" not in sql[0]
    assert "ORDER BY plan_lesson_assignments.id ASC" in sql[0]
    assert "FOR UPDATE OF personalized_lesson_versions" in sql[1]
    assert "ORDER BY personalized_lesson_versions.id ASC" in sql[1]
    assert "FOR UPDATE OF plans" in sql[2]
    assert "ORDER BY plans.id ASC" in sql[2]
    assert "FOR UPDATE OF plan_lesson_assignments" in sql[3]
    assert "ORDER BY plan_lesson_assignments.id ASC" in sql[3]
    assert "FOR UPDATE OF plan_items" in sql[4]
    assert "ORDER BY plan_items.id ASC" in sql[4]


@pytest.mark.asyncio
async def test_ready_cache_revalidates_mentor_evidence_and_allows_no_evidence(
    monkeypatch,
):
    monkeypatch.setattr(catalog, "MIN_PLAN_DETAIL_LESSON_WORDS", 1)
    no_evidence_brief = _brief()
    no_evidence_row = _cached_personalized_row(brief=no_evidence_brief)
    no_evidence_db = _FakeDB([_Result([no_evidence_row]), _Result([_technique_row()])])
    assert await catalog._load_cached_personalized_composition(
        no_evidence_db,
        brief=no_evidence_brief,
        module=_candidate(),
        sessions=(_session(),),
        session_composer=AsyncMock(),
    )

    evidence = {
        "evidence_id": "mentor-db-1",
        "claim": "Use primary filings.",
        "source_title": "Verified source",
        "source_url": "https://example.com/source",
    }
    evidence_brief = _brief(mentor_evidence=(evidence,))
    stale_row = _cached_personalized_row(
        brief=evidence_brief,
        evidence_ids=("mentor-db-1",),
    )
    stale_db = _CapturingFakeDB(
        [_Result([stale_row]), _Result([_technique_row()]), _Result()]
    )
    assert (
        await catalog._load_cached_personalized_composition(
            stale_db,
            brief=evidence_brief,
            module=_candidate(),
            sessions=(_session(),),
            session_composer=AsyncMock(),
        )
        is None
    )
    evidence_query = str(stale_db.statements[2])
    assert "mentor_evidence_claims.verification_status" in evidence_query
    assert "mentor_evidence_claims.revoked_at IS NULL" in evidence_query


@pytest.mark.asyncio
async def test_exact_assignment_pin_is_validated_in_lock_order_and_preserved(
    monkeypatch,
):
    monkeypatch.setattr(catalog, "MIN_PLAN_DETAIL_LESSON_WORDS", 1)
    assignment = SimpleNamespace(
        id="assignment-1",
        plan_id="plan-1",
        plan_item_id=None,
        module_session_id="session-1",
        personalized_lesson_version_id="personalized-1",
        week_number=1,
        status=AssignmentStatus.SCHEDULED,
        available_at=None,
        match_reason="pinned",
    )
    content = {
        "step": {
            "id": "old-step",
            "lesson_content": "immutable pinned personalized lesson",
            "estimate_minutes": 50,
            "used_mentor_evidence_ids": [],
        },
        "materials": [],
        "retrieval_follow_ups": [],
        "personalization": {"mentor_evidence_ids": []},
    }
    personalized = SimpleNamespace(
        id="personalized-1",
        user_id="user-private-id",
        module_session_id="session-1",
        module_version_id="module-version-db-1",
        status=PersonalizedLessonStatus.READY,
        revoked_at=None,
        content_json=content,
        content_hash=catalog._content_hash(content),
        model_name="old-pinned-model",
        input_hash="old-route-session-hash",
        prompt_version="old-composer-version",
        mentor_evidence_snapshot_json={"mentor_id": None, "claims": []},
    )
    locked_module = SimpleNamespace(
        id="module-db-1",
        status=CurriculumSkillStatus.ACTIVE,
    )
    locked_canonical = SimpleNamespace(
        id="module-version-db-1",
        module_id="module-db-1",
        status=VersionStatus.PUBLISHED,
        revoked_at=None,
        retrieval_metadata_json=_retrieval_metadata(),
        retrieval_metadata_hash=sha256_json(_retrieval_metadata()),
    )
    locked_plan = SimpleNamespace(id="plan-1", user_id="user-private-id")
    probe = SimpleNamespace(
        assignment_id="assignment-1",
        assignment_plan_id="plan-1",
        assignment_plan_item_id=None,
        assignment_personalized_id="personalized-1",
    )
    locked_item = SimpleNamespace(id="item-1")
    db = _CapturingFakeDB(
        [
            _Result([assignment]),
            _Result([personalized]),
            _Result([_technique_row()]),
            _Result(scalar=locked_module),
            _Result(scalar=locked_canonical),
            _Result([personalized]),
            _Result([probe]),
            _Result([personalized]),
            _Result([locked_plan]),
            _Result([assignment]),
            _Result([locked_item]),
        ]
    )
    loaded = await catalog._load_exact_assignment_pin(
        db,
        user_id="user-private-id",
        plan=SimpleNamespace(id="plan-1"),
        item=SimpleNamespace(id="item-1", week_start=1),
        brief=replace(_brief(), mentor_id=None, mentor_name=""),
        module=_candidate(),
        sessions=(_session(),),
        assignment_ids=("assignment-1",),
    )

    assert loaded.pins_present
    assert loaded.composition is not None
    assert loaded.composition.model_names == ("old-pinned-model",)
    assert loaded.personalized_ids == {"session-1": "personalized-1"}
    assert assignment.personalized_lesson_version_id == "personalized-1"
    assert assignment.plan_item_id == "item-1"
    assert assignment.status is AssignmentStatus.AVAILABLE

    sql = [
        str(statement.compile(dialect=postgresql.dialect()))
        for statement in db.statements
    ]
    assert "FOR UPDATE" not in sql[0]
    assert "FOR UPDATE" not in sql[1]
    assert "FOR UPDATE OF learning_technique_versions" in sql[2]
    assert "FOR UPDATE OF canonical_modules" in sql[3]
    assert "FOR UPDATE OF canonical_module_versions" in sql[4]
    assert "FOR UPDATE OF personalized_lesson_versions" in sql[5]
    personalized_lock_where = sql[5].split("WHERE", 1)[1].split("ORDER BY", 1)[0]
    assert "personalized_lesson_versions.status" not in personalized_lock_where
    assert "personalized_lesson_versions.revoked_at" not in personalized_lock_where
    assert "personalized_lesson_versions.user_id" not in personalized_lock_where
    assert "FOR UPDATE" not in sql[6]
    assert "FOR UPDATE OF personalized_lesson_versions" in sql[7]
    assert "FOR UPDATE OF plans" in sql[8]
    assert "FOR UPDATE OF plan_lesson_assignments" in sql[9]
    assert "FOR UPDATE OF plan_items" in sql[10]


@pytest.mark.asyncio
async def test_exact_pin_locks_full_personalized_set_before_rejecting_partial_stale(
    monkeypatch,
):
    sessions = (
        _session("session-1", position=1),
        _session("session-2", position=2),
    )
    assignments = [
        SimpleNamespace(
            id=f"assignment-{index}",
            plan_id="plan-1",
            module_session_id=session.session_id,
            personalized_lesson_version_id=f"personalized-{index}",
        )
        for index, session in enumerate(sessions, start=1)
    ]
    personalized = [
        SimpleNamespace(
            id=f"personalized-{index}",
            user_id="user-private-id",
            module_version_id="module-version-db-1",
            status=(
                PersonalizedLessonStatus.REVOKED
                if index == 1
                else PersonalizedLessonStatus.READY
            ),
            revoked_at=object() if index == 1 else None,
            mentor_evidence_snapshot_json={"mentor_id": None, "claims": []},
            content_json={"personalization": {"mentor_evidence_ids": []}},
        )
        for index in (1, 2)
    ]
    locked_canonical = SimpleNamespace(
        id="module-version-db-1",
        module_id="module-db-1",
        status=VersionStatus.PUBLISHED,
        revoked_at=None,
        retrieval_metadata_json=_retrieval_metadata(),
        retrieval_metadata_hash=sha256_json(_retrieval_metadata()),
    )
    db = _CapturingFakeDB(
        [
            _Result(assignments),
            _Result(personalized),
            _Result([_technique_row()]),
            _Result(
                scalar=SimpleNamespace(
                    id="module-db-1",
                    status=CurriculumSkillStatus.ACTIVE,
                )
            ),
            _Result(scalar=locked_canonical),
            _Result(personalized),
        ]
    )
    skip = AsyncMock()
    monkeypatch.setattr(catalog, "_skip_stale_pinned_assignments", skip)

    loaded = await catalog._load_exact_assignment_pin(
        db,
        user_id="user-private-id",
        plan=SimpleNamespace(id="plan-1"),
        item=SimpleNamespace(id="item-1", week_start=1),
        brief=replace(_brief(), mentor_id=None, mentor_name=""),
        module=_candidate(sessions=sessions),
        sessions=sessions,
        assignment_ids=("assignment-2", "assignment-1"),
    )

    assert loaded.pins_present
    assert loaded.composition is None
    assert "not READY" in loaded.reason
    locked_sql = str(db.statements[5].compile(dialect=postgresql.dialect()))
    assert "ORDER BY personalized_lesson_versions.id ASC" in locked_sql
    locked_where = locked_sql.split("WHERE", 1)[1].split("ORDER BY", 1)[0]
    assert "personalized_lesson_versions.status" not in locked_where
    assert "personalized_lesson_versions.revoked_at" not in locked_where
    skip.assert_awaited_once()


@pytest.mark.asyncio
async def test_valid_assignment_pin_bypasses_live_route_cache_and_paid_composer(
    monkeypatch,
):
    session = _session()
    candidate = _candidate(sessions=(session,))
    match = catalog.CatalogMatch(
        verdict=catalog.MatchVerdict.EXACT,
        candidate=candidate,
        reason="pinned multi-week continuation",
    )
    schedule = [
        catalog.ScheduledCatalogSession(
            week_number=1,
            position_in_week=1,
            allocated_minutes=50,
            module_id=candidate.module_id,
            module_version_id=candidate.module_version_id,
            session=session,
            is_continuation=True,
        )
    ]
    pinned_composition = _composition(model_name="old-pinned-model")
    monkeypatch.setattr(
        catalog,
        "_load_pinned_continuation",
        AsyncMock(
            return_value=(
                _gap(),
                candidate,
                match,
                schedule,
                [session],
                ("assignment-1",),
            )
        ),
    )
    monkeypatch.setattr(
        catalog,
        "build_learner_lesson_brief",
        AsyncMock(return_value=_brief()),
    )
    monkeypatch.setattr(
        catalog,
        "_load_exact_assignment_pin",
        AsyncMock(
            return_value=catalog._PinnedCompositionLoad(
                True,
                pinned_composition,
                {"session-1": "personalized-1"},
            )
        ),
    )
    route_cache = AsyncMock()
    paid_composer = AsyncMock()
    monkeypatch.setattr(catalog, "_load_cached_personalized_composition", route_cache)
    monkeypatch.setattr(catalog, "compose_personalized_lesson", paid_composer)
    monkeypatch.setattr(
        catalog,
        "_default_composer_route_provenance",
        lambda: (_ for _ in ()).throw(AssertionError("live route must not resolve")),
    )

    attempt = await catalog._try_catalog_personalized_lesson_in_savepoint(
        SimpleNamespace(),
        user_id="user-private-id",
        plan=SimpleNamespace(id="plan-1"),
        item=SimpleNamespace(id="item-1", week_start=1),
        user_profile=None,
        session_context={},
        idol=None,
        idol_evidence=None,
    )

    assert attempt.details is not None
    assert attempt.personalized_lesson_version_id == "personalized-1"
    route_cache.assert_not_awaited()
    paid_composer.assert_not_awaited()


@pytest.mark.asyncio
async def test_invalid_assignment_pin_falls_back_without_paid_recomposition(
    monkeypatch,
):
    session = _session()
    candidate = _candidate(sessions=(session,))
    match = catalog.CatalogMatch(
        verdict=catalog.MatchVerdict.EXACT,
        candidate=candidate,
        reason="pinned multi-week continuation",
    )
    schedule = [
        catalog.ScheduledCatalogSession(
            week_number=1,
            position_in_week=1,
            allocated_minutes=50,
            module_id=candidate.module_id,
            module_version_id=candidate.module_version_id,
            session=session,
            is_continuation=True,
        )
    ]
    monkeypatch.setattr(
        catalog,
        "_load_pinned_continuation",
        AsyncMock(
            return_value=(
                _gap(),
                candidate,
                match,
                schedule,
                [session],
                ("assignment-1",),
            )
        ),
    )
    monkeypatch.setattr(
        catalog,
        "build_learner_lesson_brief",
        AsyncMock(return_value=_brief()),
    )
    monkeypatch.setattr(
        catalog,
        "_load_exact_assignment_pin",
        AsyncMock(
            return_value=catalog._PinnedCompositionLoad(
                True,
                reason="pinned content is revoked",
            )
        ),
    )
    route_cache = AsyncMock()
    paid_composer = AsyncMock()
    monkeypatch.setattr(catalog, "_load_cached_personalized_composition", route_cache)
    monkeypatch.setattr(catalog, "compose_personalized_lesson", paid_composer)

    attempt = await catalog._try_catalog_personalized_lesson_in_savepoint(
        SimpleNamespace(),
        user_id="user-private-id",
        plan=SimpleNamespace(id="plan-1"),
        item=SimpleNamespace(id="item-1", week_start=1),
        user_profile=None,
        session_context={},
        idol=None,
        idol_evidence=None,
    )

    assert attempt.details is None
    assert "revoked" in attempt.reason
    route_cache.assert_not_awaited()
    paid_composer.assert_not_awaited()


def test_pinned_candidate_identity_prefers_immutable_version_metadata():
    mutable_module = SimpleNamespace(
        id="module-db-1",
        title="New mutable title",
        learning_outcome="new.mutable.outcome",
        level="expert",
        language="fr",
        artifact_type="new_artifact",
        status=CurriculumSkillStatus.ACTIVE,
        skill_id="mutable-skill-id",
        skill=SimpleNamespace(key="mutable.skill", prerequisites=[]),
    )
    session = SimpleNamespace(
        id="session-1",
        position=1,
        title="Pinned session",
        learning_objective="Pinned objective",
        estimated_minutes=50,
        content_json={"lesson_content": "canonical"},
        assessment_json={},
        artifact_spec_json={},
        technique_plan_json={},
    )
    retrieval_metadata = _retrieval_metadata(
        title="Pinned immutable title",
        skill_key="pinned.skill",
        level="beginner",
        locale="en-US",
        learning_outcome="pinned.outcome",
        artifact_type="pinned_artifact",
        prerequisites=["pinned.prerequisite"],
    )
    version = SimpleNamespace(
        id="module-version-db-1",
        module=mutable_module,
        version_number=1,
        status=VersionStatus.PUBLISHED,
        quality_score=0.95,
        content_json={"module": {"outcome_ids": ["content.outcome"]}},
        retrieval_metadata_json=retrieval_metadata,
        retrieval_metadata_hash=sha256_json(retrieval_metadata),
        source_manifest_json={
            "sources": [
                {
                    "id": "source-db-1",
                    "title": "Pinned source",
                    "url": "https://example.com/pinned-source",
                }
            ]
        },
        sessions=[session],
    )

    candidate = catalog._candidate_from_orm_version(version)

    assert candidate.title == "Pinned immutable title"
    assert candidate.skill_id == "pinned.skill"
    assert candidate.level == "beginner"
    assert candidate.locale == "en-US"
    assert candidate.outcome_ids == frozenset({"pinned.outcome"})
    assert candidate.artifact_types == frozenset({"pinned_artifact"})
    assert candidate.prerequisite_skill_ids == frozenset({"pinned.prerequisite"})


def test_candidate_rejects_corrupt_retrieval_metadata_hash():
    retrieval = _retrieval_metadata()
    version = SimpleNamespace(
        retrieval_metadata_json=retrieval,
        retrieval_metadata_hash="0" * 64,
    )

    with pytest.raises(ValueError, match="retrieval metadata hash mismatch"):
        catalog._validated_version_retrieval_recipe(version)


@pytest.mark.asyncio
async def test_assignment_never_overwrites_another_items_pin(monkeypatch):
    existing = SimpleNamespace(
        module_session_id="session-1",
        plan_item_id="other-item",
        personalized_lesson_version_id="other-personalized-version",
        week_number=1,
        position=1,
        allocated_minutes=50,
        status=AssignmentStatus.AVAILABLE,
        available_at=datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
        comparison_gap_json={},
    )
    plan_items = [
        SimpleNamespace(
            plan_id="plan-1",
            week_start=1,
            week_end=1,
            type=PlanItemType.PROJECT,
            estimated_hours=3,
        )
    ]
    db = _FakeDB([_Result(plan_items)])
    monkeypatch.setattr(
        catalog,
        "lock_catalog_assignments_for_mutation",
        AsyncMock(return_value=[existing]),
    )
    plan = SimpleNamespace(id="plan-1", weekly_hours=3, duration_weeks=1)
    item = SimpleNamespace(id="this-item", week_start=1)
    scheduled = catalog.ScheduledCatalogSession(
        week_number=1,
        position_in_week=1,
        allocated_minutes=50,
        module_id="module-db-1",
        module_version_id="module-version-db-1",
        session=_session(),
        is_continuation=False,
    )
    with pytest.raises(catalog.PersonalizationQualityError, match="another plan item"):
        await catalog._persist_plan_assignments(
            db,
            plan=plan,
            item=item,
            gap=_gap(),
            match=catalog.CatalogMatch(
                verdict=catalog.MatchVerdict.EXACT,
                candidate=_candidate(),
                reason="exact",
            ),
            schedule=[scheduled],
            personalized_ids={"session-1": "this-personalized-version"},
        )
    assert existing.plan_item_id == "other-item"
    assert existing.personalized_lesson_version_id == "other-personalized-version"


@pytest.mark.asyncio
async def test_catalog_capacity_excludes_daily_commitments_and_future_empty_budget():
    plan = SimpleNamespace(id="plan-1", weekly_hours=5, duration_weeks=2)
    rows = [
        SimpleNamespace(
            week_start=1,
            week_end=1,
            type=PlanItemType.PROJECT,
            estimated_hours=3,
        ),
        SimpleNamespace(
            week_start=1,
            week_end=1,
            type=PlanItemType.PRACTICE,
            estimated_hours=2,
        ),
        SimpleNamespace(
            week_start=2,
            week_end=2,
            type=PlanItemType.HABIT,
            estimated_hours=5,
        ),
    ]
    db = _FakeDB([_Result(rows)])
    capacity = await catalog._catalog_capacity_by_week(
        db,
        plan=plan,
        start_week=1,
        max_week=2,
    )
    assert capacity == {1: 180, 2: 0}

    module = _candidate(
        sessions=(
            _session("session-1", position=1, minutes=60),
            _session("session-2", position=2, minutes=60),
            _session("session-3", position=3, minutes=60),
            _session("session-4", position=4, minutes=60),
        )
    )
    db = _FakeDB([_Result(), _Result(rows)])
    with pytest.raises(ValueError, match="available plan weeks"):
        await catalog._existing_or_new_schedule(
            db,
            plan=plan,
            item=SimpleNamespace(id="item-1", week_start=1),
            module=module,
            gap=_gap(available_minutes=180),
        )


@pytest.mark.asyncio
async def test_skipped_stale_assignment_does_not_consume_or_block_capacity():
    stale = SimpleNamespace(
        module_session_id="session-1",
        plan_item_id=None,
        week_number=1,
        position=1,
        allocated_minutes=50,
        status=AssignmentStatus.SKIPPED,
    )
    plan_rows = [
        SimpleNamespace(
            week_start=1,
            week_end=1,
            type=PlanItemType.PROJECT,
            estimated_hours=1,
        )
    ]
    db = _FakeDB([_Result([stale]), _Result(plan_rows)])
    schedule, current = await catalog._existing_or_new_schedule(
        db,
        plan=SimpleNamespace(id="plan-1", weekly_hours=1, duration_weeks=1),
        item=SimpleNamespace(id="item-1", week_start=1),
        module=_candidate(),
        gap=_gap(available_minutes=60),
    )
    assert [row.session.session_id for row in schedule] == ["session-1"]
    assert [row.session_id for row in current] == ["session-1"]


@pytest.mark.asyncio
async def test_catalog_postprocessing_failure_rolls_back_before_bespoke_fallback():
    db = SimpleNamespace(rollback=AsyncMock(), refresh=AsyncMock())
    item = SimpleNamespace(id="item-1")
    job = SimpleNamespace(id="job-1")

    await plan_tasks._rollback_catalog_attempt_before_fallback(db, item, job)

    db.rollback.assert_awaited_once_with()
    assert db.refresh.await_args_list[0].args == (item,)
    assert db.refresh.await_args_list[1].args == (job,)


@pytest.mark.asyncio
async def test_revoked_candidate_cannot_persist_after_composition():
    db = _CapturingFakeDB([_Result([_technique_row()]), _Result(scalar=None)])
    with pytest.raises(
        catalog.PersonalizationQualityError, match="revoked or unpublished"
    ):
        await catalog._lock_and_revalidate_catalog_candidate(db, _candidate())
    sql = [
        str(statement.compile(dialect=postgresql.dialect()))
        for statement in db.statements
    ]
    assert "FOR UPDATE OF learning_technique_versions" in sql[0]
    assert "FOR UPDATE OF canonical_modules" in sql[1]
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_mentor_evidence_is_locked_in_stable_order_before_ready_persistence():
    claims = [
        SimpleNamespace(id="evidence-b", idol_id="idol-private-id"),
        SimpleNamespace(id="evidence-a", idol_id="idol-private-id"),
    ]
    db = _CapturingFakeDB([_Result(claims)])
    await catalog._lock_and_revalidate_mentor_evidence(
        db,
        evidence_ids=("evidence-b", "evidence-a"),
        mentor_id="idol-private-id",
    )
    sql = str(db.statements[0].compile(dialect=postgresql.dialect()))
    assert "mentor_evidence_claims.verification_status" in sql
    assert "mentor_evidence_claims.revoked_at IS NULL" in sql
    assert "ORDER BY mentor_evidence_claims.id ASC" in sql
    assert "FOR UPDATE OF mentor_evidence_claims" in sql

    wrong_owner_db = _FakeDB(
        [_Result([SimpleNamespace(id="evidence-a", idol_id="other-idol")])]
    )
    with pytest.raises(
        catalog.PersonalizationQualityError,
        match="revoked, missing, or reassigned",
    ):
        await catalog._lock_and_revalidate_mentor_evidence(
            wrong_owner_db,
            evidence_ids=("evidence-a",),
            mentor_id="idol-private-id",
        )


@pytest.mark.asyncio
async def test_prefetch_threads_owner_and_item_into_database_readiness(monkeypatch):
    monkeypatch.setattr(plan_tasks, "MIN_PLAN_DETAIL_LESSON_WORDS", 1)
    checker = AsyncMock(return_value=False)
    monkeypatch.setattr(catalog, "catalog_details_are_ready_in_database", checker)
    details = {
        "steps": [{"id": "step_1", "lesson_content": "complete lesson"}],
        "_generation": {
            "content_origin": "catalog_personalized",
            "status": "ready",
            "personalization_status": "ready",
            "personalized_lesson_version_id": "version-1",
        },
    }
    item = SimpleNamespace(id="item-1", details_json=details)

    assert not await plan_tasks._details_ready_for_prefetch_in_database(
        SimpleNamespace(),
        item=item,
        user_id="user-1",
    )
    checker.assert_awaited_once()
    assert checker.await_args.args[1] is details
    assert checker.await_args.kwargs == {
        "user_id": "user-1",
        "plan_item_id": "item-1",
    }
