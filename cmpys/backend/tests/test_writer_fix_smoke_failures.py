"""The five baseline writer failures of the 29 Oct smoke pilot, replayed offline.

Fixtures are the real PlanTutorialLessonSectionsOutput drafts (or their
fences) from smoke-baseline/. Each failure now either normalises and passes,
reports every defect with its fix, or receives an issue-specific correction.
Real arithmetic errors are still rejected.
"""
import json
import re

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialLessonSectionsOutput
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_writer import (
    _TUTORIAL_GROUP, _normalize_tutorial_fence_layout, _prompt, _tokens, _validated_group,
)
from app.services.planning.tutorial_blocks import fence_errors, normalize_fence
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_package_fixture

SMOKE_DRAFTS = {'project_design_2': {'check_your_understanding': '```check\n'
                                                  'Q: «Եթե առաջին շաբաթում գրանցված օգտատերերի կեսը առնվազն '
                                                  'երեք անգամ օգտագործեն գործիքը, կավելացնենք էկրանի նոր '
                                                  'տարբերակը»։ Ո՞ր տարրն է դեռ վտանգված։\n'
                                                  '- [ ] Դիտարկելի վարք\n'
                                                  '- [x] Լսարանի սահմանափակում\n'
                                                  '- [ ] Չափելի չափանիշ\n'
                                                  '- [ ] Մեկ որոշում\n'
                                                  'Why: «Կեսը» թիվ է և վարքը երևում է, բայց «գրանցված '
                                                  'օգտատերեր» խումբը անորոշ է՝ ո՞վ է հաշվվում և ե՞րբ է '
                                                  'գրանցվել։\n'
                                                  '```',
                      'core_framework': 'Փորձարկելի շրջանակը մեկ հստակ հարց է, որը կարելի է պատասխանել '
                                        'դիտարկումով։ Չորս տարր է պետք․ կոնկրետ որոշում, դիտարկելի վարք, '
                                        'չափելի հաջողության չափանիշ և սահմանափակ լսարան՝ հստակ պայմաններով։ '
                                        'Որոշումը պետք է ասի, թե ինչ ենք անելու արդյունքից հետո, ոչ թե '
                                        'պարզապես կանխատեսի։ Վարքը երևում է՝ սեղմում է, գրանցվում է, '
                                        'ավարտում է քայլը։ «Հավանել» կամ «երջանիկ լինել» վարք չէ․ զգացում է։ '
                                        'Չափանիշը թիվ է սահմանով, ընտրված որոշման պահին։ Լսարանը կոնկրետ '
                                        'խումբ է, ոչ թե «բոլորը»։\n'
                                        '\n'
                                        '```comparison\n'
                                        'Փորձարկելի չէ (Not testable)\n'
                                        '- «Բոլորը կսիրեն այն»\n'
                                        '- Որոշում չկա՝ ինչ անել արդյունքով\n'
                                        '- Հաջողությունը չափելի չէ\n'
                                        'vs\n'
                                        'Փորձարկելի է (Testable)\n'
                                        '- Դիտարկվում է կոնկրետ վարք\n'
                                        '- Մեկ հստակ որոշում\n'
                                        '- Չափանիշ՝ թիվ և սահման\n'
                                        '```\n'
                                        '\n'
                                        'Երբ երկու որոշում է միահյուսված, բաժանիր դրանք երկու փորձի։ Երբ '
                                        'վարք չկա՝ հարցրու՝ «ի՞նչ կտեսնեմ տեսանյութում»։',
                      'failure_modes': 'Տարածված սխալը մեկ փորձին երկու որոշում խառնելն է, օրինակ՝ '
                                       '«հավանո՞ւմ են և արժե՞ զարգացնել»։ Ուղղումը՝ ընտրիր մեկ որոշում, '
                                       'մյուսը թող հաջորդ փորձի համար։',
                      'references': 'Ընտրովի ընթերցում․ «Lean Analytics»՝ Alistair Croll-ի և Benjamin '
                                    'Yoskovitz-ի, գլուխ փորձարկելի վարկածների մասին։',
                      'why_this_matters': 'Փորձարկելի շրջանակը փորձի հիմքն է․ առանց դրա թիմը ժամանակ է '
                                          'կորցնում և երբեք չի իմանում, թե իրոք ինչ սովորեց։',
                      'worked_example': 'Դիտարկիր «Ժամանակացույց» թիմի թույլ շրջանակը․ «Մենք ուզում ենք '
                                        'իմանալ, արդյոք օգտատերերը հավանում են գործիքը և արդյոք այն արժե '
                                        'զարգացնել»։ Քայլ առ քայլ․\n'
                                        '\n'
                                        '```steps\n'
                                        'title: Շրջանակի ստուգում չորս տարրով\n'
                                        'Որոշում | | Երկու որոշում է միահյուսված՝ հավանելություն և '
                                        'զարգացնելու արժեք։\n'
                                        'Վարք | | «Հավանել» չի երևում։ Դիտարկելի կլիներ՝ օգտատերը գործիքով '
                                        'պլան է կազմում մինչև ավարտ։\n'
                                        'Չափանիշ | | «Ամեն ինչ լավ ստացվի» թիվ չունի և սահման չունի։\n'
                                        'Լսարան և պայմաններ | | «Կտեսնեն մեկ անգամ» պայմանն է, բայց լսարանը '
                                        'անորոշ է՝ «օգտատերեր»։\n'
                                        '```\n'
                                        '\n'
                                        'Ուղղումը․ բաժանիր երկու փորձի և ընտրիր մեկը։ Օրինակ՝ «Եթե գրասեղանի '
                                        'աշխատողների առաջին խմբի առնվազն 40%-ը մեկ նիստում կազմի առնվազն մեկ '
                                        'ամբողջական շաբաթվա պլան, ապա կներկայացնենք պրոտոտիպը '
                                        'ղեկավարությանը»։ Այստեղ կա մեկ որոշում, դիտարկելի վարք՝ ավարտված '
                                        'պլան, թվային չափանիշ՝ 40% սահմանով, և կոնկրետ լսարան՝ գրասեղանի '
                                        'աշխատողների առաջին խումբ։'},
 'software_1': {'check_your_understanding': '```check\n'
                                            "Q: Nova's queue redelivers 30 messages at $18 each. With no "
                                            'idempotency check, how many duplicate charges occur?\n'
                                            '- [x] 30\n'
                                            '- [ ] 0\n'
                                            '- [ ] 120\n'
                                            '- [ ] 540\n'
                                            'Why: Each redelivery runs the handler again and charges again, '
                                            'so duplicates equal redeliveries: 30. The 540 is the dollar '
                                            'excess, not a count of charges.\n'
                                            '```',
                'core_framework': 'Idempotency means running the same operation more than once produces the '
                                  'same result as running it once. In a job handler triggered by a message '
                                  'queue, redelivery is normal, not an error: a worker may crash after doing '
                                  'the work but before acknowledging, so the queue sends the message again. '
                                  'A handler that charges a card on every delivery will charge duplicates. '
                                  'The fix is one pattern: check a stable key before performing the effect. '
                                  'A stable key is an identifier that is identical across deliveries of the '
                                  'same logical job, such as an order id. Before doing the irreversible '
                                  'action (the charge, the email), the handler asks "have I already recorded '
                                  'this key as done?" using a store that survives restarts, like a database '
                                  'table. If yes, it skips the effect; if no, it performs the effect and '
                                  'records the key. The check must come before the effect, not after, '
                                  'because after is too late to prevent the duplicate.\n'
                                  '```diagram\n'
                                  '[Message arrives with order id]\n'
                                  '   │\n'
                                  '   ▼\n'
                                  '[Check: has this order id been done?]\n'
                                  '   │\n'
                                  '   ▼\n'
                                  '[Yes: skip the charge]\n'
                                  '   │\n'
                                  '   ▼\n'
                                  '[No: charge, then record the order id]\n'
                                  '```\n'
                                  'The diagram shows the whole concept: one key, one check, one effect. '
                                  'Everything in the practice flows from it.',
                'failure_modes': 'The common mistake is putting the check after the effect, or keying it on '
                                 'something unstable like a message id, which differs per delivery. '
                                 'Correction: check a stable business key, such as order id, before the '
                                 'effect.',
                'references': 'Optional background reference on idempotent API and handler design; Martin '
                              "Kleppmann's Designing Data-Intensive Applications.",
                'why_this_matters': 'Message queues redeliver messages after crashes, so any job handler may '
                                    'run twice. Idempotency means a second run does no extra harm, like '
                                    'charging a card or emailing twice.',
                'worked_example': "Nova Delivery's payment handler has no check, so every redelivery charges "
                                  'again. Today the queue processed 120 distinct orders and redelivered 30 '
                                  'messages for orders already handled, at $18 per order.\n'
                                  '```steps\n'
                                  'title: Nova Delivery (fictional case)\n'
                                  'unit: USD\n'
                                  'Correct charges, one per order | 2160 | 120 distinct orders times 18 '
                                  'each.\n'
                                  '+ Duplicate charges | [[result:nova_delivery_case.duplicate_charges]] | '
                                  '30 redeliveries charged again, one extra charge each.\n'
                                  '+ Excess from duplicates | [[result:nova_delivery_case.excess_charged]] | '
                                  'Each duplicate adds 18 more: 30 times 18.\n'
                                  '= Amount actually charged | 2700 | 2160 plus 540 of pure duplicates.\n'
                                  '```\n'
                                  'The correct total, with an idempotency check keyed on order id, is 120 '
                                  'orders times $18, or [[result:nova_delivery_case.expected_charges]]. The '
                                  'handler should look up the order id before the charge line, skip if the '
                                  'order is already marked done, and only otherwise charge and mark done. '
                                  'The check belongs before the charge because the charge is the effect you '
                                  'cannot undo.'},
 'software_2': {'check_your_understanding': '```check\n'
                                            "Q: Nova's queue redelivers 30 messages at $18 each. With no "
                                            'idempotency check, how many duplicate charges occur?\n'
                                            '- [x] 30\n'
                                            '- [ ] 0\n'
                                            '- [ ] 120\n'
                                            '- [ ] 540\n'
                                            'Why: Each redelivery runs the handler again and charges again, '
                                            'so duplicates equal redeliveries: 30. The 540 is the dollar '
                                            'excess, not a count of charges.\n'
                                            '```',
                'core_framework': 'Idempotency means running the same operation more than once produces the '
                                  'same result as running it once. In a job handler triggered by a message '
                                  'queue, redelivery is normal, not an error: a worker may crash after doing '
                                  'the work but before acknowledging, so the queue sends the message again. '
                                  'A handler that charges a card on every delivery will charge duplicates. '
                                  'The fix is one pattern: check a stable key before performing the effect. '
                                  'A stable key is an identifier that is identical across deliveries of the '
                                  'same logical job, such as an order id. Before doing the irreversible '
                                  'action (the charge, the email), the handler asks "have I already recorded '
                                  'this key as done?" using a store that survives restarts, like a database '
                                  'table. If yes, it skips the effect; if no, it performs the effect and '
                                  'records the key. The check must come before the effect, not after, '
                                  'because after is too late to prevent the duplicate.\n'
                                  '```diagram\n'
                                  '[Message arrives with order id]\n'
                                  '   │\n'
                                  '   ▼\n'
                                  '[Check: has this order id been done?]\n'
                                  '   │\n'
                                  '   ▼\n'
                                  '[Yes: skip the charge]\n'
                                  '   │\n'
                                  '   ▼\n'
                                  '[No: charge, then record the order id]\n'
                                  '```\n'
                                  'One key, one check, one effect: everything in the practice flows from '
                                  'this diagram.',
                'failure_modes': 'The common mistake is putting the check after the effect, or keying it on '
                                 'something unstable like a message id, which differs per delivery. '
                                 'Correction: check a stable business key, such as order id, before the '
                                 'effect.',
                'references': 'Optional background reference on idempotent handler design; Martin '
                              "Kleppmann's Designing Data-Intensive Applications.",
                'why_this_matters': 'Message queues redeliver messages after crashes, so any job handler may '
                                    'run twice. Idempotency means a second run does no extra harm, like '
                                    'charging a card or emailing twice.',
                'worked_example': "Nova Delivery's payment handler has no check, so every redelivery charges "
                                  'again. Today the queue processed 120 distinct orders and redelivered 30 '
                                  'messages for orders already handled, at $18 per order.\n'
                                  '```steps\n'
                                  'title: Nova Delivery (fictional case)\n'
                                  'unit: USD\n'
                                  'Correct charges, one per order | 2160 | 120 distinct orders times 18 '
                                  'each.\n'
                                  '+ Excess from duplicate charges | '
                                  '[[result:nova_delivery_case.excess_charged]] | 30 redeliveries each '
                                  'charge 18 again: 30 times 18.\n'
                                  '= Amount actually charged | 2700 | 2160 plus 540 of pure duplicates.\n'
                                  '```\n'
                                  'The duplicates number [[result:nova_delivery_case.duplicate_charges]] '
                                  'because each redelivery runs the handler once more. With an idempotency '
                                  'check keyed on order id, the correct total is 120 orders times $18, or '
                                  '[[result:nova_delivery_case.expected_charges]]. The handler should look '
                                  'up the order id before the charge line, skip if the order is already '
                                  'marked done, and only otherwise charge and mark done. The check belongs '
                                  'before the charge because the charge is the effect you cannot undo.'}}


