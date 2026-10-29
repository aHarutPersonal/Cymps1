"""Pilot replay-then-live: recorded responses are served free, everything else goes live."""
import hashlib
import json

import pytest

from app.services.llm.client import LLMResponse
from scripts.pilot_generation import Budget, RecordedResponses, guard_client

RATES = (1.0, 4.0)


def _sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _record(source, request_id, *, user_prompt, scenario="s", run_id="candidate-1", schema="Seed",
            data=None, error=None, response_file=True, tokens=(300, 40, 340), system_prompt=None):
    row = {"scenario_id": scenario, "run_id": run_id, "model": "fake-model", "schema": schema,
           "request_sha256": _sha(user_prompt), "id": request_id}
    if system_prompt is not None:
        row["system_sha256"] = _sha(system_prompt)
    with (source / "usage.jsonl").open("a") as stream:
        stream.write(json.dumps({**row, "status": "reserved", "reserved_usd": .05}) + "\n")
        stream.write(json.dumps({**row, "status": "finished", "charged_usd": .001, "usage_unknown": False,
            "response_received": True, "finish_reason": None if error else "stop", "error": error,
            "prompt_tokens": tokens[0], "completion_tokens": tokens[1], "total_tokens": tokens[2],
            "thoughts_tokens": 7, "duration_ms": 1234.0}) + "\n")
    if response_file:
        (source / f"{request_id}-response.json").write_text(json.dumps({
            "schema": schema, "data": data if data is not None else {"recorded": request_id},
            "error": error, "visible_response": json.dumps(data or {"recorded": request_id}),
            "finish_reason": None if error else "stop", "request_sha256": _sha(user_prompt)}))


class Seed:  # stands in for an output model; only its name is used for replay
    @staticmethod
    def model_json_schema():
        return {}


class Other(Seed):
    pass


class LiveProvider:
    model, max_tokens, provider_name = "fake-model", 1000, "fake"

    def __init__(self):
        self.last_attempt = None
        self.prompts = []

    async def generate_json(self, *, system_prompt, user_prompt, output_model=None, **kwargs):
        self.prompts.append(user_prompt)
        response = LLMResponse(data={"live": user_prompt}, finish_reason="stop",
                               prompt_tokens=2000, completion_tokens=500, total_tokens=2500)
        self.last_attempt = response
        return response


@pytest.fixture
def source(tmp_path):
    directory = tmp_path / "source"
    directory.mkdir()
    _record(directory, "r-a", user_prompt="prompt-a", data={"answer": [1, 2]})
    _record(directory, "r-err", user_prompt="prompt-err", error="zai request failed (ValueError; finish=missing)")
    _record(directory, "r-nofile", user_prompt="prompt-nofile", response_file=False)
    _record(directory, "r-other-run", user_prompt="prompt-run2", run_id="candidate-2")
    _record(directory, "r-b1", user_prompt="prompt-b", data={"n": 1})
    _record(directory, "r-b2", user_prompt="prompt-b", data={"n": 2})
    return directory


def _setup(tmp_path, source, stage=None):
    output = tmp_path / "out"
    output.mkdir()
    budget = Budget(output / "usage.jsonl", 5)
    provider = LiveProvider()
    guard_client(provider, budget=budget,
                 stage=stage or {"scenario_id": "s", "run_id": "fixes-1", "replay_run_id": "candidate-1"},
                 output_dir=output, token_rates=lambda bound: RATES, reasoning_reserve=200,
                 estimate_cost=lambda r: (r.prompt_tokens * RATES[0] + r.completion_tokens * RATES[1]) / 1e6,
                 recorded=RecordedResponses(source))
    return output, budget, provider


async def _call(provider, prompt, model=Seed):
    return await provider.generate_json(system_prompt="sys", user_prompt=prompt, output_model=model)


@pytest.mark.asyncio
async def test_recorded_hash_is_served_without_a_provider_call_or_charge(tmp_path, source):
    output, budget, provider = _setup(tmp_path, source)
    response = await _call(provider, "prompt-a")
    assert provider.prompts == []
    assert isinstance(response, LLMResponse)
    assert response.data == {"answer": [1, 2]} and response.error is None
    assert response.finish_reason == "stop" and response.raw_response == json.dumps({"answer": [1, 2]})
    assert (response.prompt_tokens, response.completion_tokens, response.total_tokens) == (300, 40, 340)
    assert budget.spent == 0 and not budget.pending
    rows = [json.loads(line) for line in (output / "usage.jsonl").read_text().splitlines()]
    assert len(rows) == 1
    assert rows[0]["charged_basis"] == "replayed" and rows[0]["charged_usd"] == 0
    assert rows[0]["replayed_from"] == "r-a" and rows[0]["status"] == "finished"
    assert rows[0]["request_sha256"] == _sha("prompt-a")
    # The new run is itself replayable: its response file is written under the new id.
    saved = json.loads((output / f"{rows[0]['id']}-response.json").read_text())
    assert saved["data"] == {"answer": [1, 2]} and saved["error"] is None
    # Callers may mutate a served response without altering a later serve.
    response.data["answer"].append(3)


