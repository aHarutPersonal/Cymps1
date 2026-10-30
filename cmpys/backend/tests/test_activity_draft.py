"""Offline coverage for the generation-only activity representation boundary."""
import copy

import pytest
from pydantic import ValidationError

from app.services.planning.activity_draft import LessonActivityDraft, TutorialActivityDraft, parse_activity_draft
from app.services.planning.package_builder import LessonPackageActivity
from app.services.practice.contracts import Activity, AnswerField, SolutionDocument, Workbook, public_workbook
from app.services.practice.solution_compiler import compile_worked_solution
from app.services.planning.activity_draft import activity_repair_reference, parse_activity_repair_draft


def draft_payload():
    return {
        "id": "cash_case", "title": "Explain the cash difference", "kind": "practice",
        "instructions": "Use the supplied period-specific facts to explain the cash difference and justify your choice.",
        "data": [{"id": "sales", "label": "Current uncollected sales", "value": 300000, "unit": "AMD"},
                 {"id": "collections", "label": "Earlier-period collections", "value": 150000, "unit": "AMD"}],
        "hint": "Distinguish earlier-period collections from current sales.",
        "minutes_min": 12, "minutes_max": 20,
        "fields": [
            {"id": "gap", "kind": "number", "label": "Cash difference", "unit": "AMD",
             "expression": "sales - collections", "tolerance": .05,
             "rubric_criterion": "Use the correct signed cash difference.",
             "explanation": "  Deduct collections from current uncollected sales. Preserve the signed result.\n"},
            {"id": "period", "kind": "choice", "label": "Which period produced the collections?",
             "choices": [{"id": "earlier", "label": "An earlier period"},
                         {"id": "current", "label": "The current period"}],
             "correct_choice": "earlier", "rubric_criterion": "Places the collections in the earlier period",
             "explanation": "The scenario explicitly identifies these as collections of earlier-period sales."},
            {"id": "reason", "kind": "text", "label": "Explain why sales and collections differ.",
             "criteria": ["Distinguishes the time of the sale from the time of the cash receipt."],
             "explanation": "Explain that the earlier sale and its later cash collection belong to different periods."},
        ],
    }


def test_repair_reference_round_trips_owned_reasoning_without_canonical_default_noise():
    original = parse_activity_draft(draft_payload())
    before = original.model_dump(mode="json")
    wire = activity_repair_reference(original)
    assert "worked_solution" not in wire
    assert "tolerance" not in wire["fields"][1]
    assert "criteria" not in wire["fields"][1]
    assert "correct_choice" not in wire["fields"][2]
    assert parse_activity_repair_draft(wire).model_dump(mode="json") == before
    assert original.model_dump(mode="json") == before


def test_scoped_repair_accepts_only_inert_copied_defaults_without_changing_content():
    raw = draft_payload()
    raw["fields"][1].update(tolerance=0.01, criteria=[], expression=None)
    raw["fields"][2].update(choices=[], correct_choice=None, tolerance=0.01)
    before = copy.deepcopy(raw)
    assert parse_activity_repair_draft(raw) == parse_activity_draft(draft_payload())
    assert raw == before


@pytest.mark.parametrize("key,value", [
    ("criteria", ["Authored reasoning must not disappear"]), ("criteria", None),
    ("tolerance", 0.02), ("tolerance", "0.01"), ("tolerance", False),
    ("expression", "sales - collections"), ("unexpected", None),
])
def test_repair_rejects_nondefault_or_malformed_inactive_properties(key, value):
    raw = draft_payload(); raw["fields"][1][key] = value
    with pytest.raises(ValidationError):
        parse_activity_repair_draft(raw)


def test_repair_keeps_tutorial_field_limit_and_required_explanation_ownership():
    with pytest.raises(ValidationError):
        parse_activity_repair_draft(draft_payload(), tutorial=True)
    raw = draft_payload(); del raw["fields"][1]["explanation"]
    with pytest.raises(ValidationError):
        parse_activity_repair_draft(raw)


