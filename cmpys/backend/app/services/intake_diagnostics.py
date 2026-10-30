"""Versioned, bounded intake checks. A correct item is not general mastery."""

from dataclasses import dataclass, replace
import re


def normalized(text: str) -> str:
    return " ".join(re.sub(r"[^\w\s]", " ", text.casefold()).split())


def answer_evidence_status(text: str) -> str:
    value = normalized(text)
    if not value:
        return "missing"
    if value in {
        "не знаю",
        "пока не знаю",
        "не уверен",
        "не уверена",
        "не помню",
        "затрудняюсь ответить",
        "i don t know",
        "i don t know yet",
        "i dont know",
        "i dont know yet",
        "i do not know",
        "i do not know yet",
        "don t know",
        "not sure",
        "unsure",
        "idk",
        "skip",
        "пропустить",
        "не хочу отвечать",
        "ok",
        "okay",
        "ок",
    }:
        return "unknown"
    return "self_reported"


def reports_no_achievements(text: str) -> bool:
    # A leading explicit answer remains meaningful when followed by an explanation.
    # A contrasting exception may contain a real achievement and needs review.
    first = re.split(r"[.!;\n]", text.strip(), maxsplit=1)[0]
    value = normalized(first)
    if re.search(r"\b(?:but|except|however|кроме|но)\b", value):
        return False
    return bool(re.match(
        r"^(?:none(?: yet)?|nothing(?: yet)?|no (?:relevant )?achievements(?: yet)?|"
        r"пока нет|пока ничего|нет|ничего)(?:$|\s)", value
    ))


def has_established_habit_evidence(text: str) -> bool:
    value = normalized(text)
    if answer_evidence_status(text) != "self_reported":
        return False
    if re.search(
        r"new (?:study )?(?:habit|schedule|routine)|(?:habit|schedule|routine) is new|no (?:past|established|existing|regular)|not (?:yet )?established|"
        r"haven t started|have not started|haven t built|no (?:study )?(?:habit|routine)|"
        r"(?:do not|don t) have (?:a |an |any )?(?:study )?(?:habit|routine|schedule)|"
        r"\b(?:none|nothing|not yet)\b|\b(?:plan|hope|want) to\b|\b(?:i will|i ll|going to)\b|\bwill start\b|"
        r"\b(?:don t|do not|cannot|can t|could|would|should)\b|"
        r"новая привычка|пока нет|пока ничего|ещ[её] не начал", value
    ):
        return False
    # A preference or available hours alone does not establish discipline.
    # Require at least a reported repeated action/cadence or sustained routine.
    has_cadence = bool(re.search(
        r"\b(?:every|each) (?:day|week|morning|evening|night|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|"
        r"\b(?:daily|weekly|regularly|consistently)\b|"
        r"\b(?:once|twice|three times|\d+ times) (?:a |per )?(?:day|week)\b|"
        r"\bfor (?:\d+|one|two|three|four|six|several) (?:weeks|months|years)\b|"
        r"кажд(?:ый|ую|ое) (?:день|неделю|утро|вечер)|ежедневно|еженедельно|регулярно", value
    ))
    has_action = bool(re.search(
        r"\b(?:i|we) (?:(?:have|been|regularly|consistently|always|usually) )*"
        r"(?:study|studied|studying|read|reading|practice|practise|practiced|practised|"
        r"practicing|practising|review|reviewed|write|writing|wrote|train|trained|"
        r"work|worked|learn|learned|learnt|learning|exercise|exercised|complete|completed)\b|"
        r"\bя (?:регулярно )?(?:читаю|учусь|занимаюсь|практикую|пишу|тренируюсь)\b", value
    ))
    return has_cadence and has_action


@dataclass(frozen=True)
class Diagnostic:
    id: str
    skill: str
    question: str
    options: tuple[str, ...] = ()
    correct: str | None = None
    criterion: str = ""
    option_feedback: tuple[str, ...] = ()

    def response_ui(self, key: str) -> dict:
        result = {
            "version": 1,
            "kind": "single_choice" if self.options else "text",
            "answer_key": key,
            "diagnostic_id": self.id,
            "allow_custom": True,
            "placeholder": "Choose an answer, explain, or say you don't know…",
        }
        if self.options:
            result["options"] = list(self.options) + ["I don't know yet"]
        return result


