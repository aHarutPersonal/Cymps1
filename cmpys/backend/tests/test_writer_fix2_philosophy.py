"""Fix 1 of the second smoke run: a qualitative worked example never gets numbers.

The philosophy writer put "= Verdict | | <note>" (no value) under reasoning
rows. The diagnostic "total '' must be a plain number" pushed the model to
invent per-phrase scores (1/0/3) the package does not contain, and review
could not bind them. Fixtures are the real drafts from smoke2-candidate/.
"""
from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialLessonSectionsOutput
from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _tokens, _validated_group
from app.services.planning.tutorial_blocks import fence_errors, normalize_fence, parse_steps
from app.services.planning.tutorial_visuals import native_fences
from tests.test_tutorial_visuals import harbor_package
from tests.test_tutorial_workload_profile import short_package

NO_NUMBERS = "this case has no numbers; do not score or count — leave step values empty"
LABELLED_STEPS = (  # the repair draft (6ff35cdf) that replaced scores with words
    'title: Library notice (fictional case)\n'
    '"Renovations" | supports A | Repair work implies a building meant to be used again, favoring A.\n'
    '"We thank patrons for their patience" | neutral | Politeness fits both readings, so it supports neither.\n'
    '= Phrases supporting A | renovations, reopen next year, more shelf space\n'
)

VERDICT_DRAFT = {'check_your_understanding': '```check\n'
                             'Q: In the library notice, why is "we thank patrons for their patience" not '
                             'evidence for Reading A (temporary closure)?\n'
                             '- [ ] Because it is too short to count\n'
                             '- [x] Because it fits a permanent closure equally well\n'
                             '- [ ] Because polite phrases are always irrelevant\n'
                             '- [ ] Because only dates can be evidence\n'
                             'Why: Support requires a phrase that fits one reading better than the other. '
                             'Thanks fits both closures, so it merely fails to contradict either reading.\n'
                             '```',
 'core_framework': 'Two interpretations can both be defensible in the sense that neither is contradicted by '
                   'the text, yet only one is actually supported. Support requires specific words that fit '
                   'one reading better than its rival. Non-contradiction — a hopeful tone, a polite regret — '
                   'fits both readings and therefore supports neither. When you weigh rival readings, sort '
                   'every phrase into two piles: genuine evidence (points toward one reading) and mere '
                   'compatibility (consistent with both). The reading with more genuine, specific evidence '
                   'wins; a pile of compatible phrases adds nothing.\n'
                   '\n'
                   '```comparison\n'
                   'Reading A has support\n'
                   '- Specific phrase fits A better than B\n'
                   '- Second phrase points the same way\n'
                   'vs\n'
                   'Reading B is only possible\n'
                   '- Nothing contradicts B\n'
                   '- Tone is neutral or polite toward both\n'
                   '```\n'
                   '\n'
                   'Test each phrase by asking: does this wording fit one reading noticeably better? "We '
                   'plan to reopen next year" fits a temporary closure far better than a permanent one — '
                   'that is support. "We thank patrons" fits either — that is mere compatibility, and '
                   'treating it as evidence is the classic error.',
 'failure_modes': 'The common mistake is counting politeness, regret, or hopeful tone as evidence for a '
                  'favored reading. Correction: ask whether the phrase fits one reading better than the '
                  'other. If it fits both, it supports neither.',
 'references': 'Optional: "Asking the Right Questions" by M. Neil Browne and Stuart Keeley on evaluating '
               'arguments.',
 'why_this_matters': 'Judging arguments means telling evidence that genuinely supports a reading from text '
                     'that merely fails to contradict it. This skill prevents overclaiming from silence.',
 'worked_example': 'A notice reads: "The library will close for renovations. We thank patrons for their '
                   'patience, and hope to reopen with more shelf space next year." Reading A: the closure is '
                   'temporary. Reading B: the closure is permanent. Walk the evidence pile by pile.\n'
                   '\n'
                   '```steps\n'
                   'title: Library notice (fictional case)\n'
                   '"Renovations" | | Repair work implies a building meant to be used again, favoring A.\n'
                   '"Hope to reopen next year" | | A dated plan to reopen — the strongest support for A.\n'
                   '"More shelf space" | | You add shelves to a future library, again favoring A.\n'
                   '"We thank patrons for their patience" | | Politeness fits both a temporary and a '
                   'permanent closure, so it supports neither.\n'
                   '= Verdict | | A has specific support; B is only uncontradicted.\n'
                   '```\n'
                   '\n'
                   'Notice what B offers: no phrase supports permanence. Its whole case is that hope "merely '
                   'fails to contradict" a permanent closure — silence, not evidence. The grateful tone '
                   'feels warm and cooperative, but it is compatible with both readings, so it belongs in '
                   'the compatibility pile. Weighing the two piles, A wins on evidence, not on tone. The '
                   'final judgment names which phrases are decisive, not just which reading feels nicer.'}