def test_repair_reference_does_not_assign_legacy_prose_or_drop_authored_inactive_data():
    raw = parse_activity_draft(draft_payload()).model_dump(mode="json")
    raw["worked_solution"] = "Legacy reasoning has no explicit ownership for the individual answer fields."
    legacy = Activity.model_validate(raw)
    assert activity_repair_reference(legacy) == legacy.model_dump(mode="json")
    raw = parse_activity_draft(draft_payload()).model_dump(mode="json")
    raw["fields"][1]["criteria"] = ["Authored incompatible data must not be silently discarded."]
    with pytest.raises(ValidationError):
        activity_repair_reference(Activity.model_validate(raw))


def test_wire_has_complete_discriminated_variants_and_no_solution_envelope():
    schema = LessonActivityDraft.model_json_schema()
    assert "worked_solution" not in schema["properties"]
    assert list(schema["properties"])[-1] == "fields"
    assert "data" in schema["required"]
    assert schema["properties"]["data"]["maxItems"] == 20
    items = schema["properties"]["fields"]["items"]
    assert items["discriminator"]["propertyName"] == "kind"
    assert len(items["oneOf"]) == 4
    for name, required, forbidden in [
        ("NumberDraftField", {"expression"}, {"choices", "correct_choice", "correct_choices", "criteria"}),
        ("ChoiceDraftField", {"choices", "correct_choice"}, {"expression", "tolerance", "criteria", "correct_choices"}),
        ("MultiChoiceDraftField", {"choices", "correct_choices"}, {"expression", "tolerance", "criteria", "correct_choice"}),
        ("TextDraftField", {"criteria"}, {"expression", "tolerance", "choices", "correct_choice", "correct_choices"}),
    ]:
        branch = schema["$defs"][name]
        assert set(branch["required"]) == {"id", "label", "kind", "explanation", *required}
        assert forbidden.isdisjoint(branch["properties"])
        assert list(branch["properties"])[-1] == "explanation"
        assert list(branch["properties"])[:3] == ["id", "label", "kind"]
        assert branch["additionalProperties"] is False
        assert "rubric_criterion" in branch["properties"]
        assert "default" not in branch["properties"]["unit"]
    assert {"SolutionDocument", "SolutionStep", "AnswerField"}.isdisjoint(schema["$defs"])


def test_adapter_preserves_all_authored_values_and_builds_canonical_solution_ownership():
    raw = draft_payload()
    original = copy.deepcopy(raw)
    actual = parse_activity_draft(raw)
    expected = copy.deepcopy(raw)
    expected["worked_solution"] = {"version": 1, "steps": [
        {"field_id": field["id"], "explanation": field.pop("explanation")}
        for field in expected["fields"]]}
    assert type(actual) is LessonPackageActivity
    assert isinstance(actual.worked_solution, SolutionDocument)
    assert actual.model_dump(mode="json") == Activity.model_validate(expected).model_dump(mode="json")
    assert raw == original
    assert [step.field_id for step in actual.worked_solution.steps] == ["gap", "period", "reason"]
    compiled = compile_worked_solution(actual)
    assert compiled.records[0].text == "(300000 - 150000) = 150000"
    assert raw["fields"][0]["explanation"] in compiled.text


@pytest.mark.parametrize("field_index", [0, 1, 2])
def test_optional_unit_and_rubric_are_preserved_for_each_field_kind(field_index):
    raw = draft_payload()
    raw["fields"][field_index]["unit"] = "years"
    raw["fields"][field_index]["rubric_criterion"] = "Use the period stated in the scenario."
    field = parse_activity_draft(raw).fields[field_index]
    assert field.unit == "years"
    assert field.rubric_criterion == "Use the period stated in the scenario."


@pytest.mark.parametrize("defect", ["unknown_solution_boolean", "nested_hint_and_times", "extra_field_property",
                                   "missing_text_criteria", "string_field", "missing_explanation", "empty_criteria",
                                   "whitespace_criteria", "whitespace_explanation", "wrong_kind_property"])
