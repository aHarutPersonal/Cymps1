"""Fix 4 (smoke2 writing_novice): activity draft id-key recovery and one complete correction.

Fixtures are verbatim smoke2-candidate responses: the seed, the first guided draft (whose
choice and field objects carry the id under a malformed ": " key, valid JSON) and the
transfer draft. The guided draft also shows an undeclared statistic ("40 adults") with
data [], which the existing undeclared-numbers check correctly rejects.
"""
import copy
import json
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.services.planning import package_builder as builder
from app.services.planning.activity_draft import TutorialActivityDraft, best_effort_activity, recover_misnamed_ids
from tests.test_staged_package_builder import Factory

SEED = json.loads('{"workbook_title":"Revise an argument for your reader","teaching_cases":[],"activity_briefs":[{"id":"guided","kind":"practice","scope":"Guided practice on an original fictional case: a short (about 60-word) memo arguing that a town should keep its evening bus service, written for a general audience with its evidence buried and its claim softened. The activity instructions show a brief worked example: a one-sentence claim revised for a specific reader (the town budget committee) with an element-by-element analysis of what changed — explicit claim, chosen evidence, audience-fit. The learner then selects from a multi_choice list which weaknesses the supplied memo sentence has (missing clear claim, evidence not connected, wrong audience focus), and rewrites the topic sentence in one text field so the strongest evidence and the audience\'s main concern come first. Learning demand: recognizing which parts of an argument a specific reader needs, guided by the shown example. Output: selected weaknesses plus one rewritten sentence."},{"id":"transfer","kind":"transfer","scope":"Independent transfer to a genuinely new original fictional case: a short letter to a school principal arguing that the school should add a morning walking club, where the letter opens with a personal anecdote, states its request only vaguely near the end, and cites one relevant fact (many students live within walking distance) without linking it to the principal\'s concern about arriving on time and ready to learn. The learner selects which sentences carry the actual request and evidence (multi_choice, graded as exact set), then rewrites the opening paragraph so the request, the audience\'s concern, and the linked evidence appear in the first two sentences (text field, criteria accept valid alternative wording). Differs from guided practice: the learner must first locate the argument pieces in unfamiliar text and adapt the revision to a different audience\'s stated concern, not merely diagnose a shown memo. Output: selected sentences plus one rewritten opening paragraph of about 40 words."}]}')
GUIDED = json.loads('{"id":"guided","title":"Diagnose and rewrite a memo sentence","kind":"practice","instructions":"Original fictional example, worked for one reader. A pool manager wrote: \\"Maybe we could think about possibly adjusting swim times at some point.\\" Revised for the town budget committee: \\"Keep the morning lap-swim hours, because 40 adults swim before work each day and the committee\'s budget supports exactly that use.\\" What changed: the claim is explicit (keep the hours, not \\"maybe adjust\\"), the evidence is chosen and connected (40 daily swimmers show real use), and it fits the audience (the committee cares about whether spending matches use).\\n\\nYour case. A memo to the town council reads: \\"It has come to our attention that some concerns exist regarding the evening bus service, and while ridership figures from last fall are apparently available somewhere, the situation probably deserves a closer look at some point.\\"\\n\\nSelect the weaknesses this sentence shows, then rewrite it as one topic sentence for the council, putting the strongest evidence and the council\'s main concern (spending money on a service people actually use) first.","data":[],"hint":"Compare the sentence with the three elements from the worked example: is the claim explicit, is evidence connected, and does it address what the council cares about?","minutes_min":2,"minutes_max":3,"fields":[{"id":"weaknesses","label":"Which weaknesses does the memo sentence show?","kind":"multi_choice","choices":[{"id":"no_claim","label":"The claim is soft and unclear"},{"id":"evidence_off","label":"The evidence is not connected or verified"},{": ":"wrong_audience","label":"It does not address the audience\'s concern"}],"correct_choices":["no_claim","evidence_off","wrong_audience"],"rubric_criterion":"Identifies all three argument weaknesses for this reader","hint":"A budget-minded council needs a clear request plus firm, connected evidence — check whether each element survives that test.","explanation":"All three weaknesses appear. The claim is softened (\\"probably deserves a closer look at some point\\") so the council cannot tell what is being asked. The evidence is disconnected (ridership figures are only \\"apparently available somewhere\\") so nothing is verified or tied to a request. And the sentence never addresses the council\'s concern with spending on services people use. Notice it is not a length problem — the sentence fails on claim, evidence and audience fit at once."},{": ":"rewrite","label":"Your rewritten topic sentence for the council","kind":"text","criteria":["States a clear, explicit request to keep the evening bus service","Cites the ridership evidence as real and connected to the request","Frames it around the council\'s concern that money go to a well-used service"],"explanation":"A strong answer: \\"Keep the evening bus service: last fall\'s ridership shows strong use, and that is exactly the well-used service this council\'s budget should support.\\" It names the request plainly, treats the ridership figures as firm evidence linked to the request, and puts the council\'s concern — funding what people actually use — front and center. Accept other wording that keeps the explicit claim, the connected evidence and the audience\'s concern in one sentence."}]}')
TRANSFER = json.loads('{"id":"transfer","title":"Refocus a letter to its reader","kind":"transfer","instructions":"Original fictional case. A parent writes this letter to a school principal, who has said the school\'s top priority is students arriving on time and ready to learn.\\n\\n\\"Dear Principal Okafor,\\n\\nLast Saturday my daughter Maya and I walked the loop around the park before breakfast, and she talked the whole time about her class garden project. It made me realize how much children enjoy moving in the morning. Many students at Maplewood live within walking distance of the school. It seems like a walking club of some kind could be a nice thing to think about at some point, if there is interest. I remember walking to school myself as a child.\\n\\nSincerely, Dana Ruiz\\"\\n\\nThe request is vague and buried near the end, and the one relevant fact is never linked to what the principal cares about.\\n\\nFirst, select the sentences that carry the actual request and the evidence. Then rewrite the opening paragraph so the request, the principal\'s stated concern, and the linked evidence appear in the first two sentences.","data":[],"hint":"Find the sentence that names what the writer wants, and the sentence that gives a fact supporting it — then tie that fact to arriving on time and ready to learn.","minutes_min":2,"minutes_max":2,"fields":[{"id":"pieces","label":"Which sentences carry the request or the evidence?","kind":"multi_choice","choices":[{"id":"request","label":"\\"It seems like a walking club of some kind could be a nice thing to think about...\\""},{"id":"evidence","label":"\\"Many students at Maplewood live within walking distance of the school.\\""},{"id":"anecdote","label":"\\"Last Saturday my daughter Maya and I walked the loop around the park...\\""},{"id":"nostalgia","label":"\\"I remember walking to school myself as a child.\\""}],"correct_choices":["request","evidence"],"rubric_criterion":"Locates the buried request and the supporting fact","hint":"Ask which sentences a principal would need to act, and which are just personal stories.","explanation":"The request is the vague \\"walking club\\" sentence near the end; the evidence is the fact that many students live within walking distance. The park anecdote and the childhood memory are personal color that delay the request without supporting it — a principal deciding on programs does not need them to evaluate it."},{"id":"rewrite","label":"Your rewritten opening paragraph","kind":"text","criteria":["States the request clearly in the first or second sentence","Names the principal\'s concern — arriving on time and ready to learn — in the first two sentences","Links the walking-distance fact to that concern as support"],"explanation":"A strong rewrite puts the argument first, for example: \\"I am writing to ask that Maplewood start a morning walking club. Since many students live within walking distance, a walking club would help them arrive on time and ready to learn, while giving them an active start to the day. The club could be supervised by parent volunteers like me.\\" Accept other wording that keeps all three moves: a clear request up front, the principal\'s stated concern, and the walking-distance fact tied directly to that concern. The anecdote can move later or drop out entirely."}]}')
STEP = {"id": "step_1", "lesson_format": "tutorial_v1", "title": "Revise an evidence-backed argument for a specific audience",
        "description": "Learn one concept, apply it to a supplied case, then transfer it to a new case.",
        "resources": ["Optional background reference"]}