SCORED_WORKED_A = ('A notice reads: "The library will close for renovations. We thank patrons for their patience, and hope to '
 'reopen with more shelf space next year." Reading A: the closure is temporary. Reading B: the closure is '
 'permanent. Walk the evidence pile by pile, counting the phrases that genuinely support A.\n'
 '\n'
 '```steps\n'
 'title: Library notice (fictional case)\n'
 '"Renovations" | 1 | Repair work implies a building meant to be used again, favoring A.\n'
 '"Hope to reopen next year" | 1 | A dated plan to reopen — the strongest support for A.\n'
 '"More shelf space" | 1 | You add shelves to a future library, again favoring A.\n'
 '"We thank patrons for their patience" | 0 | Politeness fits both a temporary and a permanent closure, so '
 'it supports neither.\n'
 '= Phrases supporting A | 3\n'
 '```\n'
 '\n'
 'Notice what B offers: no phrase supports permanence. Its whole case is that hope merely fails to '
 'contradict a permanent closure — silence, not evidence. The grateful tone feels warm and cooperative, but '
 'it is compatible with both readings, so it belongs in the compatibility pile. Weighing the two piles, A '
 'wins on evidence, not on tone. The final judgment names which phrases are decisive, not just which reading '
 'feels nicer.')
SCORED_WORKED_B = ('A library notice reads: "The library will close for renovations. We thank patrons for their patience, and '
 'hope to reopen with more shelf space next year." Reading A: the closure is temporary. Reading B: the '
 'closure is permanent. Walk each phrase and ask whether it would be odd under the rival reading. Score each '
 'phrase: 1 if it supports a reading, 0 if it fits both.\n'
 '\n'
 '```steps\n'
 'title: Library closure notice (fictional case)\n'
 '"Renovations" | 1 | Repair work implies a building meant to be used again — odd under permanent closure. '
 'Supports A.\n'
 '"Hope to reopen next year" | 1 | A dated reopening plan is strong support for A.\n'
 '"More shelf space" | 1 | You add shelves to a future working library.\n'
 '"We thank patrons for their patience" | 0 | Politeness fits either reading — patience suits a wait, not a '
 'loss.\n'
 '= Phrases supporting A | 3\n'
 '```\n'
 '\n'
 'The score is the count of phrases that support Reading A. Notice the failure of Reading B: no phrase '
 'actively supports permanence. The hopeful tone merely fails to contradict it, which is not support. '
 'Reading A rests on three phrases that would be unnecessary if closure were permanent; Reading B rests on '
 'none.')
WINS_WORKED = ('A library notice reads: "The library will close for renovations. We thank patrons for their patience, and '
 'hope to reopen with more shelf space next year." Reading A: the closure is temporary. Reading B: the '
 'closure is permanent. Walk each phrase and ask whether it would be odd under the rival reading.\n'
 '\n'
 '```steps\n'
 'title: Library closure notice (fictional case)\n'
 '"Renovations" | | Repair work implies a building meant to be used again — odd under permanent closure.\n'
 '"Hope to reopen next year" | | A dated reopening plan is strong support for A.\n'
 '"More shelf space" | | You add shelves to a future working library.\n'
 '"We thank patrons for their patience" | | Politeness fits either reading — patience suits a wait, not a '
 'loss.\n'
 '= Reading A wins on evidence | | Every substantive phrase supports A.\n'
 '```\n'
 '\n'
 'Notice the failure of Reading B: no phrase actively supports permanence. The hopeful tone merely fails to '
 'contradict it, which is not support. Reading A rests on three phrases that would be unnecessary if closure '
 'were permanent; Reading B rests on none.')


def steps_body(worked: str) -> str:
    [(kind, body)] = [fence for fence in native_fences(worked) if fence[0] == "steps"]
    return body


def validate(worked: str, context: dict, minutes: int | None = 6):
    data = dict(VERDICT_DRAFT, worked_example=worked)
    return _validated_group(LLMResponse(data=data), _TUTORIAL_GROUP, PlanTutorialLessonSectionsOutput,
        *_tokens(context), package_context=context, allotted_lesson_minutes=minutes,
        lesson_title="Compare two defensible interpretations")


def test_verdict_row_without_values_becomes_an_ordinary_row():
    body = normalize_fence("steps", steps_body(VERDICT_DRAFT["worked_example"]))
    assert body.splitlines()[-1] == "Verdict | | A has specific support, B is only uncontradicted."
    assert fence_errors("steps", body) == []
    block = parse_steps(body)
    assert block.total is None and all(row.value is None for row in block.rows)
    assert block.rows[-1].label == "Verdict"
    wins = normalize_fence("steps", steps_body(WINS_WORKED))
    assert wins.splitlines()[-1].startswith("Reading A wins on evidence | | ")
    assert fence_errors("steps", wins) == []