# All cases are fictional. No financial action or personal assets are required.
BANK = {
    "investing": (
        Diagnostic(
            "investing.profit_cash.v1",
            "profit_vs_cash",
            "A fictional business earns 100 on credit and pays 60 in expenses. "
            "Its customer hasn’t paid yet. Ignoring taxes and other transactions, "
            "what are its profit and change in cash?",
            (
                "Profit 40; cash change −60",
                "Profit 40; cash change 40",
                "Profit 100; cash change −60",
            ),
            "Profit 40; cash change −60",
        ),
        Diagnostic(
            "investing.maintenance.v1",
            "maintenance_vs_growth",
            "A fictional business has 120 in operating cash flow after working-capital changes. "
            "Maintenance costs 30; optional expansion costs 50. Ignoring financing, "
            "how much remains after maintenance, before expansion?",
            ("40", "90", "120"),
            "90",
        ),
    ),
    "geometry": (
        Diagnostic(
            "geometry.right_triangle.v1",
            "pythagorean_calculation",
            "Quick skill check. A right triangle has perpendicular sides of 3 cm and 4 cm. "
            "What is the length of its hypotenuse?",
            ("5 cm", "7 cm", "12 cm"),
            "5 cm",
        ),
        Diagnostic(
            "geometry.assumption.v1",
            "pythagorean_precondition",
            "A different triangle has two sides of 5 cm and 12 cm. Its angles are unknown. "
            "Can you conclude that its third side is 13 cm?",
            (
                "Yes, for every triangle",
                "Only if those two sides meet at a right angle",
                "No triangle can have those lengths",
            ),
            "Only if those two sides meet at a right angle",
        ),
    ),
    "reasoning": (
        Diagnostic(
            "reasoning.implication.v1",
            "logical_implication",
            "Quick skill check. Assume all members of a club read books. Alex reads books. "
            "Must Alex belong to the club?",
            (
                "Yes",
                "No, the premises do not establish membership",
                "Alex cannot be a member",
            ),
            "No, the premises do not establish membership",
        ),
        Diagnostic(
            "reasoning.counterexample.v1",
            "universal_counterexample",
            "Someone claims every member of a club reads daily. "
            "Which observation would disprove that claim?",
            (
                "A member who does not read daily",
                "A non-member who reads daily",
                "A member who reads daily",
            ),
            "A member who does not read daily",
        ),
    ),
    "programming": (
        Diagnostic(
            "programming.assignment.v1", "assignment_and_state",
            "Read this pseudocode: score = 2; saved = score; score = 5. "
            "What value does saved hold at the end?",
            ("2", "5", "7"), "2",
            "Trace the value copied by an assignment before a later reassignment.",
            ("", "Selected automatic updating of a previously copied value.",
             "Selected addition although the program contains no addition."),
        ),
        Diagnostic(
            "programming.boundary.v1", "conditional_boundary",
            "A function should accept ages 18 and above. Its condition is age > 18. "
            "Which input exposes the boundary error?",
            ("17", "18", "19"), "18",
            "Choose the boundary input where required and implemented behavior differ.",
            ("Selected an input both conditions reject.", "",
             "Selected an input both conditions accept."),
        ),
    ),
    "writing": (
        Diagnostic(
            "writing.supported_claim.v1", "claim_evidence_alignment",
            "A team tested a draft email with five volunteers; four found the date clearer. "
            "Which claim is supported by this evidence?",
            ("Most of these volunteers found the date clearer",
             "The draft works better for every reader", "The draft doubles attendance"),
            "Most of these volunteers found the date clearer",
            "Keep the claim within the sample and outcome actually observed.",
            ("", "Generalized a small volunteer sample to every reader.",
             "Claimed an attendance effect that was not measured."),
        ),
        Diagnostic(
            "writing.actionable_request.v1", "actionable_request",
            "A colleague must approve a draft by Friday so it can be printed Monday. "
            "Which request gives them the action, deadline and reason?",
            ("Please look at this when you can",
             "Please approve the draft by Friday so we can print Monday",
             "Printing happens Monday; this draft matters"),
            "Please approve the draft by Friday so we can print Monday",
            "Make the reader's required action, deadline and purpose explicit.",
            ("Selected a request without a deadline or purpose.", "",
             "Selected context without an explicit approval request or deadline."),
        ),
    ),
    "data": (
        Diagnostic(
            "data.denominator.v1", "compare_rates",
            "In two fictional samples, 20 of 100 visitors in A signed up, "
            "and 30 of 300 in B signed up. Which sample has the higher signup rate?",
            ("A", "B", "They have the same rate"), "A",
            "Compare proportions using each sample's own denominator.",
            ("", "Selected the larger count despite its lower proportion.",
             "Selected equal rates despite different proportions."),
        ),
        Diagnostic(
            "data.causality.v1", "causal_inference_limit",
            "Sales rose after a website redesign, during a holiday promotion. "
            "There was no comparison group. What can this observation establish?",
            ("The redesign caused the increase", "The promotion caused all of it",
             "Sales rose; the separate effects are not established"),
            "Sales rose; the separate effects are not established",
            "Distinguish an observed change from an isolated causal effect.",
            ("Attributed the change to the redesign without isolating its effect.",
             "Attributed the whole change to the promotion without isolating its effect.", ""),
        ),
    ),
    "general": (
        Diagnostic(
            "general.work_sample.v1",
            "goal_specific_sample",
            "For one small task related to your goal, what would your solution look like? "
            "A short example or ‘I don’t know yet’ is enough. Keep private details out.",
        ),
        Diagnostic(
            "general.validation.v1",
            "goal_specific_validation",
            "For that task, what concrete check would tell you whether your solution works? "
            "If you have not learned how to check it yet, say so.",
        ),
    ),
}
# Keep old question IDs and conditions available for already answered sessions.
GENERAL_CURRENT = (
    Diagnostic(
        "general.attempt.v2", "goal_specific_sample",
        "For your goal, choose one small task and attempt it now. "
        "Show a short answer or a few lines of work; mark where you get stuck. "
        "An honest ‘I don’t know yet’ is fine.",
        criterion="Check the actual attempt against its stated task; distinguish unaided work from help needed.",
    ),
    Diagnostic(
        "general.check.v2", "goal_specific_validation",
        "For a small task toward your goal, show one concrete test that could expose "
        "a mistake in your solution. State what result would count as a failure. "
        "‘I don’t know yet’ is fine.",
        criterion="The check must test the claimed result and identify a possible failure, not just express confidence.",
    ),
)
BY_ID = {item.id: item for pair in (*BANK.values(), GENERAL_CURRENT) for item in pair}