CONTEXT = {"lesson_format": "tutorial_v1", "allotted_lesson_minutes": None, "target_practice_minutes": 3,
           "goal": "Revise an evidence-backed argument for a specific audience",
           "component_recovery": "bounded_per_component"}
STATISTIC = "40 adults swim before work each day"


def without_statistic(draft):
    clean = copy.deepcopy(draft)
    clean["instructions"] = (clean["instructions"]
        .replace(STATISTIC, "the early lap swimmers fill the pool before work each day")
        .replace("40 daily swimmers show real use", "the regular swimmers show real use"))
    return clean


def test_recorded_guided_draft_recovers_both_misnamed_ids():
    original = copy.deepcopy(GUIDED)
    recovered, count = recover_misnamed_ids(GUIDED)
    assert GUIDED == original and count == 2  # The provider object is never mutated.
    weaknesses, rewrite = recovered["fields"]
    assert weaknesses["choices"][2] == {"id": "wrong_audience", "label": "It does not address the audience's concern"}
    assert list(rewrite)[0] == "id" and rewrite["id"] == "rewrite" and ": " not in rewrite
    TutorialActivityDraft.model_validate(recovered)  # Schema-valid; component checks still apply.
    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(GUIDED)


@pytest.mark.parametrize("mutate", [
    lambda d: d["fields"][1].update({"id": "rewrite"}),                      # id already present
    lambda d: d["fields"][1].update({"other": "x"}),                         # two unknown keys
    lambda d: d["fields"][1].update({": ": "Rewrite it"}),                   # value is not an id token
    lambda d: d["fields"][0]["choices"][2].update({"note": "audience"}),     # two unknown keys
    lambda d: d["fields"][0]["choices"][2].update({": ": 7}),                # not a string
])
def test_anything_but_one_id_like_unknown_key_is_left_for_validation(mutate):
    draft = copy.deepcopy(GUIDED)
    mutate(draft)
    recovered, count = recover_misnamed_ids(draft)
    assert count < 2 and ": " in json.dumps(recovered)
    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(recovered)


