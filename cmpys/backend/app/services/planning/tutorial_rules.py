"""Shared tutorial principles, loaded from the same source as generator prompts."""
from app.services.llm.prompt_loader import resolve_prompt_text


def tutorial_rule(rule_id: str) -> str:
    text = resolve_prompt_text("tutorial_contract.txt")
    marker = "[" + rule_id + "]"
    for paragraph in text.split("\n["):
        paragraph = paragraph if paragraph.startswith("[") else "[" + paragraph
        if paragraph.startswith(marker):
            return paragraph.strip()
    raise ValueError(f"Missing tutorial rule: {rule_id}")


TUTORIAL_TRANSFER_RULE = tutorial_rule("R-TRANSFER")


def tutorial_writer_rules() -> str:
    # The writer does not generate answer fields or activity timing metadata.
    return ("\n".join(tutorial_rule(rule_id) for rule_id in (
        "R-TRANSFER", "R-SOURCES", "R-LANGUAGE")) + "\n" + tutorial_evidence_rule())


def tutorial_evidence_rule() -> str:
    return next(line for line in resolve_prompt_text("tutorial_domain_qualitative.txt").splitlines()
                if line.startswith("- Evidence must"))


REVIEW_SEVERITY_RULE = (
    "Classify each finding as blocking or advisory. Blocking means a wrong fact or number, "
    "a contradiction, an answer leak, wrong learner language, an invented source, or an "
    "exercise that cannot be passed from supplied inputs or does not test the requested skill. "
    "For every blocker, quote the defective text and explain its effect on learning or grading. "
    "Wording preferences, harmless rounding and optional refinements are advisory. A preparatory "
    "sub-step need not have a separate field or criterion if the required skill is assessed. "
    "Small factual errors and contradictions still block; their short length is not a reason "
    "to downgrade them. Set acceptable=true when no blocking defects remain. Advisory-only "
    "verdicts require the same complete audits as approvals. Server schema, arithmetic, "
    "source-grounding and privacy checks remain mandatory."
)


def tutorial_review_rules() -> str:
    # Both reviewer templates already include the transfer rule for legacy lessons.
    # Add the other shared principles once, without repeating transfer instructions.
    # R-TIME stays generator-only: tutorial exercise time is server-set and reviewers
    # judge whether an exercise is correct, not how long it takes (owner, 2026-11-06).
    contract = resolve_prompt_text("tutorial_contract.txt")
    for rule_id in ("R-TRANSFER", "R-TIME"):
        contract = contract.replace(tutorial_rule(rule_id), "", 1)
    return (contract + "\n" + tutorial_evidence_rule()
            + "\n" + REVIEW_SEVERITY_RULE)