def test_observed_shape_errors_are_rejected_without_invention_or_dropping_content(defect):
    raw = draft_payload()
    if defect == "unknown_solution_boolean":
        raw["worked_solution"] = {"approved": True}
    elif defect == "nested_hint_and_times":
        raw["worked_solution"] = {key: raw.pop(key) for key in ("hint", "minutes_min", "minutes_max")}
    elif defect == "extra_field_property":
        raw["fields"][0]["approved"] = True
    elif defect == "missing_text_criteria":
        del raw["fields"][2]["criteria"]
    elif defect == "string_field":
        raw["fields"].extend(["text", "Explain the case using a specific criterion."])
    elif defect == "missing_explanation":
        del raw["fields"][0]["explanation"]
    elif defect == "empty_criteria":
        raw["fields"][2]["criteria"] = []
    elif defect == "whitespace_criteria":
        raw["fields"][2]["criteria"] = ["  \n  "]
    elif defect == "whitespace_explanation":
        raw["fields"][0]["explanation"] = " " * 40
    else:
        raw["fields"][2]["expression"] = "sales - collections"
    original = copy.deepcopy(raw)
    with pytest.raises(ValidationError):
        parse_activity_draft(raw)
    assert raw == original


@pytest.mark.parametrize("defect", ["unknown_formula", "constant_answer", "cancelled_formula", "duplicate_field",
                                   "duplicate_datum", "invalid_choice_key", "invalid_interval", "short_total_reasoning"])
def test_adapter_runs_canonical_cross_field_math_and_solution_checks(defect):
    raw = draft_payload()
    if defect == "unknown_formula":
        raw["fields"][0]["expression"] = "sales - absent"
    elif defect == "constant_answer":
        raw["fields"][0]["expression"] = "150000"
    elif defect == "cancelled_formula":
        raw["fields"][0]["expression"] = "sales - sales"
    elif defect == "duplicate_field":
        raw["fields"][1]["id"] = raw["fields"][0]["id"]
    elif defect == "duplicate_datum":
        raw["data"].append(copy.deepcopy(raw["data"][0]))
    elif defect == "invalid_choice_key":
        raw["fields"][1]["correct_choice"] = "absent"
    elif defect == "invalid_interval":
        raw["minutes_min"] = 30
    else:
        raw["fields"] = [raw["fields"][0]]
        raw["fields"][0]["explanation"] = "The inputs are subtracted."
    with pytest.raises(ValueError):
        parse_activity_draft(raw)


@pytest.mark.parametrize("defect", ["too_many_data", "too_many_fields", "too_many_choices", "too_many_criteria",
                                   "long_criterion", "long_label", "long_unit", "bad_tolerance", "long_explanations"])
def test_draft_preserves_canonical_capacity_limits(defect):
    raw = draft_payload()
    if defect == "too_many_data":
        raw["data"] = [{"id": f"item_{i}", "label": "Raw datum", "value": i} for i in range(21)]
    elif defect == "too_many_fields":
        raw["fields"] = [{**raw["fields"][2], "id": f"field_{i}"} for i in range(11)]
    elif defect == "too_many_choices":
        raw["fields"][1]["choices"] = [{"id": f"choice_{i}", "label": "A choice"} for i in range(9)]
    elif defect == "too_many_criteria":
        raw["fields"][2]["criteria"] *= 6
    elif defect == "long_criterion":
        raw["fields"][2]["criteria"] = ["x" * 501]
    elif defect == "long_label":
        raw["fields"][0]["label"] = "x" * 301
    elif defect == "long_unit":
        raw["fields"][0]["unit"] = "x" * 41
    elif defect == "bad_tolerance":
        raw["fields"][0]["tolerance"] = 1.01
    else:
        raw["fields"][0]["explanation"] = "x" * 4000
    with pytest.raises(ValueError):
        parse_activity_draft(raw)


def test_mutated_draft_is_revalidated_and_private_explanations_do_not_leak_publicly():
    raw = draft_payload()
    draft = LessonActivityDraft.model_validate(raw)
    activity = parse_activity_draft(draft)
    transfer = activity.model_copy(deep=True, update={"id": "transfer_case", "kind": "transfer"})
    public = public_workbook(Workbook(title="Cash timing", activities=[activity, transfer]))
    for item in public["activities"]:
        assert "worked_solution" not in item
        assert all("explanation" not in field for field in item["fields"])
    draft.fields[0].explanation = " " * 40
    with pytest.raises(ValidationError):
        parse_activity_draft(draft)