@pytest.mark.asyncio
async def test_each_recording_is_served_at_most_as_often_as_recorded(tmp_path, source):
    output, budget, provider = _setup(tmp_path, source)
    first, second, third = [await _call(provider, "prompt-b") for _ in range(3)]
    assert (first.data, second.data) == ({"n": 1}, {"n": 2})
    assert third.data == {"live": "prompt-b"} and provider.prompts == ["prompt-b"]
    again = await _call(provider, "prompt-a")
    assert again.data == {"answer": [1, 2]}
    assert (await _call(provider, "prompt-a")).data == {"live": "prompt-a"}
    rows = [json.loads(line) for line in (output / "usage.jsonl").read_text().splitlines()]
    bases = [row["charged_basis"] for row in rows if row["status"] == "finished"]
    assert bases == ["replayed", "replayed", "actual", "replayed", "actual"]
    assert budget.spent == pytest.approx(2 * (2000 * 1.0 + 500 * 4.0) / 1e6)


@pytest.mark.asyncio
async def test_unrecorded_errored_or_unsaved_requests_go_live_and_are_charged(tmp_path, source):
    output, budget, provider = _setup(tmp_path, source)
    for prompt in ("prompt-new", "prompt-err", "prompt-nofile"):
        assert (await _call(provider, prompt)).data == {"live": prompt}
    assert provider.prompts == ["prompt-new", "prompt-err", "prompt-nofile"]
    finished = [json.loads(line) for line in (output / "usage.jsonl").read_text().splitlines()
                if json.loads(line)["status"] == "finished"]
    assert [row["charged_basis"] for row in finished] == ["actual"] * 3
    assert budget.spent == pytest.approx(3 * (2000 * 1.0 + 500 * 4.0) / 1e6)


@pytest.mark.asyncio
async def test_replay_is_scoped_to_scenario_mapped_run_and_schema(tmp_path, source):
    _, _, provider = _setup(tmp_path, source)
    # prompt-run2 was recorded for candidate-2; this run replays candidate-1.
    assert (await _call(provider, "prompt-run2")).data == {"live": "prompt-run2"}
    assert (await _call(provider, "prompt-a", model=Other)).data == {"live": "prompt-a"}
    other = tmp_path / "other"
    other.mkdir()
    _, _, elsewhere = _setup(other, source, {"scenario_id": "t", "run_id": "fixes-1",
                                             "replay_run_id": "candidate-1"})
    assert (await _call(elsewhere, "prompt-a")).data == {"live": "prompt-a"}
    mapped = tmp_path / "mapped"
    mapped.mkdir()
    _, _, second = _setup(mapped, source, {"scenario_id": "s", "run_id": "fixes-2",
                                           "replay_run_id": "candidate-2"})
    assert (await _call(second, "prompt-run2")).data == {"recorded": "r-other-run"}
    assert second.prompts == []


@pytest.mark.asyncio
async def test_without_a_replay_run_id_nothing_is_replayed(tmp_path, source):
    _, _, provider = _setup(tmp_path, source, {"scenario_id": "s", "run_id": "candidate-1"})
    assert (await _call(provider, "prompt-a")).data == {"live": "prompt-a"}


@pytest.mark.asyncio
async def test_a_recorded_system_prompt_hash_must_match(tmp_path, source):
    _record(source, "r-sys-old", user_prompt="prompt-sys", system_prompt="old system prompt")
    _record(source, "r-sys-same", user_prompt="prompt-sys2", system_prompt="sys")
    output, _, provider = _setup(tmp_path, source)
    assert (await _call(provider, "prompt-sys")).data == {"live": "prompt-sys"}
    assert (await _call(provider, "prompt-sys2")).data == {"recorded": "r-sys-same"}
    rows = [json.loads(line) for line in (output / "usage.jsonl").read_text().splitlines()]
    assert all(row["system_sha256"] == _sha("sys") for row in rows)