def test_verdict_draft_now_passes_the_writer_for_a_package_without_numbers():
    context = short_package().writer_context()
    assert context["teaching_cases"] == []
    for worked in (VERDICT_DRAFT["worked_example"], WINS_WORKED):
        for minutes in (6, None):
            result, issues = validate(worked, context, minutes)
            assert issues == [] and result is not None
            assert "\n= " not in result["worked_example"]  # stored text is the normalised row


def test_invented_scores_are_rejected_when_the_package_has_no_numbers():
    context = short_package().writer_context()
    for worked in (SCORED_WORKED_A, SCORED_WORKED_B):
        result, issues = validate(worked, context)
        assert result is None
        flagged = [issue for issue in issues if NO_NUMBERS in issue]
        # Every scored row and the total row, each named by its line.
        assert len(flagged) == 5, issues
        assert all(issue.startswith("worked_example steps fence is invalid: line '") for issue in flagged)
        assert any("'= Phrases supporting A | 3'" in issue and "without the leading" in issue
                   for issue in flagged)
        assert not any("plain number" in issue or "must equal the sum" in issue for issue in issues)


def test_word_values_in_a_case_without_numbers_never_ask_for_a_plain_number():
    errors = fence_errors("steps", LABELLED_STEPS, case_has_numbers=False)
    assert len(errors) == 3 and all(NO_NUMBERS in error for error in errors)
    assert not any("plain number" in error for error in errors)


def test_scores_are_judged_by_the_ordinary_grammar_when_the_case_has_numbers():
    # The tightening is scoped: a package with case data keeps today's rules.
    context = harbor_package().writer_context()
    body = steps_body(SCORED_WORKED_A)
    assert fence_errors("steps", body) == []
    assert fence_errors("steps", body, case_has_numbers=True) == []
    result, issues = validate(SCORED_WORKED_A, context)
    assert not any(NO_NUMBERS in issue for issue in issues)


def test_numeric_fence_with_an_empty_total_is_still_rejected_without_inviting_new_numbers():
    for total in ("= Area | | The triangle's area.", "= Area |"):
        body = ("title: Triangle area\nunit: cm²\nBase × height | 24 | 6 × 4\n"
                f"Half of it | −12 | A triangle is half of that rectangle.\n{total}\n")
        normalized = normalize_fence("steps", body)
        assert normalized.splitlines()[-1].startswith("= Area"), "a numeric total keeps its ="
        errors = fence_errors("steps", normalized)
        assert len(errors) == 1, errors
        [error] = errors
        assert "sum of the rows above (12)" in error
        assert "never add numbers to rows that had none" in error
        assert "plain number" not in error


def test_reasoning_rows_with_an_unnormalised_equals_row_get_a_targeted_fix():
    body = "title: Two readings\nFirst phrase | | Supports A.\nSecond phrase | | Fits both.\n= Verdict | | A wins.\n"
    [error] = fence_errors("steps", body)
    assert "remove the leading" in error and "plain number" not in error


def test_equals_row_keeps_its_total_when_any_row_holds_a_digit():
    # Review round 2: digits in labels or notes make this a numeric fence. Dropping
    # its "=" would hide the wrong 900 (true 200) from the total check.
    body = ("title: June profit\nRevenue 500 | | from the sales log\nCosts 300 | | rent and stock\n"
            "= Profit | | 900 left over\n")
    normalized = normalize_fence("steps", body)
    assert normalized.splitlines()[-1] == "= Profit | | 900 left over"
    [error] = fence_errors("steps", normalized)
    assert error.startswith("line '= Profit | | 900 left over': the \"=\" total row has no number")
    assert "never add numbers to rows that had none" in error
    assert "carry no numbers" not in error and "plain number" not in error
    # A digit only in the "=" row's note also keeps it a total.
    digit_note = "title: T\nFirst | | Supports A.\nSecond | | Fits both.\n= Verdict | | 3 phrases.\n"
    assert normalize_fence("steps", digit_note).splitlines()[-1].startswith("= Verdict")
    assert "carry no numbers" not in fence_errors("steps", digit_note)[0]


def test_corrections_put_input_values_in_the_note_never_the_label():
    import inspect
    from app.services.planning import lesson_writer, tutorial_blocks, tutorial_visuals
    for module in (tutorial_blocks, tutorial_visuals, lesson_writer):
        source = inspect.getsource(module)
        assert "label or note" not in source and "in the label" not in source, module.__name__
    [error] = fence_errors("steps", "title: Area\nBase × height | 24 | 6 × 4\nHalf of it | −12 | Half.\n= Area | 30\n")
    assert "put the value in the note" in error
