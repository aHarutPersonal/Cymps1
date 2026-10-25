"""Opt-in paid, synthetic first-pass lesson comparison. Never publishes content.

Run from the backend directory with PYTHONPATH=. and an explicit --max-usd.
The cap uses configured conservative provider prices, not an invoice. A request
reserves UTF-8 byte length (an intentionally loose token bound), wire overhead,
and the entire visible + reasoning output ceiling before it can leave the process.
Unknown usage retains its reservation. No SDK retries or provider fallback.
The append-only ledger prevents a restart from silently resetting the cap.
"""
import argparse
import asyncio
import hashlib
import json
import math
import os
import re
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

    def finish(self, request_id, actual, metadata):
        if actual is not None and (not math.isfinite(actual) or actual < 0):
            raise ValueError("Invalid billed cost; keep the pending reservation")
        reserved = self.pending.pop(request_id)
        charged = reserved if actual is None else actual
        self.spent += charged
        self.append({**metadata, "id": request_id, "status": "finished", "charged_usd": charged,
                     "usage_unknown": actual is None})
        if charged > reserved:
            raise RuntimeError("Usage exceeded conservative reservation; pilot stopped")


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

    def factory(**options):
        client = get_llm_client(**{**options, "allow_fallback": False})
        generate = client.generate_json
        async def guarded(*, system_prompt, user_prompt, output_model=None, **kwargs):
            nonlocal replay
            if replay is not None:
                if output_model is not LessonPackage or stage.get("stage") != "package":
                    raise RuntimeError("Unexpected request before truncated package recovery")
                previous, replay = replay, None
                return previous
            schema = output_model.model_json_schema() if output_model else kwargs.get("json_schema", {})
            input_bound = len((system_prompt + user_prompt + json.dumps(schema)).encode()) + 8192
            reserve_tokens = getattr(settings, settings.llm_provider + "_reasoning_token_reserve")
            output_bound = (client.max_tokens or 4096) + reserve_tokens
            rates = price_card_for_model(client.model, settings.llm_provider).token_rates(input_bound)
            # Additional margin protects the account from small rate/rounding differences.
            reserved = (input_bound * rates[0] + output_bound * rates[1]) / 1_000_000 * 1.25
            request_details = _request_diagnostics(user_prompt, output_model.__name__ if output_model else None)
            request_id = budget.reserve(reserved, {**stage, "model": client.model,
                **request_details,
                "input_bound": input_bound, "output_bound": output_bound,
                "schema": output_model.__name__ if output_model else None})
            response = None
            previous_attempt = getattr(client, "last_attempt", None)
            attempt_started = time.perf_counter()
            try:
                response = await generate(system_prompt=system_prompt, user_prompt=user_prompt,
                                          output_model=output_model, **kwargs)
                return response
            finally:
                actual = None
                if response is not None and response.prompt_tokens is not None and response.total_tokens is not None:
                    actual = estimate_cost_usd(model=client.model, provider=settings.llm_provider,
                        prompt_tokens=response.prompt_tokens, completion_tokens=response.completion_tokens,
                        total_tokens=response.total_tokens)
                # Synthetic content only. Keep visible structured drafts for
                # reproducible failures; never retain provider reasoning.
                if response is not None:
                    (args.output / (request_id + "-response.json")).write_text(json.dumps({
                        "schema": output_model.__name__ if output_model else None,
                        "data": response.data, "error": response.error,
                        "visible_response": response.raw_response,
                        "finish_reason": response.finish_reason,
                        **request_details,
                    }, ensure_ascii=False, indent=2))
                budget.finish(request_id, actual, {**stage, "model": client.model,
                    **request_details,
                    **_attempt_diagnostics(response, client, previous_attempt, attempt_started,
                        output_model.__name__ if output_model else None)})
        client.generate_json = guarded
        return client

    cases = json.loads((Path(__file__).parents[1] / "tests/fixtures/generation_scenarios.json").read_text())
    selected = [next(c for c in cases if c["domain"] == domain and c["learner_level"] == "novice" and c["evidence_status"] == "missing")
                for domain in args.domains.split(",")]
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
    asyncio.run(run(parser.parse_args()))
