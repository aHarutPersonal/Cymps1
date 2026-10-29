"""Opt-in paid, synthetic first-pass lesson comparison. Never publishes content.

Run from the backend directory with PYTHONPATH=. and an explicit --max-usd.
The cap uses configured conservative provider prices, not an invoice. A request
reserves UTF-8 byte length (an intentionally loose token bound), wire overhead,
and the entire visible + reasoning output ceiling before it can leave the process.
Unknown usage retains its reservation, except a cancellation that received no
stream event or usage, which books only its input part. No SDK retries or
provider fallback. --replay-from serves recorded responses free, marked "replayed".
The append-only ledger prevents a restart from silently resetting the cap.
"""
import argparse
import asyncio
import hashlib
import json
import math
import os
import re
import statistics
import time
from pathlib import Path
from uuid import uuid4


def _request_diagnostics(user_prompt, schema_name):
    """Identify concurrent synthetic scopes without copying source text or IDs."""
    result = {"request_sha256": hashlib.sha256(user_prompt.encode("utf-8")).hexdigest()}
    if schema_name != "ReviewEvidencePatch":
        return result
    try:
        body = json.loads(user_prompt)
        spans = body["numeric_spans"]
        owners = body["numeric_span_owners"]
        activities = body["package"]["workbook"]["activities"]
        if (type(spans) is not dict or type(owners) is not dict or type(activities) is not list
                or any(type(key) is not str or re.fullmatch(r"n[1-9][0-9]*", key) is None for key in spans)):
            return result
        ids = [activity["id"] for activity in activities]
        if any(type(key) is not str for key in ids) or len(ids) != len(set(ids)):
            return result
        positions = {"practice." + key: index for index, key in enumerate(ids)}
        if any(owners.get(key) not in positions for key in spans):
            return result
        result.update(request_scope_kind="package_evidence", request_claim_ids=list(spans),
                      request_owner_positions=sorted({positions[owners[key]] for key in spans}))
    except (KeyError, TypeError, ValueError):
        pass
    return result


def _attempt_diagnostics(response, client, previous_attempt, started, schema_name):
    """Retain safe cancellation timing without changing conservative billing."""
    observed = response
    if observed is None:
        last_attempt = getattr(client, "last_attempt", None)
        if last_attempt is not previous_attempt:
            observed = last_attempt
    result = {
        "schema": schema_name,
        "response_received": response is not None,
        "duration_ms": (time.perf_counter() - started) * 1000,
    }
    if observed is not None:
        result.update({key: getattr(observed, key, None) for key in (
            "duration_ms", "first_event_ms", "first_content_ms", "response_chars", "finish_reason", "prompt_tokens", "completion_tokens",
            "total_tokens", "thoughts_tokens", "error", "effective_parameters",
        )})
    return result


class Budget:
    def __init__(self, path, cap):
        if not math.isfinite(cap) or not 0 < cap <= 10:
            raise ValueError("This pilot requires an explicit cap between $0 and $10")
        self.path, self.cap = Path(path), cap
        self.rows = [json.loads(line) for line in self.path.read_text().splitlines()] if self.path.exists() else []
        self.pending = {}
        self.spent = 0.0
        for row in self.rows:
            if row["status"] == "reserved":
                self.pending[row["id"]] = row["reserved_usd"]
            else:
                self.spent += row["charged_usd"]
                self.pending.pop(row["id"], None)

    def append(self, row):
        with self.path.open("a") as stream:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

    def reserve(self, amount, metadata):
        if not math.isfinite(amount) or amount <= 0 or self.spent + sum(self.pending.values()) + amount > self.cap:
            raise RuntimeError("Pilot budget exhausted; no request sent")
        request_id = str(uuid4())
        self.pending[request_id] = amount
        self.append({**metadata, "id": request_id, "status": "reserved", "reserved_usd": amount})
        return request_id

    def finish(self, request_id, actual, metadata, *, input_only_usd=None):
        """Book a settled request. Unknown usage keeps the whole reservation,
        except a cancellation the caller proved saw no response or usage
        (``input_only_usd``): the prompt may be billed, no output was produced."""
        for amount in (actual, input_only_usd):
            if amount is not None and (not math.isfinite(amount) or amount < 0):
                raise ValueError("Invalid billed cost; keep the pending reservation")
        reserved = self.pending.pop(request_id)
        if actual is not None:
            charged, basis = actual, "actual"
        elif input_only_usd is not None:
            charged, basis = min(input_only_usd, reserved), "input_only_cancelled"
        else:
            charged, basis = reserved, "full_reserve"
        self.spent += charged
        self.append({**metadata, "id": request_id, "status": "finished", "charged_usd": charged,
                     "usage_unknown": actual is None, "charged_basis": basis})
        if charged > reserved:
            raise RuntimeError("Usage exceeded conservative reservation; pilot stopped")

    def record_replay(self, metadata):
        """A recorded response served again: nothing was sent, nothing is charged."""
        request_id = str(uuid4())
        self.append({**metadata, "id": request_id, "status": "finished", "charged_usd": 0.0,
                     "usage_unknown": False, "charged_basis": "replayed"})
        return request_id