def nova_package() -> dict:
    raw = structured_package_fixture(package_payload())
    for activity in raw["workbook"]["activities"]:
        activity.update(minutes_min=1, minutes_max=2)
    raw["teaching_cases"] = [{
        "id": "nova_delivery_case",
        "assumptions": "Nova Delivery is fictional; one day of charges in USD at 18 per order.",
        "data": [{"id": "orders", "label": "Distinct orders", "value": 120, "unit": "orders"},
                 {"id": "price", "label": "Charge per order", "value": 18, "unit": "USD"},
                 {"id": "redeliveries", "label": "Redelivered messages", "value": 30, "unit": "messages"}],
        "results": [{"id": "duplicate_charges", "label": "Duplicate charges", "expression": "redeliveries * 1",
                     "unit": "charges", "decimal_places": 0},
                    {"id": "excess_charged", "label": "Excess charged", "expression": "redeliveries * price",
                     "unit": "USD", "decimal_places": 0},
                    {"id": "expected_charges", "label": "Expected charges", "expression": "orders * price",
                     "unit": "USD", "decimal_places": 0}]}]
    return LessonPackage.model_validate(raw).writer_context()


def validate(data: dict, context: dict | None = None):
    tokens = _tokens(context) if context else (set(), set())
    return _validated_group(LLMResponse(data=data), _TUTORIAL_GROUP, PlanTutorialLessonSectionsOutput,
                            *tokens, package_context=context, allotted_lesson_minutes=None)