def test_top_level_and_other_objects_are_not_recovered():
    draft = copy.deepcopy(without_statistic(GUIDED))
    draft = recover_misnamed_ids(draft)[0]
    draft[": "] = "guided"
    recovered, count = recover_misnamed_ids(draft)
    assert count == 0 and recovered[": "] == "guided"


def test_best_effort_preview_drops_only_invalid_fields_and_reports_undeclared_numbers():
    draft = recover_misnamed_ids(GUIDED)[0]
    draft["fields"][1]["criteria"] = []
    preview = best_effort_activity(draft)
    assert [field.id for field in preview.fields] == ["weaknesses"]
    with pytest.raises(builder.UndeclaredNumbersError):
        builder.require_component_checks(preview)
    draft["hint"] = ""  # A shared property is invalid: no preview.
    assert best_effort_activity(draft) is None


@pytest.mark.asyncio
async def test_recovered_draft_gets_one_correction_naming_the_statistic(monkeypatch):
    monkeypatch.setattr(builder, "record_llm_response", AsyncMock(return_value=True))
    factory = Factory({"seed": [SEED], "guided": [GUIDED, without_statistic(recover_misnamed_ids(GUIDED)[0])],
                       "transfer": [TRANSFER]})
    package, _, _ = await builder.generate_initial_package(STEP, CONTEXT, client_factory=factory)
    assert package is not None and factory.counts["guided"] == 2
    correction = [data for name, _, data in factory.requests if name == "guided"][1]["correction"]
    assert [item["type"] for item in correction["validation_errors"]] == ["undeclared_numbers"]
    assert correction["rejected_component"]["fields"][1]["id"] == "rewrite"