def _cancelled_before_response(cancelled, response, details):
    """True only for a cancellation that observed no stream event, text or usage.

    A stream that had started may already have produced billable reasoning or
    visible output, so it keeps the whole reservation like any other unknown.
    """
    return (cancelled and response is None and details.get("first_event_ms") is None
            and details.get("first_content_ms") is None and not details.get("response_chars")
            and all(details.get(key) is None for key in ("prompt_tokens", "completion_tokens", "total_tokens")))


class RecordedResponses:
    """Settled, error-free responses of an earlier run, served by request hash.

    Keyed by (scenario_id, run_id, schema, request_sha256); each recording is
    served at most once, so a hash recorded N times is served at most N times.
    A recording that kept a system-prompt hash is served only for that prompt.
    """

    def __init__(self, directory):
        directory = Path(directory)
        self.entries = {}
        for line in (directory / "usage.jsonl").read_text().splitlines():
            row = json.loads(line)
            if row.get("status") != "finished" or row.get("error") or not row.get("request_sha256"):
                continue
            path = directory / (str(row["id"]) + "-response.json")
            if not path.exists():
                continue
            saved = json.loads(path.read_text())
            if saved.get("error") or saved.get("request_sha256", row["request_sha256"]) != row["request_sha256"]:
                continue
            key = (row.get("scenario_id"), row.get("run_id"), row.get("schema"), row["request_sha256"])
            self.entries.setdefault(key, []).append((row, saved))

    def take(self, stage, schema_name, request_sha256, system_sha256):
        if not stage.get("replay_run_id"):
            return None
        queue = self.entries.get((stage.get("scenario_id"), stage["replay_run_id"], schema_name, request_sha256), [])
        for index, (row, saved) in enumerate(queue):
            if row.get("system_sha256", system_sha256) == system_sha256:
                return queue.pop(index)
        return None


def guard_client(client, *, budget, stage, output_dir, token_rates, reasoning_reserve, estimate_cost,
                 recorded=None):
    """Replace ``client.generate_json`` with the budget-guarded (or replayed) call."""
    from app.services.llm.client import LLMResponse

    generate = client.generate_json

    async def guarded(*, system_prompt, user_prompt, output_model=None, **kwargs):
        schema_name = output_model.__name__ if output_model else None
        request_details = {**_request_diagnostics(user_prompt, schema_name),
                           "system_sha256": hashlib.sha256(system_prompt.encode("utf-8")).hexdigest()}
        served = None if recorded is None else recorded.take(
            stage, schema_name, request_details["request_sha256"], request_details["system_sha256"])
        if served is not None:
            row, saved = served
            response = LLMResponse(
                data=json.loads(json.dumps(saved["data"])), raw_response=saved.get("visible_response"),
                finish_reason=saved.get("finish_reason"), model=row.get("model") or client.model,
                provider=getattr(client, "provider_name", None),
                **{key: row.get(key) for key in ("prompt_tokens", "completion_tokens", "total_tokens",
                    "thoughts_tokens", "duration_ms", "first_event_ms", "first_content_ms", "response_chars")},
                effective_parameters=dict(row.get("effective_parameters") or {}),
                transport_success=True, json_valid=True)
            request_id = budget.record_replay({**stage, "model": response.model, **request_details,
                "schema": schema_name, "replayed_from": row["id"], "response_received": True,
                **{key: getattr(response, key) for key in ("finish_reason", "prompt_tokens", "completion_tokens",
                    "total_tokens", "thoughts_tokens", "duration_ms", "error", "effective_parameters")}})
            (Path(output_dir) / (request_id + "-response.json")).write_text(json.dumps({
                "schema": schema_name, "data": saved["data"], "error": None,
                "visible_response": response.raw_response, "finish_reason": response.finish_reason,
                "replayed_from": row["id"], **request_details,
            }, ensure_ascii=False, indent=2))
            return response
        schema = output_model.model_json_schema() if output_model else kwargs.get("json_schema", {})
        input_bound = len((system_prompt + user_prompt + json.dumps(schema)).encode()) + 8192
        output_bound = (client.max_tokens or 4096) + reasoning_reserve
        rates = token_rates(input_bound)
        # Additional margin protects the account from small rate/rounding differences.
        input_reserved = input_bound * rates[0] / 1_000_000 * 1.25
        reserved = input_reserved + output_bound * rates[1] / 1_000_000 * 1.25
        request_id = budget.reserve(reserved, {**stage, "model": client.model,
            **request_details,
            "input_bound": input_bound, "output_bound": output_bound,
            "schema": schema_name})
        response = None
        cancelled = False
        previous_attempt = getattr(client, "last_attempt", None)
        attempt_started = time.perf_counter()
        try:
            response = await generate(system_prompt=system_prompt, user_prompt=user_prompt,
                                      output_model=output_model, **kwargs)
            return response
        except asyncio.CancelledError:
            cancelled = True
            raise
        finally:
            actual = None
            if response is not None and response.prompt_tokens is not None and response.total_tokens is not None:
                actual = estimate_cost(response)
            # Synthetic content only. Keep visible structured drafts for
            # reproducible failures; never retain provider reasoning.
            if response is not None:
                (Path(output_dir) / (request_id + "-response.json")).write_text(json.dumps({
                    "schema": schema_name,
                    "data": response.data, "error": response.error,
                    "visible_response": response.raw_response,
                    "finish_reason": response.finish_reason,
                    **request_details,
                }, ensure_ascii=False, indent=2))
            details = _attempt_diagnostics(response, client, previous_attempt, attempt_started, schema_name)
            budget.finish(request_id, actual, {**stage, "model": client.model, **request_details, **details},
                          input_only_usd=input_reserved if _cancelled_before_response(cancelled, response, details)
                          else None)

    client.generate_json = guarded
    return client


