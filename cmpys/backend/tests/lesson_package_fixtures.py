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