def steps_body(text: str) -> str:
    return re.search(r"```steps\n(.*?)```", text, re.S)[1]


# --- software_novice_evidence: a note after the total number ----------------

def test_software_total_row_note_is_normalised_and_the_draft_is_stored_normalised():
    context = nova_package()
    payload, issues = validate(SMOKE_DRAFTS["software_2"], context)
    assert issues == []
    assert "= Amount actually charged | 2700\n```" in payload["worked_example"]
    assert "2160 plus 540 of pure duplicates" not in payload["worked_example"]
    # Everything else is untouched.
    assert payload["core_framework"] == SMOKE_DRAFTS["software_2"]["core_framework"]


def test_software_real_sum_error_is_still_rejected_with_the_running_total_hint():
    # 2160 + 30 duplicate charges + 540 = 2730, not 2700: a real arithmetic slip.
    payload, issues = validate(SMOKE_DRAFTS["software_1"], nova_package())
    assert payload is None
    [issue] = issues
    assert issue.startswith("worked_example steps fence is invalid: total 2700 must equal the sum")
    assert "(2730)" in issue and "every row with a number adds into the running total" in issue


def test_software_note_is_reported_with_its_fix_when_not_normalised():
    body = steps_body(SMOKE_DRAFTS["software_2"]["worked_example"]).replace(
        "[[result:nova_delivery_case.excess_charged]]", "540")
    [error] = fence_errors("steps", body)
    assert "line '= Amount actually charged | 2700 | 2160 plus 540" in error
    assert 'remove the text after the number on the "=" row' in error