async def run(args):
    from app.core.config import settings
    from app.services.llm.client import get_llm_client
    from app.services.llm.pricing import price_card_for_model, estimate_cost_usd
    from app.services.llm.prompt_loader import load_and_render
    from app.services.llm.schemas import PlanDetailLessonSectionsOutput
    from app.services.planning.lesson_package import LessonPackage, generate_package, render_package_results
    from app.services.planning.lesson_review import review_lesson
    from app.tasks.plans import _assemble_parallel_lesson_response, _writing_thinking_level

    if settings.llm_provider not in {"openlux", "zai"} or not settings.llm_configured:
        raise RuntimeError("Pilot requires a configured, bounded streaming provider")
    # Process-local only: synthetic reports stay local and never enter learner DBs.
    settings.llm_usage_telemetry_enabled = False
    settings.llm_admission_limits = {}
    from app.services.llm import recovery
    recovery.operational_recovery_client = lambda *a, **kw: None
    args.output.mkdir(parents=True, exist_ok=True, mode=0o700)
    budget = Budget(args.output / "usage.jsonl", args.max_usd)
    stage = {}
    replay = None
    if args.resume_truncated_package and args.resume_package_response:
        raise ValueError("Choose one recorded response to resume")
    if args.full_pipeline and (args.resume_truncated_package or args.resume_package_response):
        raise ValueError("A full-pipeline measurement must start with a fresh package inside its deadline")
    resume_path = args.resume_truncated_package or args.resume_package_response
    if resume_path:
        from app.services.llm.client import LLMResponse
        from app.services.planning.lesson_package import parse_package_response
        saved = json.loads(resume_path.read_text())
        request_id = resume_path.name.removesuffix("-response.json")
        settled = [row for row in budget.rows if row.get("id") == request_id and row["status"] == "finished"]
        if (saved.get("schema") != "LessonPackage" or len(settled) != 1
                or settled[0].get("scenario_id") != "accounting_novice_missing"
                or args.domains != "accounting" or args.tiers != "balanced"):
            raise ValueError("Resume requires the settled accounting package in this ledger")
        if args.resume_truncated_package:
            if ("finish=length" not in str(saved.get("error"))
                    or "finish=length" not in str(settled[0].get("error"))):
                raise ValueError("Expected a recorded truncated response")
            replay = LLMResponse(data={}, error=saved["error"], finish_reason="length")
        else:
            if saved.get("error") or saved.get("finish_reason") != "stop":
                raise ValueError("Cannot resume an incomplete response as a package")
            replay = LLMResponse(data=parse_package_response(saved["data"]).model_dump(mode="json"),
                                 finish_reason="stop")
        if any(row.get("resumed_request") == request_id for row in budget.rows):
            raise ValueError("This failed request has already been resumed")
        # A durable marker prevents replay from creating another retry allowance.
        budget.append({"id": str(uuid4()), "status": "finished", "charged_usd": 0,
                       "resumed_request": request_id})

    replay_from = getattr(args, "replay_from", None)
    if replay_from is not None and not args.tutorial:
        raise ValueError("--replay-from applies to tutorial mode only")
    recorded = RecordedResponses(replay_from) if replay_from is not None else None

    def factory(**options):
        client = get_llm_client(**{**options, "allow_fallback": False})
        guard_client(client, budget=budget, stage=stage, output_dir=args.output,
            token_rates=lambda bound: price_card_for_model(client.model, settings.llm_provider).token_rates(bound),
            reasoning_reserve=getattr(settings, settings.llm_provider + "_reasoning_token_reserve"),
            estimate_cost=lambda response: estimate_cost_usd(model=client.model, provider=settings.llm_provider,
                prompt_tokens=response.prompt_tokens, completion_tokens=response.completion_tokens,
                total_tokens=response.total_tokens),
            recorded=recorded)
        guarded = client.generate_json
        async def resumable(*, system_prompt, user_prompt, output_model=None, **kwargs):
            nonlocal replay
            if replay is not None:
                if output_model is not LessonPackage or stage.get("stage") != "package":
                    raise RuntimeError("Unexpected request before truncated package recovery")
                previous, replay = replay, None
                return previous
            return await guarded(system_prompt=system_prompt, user_prompt=user_prompt,
                                 output_model=output_model, **kwargs)
        client.generate_json = resumable
        return client

    cases = json.loads((Path(__file__).parents[1] / "tests/fixtures/generation_scenarios.json").read_text())
    selected = [next(c for c in cases if c["domain"] == domain and c["learner_level"] == "novice" and c["evidence_status"] == "missing")
                for domain in args.domains.split(",")]
    if args.outline:
        await _run_outline_cases(args, cases, factory, budget, stage, load_and_render)
        return
    if args.tutorial:
        if args.scenarios:
            wanted = args.scenarios.split(",")
            selected = [c for c in cases if c["id"] in wanted] if wanted != ["all"] else cases
        await _run_tutorial_cases(args, selected, factory, budget, stage, load_and_render)
        return
    for case in selected:
        prefix = case["id"] + ("-" + args.label if args.label else "")
        stage.update(scenario_id=case["id"], stage="package", tier="balanced")
        package_start = time.perf_counter()
        # The outline title contract is shorter than a full learning goal.
        title = case["goal"] if len(case["goal"]) <= 60 else case["goal"][:61].rsplit(" ", 1)[0]
        step = {"id": "step_1", "title": title,
                "description": "Learn the concept, apply it to the supplied case, then transfer and revise independently.",
                "resources": ["Optional background reference"]}
        context = {"goal": case["goal"], "learner_context": {"level": case["learner_level"],
            "locale": case["locale"], "untrusted_note": case["untrusted_note"]},
            "mentor_evidence": {}, "target_practice_minutes": 40}
        package, package_ms = None, None
        if not args.full_pipeline:
            package, response, _ = await generate_package(step, context, client_factory=factory)
            package_ms = (time.perf_counter() - package_start) * 1000
            (args.output / (prefix + "-package.json")).write_text(json.dumps(response.data, indent=2, ensure_ascii=False))
            if package is None:
                print(json.dumps({"scenario": case["id"], "stage": "package", "error": response.error}), flush=True)
                continue
        for tier in args.tiers.split(","):
            if tier not in {"quality", "balanced", "fast"}:
                raise ValueError("Unsupported tier")
            artifact_path = args.output / (prefix + "-" + tier + ".json")
            if artifact_path.exists():
                continue
            stage.update(stage="writer", tier=tier)
            spent_before = budget.spent
            started = time.perf_counter()
            materials = [{"title": "Optional background reference", "type": "course",
                          "reason": "Optional context only; unavailable during this pilot."}]
            if args.full_pipeline:
                from app.tasks.plans import _generate_plan_item_details_parallel
                from app.services.planning.lesson_package import validation_identity
                validations = {}
                # Package, its preflight, writing and review share the normal
                # deadline. A pre-generated package would understate latency.
                packages = {}
                outline = {"steps": [step], "materials": [{**materials[0], "author_or_creator": None,
                    "search_query": "Optional background reference", "duration_minutes": 15}],
                    "definition_of_done": "Complete both prepared activities and revise using feedback.",
                    "mental_model": "Apply the mechanism to a new case and explain the reasoning."}
                from app.services.llm.schemas import PlanItemDetailsOutlineOutput
                outline = PlanItemDetailsOutlineOutput.model_validate(outline).model_dump(mode="json")
                stage.update(stage="full_pipeline")
                async with asyncio.timeout(480):
                    lesson, calls, error = await _generate_plan_item_details_parallel(
                        system_prompt=load_and_render("planner_system.txt", {}), task_title=case["goal"],
                        mission_hours=1, user_goal=case["goal"], learning_preferences="Substantial teaching with in-app practice",
                        idol_name="No verified mentor", idol_domain=case["domain"], idol_evidence={},
                        session_context=json.dumps(context), active_tier=tier, routing_reason="local_budgeted_pilot",
                        client_factory=factory, existing_checkpoint={"_generation": {"outline": outline}},
                        prepared_packages=packages, validation_records=validations)
                report = {"scenario_id": case["id"], "tier": tier, "full_pipeline": True,
                    "accepted": bool(validations) and not error, "adjudicated": False,
                    "elapsed_ms": (time.perf_counter() - started) * 1000, "package_ms": package_ms,
                    "estimated_cost_usd": budget.spent - spent_before,
                    "cost_scope": "complete lesson pipeline including package" if args.full_pipeline else "lesson excluding shared package",
                    "failures": [error] if error else [], "lesson": lesson,
                    "validation_identity": validation_identity(),
                    "lesson_validation": validations,
                    "packages": {key: value.model_dump(mode="json") for key, value in packages.items()},
                    "attempts": [{"stage": c[0], "error": c[1].error, "duration_ms": c[1].duration_ms} for c in calls]}
                artifact_path.write_text(json.dumps(report, indent=2, ensure_ascii=False))
                print(json.dumps({k: v for k, v in report.items() if k not in {"lesson", "validation_identity", "attempts", "packages", "lesson_validation"}}), flush=True)
                continue
            prompt = load_and_render("plan_item_detail_lesson.txt", {
                "task_title": case["goal"], "mission_hours": 1, "user_goal": case["goal"],
                "learning_preferences": "Substantial, self-contained teaching with in-app practice",
                "idol_name": "No verified mentor", "idol_evidence_json": {},
                "session_context": json.dumps(context), "step_json": step, "materials_json": materials,
                "prior_error": "", "target_lesson_minutes": 60, "target_practice_minutes": 40}, strict=True)
            client = factory(timeout=180, max_tokens=16000, tier=tier, thinking_level=_writing_thinking_level(tier))
            response = await client.generate_json(system_prompt=load_and_render("planner_system.txt", {}),
                user_prompt=prompt + "\nAPPROVED LESSON PACKAGE (reference data):\n" + json.dumps(package.writer_context()),
                output_model=PlanDetailLessonSectionsOutput)
            sections = response.data.copy()
            if not response.error:
                try:
                    response.data = render_package_results(response.data, package)
                except ValueError as exc:
                    response.error = str(exc)
            _assemble_parallel_lesson_response(response, step=step, material_titles={"Optional background reference"}, target_minutes=60)
            failures = [response.error] if response.error else []
            review_data = None
            if not failures:
                stage.update(stage="review")
                failures, reviewed, _ = await review_lesson(response.data, client_factory=factory,
                    context={**context, "lesson_package": package.review_context()})
                review_data = reviewed.data
                low, high = package.practice_range
                if not failures and not low <= reviewed.data["practice_minutes"] <= high:
                    failures.append("Reviewed practice duration outside executable workbook bounds")
            report = {"scenario_id": case["id"], "tier": tier, "model": client.model,
                "accepted": not failures, "adjudicated": False, "repair_count": 0,
                "elapsed_ms": (time.perf_counter() - started) * 1000, "package_ms": package_ms,
                "estimated_cost_usd": budget.spent - spent_before,
                    "cost_scope": "complete lesson pipeline including package" if args.full_pipeline else "lesson excluding shared package",
                "failures": failures, "review": review_data, "sections": sections, "lesson": response.data}
            artifact_path.write_text(json.dumps(report, indent=2, ensure_ascii=False))
            print(json.dumps({k: v for k, v in report.items() if k not in {"review", "sections", "lesson"}}), flush=True)
    print(json.dumps({"estimated_charged_or_reserved_usd": budget.spent + sum(budget.pending.values()),
                      "cap_usd": budget.cap, "promotion": "not permitted by a small unadjudicated pilot"}), flush=True)