# Added guidance never changes an old item's question, answer key or identity.
_LEGACY_CRITERIA = {
    "investing.profit_cash.v1": "Separate earned revenue from cash received and subtract the paid expenses.",
    "investing.maintenance.v1": "Subtract maintenance from operating cash flow; exclude optional expansion at this stage.",
    "geometry.right_triangle.v1": "Calculate the hypotenuse from the squares of the two perpendicular sides.",
    "geometry.assumption.v1": "Check the right-angle prerequisite before applying the Pythagorean theorem.",
    "reasoning.implication.v1": "Distinguish an implication from its converse.",
    "reasoning.counterexample.v1": "Disprove a universal claim with a member that violates it.",
    "general.work_sample.v1": "Review the sample for correctness in its own task; a description alone is not checked performance.",
    "general.validation.v1": "Check whether the proposed test could detect an error in the specific solution.",
}
_LEGACY_OPTION_FEEDBACK = {
    "investing.profit_cash.v1": (
        "", "Treated unpaid revenue as cash received.",
        "Did not subtract expenses when calculating profit.",
    ),
    "investing.maintenance.v1": (
        "Subtracted optional expansion although the question asks before expansion.",
        "", "Did not subtract maintenance.",
    ),
    "geometry.right_triangle.v1": (
        "", "Added the side lengths instead of using the right-triangle relation.",
        "Multiplied the side lengths instead of calculating the hypotenuse.",
    ),
    "geometry.assumption.v1": (
        "Applied a right-triangle relation without the required angle evidence.",
        "", "Rejected a possible triangle instead of checking its angle condition.",
    ),
    "reasoning.implication.v1": (
        "Reversed the direction of the given implication.", "",
        "Treated insufficient evidence of membership as proof of non-membership.",
    ),
    "reasoning.counterexample.v1": (
        "", "Used a non-member to test a claim restricted to members.",
        "Selected an example consistent with the claim, not a counterexample.",
    ),
}