# --- accounting_novice_evidence: two results in one steps fence -------------

ACCOUNTING_1 = """title: November cafe (fictional case)
unit: USD
Revenue earned | 4800 | Cash sales plus invoiced corporate sales count as earned, even if unpaid.
− Expenses incurred | −3300 | Includes an unpaid supplier invoice due in December.
= Accrual profit | 1500

Cash collected | 4100 | Only money that actually arrived in November.
− Cash paid | −2900 | Suppliers, wages and rent actually paid.
= Change in cash | 1200
"""
ACCOUNTING_2 = """title: November cafe (fictional case)
unit: USD
Revenue earned | 4800 | Cash sales plus invoiced corporate sales count as earned, even if unpaid.
− Expenses incurred | −3300 | Includes an unpaid supplier invoice due in December.
= Accrual profit | 1500 | Performance for the month.
"""


def test_accounting_second_result_gets_the_one_final_total_hint():
    errors = fence_errors("steps", ACCOUNTING_1)
    [mid] = [error for error in errors if error.startswith("line '= Accrual profit | 1500'")]
    assert 'only the last line may start with "="' in mid
    assert "total the main result" in mid and "its own valued row, the chart or prose" in mid
    assert "never a second" in mid
    # The sum of the two halves is not misreported as an arithmetic slip.
    assert not any("must equal the sum" in error for error in errors)