_TITLE_BREAKS = {"using", "from", "for", "of", "with", "in", "on", "by", "to", "into", "via", "through", "while"}
_TITLE_DANGLING = _TITLE_BREAKS | {"a", "an", "the", "and", "or"}


def outline_title(goal: str, *, aim: int = 44, limit: int = 60) -> str:
    """A complete lesson title from a scenario goal, as the outline contract asks.

    The contract aims for fewer than 45 characters and allows 60. A longer
    goal is cut before a qualifying phrase ("... using a fictional ledger"),
    never mid-phrase, so the semantic review sees a complete title.
    """
    words = goal.split()
    # The longest prefix of three or more words that ends before a qualifying phrase.
    natural = [" ".join(words[:end]) for end in range(len(words) - 1, 2, -1)
               if words[end].lower() in _TITLE_BREAKS and words[end - 1].lower() not in _TITLE_DANGLING]
    for bound in (aim, limit):
        if len(goal) <= bound:
            return goal
        fitting = [title for title in natural if len(title) <= bound]
        if fitting:
            return fitting[0]
    while words and (len(" ".join(words)) > limit or words[-1].lower() in _TITLE_DANGLING):
        words.pop()
    return " ".join(words)


def tutorial_outline(case: dict) -> dict:
    """A one-tutorial tutorial_v1 scaffold for a scenario, validated like a generated one."""
    from app.services.llm.schemas import PlanTutorialOutlineOutput

    title = outline_title(case["goal"])
    # Explicit markers keep the scaffold valid for baseline code, where they are required.
    step = {"id": "step_1", "lesson_format": "tutorial_v1", "title": title,
            "description": "Learn one concept, apply it to a supplied case, then transfer it to a new case.",
            "resources": ["Optional background reference"]}
    material = {"title": "Optional background reference", "type": "course", "author_or_creator": None,
                "search_query": "Optional background reference", "duration_minutes": 15,
                "reason": "Optional context only; unavailable during this pilot."}
    return PlanTutorialOutlineOutput.model_validate({
        "lesson_format": "tutorial_v1", "steps": [step], "materials": [material],
        "definition_of_done": "Complete both prepared activities and revise using feedback.",
        "mental_model": "Apply the mechanism to a new case and explain the reasoning."}).model_dump(mode="json")