def test_default_assessment_values_and_optional_diagram_keep_canonical_behavior():
    raw = draft_payload()
    del raw["fields"][0]["tolerance"]
    raw["diagram"] = {"caption": "A qualitative timing diagram.", "points": [
        {"label": "Sale", "x": 10, "y": 50}, {"label": "Cash", "x": 80, "y": 50}], "closed": False}
    activity = parse_activity_draft(raw)
    assert activity.fields[0].tolerance == AnswerField.model_fields["tolerance"].default
    assert activity.fields[1].expression is None and activity.fields[2].choices == []
    assert activity.diagram.model_dump(mode="json") == raw["diagram"]


@pytest.mark.parametrize("criteria", [
    ["", "Distinguishes the periods."],
    ["", "Substantive criterion.", "  "],
    [" \n\t", "  Պահպանիր տարբերակումը։\n"],
    ["  Պահպանիր տարբերակումը։\n", "", "Keeps the sign and units.", "", "Keeps the sign and units."],
    ["", "", "Distinguishes the periods.", "", ""],
])
def test_fresh_wire_empty_criteria_cleanup_preserves_every_nonempty_byte_and_order(criteria):
    raw = draft_payload()
    raw["fields"][2]["criteria"] = criteria
    original = copy.deepcopy(raw)
    expected = copy.deepcopy(raw)
    expected["fields"][2]["criteria"] = [value for value in criteria if value.strip()]

    # The pure adapter performs no request: the result equals the separately
    # validated complete draft with only the zero-content entries removed.
    actual = parse_activity_draft(raw)
    assert actual == parse_activity_draft(expected)
    assert actual.fields[2].criteria == expected["fields"][2]["criteria"]
    assert [value.encode("utf-8") for value in actual.fields[2].criteria] == [
        value.encode("utf-8") for value in criteria if value.strip()]
    assert raw == original
    # Neither the strict wire model nor the persisted field model is relaxed.
    with pytest.raises(ValidationError):
        LessonActivityDraft.model_validate(raw)
    canonical = actual.model_dump(mode="json")
    canonical["fields"][2]["criteria"] = original["fields"][2]["criteria"]
    with pytest.raises(ValidationError):
        Activity.model_validate(canonical)


@pytest.mark.parametrize("criteria", [
    [], [""], ["", "", ""], ["", "  \n  "], ["", None], None,
    ["", "Substantive criterion.", None],
    ["", "Substantive criterion.", False],
    ["", "Substantive criterion.", "x" * 501],
    ["", "", "", "", "", "Substantive criterion."],
    ("", "Substantive criterion."),
])
def test_empty_criteria_cleanup_does_not_hide_invalid_or_oversized_rubrics(criteria):
    raw = draft_payload()
    raw["fields"][2]["criteria"] = criteria
    original = copy.deepcopy(raw)
    with pytest.raises(ValidationError):
        parse_activity_draft(raw)
    assert raw == original


@pytest.mark.parametrize("defect", ["unknown_root", "unknown_field", "missing_criteria",
                                   "number_criteria", "choice_criteria", "invalid_formula"])
def test_empty_criteria_cleanup_preserves_all_other_validation_failures(defect):
    raw = draft_payload()
    raw["fields"][2]["criteria"] = ["", "Distinguishes both periods."]
    if defect == "unknown_root":
        raw["explanation"] = "A misplaced private explanation must not be silently assigned."
    elif defect == "unknown_field":
        raw["fields"][2]["private_extra"] = "Retain unknown data for rejection."
    elif defect == "missing_criteria":
        del raw["fields"][2]["criteria"]
    elif defect in {"number_criteria", "choice_criteria"}:
        raw["fields"][0 if defect == "number_criteria" else 1]["criteria"] = [""]
    else:
        raw["fields"][0]["expression"] = "sales - unknown"
    original = copy.deepcopy(raw)
    with pytest.raises(ValueError):
        parse_activity_draft(raw)
    assert raw == original


def test_empty_criteria_cleanup_never_relocates_an_unowned_root_explanation():
    raw = draft_payload()
    raw["fields"][2]["criteria"] = ["", "Distinguishes both periods."]
    raw["explanation"] = raw["fields"][2].pop("explanation")
    original = copy.deepcopy(raw)
    with pytest.raises(ValidationError) as failure:
        parse_activity_draft(raw)
    locations = {tuple(error["loc"]) for error in failure.value.errors(include_input=False)}
    assert ("fields", 2, "text", "explanation") in locations
    assert ("explanation",) in locations
    assert raw == original