def test_accounting_corrected_total_with_note_is_normalised_and_accepted():
    assert fence_errors("steps", ACCOUNTING_2)
    normalised = normalize_fence("steps", ACCOUNTING_2)
    assert normalised.endswith("= Accrual profit | 1500\n")
    assert fence_errors("steps", normalised) == []


# --- geometry_experienced_evidence: bare unit line + multiplicative steps ----

GEOMETRY_1 = """title: Pennant banner area
cm
Base | 30 | The chosen side, measured along the bottom edge.
Height | 14 | Perpendicular from the base line to the vertex.
Multiply | 420 | 30 × 14 gives the full rectangle's area.
Halve it | −210 | Two identical pennants fill one rectangle, so one is half.
= Area | 210
"""


def test_geometry_unit_line_is_normalised_and_the_masked_sum_defect_is_reported():
    # Before: only "row 'cm' must be ..." was reported, hiding the real defect.
    raw = fence_errors("steps", GEOMETRY_1)
    assert any("line 'cm'" in error and "unit: cm" in error for error in raw)
    assert any("(254)" in error for error in raw)
    normalised = normalize_fence("steps", GEOMETRY_1)
    assert normalised.startswith("title: Pennant banner area\nunit: cm\nBase | 30 |")
    [error] = fence_errors("steps", normalised)
    assert "total 210 must equal the sum of the rows above it (254)" in error
    assert "give inputs such as base or height an empty number cell" in error
    assert "write a product as one row" in error


# --- philosophy_experienced_evidence: missing [x] behind a semicolon --------

PHILOSOPHY_1 = """Q: In the garden notice, which detail most strongly supports Reading B, the appeal to shared values?
- [ ] The vote takes place on Saturday
- [ ] The closing appeal to rhythms and tradition
- [ ] A sign-up system is on the ballot
Why: Rhythms and tradition are value words that invite feelings about continuity; the other options are background facts that support neither reading strongly.
"""


def test_philosophy_semicolon_is_normalised_and_the_missing_answer_is_reported_at_once():
    raw = fence_errors("check", PHILOSOPHY_1)
    assert any("semicolon" in error for error in raw)
    assert any("mark at least one correct option with [x]" in error for error in raw)
    normalised = normalize_fence("check", PHILOSOPHY_1)
    assert "about continuity, the other options" in normalised
    [error] = fence_errors("check", normalised)
    assert "mark at least one correct option with [x]" in error
    fixed = normalised.replace("- [ ] The closing", "- [x] The closing")
    assert fence_errors("check", fixed) == []