async def _run_tutorial_cases(args, selected, factory, budget, stage, load_and_render):
    """Full tutorial_v1 pipeline per scenario and repeat, as evaluate_generation rows."""
    from app.services.planning.lesson_package import validation_identity
    from app.tasks.plans import _generate_plan_item_details_parallel

    for case in selected:
        context = {"goal": case["goal"], "learner_context": {"level": case["learner_level"],
            "locale": case["locale"], "untrusted_note": case["untrusted_note"]}, "mentor_evidence": {}}
        for repeat in range(1, args.repeats + 1):
            run_id = f"{args.arm}-{repeat}"
            artifact_path = args.output / f"{case['id']}-{run_id}.json"
            if artifact_path.exists():
                continue
            stage.update(scenario_id=case["id"], stage="tutorial_pipeline", tier="balanced", run_id=run_id)
            if getattr(args, "replay_from", None) is not None:
                # Repeat N replays the recorded run N (default "candidate-N") of --replay-from.
                stage["replay_run_id"] = args.replay_run_id.format(n=repeat)
            spent_before, started = budget.spent, time.perf_counter()
            validations, packages = {}, {}
            error, lesson, calls = None, None, []
            try:
                async with asyncio.timeout(480):
                    lesson, calls, error = await _generate_plan_item_details_parallel(
                        system_prompt=load_and_render("planner_system.txt", {}), task_title=case["goal"],
                        mission_hours=0.1, user_goal=case["goal"],
                        learning_preferences="Short tutorials with a worked example and in-app practice",
                        idol_name="No verified mentor", idol_domain=case["domain"], idol_evidence={},
                        session_context=json.dumps(context), active_tier="balanced",
                        routing_reason="local_budgeted_tutorial_pilot", client_factory=factory,
                        existing_checkpoint={"_generation": {"outline": tutorial_outline(case)}},
                        prepared_packages=packages, validation_records=validations)
            except TimeoutError:
                error = "Tutorial pilot deadline reached"
            except RuntimeError as exc:
                if "pilot" not in str(exc).lower() and "cap" not in str(exc).lower():
                    raise
                error = str(exc)  # Budget stop: record the partial run, then stop spending.
            row = {"scenario_id": case["id"], "run_id": run_id, "arm": args.arm,
                   "accepted": bool(validations) and not error, "adjudicated": False,
                   "quality_score": None, "usable_ms": (time.perf_counter() - started) * 1000,
                   "cost_usd": budget.spent - spent_before,
                   "repair_count": sum(any(k in str(c[0]) for k in ("repair", "correct", "recheck", "_2")) for c in calls),
                   "calls": len(calls), "failures": [error] if error else [],
                   "validation_identity": validation_identity(),
                   "attempts": [{"stage": c[0], "error": c[1].error, "duration_ms": c[1].duration_ms} for c in calls],
                   "packages": {k: v.model_dump(mode="json") for k, v in packages.items()}, "lesson": lesson}
            artifact_path.write_text(json.dumps(row, indent=2, ensure_ascii=False))
            with (args.output / "runs.jsonl").open("a") as handle:
                handle.write(json.dumps({k: v for k, v in row.items() if k not in {"lesson", "packages", "attempts", "validation_identity"}}) + "\n")
            print(json.dumps({k: row[k] for k in ("scenario_id", "run_id", "accepted", "usable_ms", "cost_usd", "calls", "failures")}), flush=True)
            if budget.spent + sum(budget.pending.values()) >= budget.cap:
                print(json.dumps({"stopped": "budget cap reached"}), flush=True)
                return
    print(json.dumps({"estimated_charged_or_reserved_usd": budget.spent + sum(budget.pending.values()),
                      "cap_usd": budget.cap, "promotion": "screening only; not the promotion rule"}), flush=True)


