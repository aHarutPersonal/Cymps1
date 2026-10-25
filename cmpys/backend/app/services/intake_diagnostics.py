"""Versioned, bounded intake checks. A correct item is not general mastery."""

from dataclasses import dataclass
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
BY_ID = {item.id: item for pair in BANK.values() for item in pair}


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
    elif not text or text in {"not specified", "learn", "учиться"}:
        domain = (
            "investing" if re.search(r"buffett|баффет", normalized(idol)) else "general"
        )
    else:
        domain = "general"
    return BANK[domain][0 if key == "foundation_check" else 1]


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
        if answer_evidence_status(answer) != "self_reported" or value in {
            "i don t know yet",
            "пока не знаю",
        }:
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
        result.append(
            {
                "check": key,
                "diagnostic_id": item.id,
                "skill_id": item.skill,
                "status": status,
                "answer": answer,
                "scope": "One brief item; not proof of mastery or professional level.",
            }
        )
    return result