def test_philosophy_normalisation_reaches_the_stored_sections():
    data = {"check_your_understanding": "Pick one.\n\n```check\n" + PHILOSOPHY_1.replace(
        "- [ ] The closing", "- [x] The closing") + "```", "references": "A; B stays in prose."}
    normalised = _normalize_tutorial_fence_layout(data)
    assert "continuity, the other options" in normalised["check_your_understanding"]
    assert normalised["references"] == "A; B stays in prose."


# --- project_design_novice_missing: 372-373 words, below the length floor ---

def test_project_design_short_draft_gets_an_add_words_correction():
    draft = SMOKE_DRAFTS["project_design_2"]
    payload, issues = validate(draft)
    assert payload is None
    [issue] = issues
    assert issue.startswith("tutorial fields have 373 words; they must total 430-720 words")
    prompt = _prompt(_TUTORIAL_GROUP, "context", nova_package(), issues, previous_sections=draft)
    correction = prompt[prompt.index("REVISE THE PREVIOUS COMPLETE DRAFT"):prompt.index("\nLESSON CONTEXT")]
    assert "373 words" in correction and "430-720" in correction
    assert "add about 117 words" in correction.lower()  # toward the 490-word aim
    for name, words, low, high in (("why_this_matters", 19, 25, 35), ("core_framework", 127, 150, 190),
                                   ("worked_example", 128, 140, 190), ("failure_modes", 23, 30, 50),
                                   ("references", 13, 15, 25)):
        assert f"{name} ({words} words; its range is {low}-{high})" in correction
    assert "check_your_understanding (" not in correction
    assert "Remove nothing" in correction
    assert "Remove repetition" not in correction and "verbose" not in correction


def test_project_design_first_attempt_mixes_fence_and_length_instructions():
    draft = json.loads(json.dumps(SMOKE_DRAFTS["project_design_2"]))
    draft["core_framework"] = draft["core_framework"].replace(" (Not testable)", "").replace(" (Testable)", "")
    payload, issues = validate(draft)
    assert any("comparison fence is invalid" in issue and "translation in parentheses" in issue for issue in issues)
    prompt = _prompt(_TUTORIAL_GROUP, "context", nova_package(), issues, previous_sections=draft)
    correction = prompt[prompt.index("REVISE THE PREVIOUS COMPLETE DRAFT"):prompt.index("\nLESSON CONTEXT")]
    assert "Fix the native block lines named in the issues" in correction
    assert "edit prose only as needed for the budget" in correction
    assert "add about" in correction.lower() and "Remove nothing from the prose" in correction
    assert "Fix only" not in correction and "native block line and binding" not in correction


def test_fence_only_correction_keeps_every_other_sentence():
    context = nova_package()
    payload, issues = validate(SMOKE_DRAFTS["software_1"], context)
    prompt = _prompt(_TUTORIAL_GROUP, "context", context, issues, previous_sections=SMOKE_DRAFTS["software_1"])
    correction = prompt[prompt.index("REVISE THE PREVIOUS COMPLETE DRAFT"):prompt.index("\nLESSON CONTEXT")]
    assert "Fix only the native block lines named in the issues" in correction
    assert "keep every other sentence" in correction
    assert "Remove repetition" not in correction and "add about" not in correction.lower()


def test_too_long_draft_keeps_the_trimming_correction():
    draft = json.loads(json.dumps(SMOKE_DRAFTS["software_2"]))
    draft["core_framework"] += " Padding sentence that repeats the idea once more." * 40
    payload, issues = validate(draft, nova_package())
    assert payload is None and any(issue.startswith("tutorial fields have ") for issue in issues)
    prompt = _prompt(_TUTORIAL_GROUP, "context", nova_package(), issues, previous_sections=draft)
    correction = prompt[prompt.index("REVISE THE PREVIOUS COMPLETE DRAFT"):prompt.index("\nLESSON CONTEXT")]
    assert "Remove repetition and verbose phrasing" in correction
    assert "Remove nothing" not in correction
