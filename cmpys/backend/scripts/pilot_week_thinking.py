"""Opt-in paid comparison of the Week 1 expansion request at different reasoning levels.

Replays one saved plan backbone (from a local plan job's checkpoint) through the
production week prompt and validators, once per arm and repeat. Only the first
attempt is measured: the production quality-tier retry is the same for every arm.
Uses the budget guard from pilot_generation.py; never writes learner data.

Run from the backend directory with PYTHONPATH=. and an explicit --max-usd.
"""
import argparse
import asyncio
import json
import statistics
import time
from pathlib import Path


async def run(args):
    import sqlalchemy as sa
    from sqlalchemy.ext.asyncio import create_async_engine

    from app.core.config import settings
    from app.services.llm import recovery
    from app.services.llm.client import get_llm_client
    from app.services.llm.pricing import estimate_cost_usd, price_card_for_model
    from app.services.planning import generator as g
    from scripts.pilot_generation import Budget, guard_client

    if args.claude_model and args.openai_model:
        raise ValueError("Choose one of --claude-model and --openai-model")
    if not (args.claude_model or args.openai_model) and (settings.llm_provider != "routed" or not settings.llm_configured):
        raise RuntimeError("Pilot requires LLM_PROVIDER=routed with a configured provider key")
    settings.llm_usage_telemetry_enabled = False
    settings.llm_admission_limits = {}
    recovery.operational_recovery_client = lambda *a, **kw: None

    job = json.loads(args.backbone_job.read_text())
    backbone = job["checkpoint"]["stages"]["backbone"]["record"]["payload"]
    week = g.PlanBackboneWeek.model_validate(backbone["weeks"][0])
    weekly_minutes = int(job["weekly_minutes"])

    engine = create_async_engine(settings.database_url)
    async with engine.connect() as conn:
        session = (await conn.execute(sa.text(
            "select user_goal, comparison_output, blueprint_output from intake_sessions where id = :id"),
            {"id": job["session_id"]})).one()
        idol = (await conn.execute(sa.text("select name, domain from idols where id = :id"),
                                   {"id": job["idol_id"]})).one()
    await engine.dispose()

    # The production call also prepends the learner placement; the comparison and
    # blueprint are the bulk of its session context.
    session_context = "\n\n".join(v for v in (session.comparison_output, session.blueprint_output) if v)
    user_prompt = g.render_prompt(g.load_prompt("plan_week_generate"), {
        "user_goal": g.sanitize_untrusted_input(session.user_goal or job.get("focus") or ""),
        **g.capacity_prompt_params(weekly_minutes),
        "user_context": "",
        "idol_name": idol.name,
        "idol_domain": idol.domain or "general",
        "roadmap_thesis": backbone["roadmap_thesis"],
        "backbone_week_json": week.model_dump(mode="json"),
        "session_context": g.sanitize_untrusted_input(session_context),
    }, prompt_name="plan_week_generate.txt", strict=True)
    system_prompt = g.load_prompt("planner_system")

    args.output.mkdir(parents=True, exist_ok=True, mode=0o700)
    budget = Budget(args.output / "usage.jsonl", args.max_usd)
    stage = {}

    def factory(**options):
        if args.claude_model:
            from scripts.pilot_claude_client import ClaudePilotClient, claude_token_rates
            # Same 2,048-token reasoning reserve on top of max_tokens the app clients send.
            claude = ClaudePilotClient(model=args.claude_model, max_tokens=options.get("max_tokens"),
                                       thinking_level=options.get("thinking_level"),
                                       timeout=options.get("timeout", 150), reasoning_reserve=2048,
                                       json_mode=args.claude_json_mode)
            guard_client(claude, budget=budget, stage=stage, output_dir=args.output,
                         token_rates=lambda bound: claude_token_rates(args.claude_model, bound),
                         reasoning_reserve=2048, estimate_cost=claude.estimate_cost)
            return claude
        if args.openai_model:
            from scripts.pilot_openai_client import OpenAIPilotClient, openai_token_rates
            gpt = OpenAIPilotClient(model=args.openai_model, max_tokens=options.get("max_tokens"),
                                    thinking_level=options.get("thinking_level"),
                                    timeout=options.get("timeout", 150),
                                    reasoning_reserve=args.openai_reasoning_reserve,
                                    json_mode=args.openai_json_mode)
            guard_client(gpt, budget=budget, stage=stage, output_dir=args.output,
                         token_rates=lambda bound: openai_token_rates(args.openai_model, bound),
                         reasoning_reserve=args.openai_reasoning_reserve, estimate_cost=gpt.estimate_cost)
            return gpt
        client = get_llm_client(**{**options, "allow_fallback": False, "operation": "plan_week_generation"})
        guard_client(client, budget=budget, stage=stage, output_dir=args.output,
            token_rates=lambda bound: price_card_for_model(client.model).token_rates(bound),
            reasoning_reserve=getattr(client, "reasoning_reserve", 2048),
            estimate_cost=lambda response: estimate_cost_usd(model=client.model, provider=client.provider_name,
                prompt_tokens=response.prompt_tokens, completion_tokens=response.completion_tokens,
                total_tokens=response.total_tokens))
        return client

    def issues(validated, response):
        if validated is None:
            return [str(response.error or "week schema validation failed")]
        found = g.validate_plan_contract(validated, duration_weeks=1, weekly_minutes=weekly_minutes,
                                         start_week=week.week_number, require_cycle_fields=False)
        if len(validated.weeks) == 1:
            found.extend(g.validate_week_against_backbone(validated.weeks[0], week,
                                                          weekly_minutes=weekly_minutes))
        return found

    async def attempt(arm, repeat):
        # A generous timeout measures true latency against the 90 s production cap.
        client = factory(timeout=150, max_tokens=g.PLAN_WEEK_MAX_TOKENS, tier="balanced", thinking_level=arm)
        started = time.perf_counter()
        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt, user_prompt=user_prompt,
            output_model=g.ExecutionPlanResponse, repair_on_failure=False)
        duration_ms = (time.perf_counter() - started) * 1000
        found = issues(validated, response)
        cost = None
        if hasattr(client, "estimate_cost"):
            cost = client.estimate_cost(response)
        elif response.prompt_tokens is not None and response.total_tokens is not None:
            cost = estimate_cost_usd(model=client.model, provider=getattr(client, "provider_name", None),
                prompt_tokens=response.prompt_tokens, completion_tokens=response.completion_tokens,
                total_tokens=response.total_tokens)
        row = {"arm": arm, "repeat": repeat, "model": response.model or client.model,
               "provider": getattr(client, "provider_name", None), "duration_ms": duration_ms,
               "finish_reason": response.finish_reason, "prompt_tokens": response.prompt_tokens,
               "completion_tokens": response.completion_tokens,
               "thoughts_tokens": getattr(response, "thoughts_tokens", None), "cost_usd": cost,
               "valid": not found, "issues": found[:5], "error": response.error}
        (args.output / f"week-{arm}-{repeat}.json").write_text(json.dumps(
            {**row, "week": validated.model_dump(mode="json") if validated is not None else None},
            indent=2, ensure_ascii=False, default=str))
        return row

    log_path = args.output / "week-runs.jsonl"
    rows = [json.loads(line) for line in log_path.read_text().splitlines()] if log_path.exists() else []
    done = {(row["arm"], row["repeat"]) for row in rows}
    arms = args.arms.split(",")
    for repeat in range(1, args.repeats + 1):
        todo = [arm for arm in arms if (arm, repeat) not in done]
        if not todo:
            continue
        stage.update(scenario_id="saved_backbone", stage="week_one", tier="balanced", run_id=f"r{repeat}")
        new_rows = await asyncio.gather(*(attempt(arm, repeat) for arm in todo))
        with log_path.open("a") as handle:
            for row in new_rows:
                handle.write(json.dumps(row, default=str) + "\n")
                print(json.dumps({k: row[k] for k in ("arm", "repeat", "duration_ms", "finish_reason",
                                                       "valid", "cost_usd", "error")}, default=str), flush=True)
        rows.extend(new_rows)
        if budget.spent + sum(budget.pending.values()) >= budget.cap:
            print(json.dumps({"stopped": "budget cap reached"}), flush=True)
            break

    summary = {}
    for arm in arms:
        runs = [row for row in rows if row["arm"] == arm]
        if not runs:
            continue
        valid = [row for row in runs if row["valid"]]
        durations = sorted(row["duration_ms"] for row in runs)
        summary[arm] = {"model": runs[-1].get("model"), "runs": len(runs), "valid": len(valid),
                        "valid_within_90s": sum(row["duration_ms"] <= 90_000 for row in valid),
                        "median_ms": round(statistics.median(durations)), "max_ms": round(durations[-1]),
                        "mean_completion_tokens": round(statistics.mean(
                            row["completion_tokens"] or 0 for row in runs)),
                        "cost_usd": round(sum(row["cost_usd"] or 0 for row in runs), 4)}
    (args.output / "week-summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps({"summary": summary, "estimated_charged_or_reserved_usd":
                      budget.spent + sum(budget.pending.values()), "cap_usd": budget.cap}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-usd", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--backbone-job", type=Path, required=True,
                        help="JSON with job_id, weekly_minutes, session_id, idol_id and checkpoint")
    parser.add_argument("--arms", default="low,off")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--claude-model", default="",
                        help="Run on this Claude model (claude-haiku-5-5, claude-sonnet-5-5 or claude-opus-5-5) "
                             "instead of LLM_PROVIDER; arms are effort levels (low/medium/high); key from "
                             "ANTHROPIC_API_KEY")
    parser.add_argument("--claude-json-mode", default="auto", choices=["auto", "native", "prompt"],
                        help="Claude JSON contract (see scripts/pilot_claude_client.py)")
    parser.add_argument("--openai-model", default="",
                        help="Run on this OpenAI model directly (gpt-5.6-luna, gpt-5.6-terra or gpt-5.6-sol) "
                             "instead of LLM_PROVIDER; arms are reasoning efforts (low/medium/high); key from "
                             "OPENAI_API_KEY. Excludes --claude-model")
    parser.add_argument("--openai-reasoning-reserve", type=int, default=2048,
                        help="Extra completion tokens for GPT reasoning")
    parser.add_argument("--openai-json-mode", default="auto", choices=["auto", "native", "prompt"],
                        help="OpenAI JSON contract (see scripts/pilot_openai_client.py)")
    asyncio.run(run(parser.parse_args()))