@pytest.mark.asyncio
async def test_schema_failure_correction_also_hears_component_check_defects(monkeypatch):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    broken = copy.deepcopy(GUIDED)
    broken["fields"][1]["criteria"] = []  # A real schema error recovery must not hide.
    factory = Factory({"seed": [SEED], "guided": [broken, without_statistic(recover_misnamed_ids(GUIDED)[0])],
                       "transfer": [TRANSFER]})
    package, _, _ = await builder.generate_initial_package(STEP, CONTEXT, client_factory=factory)
    assert package is not None and factory.counts["guided"] == 2
    errors = [data for name, _, data in factory.requests if name == "guided"][1]["correction"]["validation_errors"]
    types = [item["type"] for item in errors]
    assert "too_short" in types and types[-1] == "undeclared_numbers"
    assert not any(item.get("loc", [None])[-1:] == [": "] for item in errors)  # ids were recovered first
    metadata = next(call.kwargs["response"].effective_parameters["component_validation"]
                    for call in record.await_args_list
                    if call.kwargs.get("metadata", {}).get("component") == "activity_guided"
                    and not call.kwargs["metadata"]["correction"])
    assert {"type": "undeclared_numbers", "loc": []} in metadata["errors"]


@pytest.mark.parametrize("key", [": ", "", " ", "-", "_id", "Id", "ID", "id ", "iD"])
def test_only_empty_punctuation_or_id_spelled_keys_are_recovered(key):
    draft = copy.deepcopy(GUIDED)
    draft["fields"][1] = {(key if name == ": " else name): value for name, value in draft["fields"][1].items()}
    recovered, count = recover_misnamed_ids(draft)
    assert count == 2 and recovered["fields"][1]["id"] == "rewrite"


@pytest.mark.parametrize("key", ["units", "name", "lable", "field", "identifier"])
def test_a_misspelled_known_property_is_never_turned_into_an_id(key):
    # Review example: {"label": ..., "kind": "number", "units": "usd", ...} must not become id "usd".
    field = {"label": "Net cash in June", "kind": "number", key: "usd", "expression": "cash_in - cash_out",
             "rubric_criterion": "Separates cash timing from accrual timing",
             "explanation": "Net cash counts only the money that actually moved in June."}
    recovered, count = recover_misnamed_ids({"fields": [field]})
    assert count == 0 and recovered["fields"][0] == field and "id" not in recovered["fields"][0]


@pytest.mark.asyncio
async def test_an_unexpected_preview_check_error_keeps_the_original_schema_error(monkeypatch):
    monkeypatch.setattr(builder, "record_llm_response", AsyncMock(return_value=True))
    real = builder.require_component_checks

    def flaky(activity):
        if len(activity.fields) == 1:  # Only the one-field preview of the broken guided draft.
            raise RuntimeError("unexpected preview failure")
        return real(activity)

    monkeypatch.setattr(builder, "require_component_checks", flaky)
    broken = copy.deepcopy(GUIDED)
    broken["fields"][1]["criteria"] = []
    factory = Factory({"seed": [SEED], "guided": [broken, without_statistic(recover_misnamed_ids(GUIDED)[0])],
                       "transfer": [TRANSFER]})
    package, _, _ = await builder.generate_initial_package(STEP, CONTEXT, client_factory=factory)
    assert package is not None and factory.counts["guided"] == 2
    errors = [data for name, _, data in factory.requests if name == "guided"][1]["correction"]["validation_errors"]
    assert "too_short" in [item["type"] for item in errors]
    assert "undeclared_numbers" not in [item["type"] for item in errors]