def select_diagnostic(key: str | None, goal: str, idol: str) -> Diagnostic | None:
    if key not in {"foundation_check", "application_check"}:
        return None
    text = normalized(goal)
    if re.search(r"geometr|геометр|triangle|треуголь", text):
        domain = "geometry"
    elif re.search(r"invest|инвест|accounting|бухгалтер|valuation", text):
        domain = "investing"
    elif re.search(r"philosoph|философ|logic|логик|argument|аргумент", text):
        domain = "reasoning"
    elif re.search(r"\b(?:programming|coding|python|javascript|software)\b|программир", text):
        domain = "programming"
    elif re.search(r"data analys|data analytic|\b(?:statistics|spreadsheet|excel)\b|статистик|анализ данных", text):
        domain = "data"
    elif re.search(r"business writing|copywriting|\b(?:emails?|memos?)\b|делов.*письм|копирайт", text):
        domain = "writing"
    elif not text or text in {"not specified", "learn", "учиться"}:
        domain = (
            "investing" if re.search(r"buffett|баффет", normalized(idol)) else "general"
        )
    else:
        domain = "general"
    index = 0 if key == "foundation_check" else 1
    if domain == "general":
        item = GENERAL_CURRENT[index]
        # The goal is literal learner data. Store the exact displayed question
        # with the answer so later generators can assess the same task.
        goal_label = " ".join(goal.split()[:12])[:80]
        if goal_label != " ".join(goal.split()):
            goal_label += "…"
        return replace(item, question=(f'Goal: “{goal_label}”.\n' if goal_label else "") + item.question)
    return BANK[domain][index]


def diagnostic_summary(answers: dict) -> list[dict]:
    result = []
    for key in ("foundation_check", "application_check"):
        records = answers.get(key) or []
        record = records[-1] if records else {}
        item = BY_ID.get(record.get("diagnostic_id"))
        if item is None:
            result.append({"check": key, "status": "not_assessed"})
            continue
        answer = record.get("answer", "")
        value = normalized(answer)
        if (
            # Sent with the "I don't have one yet" choice: nothing was
            # provided, so the check is not established (as for an empty
            # answer), never a submitted answer that "needs review".
            record.get("missing_evidence") is True
            or answer_evidence_status(answer) != "self_reported"
            or value in {"i don t know yet", "пока не знаю"}
        ):
            status = "unknown"
        elif item.correct is None:
            status = "needs_review"
        elif answer.strip().casefold() == item.correct.casefold():
            status = "correct_on_item"
        elif answer.strip().casefold() in {
            option.casefold() for option in item.options
        }:
            status = "needs_practice_on_item"
        else:
            # Free prose and alternative notations require interpretation, not
            # a false failure from an exact-string grader.
            status = "needs_review"
        criterion = item.criterion or _LEGACY_CRITERIA.get(item.id, "")
        issue = None
        if status == "needs_practice_on_item":
            index = next(i for i, option in enumerate(item.options)
                         if answer.strip().casefold() == option.casefold())
            feedback = item.option_feedback or _LEGACY_OPTION_FEEDBACK.get(item.id, ())
            issue = (feedback[index] if feedback else
                     "The selected option does not satisfy the checked criterion.")
        next_check = {
            "correct_on_item": "Use a fresh unaided case for this skill before increasing difficulty.",
            "needs_practice_on_item": "Check the selected error with a changed case; target this skill only.",
            "needs_review": "Review the actual response against the criterion; clarify uncertainty in the first lesson.",
            "unknown": "Offer a short supported prerequisite check; do not assume beginner level.",
        }[status]
        result.append(
            {
                "check": key,
                "diagnostic_id": item.id,
                "skill_id": item.skill,
                "status": status,
                "answer": answer,
                "question": record.get("question") or item.question,
                "criterion": criterion,
                "observed_issue": issue,
                "next_check": next_check,
                "scope": "One brief item; not proof of mastery or professional level.",
            }
        )
    return result
