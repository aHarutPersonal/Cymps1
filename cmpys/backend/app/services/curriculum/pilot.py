"""Deterministic pilot taxonomy and evidence-technique registry.

These manifests are application data, not migration data.  The control tick
may idempotently materialize them only while ``CURRICULUM_ENABLED`` is true.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.services.curriculum.hashing import curriculum_identity_hash, sha256_json
from app.services.curriculum.schemas import EvidenceTier, TechniqueId
from app.services.tavily import is_direct_resource_url


PILOT_TAXONOMY_VERSION = "pilot-2026.1"
TECHNIQUE_REGISTRY_VERSION = "evidence-techniques-2026.1"


class PilotSkill(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    skill_key: str
    domain: str
    title: str
    level: str
    locale: str = "en"
    learning_outcome: str
    prerequisites: tuple[str, ...] = ()
    estimated_minutes: int = Field(ge=40, le=600)
    priority: int = Field(ge=0, le=100)

    @property
    def identity_hash(self) -> str:
        return curriculum_identity_hash(
            skill_key=self.skill_key,
            level=self.level,
            locale=self.locale,
            learning_outcome=self.learning_outcome,
            taxonomy_version=PILOT_TAXONOMY_VERSION,
        )


class TechniqueRegistryEntry(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    technique_id: TechniqueId
    version: str = TECHNIQUE_REGISTRY_VERSION
    evidence_tier: EvidenceTier
    source_urls: tuple[str, ...] = Field(min_length=1)
    applicable_to: tuple[str, ...] = Field(min_length=1)
    implementation_contract: tuple[str, ...] = Field(min_length=1)
    limitations: tuple[str, ...] = Field(min_length=1)

    @field_validator("source_urls")
    @classmethod
    def direct_urls(cls, value: tuple[str, ...]) -> tuple[str, ...]:
        invalid = [url for url in value if not is_direct_resource_url(url)]
        if invalid:
            raise ValueError(f"technique evidence URLs must be direct: {invalid}")
        return value

    @property
    def content_hash(self) -> str:
        return sha256_json(self)


PILOT_SKILLS: tuple[PilotSkill, ...] = (
    PilotSkill(
        skill_key="investing.financial_statement_literacy",
        domain="investing",
        title="Read the three core financial statements",
        level="beginner",
        learning_outcome="Trace how one business event changes the income statement, balance sheet, and cash-flow statement.",
        estimated_minutes=180,
        priority=100,
    ),
    PilotSkill(
        skill_key="investing.intrinsic_value",
        domain="investing",
        title="Build a basic intrinsic-value range",
        level="beginner",
        learning_outcome="Build and explain a transparent intrinsic-value range from explicit cash-flow and discount-rate assumptions.",
        prerequisites=("investing.financial_statement_literacy",),
        estimated_minutes=240,
        priority=98,
    ),
    PilotSkill(
        skill_key="investing.margin_of_safety",
        domain="investing",
        title="Apply a margin of safety",
        level="intermediate",
        learning_outcome="Set and defend a margin-of-safety threshold that reflects uncertainty, downside, and valuation sensitivity.",
        prerequisites=("investing.intrinsic_value",),
        estimated_minutes=180,
        priority=96,
    ),
    PilotSkill(
        skill_key="investing.circle_of_competence",
        domain="investing",
        title="Define a circle of competence",
        level="beginner",
        learning_outcome="Create an evidence-based boundary for which businesses can and cannot currently be evaluated with confidence.",
        estimated_minutes=120,
        priority=94,
    ),
    PilotSkill(
        skill_key="investing.business_quality",
        domain="investing",
        title="Evaluate business quality",
        level="intermediate",
        learning_outcome="Evaluate business quality using economics, reinvestment opportunity, resilience, and management evidence.",
        prerequisites=("investing.financial_statement_literacy",),
        estimated_minutes=240,
        priority=92,
    ),
    PilotSkill(
        skill_key="investing.moat_analysis",
        domain="investing",
        title="Test a competitive advantage",
        level="intermediate",
        learning_outcome="Identify a proposed competitive advantage and test its mechanism, durability, evidence, and failure conditions.",
        prerequisites=("investing.business_quality",),
        estimated_minutes=180,
        priority=90,
    ),
    PilotSkill(
        skill_key="investing.capital_allocation",
        domain="investing",
        title="Assess management capital allocation",
        level="intermediate",
        learning_outcome="Judge management capital-allocation decisions against opportunity cost and long-term per-share value creation.",
        prerequisites=("investing.financial_statement_literacy",),
        estimated_minutes=180,
        priority=88,
    ),
    PilotSkill(
        skill_key="investing.risk_management",
        domain="investing",
        title="Map investment risk before return",
        level="intermediate",
        learning_outcome="Produce a pre-investment risk map covering permanent-loss mechanisms, probabilities, mitigations, and monitoring triggers.",
        estimated_minutes=180,
        priority=86,
    ),
    PilotSkill(
        skill_key="investing.investment_thesis",
        domain="investing",
        title="Write a falsifiable investment thesis",
        level="beginner",
        learning_outcome="Write a concise investment thesis with evidence, assumptions, valuation, disconfirming signals, and an explicit no-buy case.",
        prerequisites=("investing.financial_statement_literacy",),
        estimated_minutes=180,
        priority=84,
    ),
    PilotSkill(
        skill_key="investing.decision_journal",
        domain="investing",
        title="Build an investment decision journal",
        level="beginner",
        learning_outcome="Record a decision so future review can separate process quality, assumptions, luck, and outcome knowledge.",
        estimated_minutes=90,
        priority=82,
    ),
    PilotSkill(
        skill_key="entrepreneurship.problem_discovery",
        domain="entrepreneurship",
        title="Discover a costly customer problem",
        level="beginner",
        learning_outcome="Turn observations into a specific, testable customer problem with frequency, severity, and current-alternative evidence.",
        estimated_minutes=180,
        priority=100,
    ),
    PilotSkill(
        skill_key="entrepreneurship.customer_interviews",
        domain="entrepreneurship",
        title="Run evidence-seeking customer interviews",
        level="beginner",
        learning_outcome="Plan and conduct interviews that elicit concrete past behavior without pitching or leading the participant.",
        prerequisites=("entrepreneurship.problem_discovery",),
        estimated_minutes=240,
        priority=98,
    ),
    PilotSkill(
        skill_key="entrepreneurship.hypothesis_design",
        domain="entrepreneurship",
        title="Write falsifiable product hypotheses",
        level="beginner",
        learning_outcome="Express customer, problem, value, and behavior assumptions as falsifiable hypotheses with decision thresholds.",
        prerequisites=("entrepreneurship.problem_discovery",),
        estimated_minutes=120,
        priority=96,
    ),
    PilotSkill(
        skill_key="entrepreneurship.value_proposition",
        domain="entrepreneurship",
        title="Craft an evidence-based value proposition",
        level="beginner",
        learning_outcome="Create a value proposition tied to a verified job, painful alternative, differentiated mechanism, and measurable outcome.",
        prerequisites=("entrepreneurship.customer_interviews",),
        estimated_minutes=180,
        priority=94,
    ),
    PilotSkill(
        skill_key="entrepreneurship.mvp_scoping",
        domain="entrepreneurship",
        title="Scope a minimum viable test",
        level="beginner",
        learning_outcome="Design the smallest credible test that isolates the riskiest assumption and produces a decision-quality signal.",
        prerequisites=("entrepreneurship.hypothesis_design",),
        estimated_minutes=180,
        priority=92,
    ),
    PilotSkill(
        skill_key="entrepreneurship.experiment_design",
        domain="entrepreneurship",
        title="Design decisive product experiments",
        level="intermediate",
        learning_outcome="Design an experiment with a causal question, valid measure, threshold, bias controls, and precommitted next decision.",
        prerequisites=("entrepreneurship.hypothesis_design",),
        estimated_minutes=240,
        priority=90,
    ),
    PilotSkill(
        skill_key="entrepreneurship.pricing_validation",
        domain="entrepreneurship",
        title="Validate willingness to pay",
        level="intermediate",
        learning_outcome="Test pricing using behaviorally credible evidence and distinguish stated preference from willingness to pay.",
        prerequisites=("entrepreneurship.value_proposition",),
        estimated_minutes=180,
        priority=88,
    ),
    PilotSkill(
        skill_key="entrepreneurship.unit_economics",
        domain="entrepreneurship",
        title="Model unit economics",
        level="intermediate",
        learning_outcome="Build a transparent unit-economics model and identify which assumptions most affect contribution margin and payback.",
        estimated_minutes=240,
        priority=86,
    ),
    PilotSkill(
        skill_key="entrepreneurship.distribution_channels",
        domain="entrepreneurship",
        title="Select and test a distribution channel",
        level="intermediate",
        learning_outcome="Choose a channel from customer behavior and economics, then design a bounded test with explicit success criteria.",
        prerequisites=("entrepreneurship.value_proposition",),
        estimated_minutes=180,
        priority=84,
    ),
    PilotSkill(
        skill_key="entrepreneurship.product_metrics",
        domain="entrepreneurship",
        title="Choose decision-useful product metrics",
        level="intermediate",
        learning_outcome="Define a metric set that connects user value, behavior, retention, business outcome, and guardrails without vanity measures.",
        prerequisites=("entrepreneurship.experiment_design",),
        estimated_minutes=180,
        priority=82,
    ),
)


_IES_GUIDE = "https://ies.ed.gov/ncee/wwc/PracticeGuide/1"
_DUNLOSKY = "https://doi.org/10.1177/1529100612453266"


TECHNIQUE_REGISTRY: tuple[TechniqueRegistryEntry, ...] = (
    TechniqueRegistryEntry(
        technique_id=TechniqueId.RETRIEVAL_PRACTICE,
        evidence_tier=EvidenceTier.STRONG,
        source_urls=(_DUNLOSKY, "https://doi.org/10.1126/science.1152408"),
        applicable_to=("conceptual knowledge", "procedural knowledge", "durable recall"),
        implementation_contract=("Require recall or application before showing the answer.", "Give corrective feedback after the attempt."),
        limitations=("Do not reduce complex performance to trivia recall.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.SPACED_PRACTICE,
        evidence_tier=EvidenceTier.STRONG,
        source_urls=(_DUNLOSKY, "https://doi.org/10.1037/0033-2909.132.3.354"),
        applicable_to=("retention across weeks", "skills requiring repeated retrieval"),
        implementation_contract=("Schedule at least one retrieval on a later day.", "Change the retrieval context rather than repeat identical prose."),
        limitations=("Spacing needs a durable follow-up scheduler; a note saying 'review later' is insufficient.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.WORKED_EXAMPLES,
        evidence_tier=EvidenceTier.STRONG,
        source_urls=(_IES_GUIDE, "https://doi.org/10.1207/S1532690XCI1901_1"),
        applicable_to=("novices", "multi-step procedures", "new analytical frameworks"),
        implementation_contract=("Show a complete solution with reasoning and decision points.", "Link each step to the general principle it instantiates."),
        limitations=("Experts may benefit more from independent problem solving than fully worked steps.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.GUIDANCE_FADING,
        evidence_tier=EvidenceTier.MODERATE,
        source_urls=(_IES_GUIDE, "https://doi.org/10.1207/S1532690XCI1901_1"),
        applicable_to=("novice-to-independent procedural learning",),
        implementation_contract=("Follow a complete example with partially completed practice.", "End with an independent attempt using the same success standard."),
        limitations=("Fade only after the learner has enough schema to avoid random guessing.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.SELF_EXPLANATION,
        evidence_tier=EvidenceTier.MODERATE,
        source_urls=(_DUNLOSKY, "https://doi.org/10.1207/s15516709cog1302_1"),
        applicable_to=("worked examples", "causal reasoning", "transfer"),
        implementation_contract=("Ask why each important step follows.", "Require the learner to connect the case to a general rule."),
        limitations=("Unguided explanation can rehearse misconceptions; provide criteria or feedback.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.INTERLEAVING,
        evidence_tier=EvidenceTier.MODERATE,
        source_urls=(_IES_GUIDE, "https://doi.org/10.1007/s10648-007-9049-6"),
        applicable_to=("choosing among confusable strategies", "case discrimination"),
        implementation_contract=("Mix at least two problem types without naming the method first.", "Ask the learner to justify the selected method."),
        limitations=("Do not interleave unrelated tasks merely to add variety.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.ACTIVE_APPLICATION,
        evidence_tier=EvidenceTier.STRONG,
        source_urls=("https://doi.org/10.1073/pnas.1319030111",),
        applicable_to=("applied skills", "decision making", "artifact production"),
        implementation_contract=("Require a decision or artifact, not only reading.", "Make the task match the target performance."),
        limitations=("Effect estimates from STEM classrooms should not be copied directly to every professional domain.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.FEEDBACK_REVISION,
        evidence_tier=EvidenceTier.STRONG,
        source_urls=("https://doi.org/10.3102/003465430298487",),
        applicable_to=("artifact quality", "misconception correction", "deliberate improvement"),
        implementation_contract=("Compare current work with an explicit standard.", "Require a concrete revision after actionable feedback."),
        limitations=("Praise or scores alone do not specify the next correction.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.MASTERY_CHECKS,
        evidence_tier=EvidenceTier.MODERATE,
        source_urls=("https://doi.org/10.3102/0013189X013006004",),
        applicable_to=("prerequisite sequences", "safety-critical foundations"),
        implementation_contract=("Test the stated prerequisite with observable criteria.", "Route failed checks to corrective practice before progression."),
        limitations=("A single threshold should not imply permanent mastery or ignore measurement error.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.CONCRETE_ABSTRACT_LINKING,
        evidence_tier=EvidenceTier.MODERATE,
        source_urls=(_IES_GUIDE,),
        applicable_to=("concept formation", "transfer from cases to frameworks"),
        implementation_contract=("Show how concrete features map to abstract components.", "Test the same abstraction in a meaningfully different case."),
        limitations=("One memorable example can create a brittle, example-bound rule.",),
    ),
    TechniqueRegistryEntry(
        technique_id=TechniqueId.VISUAL_VERBAL,
        evidence_tier=EvidenceTier.MODERATE,
        source_urls=("https://doi.org/10.1017/CBO9780511811678",),
        applicable_to=("systems", "sequences", "relationships difficult to express linearly"),
        implementation_contract=("Use a visual only when its spatial structure carries meaning.", "Explain the same relationship in concise aligned words."),
        limitations=("Decorative or redundant visuals increase cognitive load without improving understanding.",),
    ),
)


def validate_pilot_manifests() -> None:
    identities = [skill.identity_hash for skill in PILOT_SKILLS]
    if len(identities) != len(set(identities)):
        raise ValueError("pilot skill identities must be unique")
    technique_ids = [entry.technique_id for entry in TECHNIQUE_REGISTRY]
    if len(technique_ids) != len(set(technique_ids)):
        raise ValueError("technique registry entries must be unique")
    expected = set(TechniqueId)
    if set(technique_ids) != expected:
        raise ValueError("technique registry must cover every supported technique")


validate_pilot_manifests()
