"""Small executable assessment fixture; never used as generated production text."""
def package_payload():
    return {"teaching_cases": [], "workbook": {
        "title": "Apply and revise an argument",
        "activities": [{
            "id": name, "title": title, "kind": kind,
            "instructions": "Write a claim about the supplied scenario, give a reason, test an objection and revise the claim.",
            "data": [], "fields": [{"id": "argument", "label": "Claim, reason, objection and revision",
                "kind": "text", "criteria": ["States a claim", "Addresses an objection", "Revises using a reason"]}],
            "hint": "Check whether the objection targets the reason supporting your claim.",
            "worked_solution": "A defensible claim specifies its conditions. A strong objection tests those conditions, and a revision narrows the claim accordingly.",
            "minutes_min": 15, "minutes_max": 45,
        } for name, title, kind in [("guided", "Guided argument", "practice"),
                                   ("transfer", "Independent argument", "transfer")]]}}


def multi_choice_first(activity: dict) -> dict:
    """Turn a fixture activity's first text field into a multi-select, as a new tutorial needs.

    New tutorial activities carry a number or multi_choice answer; the saved
    text-only fixtures above stay valid for everything that is not generated now.
    """
    first = activity["fields"][0]
    activity["fields"][0] = {
        "id": first["id"], "kind": "multi_choice", "label": first["label"],
        "choices": [{"id": "claim", "label": "A claim with its conditions"},
                    {"id": "slogan", "label": "A slogan without a reason"},
                    {"id": "objection", "label": "An objection that tests the reason"}],
        "correct_choices": ["claim", "objection"],
        "rubric_criterion": "Names the parts of a tested argument",
    }
    return activity