# Missions span the 2-3 h range where the 45 s outline cap failed live (26 Oct).
OUTLINE_MISSIONS = (("accounting_novice_evidence", 2.0), ("writing_experienced_missing", 2.5),
                    ("software_novice_evidence", 3.0))
# Explicit reasoning levels: "medium" (sent as high) was the default before 26 Oct.
OUTLINE_ARMS = ("medium", "low")


def outline_mission(case: dict, hours: float) -> dict:
    """A multi-hour mission for one scenario (synthetic content only)."""
    return {"title": case["goal"],
            "description": (f"Over about {hours:g} hours, build this skill step by step: "
                            f"{case['goal'][0].lower() + case['goal'][1:]}. Study each idea on a supplied "
                            "case, practise it in the app, and finish by revising one complete piece of work."),
            "success_metric": (f"A revised, self-checked piece of {case['domain'].replace('_', ' ')} work "
                               "that applies the skill to a new case.")}


def summarize_outline_runs(rows: list[dict], *, cap_ms: float = 45_000) -> dict:
    """Per arm: valid outlines, how many fit the production cap, latency, cost and size."""
    summary = {}
    for arm in sorted({row["arm"] for row in rows}):
        runs = [row for row in rows if row["arm"] == arm]
        valid = [row for row in runs if not row["error"]]
        durations = sorted(row["duration_ms"] for row in runs)
        summary[arm] = {
            "runs": len(runs), "valid": len(valid),
            "valid_within_cap": sum(row["duration_ms"] <= cap_ms for row in valid),
            "median_ms": round(statistics.median(durations)), "max_ms": round(durations[-1]),
            "cost_usd": round(sum(row["cost_usd"] or 0 for row in runs), 4),
            "mean_lessons": round(statistics.mean(row["lessons"] for row in valid), 1) if valid else None,
        }
    return summary