# ---------------------------------------------------------------------------
# Practice v3 on the generation wire: multi_choice, field hints, misconceptions
# ---------------------------------------------------------------------------

def v3_draft():
    return {
        "id": "guided", "title": "Classify the spending", "kind": "practice",
        "instructions": "A fictional workshop spends money on the items in the table. Find upkeep spending and classify each item.",
        "data": [{"id": "total", "label": "Total spending", "value": 70, "unit": "m"},
                 {"id": "growth", "label": "Growth spending", "value": 25, "unit": "m"}],
        "hint": "Separate spending that keeps the workshop running from spending that grows it.",
        "minutes_min": 4, "minutes_max": 8,
        "fields": [
            {"id": "upkeep", "kind": "number", "label": "Upkeep spending", "prefix": "$", "unit": "m",
             "expression": "total - growth", "hint": "Take the growth part out of the total.",
             "rubric_criterion": "Uses upkeep spending, not total spending",
             "misconceptions": [{"expression": "total", "feedback": "That is the total. Growth spending is not upkeep."}],
             "explanation": "Upkeep is the total minus the growth part, because growth spending expands the workshop rather than maintaining it."},
            {"id": "items", "kind": "multi_choice", "label": "Which items are growth spending?",
             "choices": [{"id": "shed", "label": "A new shed"}, {"id": "lathe", "label": "A second lathe"},
                         {"id": "belts", "label": "Replacement belts"}],
             "correct_choices": ["shed", "lathe"], "rubric_criterion": "Separates growth from upkeep",
             "explanation": "A new shed and a second lathe add capacity; replacement belts only keep the existing lathe running."},
        ],
    }


def test_multi_choice_draft_round_trips_and_renders_its_correct_labels():
    canonical = parse_activity_draft(v3_draft())
    number, multi = canonical.fields
    assert multi.kind == "multi_choice" and multi.correct_choices == ["shed", "lathe"]
    assert (number.prefix, number.hint, number.misconceptions[0].expression) == ("$", "Take the growth part out of the total.", "total")
    assert isinstance(canonical.worked_solution, SolutionDocument)
    text = compile_worked_solution(canonical).text
    assert "A new shed" in text and "A second lathe" in text
    # The correct set is the key: the distractor label is not the answer.
    assert "Replacement belts" not in text
    wire = activity_repair_reference(canonical)
    assert "correct_choices" not in wire["fields"][0] and "prefix" not in wire["fields"][1]
    assert "misconceptions" not in wire["fields"][1] and "correct_choice" not in wire["fields"][1]
    assert parse_activity_repair_draft(wire).model_dump(mode="json") == canonical.model_dump(mode="json")


def test_wire_exposes_four_discriminated_kinds_and_their_v3_properties():
    schema = LessonActivityDraft.model_json_schema()
    items = schema["properties"]["fields"]["items"]
    assert len(items["oneOf"]) == 4
    multi = schema["$defs"]["MultiChoiceDraftField"]
    assert set(multi["required"]) == {"id", "label", "kind", "explanation", "choices", "correct_choices"}
    assert {"expression", "tolerance", "correct_choice", "criteria", "prefix", "misconceptions"}.isdisjoint(multi["properties"])
    assert list(multi["properties"])[-1] == "explanation" and list(multi["properties"])[:3] == ["id", "label", "kind"]
    number = schema["$defs"]["NumberDraftField"]["properties"]
    assert {"prefix", "misconceptions", "hint", "rubric_criterion"} <= set(number)
    for name in ("ChoiceDraftField", "TextDraftField", "MultiChoiceDraftField"):
        assert {"hint", "rubric_criterion"} <= set(schema["$defs"][name]["properties"])
        assert "misconceptions" not in schema["$defs"][name]["properties"]
    assert "prefix" not in schema["$defs"]["ChoiceDraftField"]["properties"]


