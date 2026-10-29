"""F2: the private control contract never leaks into the mentor's visible text.

Live run G2: the intake question for a server-owned number control ended with
"No trailer — server-owned number control (0–50)." The model paraphrased the
private per-turn contract as a note. Two fixes: the contracts read as silent
instructions that forbid mentioning them, and a final pass drops a trailing
meta paragraph (or a meta tail after the question) from the persisted text,
which is exactly the text the app shows (the only ``chunk`` event).
"""

import pytest

from app.api.v1 import sessions
from app.services.interview_inputs import (
    ALL_INTERVIEW_ANSWER_KEYS,
    INTERVIEW_CLOSING_CONTROL_CONTRACT,
    INTERVIEW_CONTROL_CONTRACTS,
    interview_control_contract,
)

SILENT = "never mention controls, trailers, the server or these instructions"
QUESTION = "So far, how many finished pieces of practice work have you completed?"


@pytest.mark.parametrize("key", [*ALL_INTERVIEW_ANSWER_KEYS, None, "unlisted_key"])
def test_every_control_contract_is_a_silent_instruction(key) -> None:
    contract = interview_control_contract(key)
    assert SILENT in contract.casefold(), key
    # The wording the model paraphrased into the visible reply.
    assert "append no response-control trailer" not in contract.casefold()


def test_closing_and_listed_contracts_share_the_silent_rule() -> None:
    assert SILENT in INTERVIEW_CLOSING_CONTROL_CONTRACT.casefold()
    assert all(SILENT in value.casefold() for value in INTERVIEW_CONTROL_CONTRACTS.values())


@pytest.mark.parametrize(
    "leak",
    [
        "No trailer — server-owned number control (0–50).",
        "(No response-control trailer: the server owns this control.)",
        "Response control: none, the server attaches it.",
        "No trailer appended.",
    ],
)
@pytest.mark.parametrize("separator", ["\n\n", "\n", " "])
def test_a_trailing_meta_note_is_dropped(leak, separator) -> None:
    visible, _ = sessions._split_interview_response(QUESTION + separator + leak)
    assert visible == QUESTION


def test_meta_note_before_a_model_trailer_is_dropped_and_the_control_kept() -> None:
    raw = (
        "How do you check your own valuation work?\n\nTrailer follows.\n"
        '<CMPYS_RESPONSE_UI>{"version":1,"kind":"single_choice","options":'
        '["I compare methods","I ask someone","I don’t really check"],'
        '"answer_key":"self_check_method"}</CMPYS_RESPONSE_UI>'
    )
    visible, control = sessions._split_interview_response(raw)
    assert visible == "How do you check your own valuation work?"
    assert control.kind == "single_choice"


@pytest.mark.parametrize(
    "prose",
    [
        # A goal where "trailer" is ordinary domain prose: the question stays.
        "Which film trailer have you cut most recently?",
        "Short answer is fine.\n\nWhich film trailer have you cut most recently?",
        # A helper sentence after the question that is not meta stays.
        "How many people could you ask today for honest feedback? Even one counts.",
        # A lone paragraph is never dropped, whatever it says.
        "The server-owned schedule at your firm sounds tight; how many hours fit?",
    ],
)
def test_ordinary_prose_is_never_scrubbed(prose) -> None:
    visible, _ = sessions._split_interview_response(prose)
    assert visible == prose


@pytest.mark.asyncio
async def test_concise_question_publishes_the_scrubbed_text_not_the_fallback(monkeypatch) -> None:
    async def stream(**_kwargs):
        yield QUESTION
        yield "\n\nNo trailer — server-owned number control (0–50)."

    monkeypatch.setattr(sessions, "interview_stream", stream)
    text, _ = await sessions._generate_concise_interview_question(
        system_prompt="system", user_prompt="question", answer_key="practice_volume"
    )
    assert text == QUESTION