async def _run_outline_cases(args, cases, factory, budget, stage, load_and_render):
    """The production outline request at each reasoning level, paired in time."""
    from app.core.config import settings
    from app.services.llm.pricing import estimate_cost_usd
    from app.services.llm.schemas import (MAX_PLAN_DETAIL_MATERIALS, MAX_PLAN_DETAIL_RESOURCES_PER_LESSON,
                                          MIN_PLAN_DETAIL_MATERIALS, PlanTutorialOutlineOutput)
    from app.tasks.plans import (_outline_client_options, _plan_detail_lesson_count_bounds,
                                 _validate_plan_detail_outline_response)

    by_id = {case["id"]: case for case in cases}
    log_path = args.output / "outline-runs.jsonl"
    rows = [json.loads(line) for line in log_path.read_text().splitlines()] if log_path.exists() else []
    done = {(row["scenario_id"], row["arm"], row["repeat"]) for row in rows}
    system_prompt = load_and_render("planner_system.txt", {})

    async def attempt(case, hours, arm, repeat, prompt, minimum, maximum):
        options = _outline_client_options(tutorial=True, maximum_lessons=maximum, tier="balanced")
        production_timeout = options["timeout"]
        options["thinking_level"] = arm
        # A generous request timeout measures true latency against the production cap.
        client = factory(**{**options, "timeout": 150})
        started = time.perf_counter()
        response = await client.generate_json(system_prompt=system_prompt, user_prompt=prompt,
                                              output_model=PlanTutorialOutlineOutput)
        duration_ms = (time.perf_counter() - started) * 1000
        _validate_plan_detail_outline_response(response, minimum_lessons=minimum, maximum_lessons=maximum,
                                               tutorial=True)
        cost = None
        if response.prompt_tokens is not None and response.total_tokens is not None:
            cost = estimate_cost_usd(model=client.model, provider=settings.llm_provider,
                prompt_tokens=response.prompt_tokens, completion_tokens=response.completion_tokens,
                total_tokens=response.total_tokens)
        steps = [] if response.error else response.data.get("steps", [])
        row = {"scenario_id": case["id"], "mission_hours": hours, "arm": arm, "repeat": repeat,
               "thinking_level": options["thinking_level"], "production_timeout_s": production_timeout,
               "max_tokens": options["max_tokens"], "lesson_bounds": [minimum, maximum],
               "duration_ms": duration_ms, "finish_reason": response.finish_reason,
               "prompt_tokens": response.prompt_tokens, "completion_tokens": response.completion_tokens,
               "thoughts_tokens": getattr(response, "thoughts_tokens", None), "cost_usd": cost,
               "error": response.error, "lessons": len(steps),
               "materials": 0 if response.error else len(response.data.get("materials", [])),
               "mean_description_words": round(statistics.mean(len(str(s.get("description", "")).split())
                                                                for s in steps), 1) if steps else None}
        (args.output / f"{case['id']}-{arm}-{repeat}.json").write_text(json.dumps(
            {**row, "outline": None if response.error else response.data}, indent=2, ensure_ascii=False))
        return row

    for scenario_id, hours in OUTLINE_MISSIONS:
        case = by_id[scenario_id]
        minimum, maximum = _plan_detail_lesson_count_bounds(hours, lesson_format="tutorial_v1")
        mission = outline_mission(case, hours)
        context = {"goal": case["goal"], "learner_context": {"level": case["learner_level"],
            "locale": case["locale"], "untrusted_note": case["untrusted_note"]}, "mentor_evidence": {}}
        session_context = (json.dumps(context) + "\n\nCurrent mission (an incremental step toward the overall goal):\n"
                           + json.dumps(mission, ensure_ascii=False))
        prompt = load_and_render("plan_item_tutorial_outline.txt", {
            "task_title": mission["title"], "mission_hours": hours, "user_goal": case["goal"],
            "learning_preferences": "Short tutorials with a worked example and in-app practice",
            "idol_name": "No verified mentor", "idol_domain": case["domain"], "idol_evidence_json": {},
            "session_context": session_context, "minimum_lessons": minimum, "maximum_lessons": maximum,
            "minimum_materials": MIN_PLAN_DETAIL_MATERIALS, "maximum_materials": MAX_PLAN_DETAIL_MATERIALS,
            "maximum_resources_per_lesson": MAX_PLAN_DETAIL_RESOURCES_PER_LESSON}, strict=True)
        for repeat in range(1, args.repeats + 1):
            arms = [arm for arm in OUTLINE_ARMS if (scenario_id, arm, repeat) not in done]
            if not arms:
                continue
            stage.update(scenario_id=scenario_id, stage="outline", tier="balanced", run_id=f"r{repeat}")
            new_rows = await asyncio.gather(*(attempt(case, hours, arm, repeat, prompt, minimum, maximum)
                                              for arm in arms))
            with log_path.open("a") as handle:
                for row in new_rows:
                    handle.write(json.dumps(row) + "\n")
                    print(json.dumps({k: row[k] for k in ("scenario_id", "mission_hours", "arm", "repeat",
                        "duration_ms", "finish_reason", "lessons", "cost_usd", "error")}), flush=True)
            rows.extend(new_rows)
            if budget.spent + sum(budget.pending.values()) >= budget.cap:
                print(json.dumps({"stopped": "budget cap reached"}), flush=True)
                break
    summary = summarize_outline_runs(rows)
    (args.output / "outline-summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps({"summary": summary, "estimated_charged_or_reserved_usd":
                      budget.spent + sum(budget.pending.values()), "cap_usd": budget.cap}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-usd", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--domains", default="accounting,geometry,writing")
    parser.add_argument("--tiers", default="quality,balanced")
    parser.add_argument("--label", default="", choices=["", "corrected"])
    parser.add_argument("--full-pipeline", action="store_true")
    parser.add_argument("--resume-truncated-package", type=Path)
    parser.add_argument("--resume-package-response", type=Path)
    parser.add_argument("--tutorial", action="store_true", help="Run the full tutorial_v1 pipeline")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--scenarios", default="", help="Comma-separated scenario ids, or 'all' (tutorial mode)")
    parser.add_argument("--arm", default="candidate", choices=["baseline", "candidate", "fixes"])
    parser.add_argument("--replay-from", type=Path,
                        help="Tutorial mode: serve settled, error-free responses recorded in this pilot "
                             "directory by request hash (free); every other request goes live under the cap")
    parser.add_argument("--replay-run-id", default="candidate-{n}",
                        help="Recorded run replayed by repeat {n} (default candidate-{n})")
    parser.add_argument("--outline", action="store_true",
                        help="Compare the tutorial outline request at medium vs low reasoning")
    asyncio.run(run(parser.parse_args()))