def test_tutorial_draft_enforces_the_new_workbook_rules():
    text = {"id": "why", "kind": "text", "label": "Explain your decision using the case facts.",
            "criteria": ["Uses the supplied figures"],
            "explanation": "A strong answer ties the classification to what the item adds to capacity."}
    only_text = v3_draft(); only_text["fields"] = [text]
    assert TutorialActivityDraft.model_validate(only_text).fields[0].kind == "text"
    repaired = parse_activity_repair_draft(only_text, tutorial=True)
    assert repaired.fields[0].kind == "text"
    assert repaired.worked_solution.steps[0].field_id == "why"
    two_texts = v3_draft(); two_texts["fields"] = [text, {**text, "id": "why2"}]
    with pytest.raises(ValidationError) as error:
        TutorialActivityDraft.model_validate(two_texts)
    assert "at most one text field" in str(error.value)
    # Legacy lesson drafts (their prompt is unchanged) keep accepting text-only work.
    LessonActivityDraft.model_validate(only_text)
    parse_activity_draft(only_text)
    # The intended pair is accepted, in either order of kinds.
    paired = v3_draft(); paired["fields"] = [paired["fields"][1], text]
    assert [f.kind for f in parse_activity_repair_draft(paired, tutorial=True).fields] == ["multi_choice", "text"]


@pytest.mark.parametrize("index", [0, 1])
def test_tutorial_draft_requires_a_rubric_criterion_on_scored_fields(index):
    raw = v3_draft(); del raw["fields"][index]["rubric_criterion"]
    with pytest.raises(ValidationError) as error:
        TutorialActivityDraft.model_validate(raw)
    assert "rubric_criterion" in str(error.value)
    LessonActivityDraft.model_validate(raw)  # not required for legacy lesson drafts
    schema = TutorialActivityDraft.model_json_schema()
    for name in ("NumberDraftField", "ChoiceDraftField", "MultiChoiceDraftField"):
        assert "rubric_criterion" in schema["$defs"][name]["required"]
    assert "rubric_criterion" not in schema["$defs"]["TextDraftField"]["required"]
    assert "rubric_criterion" not in LessonActivityDraft.model_json_schema()["$defs"]["NumberDraftField"]["required"]


def test_private_repair_can_patch_a_multi_choice_answer_key_and_nothing_else():
    from app.services.planning.lesson_package import LessonPackage, PrivatePackageRepair, apply_private_package_repair

    def package():
        first = parse_activity_draft(v3_draft()).model_dump(mode="json")
        second = {**copy.deepcopy(first), "id": "transfer", "kind": "transfer"}
        return LessonPackage.model_validate({"teaching_cases": [], "workbook": {"title": "Classify", "activities": [first, second]}})

    patched = apply_private_package_repair(package(), PrivatePackageRepair.model_validate(
        {"field_patches": [{"activity_id": "guided", "field_id": "items", "correct_choices": ["shed"]}]}))
    assert patched.workbook.activities[0].fields[1].correct_choices == ["shed"]
    with pytest.raises(ValueError):
        apply_private_package_repair(package(), PrivatePackageRepair.model_validate(
            {"field_patches": [{"activity_id": "guided", "field_id": "items", "correct_choice": "shed"}]}))
    with pytest.raises(ValueError):
        apply_private_package_repair(package(), PrivatePackageRepair.model_validate(
            {"field_patches": [{"activity_id": "guided", "field_id": "items", "correct_choices": ["missing"]}]}))


@pytest.mark.parametrize("expression", ["70", "total / total", "total - total"])
def test_misconceptions_are_derived_from_named_facts_like_the_answer(expression):
    raw = v3_draft()
    raw["fields"][0]["misconceptions"] = [{"expression": expression, "feedback": "A guessed constant is not a mistake."}]
    with pytest.raises(ValidationError):
        parse_activity_draft(raw)
    from app.services.planning.lesson_package import LessonPackage

    good = parse_activity_draft(v3_draft()).model_dump(mode="json")
    good["fields"][0]["misconceptions"] = [{"expression": expression, "feedback": "A guessed constant is not a mistake."}]
    other = {**copy.deepcopy(good), "id": "transfer", "kind": "transfer"}
    with pytest.raises(ValidationError):
        LessonPackage.model_validate({"teaching_cases": [], "workbook": {"title": "Classify", "activities": [good, other]}})


@pytest.mark.parametrize("blank", ["     ", " \t\n  "])
def test_tutorial_draft_rejects_a_whitespace_only_rubric_criterion(blank):
    raw = v3_draft(); raw["fields"][0]["rubric_criterion"] = blank
    with pytest.raises(ValidationError) as error:
        TutorialActivityDraft.model_validate(raw)
    assert "rubric_criterion" in str(error.value)
