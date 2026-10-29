# CMPYS generation — prompt quality, business value and speed: improvement plan

> **For agentic workers:** Phase 0 and Phase 1 tasks are implementation-ready. REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans; steps use `- [ ]`. Phases 2–3 are design-level: each gets its own implementation plan after the owner approves its scope.

| | |
|---|---|
| Date | 26 October 2026 |
| Baseline | `main` @ `657463d` (deployed source of the 25 Oct simulator test) |
| Status | Phase 1 slice B implemented offline on 26 Oct (uncommitted, not deployed, no paid runs) — see "Slice B implementation notes" |
| Spec | [README priorities](../../../../../README.md#priorities-and-tradeoffs) · [README business measures](../../../../../README.md#business-measures) · [APP_GUIDE known gaps](../../../../../docs/APP_GUIDE.md#known-gaps-and-verification-status) |

**Goal:** shorten *interview finished → first tutorial usable* and per-tutorial preparation time, while raising first-pass quality and the business value of what is generated — without weakening any quality gate.

**Approach:** measure the real critical path from telemetry that already exists; stop making the learner wait for work they never see; take serial waits and hidden reasoning out of the first-value path; rebuild the tutorial prompts from accumulated incident patches into a layered contract with exemplars, so fewer drafts need repair; turn the two open content defects (unsupported mentor anecdotes, transfer-answer leaks) from prompt pleas into checkable contracts; ship each phase as one batched deploy behind the existing promotion rule.

**Tech stack:** FastAPI + Celery/Redis; Z.ai GLM-5.3 / GLM-5.3-Flash over OpenAI-compatible streaming (`zai.py`); templates in `cmpys/prompts`; Pydantic contracts; Flutter client (`fe/cmpys`); existing eval tooling (`app/services/llm/evaluation.py`, `scripts/pilot_generation.py`, `scripts/evaluate_generation.py`, `tests/fixtures/generation_scenarios.json`).

**Path shorthand:** `plans.py` means `cmpys/backend/app/tasks/plans.py`; API routes are written `api/v1/…`; other backend paths are relative to `cmpys/backend/app/`, Flutter paths to `fe/cmpys/lib/`, prompts to `cmpys/prompts/`.

## Executive summary

1. **The learner is blocked in Mentor Lab while four model calls run in series, and sees none of their output.** Comparison → blueprint → plan backbone → week 1 run one after another; the screen shows a progress bar and three rotating quote cards; the streamed comparison and blueprint are stored but never rendered there, and "Enter CMPYS" unlocks only when the plan job has finished *and* both texts exist (`mentor_lab_step.dart:402-416`). The blueprint alone delays the plan job (`sessions.py:2966`) for text the learner first sees later on a Plan-tab card.
2. **The first tutorial needs six more serial calls behind a spinner.** Outline → seed → activities → preflight review → prose → content review. The mission screen shows only a percentage until tutorial 1 is approved; the outline stays hidden (`api/v1/plans.py:1660-1682`), and Today does not link to the mission at all.
3. **Every Z.ai call reasons, including the short ones.** Thinking is always enabled (`zai.py:44`); the outline runs at high effort.
4. **Tokens are spent on fields no one reads.** Tutorial `substeps` (validated and even repaired by a separate call), backbone/week friction fields, the 35–70-word week `primary_mission`, constant outline fields, and in background jobs, book `sections`/`ideas`/`promise` and feed video items.
5. **The tutorial prompts have become incident logs.** Seventy negations in one prompt, duplicated blocks, accounting and literary patches inside universal rules, no positive exemplar, and ~95 tests pinning exact sentences. This is the main cause of repairs, and repairs are serial.
6. **The two open content defects are not checkable.** Unsupported mentor anecdotes and a transfer-answer leak passed automatic review because "never invent" and "never reveal" live only in prompts.

The last per-call measurements (4–17 Oct) cover older lesson formats. On 4 Oct the server took 27 s to the results, 90 s to the roadmap and 158 s to the first approved lesson, counted from the start of results generation. Per stage, the seed's p50 was 28 s, activities 40 s and preflight 25 s. Z.ai writes about 75–120 output tokens per second, and latency tracks output length (r ≈ 0.95). The 25 Oct tutorial run recorded outcomes only, so Phase 0 measures the current pipeline before anything changes.

Recommended first slice (Phase 1, slice B): reasoning control per operation, no generation of unread or constant fields, the tutorial prompt rebuild, scorer de-anchoring and interview cleanup — one batched deploy, promoted only if the existing 24-scenario rule passes. The largest single speed win, unblocking Mentor Lab (Phase 2.1), needs one owner decision (D1).

## Slice B implementation notes (26 Oct)

Done offline: Tasks 1.1–1.5. The backend suite passes (4,741 passed, 6 skipped); the clean `657463d` baseline was 4,696 passed, 6 skipped.

Departures from the task specs:
- **1.1:** every override defaults to empty, so runtime behavior is unchanged until `ZAI_REASONING_OVERRIDES` names an operation that passed the eval. The keys are `interview_stream`, `comparison_stream`, `blueprint_stream`, `comparison_scores`, `plan_item_tutorial_outline`, `lesson_package_seed`, `lesson_practice_review` and `lesson_practice_generate`.
- **1.2:** the constant outline fields and the friction, thesis and anti-goal fields are gone. Tutorial `substeps` were **not** removed: they reach 63 code sites, including capacity checks and hashed contract files, for about 150 tokens per tutorial. Removing them is still pending owner decision D7.
- **1.3:**
  - Both domain notes are included in both prompts, as labeled sections, instead of being picked by code: the seed has no reliable domain signal, and a wrong pick would silently drop rules the validators depend on.
  - The numeric answer rules only reach activities.
  - Rendered input size stayed roughly flat (seed 9.4K → 10.2K characters, activity 15.0K → 15.7K, about 2.9K of it exemplars); activity negations went from 70 to 52. The expected speed gain comes from the output targets (aim near 1,500 characters instead of 3,000) and from fewer corrections, and is unmeasured until Task 0.3.
  - No test pinned the tutorial prompt text, because the phrase-pinning tests cover the legacy `lesson_*` prompts, which are left unchanged.
- **Identity:**
  - The deployed identity `03b5bc34…` is pinned in `_COMPATIBLE_TUTORIAL_READ_IDENTITIES`, so tutorials published before this change stay readable.
  - Old capacity pins are deliberately retired, because the prompt contract changed; pending and in-flight tutorial drafts will regenerate after deploy.
  - `prompt_hash` now hashes the include-resolved text.
- **Before any deploy:** run Task 0.3 (baseline and candidate eval) under an owner-approved budget, and deploy in a window with no running detail jobs.
- **Also done offline (later on 26 Oct):**
  - **0.1:** `scripts/generation_latency_report.py`, validated against a migrated empty database; running it against production still needs D3.
  - **0.2:** leak, mentor-claim and stage-latency screens in `evaluation.py`; `promotion_decision` now refuses runs with leaks or unsupported claims.
  - **1.6:** the feedback contract in `lesson_practice_review.txt`, not covered by the tutorial eval.
  - **Eval tooling:** `pilot_generation.py --tutorial --scenarios all --repeats N --arm …` runs the real `tutorial_v1` pipeline.
  - The suite stands at 4,756 passed, 6 skipped.
- **Owner decisions (26 Oct):** D1 yes, D6 yes, D4 yes after a host check; D7 needed explanation.
  - **D1 done:** the plan job is dispatched right after the comparison is saved (`sessions.py`, Part 1.5), so it runs alongside the blueprint, which is optional plan context. The Mentor Lab gate is unchanged, because the blueprint finishes well before the plan.
  - **D6 done:** Mentor Lab shows the comparison as it streams, in a card mirroring the Compare tab's verdict card, with "Read the full perspective". The quote cards are kept. `flutter analyze` is clean and 504 Flutter tests pass; the card hasn't been checked in the simulator yet.
- **D4 host check (read-only):**
  - Production is a `t4g.small` (2 vCPU, 1.8 GB) with about 300 MB available and 631 MB of its 1 GB swap in use.
  - The workers run the `solo` pool, which ignores `CELERY_DEFAULT_CONCURRENCY=2`, so concurrency is effectively 1.
  - Another worker process risks out-of-memory failures, so it needs a larger instance first (owner decision).
  - Production has `CURRICULUM_ENABLED`, `LESSON_CATALOG_FIRST_ENABLED` and `ADAPTIVE_ROUTING_ENABLED` all true, with `LLM_PROVIDER=zai`. This answers S9.
- **Eval results (26 Oct, Z.ai GLM-5.3, one tutorial per run):**
  - **Current prompts:** 5 of 36 runs accepted (14%); 3 of 24 on the first run per scenario.
  - **Slice B:** 10 of 35 accepted (29%); 9 of 24 on the first run.
  - **Accepted tutorial time:** p50 63 s → 49 s, p95 206 s → 138 s.
  - **Cost per accepted tutorial:** USD 0.74 → USD 0.37.
  - **Main slice-B failures:** the exercise check giving up (11), word-count limits (6), real content defects (5), number evidence in the final review (3).
  - **Substeps removal + resolver ("fixes"):** 2 of 12 accepted versus slice B's 3 of 12 on the same scenarios, which is within noise. Evidence calls went 28 → 27, so the resolver alone doesn't lift acceptance, because almost every exercise also has calculated numbers.
  - **Next lever:** the arithmetic checker (design step 3) and word-count tolerance.
  - **Total paid spend:** about USD 9 of the 20 approved.
  - **Blind quality scoring of the 15 accepted tutorials (separate agent, labels hidden):**
    - **Current prompts:** mean 0.65, with critical defects in 5 of 5.
    - **Slice B:** mean 0.66, with critical defects in 4 of 10. Every writing, philosophy and project-design tutorial was clean; the defects were in accounting (3) and software (1).
    - **Defect types:** transfer answers revealed in lessons, instructions or hints; transfer cases that are near copies of the worked case; wrong private answer keys (6032, 4729). The automatic gates passed all of them.
    - **Implication:** the semantic leak and isomorphism checks (Q5) need to run inside the pipeline, not only in the eval. Raw field labels in Guided Practice are a reader-quality issue. The truncated titles came from the pilot harness, not the product.
- **Task 0.3 ran** under the owner's USD 20 approval (USD 10 cap per side, on a dedicated test key). Task 1.7 waits until it ends, because it edits hashed reviewer files the candidate side is using.

## Global constraints

- Priority order (README): instructional quality and valid assessment → user-visible speed → cost. A change that lowers first-pass acceptance or any cohort's quality, or adds a critical defect, is rejected — the existing `promotion_decision` rule (`evaluation.py:77`).
- Workload honesty (BN-05) and the capacity tolerance (larger of 5 min or 10 %) are fixed. Never relabel estimates to fit.
- No paid provider call without a fresh, explicit owner budget. The USD 12 ceiling in `USER.md` belonged to the 24 Oct simulator QA task and does not carry over.
- A push to `main` is a production deploy. Editing any prompt listed in `validation_identity()` or any Python file in its `generation_contract_hash` (`lesson_package.py:536-551`) invalidates in-flight tutorial drafts; editing curriculum prompts invalidates curriculum jobs. One batched deploy per phase, in a window with no jobs in flight.
- Provider policy: direct Z.ai GLM-5.3 / Flash is the live text route; OpenLux is preferred for anything else; direct Gemini only where required. Model changes are pre-authorized when they serve quality first, visible speed second.
- Learner-visible text follows the requested locale (the eval set covers `en` and `hy`).
- Waiting screens keep the owner's chosen polished style (quote cards with portraits); any change to what they show is an owner decision.

## Review focus

The five failure modes most likely to bite learners after these changes, most likely first. Each has a test or gate in its owning task.

1. **Stale drafts surviving a contract change.** If `validation_identity` hashes only the parent prompt files, an edit to an included contract, domain pack or exemplar would let old private drafts be reused against new rules. Expected: any change to any included file invalidates the drafts. Test: `test_validation_identity_changes_when_included_file_changes` (Task 1.3).
2. **Numeric tutorials with reasoning off.** Sign, threshold or derivation errors. Expected: no rise in arithmetic or proof rejections. Gate: per-operation eval adoption (Task 1.1, Step 6). The seed keeps `low` unless it passes on accounting and geometry.
3. **Armenian (`hy`) output after the rebuild.** Shorter prompts and exemplars written in English can pull learner-visible text toward English. Expected: no `locale:hy` cohort regression, which `promotion_decision` already enforces per cohort (Task 1.3, Step 5).
4. **Learners with no evidence.** De-anchoring the scorer could turn "none yet" into fabricated comparability. Expected: no `comparable` verdict without evidence on both sides. Gate: adjudication of the `evidence_status: missing` scenarios (Task 1.4, Step 5).
5. **Qualitative transfer leaks.** A model answer copied into public instructions or prose. Expected: zero leak spans. Gate: `qualitative_leak_spans` in the promotion rule (Task 0.2).

---

## 1. How generation works today

### 1.1 What the learner experiences, end to end

| Step | Screen and wait | Model work behind it | Shown while waiting |
|---|---|---|---|
| Discovery | One blocking call, 60 s client timeout (`discovery_step.dart:120-172`) | Published catalog first, LLM fallback (`idol_suggest.txt`) | "Finding your matches…" with canned lines |
| Intake | ~9 turns; kickoff, weekly-hours and closing turns are canned. Each LLM turn is buffered in full (18 s cap, canned fallback; `sessions.py:94`, `1916-1960`) and appears at once | `interview_system.xml` + `interview_question.txt`, GLM-5.3-Flash, reasoning on (`gemini.py:253`) | Typing dots |
| **Mentor Lab** | **Blocked** until the plan job completes and both texts exist (`mentor_lab_step.dart:402-416`); plan pipeline budget 480 s (`plans.py:80`) | **Serial:** comparison → blueprint → *job dispatch* (`sessions.py:2966`) → backbone → week-1 expansion → finalize. Scores run in parallel (`sessions.py:2859-2867`) | Progress bar, status line, three static quote cards rotating every 18 s. Comparison and blueprint text **not shown** |
| Today | Lands here (`onboarding_flow.dart:136`) | — | Week-1 daily habits only; no link to the mission or tutorial |
| Mission detail (≥ 3 taps) | Polls every 2–15 s; "taking long" card after 2 min (`plan_item_detail_screen.dart:249-272`, `987-1021`) | **Serial for tutorial 1:** outline → seed → 2 activities (parallel) → preflight review → prose → content review → publish, plus conditional repairs | Spinner and percentage; the outline stays hidden until a lesson is approved (`api/v1/plans.py:1660-1682`). After that, tutorials unlock one by one — "Start now while the next tutorials are prepared" |
| Practice submit | Whole exercise disabled, "Checking…", 70 s client timeout | Deterministic checks, then LLM grading of text answers only (`api/v1/practice.py:429-456`) | Button label |

### 1.2 Model calls on the first-value path

| # | Stage | Prompt | Model / reasoning | Limits |
|---|---|---|---|---|
| 1 | Comparison | `comparison_generate.txt` + `persona_system.txt` | GLM-5.3 / low | streamed |
| — | Scores (parallel) | `comparison_scores.txt` | Flash / low | 3,500 tok, 40 s |
| 2 | Blueprint | `blueprint_generate.txt` | GLM-5.3 / low | 350–550 words |
| 3 | Backbone | `planner_system.txt` + `plan_backbone_generate.txt` | GLM-5.3 / low | 9,000 tok, 90 s |
| 4 | Week-1 expansion | `plan_week_generate.txt` | GLM-5.3 / low | 8,000 tok, 90 s |
| 5 | Mission outline (~20 tutorials) | `plan_item_tutorial_outline.txt` | GLM-5.3 / **high** (`medium` maps to high) | ≤ 24,000 tok, 45 s |
| 6 | Package seed | `tutorial_package_seed.txt` | GLM-5.3 / low | 2,200 + 2,048 reserve |
| 7 | Activities ×2 | `tutorial_activity_generate.txt` | GLM-5.3 / low | 4,000 tok each |
| 8 | Preflight review | inline `_SEMANTIC_PROMPT` (`package_preflight.py:86`) | GLM-5.3 / low | — |
| 9 | Prose | `_TUTORIAL_CONTRACT` (`lesson_writer.py:109`) + context tail of `plan_item_detail_lesson.txt` | low | — |
| 10 | Content review | inline (`lesson_review.py:2287`) | GLM-5.3 / low | 4,000 / 8,000 tok, 120 s |
| + | Repairs | seed/activity correction, ownership mapping, preflight repair + recheck, binding repair, prose compression, review repair + re-review | | each 1–2 serial calls |

Structural facts that shape every latency number:

- **Reasoning is always on.** `ZaiLLMClient` sends `thinking: {"type": "enabled"}` on every request and maps effort to only low/high/max (`zai.py:18-21`, `43-44`): `minimal` and `none` become `low`, `medium` becomes `high`.
- **Narrow concurrency.** One job runs at most two provider calls at once (`plans.py:117-121`, `llm_admission_per_user=2`); the package stage has its own semaphore of two (`package_builder.py:463`). Tutorial 1 runs alone until published (`plans.py:1982-2016`); tutorials 2–3 then run together; later batches continue on `low_priority` (`plans.py:3766`). All week-1 missions are prefetched at plan finalize (`plans.py:2442`).
- **Single-slot queues.** Plan jobs use `high_priority`; the first mission's tutorial job uses `default` (`plans.py:4429-4433`). Every interactive worker defaults to the solo pool with concurrency 1 (`docker-entrypoint.sh:6-8`, `docker-compose.prod.yml:208-213`, `.env.example:4-9`). Unless production overrides these, two learners finishing intake at the same time are served one after the other.
- **Repairs are serial**, so first-pass acceptance moves p95 more than any single prompt's raw speed.

### 1.3 What is already measurable

`llm_usage_events` rows hold operation, model, prompt/completion tokens, estimated cost, `duration_ms`, success, `result_status`, `quality_score` and metadata including `first_event_ms`, `first_content_ms`, `admission_wait_ms`, `cached_prompt_tokens` and stage/correction flags (`models/llm_usage_event.py:21-35`, `telemetry.py:87`); reasoning tokens come from usage details (`openlux.py:213-216`). `first_content_ms − first_event_ms` isolates hidden-reasoning time per call. Plans record `generation_metrics.plan_ready_ms` (`plans.py:2443-2451`). The baseline needs a report, not new instrumentation (Task 0.1).

### 1.4 Measured evidence

Sources: release and pilot artifacts in `docs/releases/2026-10-14…17-*`, `cmpys/business/generation-pilot-2026-10-14/usage.jsonl`, and historical reports read from git `HEAD` (deleted in the working tree by the 25 Oct consolidation). **There is no per-call evidence after 17 Oct, and none for `tutorial_v1`**; every stage number below measures the older long-lesson or staged-package pipelines and probably overstates short-tutorial times. † = before 1 Oct.

| Stage | Latency | Output tokens | Notes |
|---|---|---|---|
| Interview turn (Z.ai) | adaptive ≈ 3 s; fixed questions 0.04 s | — | 4 Oct |
| Comparison + blueprint | 26.6 s (older samples 39–43 s) | — | 4 Oct, fresh account |
| Backbone + week 1 | 64 s | — | 4 Oct; earlier a 90 s roadmap timeout failed the plan at 172 s |
| Outline† | 27–37 s; one failure at 149 s | — | 15 Sep |
| Package seed | n=30: p50 28 s, p95 78 s | p50 1.9K (max 3.4K) | truncated ×3, schema errors ×8, duplicate keys |
| Activities | n=38: p50 40 s, p95 87 s, max 90 s (cap) | p50 4.2K (max 6.0K) | truncated ×3, schema errors ≥ 6 |
| Package preflight | n=30: p50 25 s, p95 53 s | 2.3K + 1.4K reasoning | 14.7K input |
| Evidence patch / private repair | p50 17 s / 10 s | 0.8K / 1.5K | |
| Final review | 20–111 s (n=3); 120 s timeouts | — | 40.7K input when packaged |
| Practice review | timeout raised 15 → 45 s after a live failure | — | 22 Oct |

- **End to end (4 Oct, server side, after queue isolation):** results 26.6 s → roadmap 89.8 s → first approved lesson 157.9 s. Manual UI timing before queue isolation: roadmap ≈ 311 s and first lesson ≈ 593 s after the last intake answer (upper bounds).
- **Synthetic batch v11–v22** (16–17 Oct, 33 cases, accounting/geometry/writing): p50 157 s (p90 227, max 297), 5 calls per case (max 13), USD 0.134 per case (max 0.405). Automated checks accepted 1 of 33; independent review accepted 0.
- **What drives latency:** Z.ai produced ~75–120 output tokens/s; latency tracked output tokens at r ≈ 0.95 on GLM† (0.84 on Gemini†). Review calls carry 11–41K input tokens yet stay comparatively fast — generators are output-bound.
- **Failure mix:** 9 of 129 responses (7 %) ended `finish=length`; strict-schema and JSON-shape failures made the seed unavailable in 3 cases and an activity in 5; the numeric proof/grounding gate was the largest rejection class (Q6).

### 1.5 Settled decisions this plan builds on (not re-proposed)

- Direct Z.ai GLM-5.3 / Flash is the provider; OpenLux was dropped for timeouts. One Gemini quality recovery only for a genuine Z.ai transport failure — never for content or schema failures, and no third writing attempt.
- Plan, week and correction calls run at *low* reasoning, because `medium` ran as high and blew the 90 s / 180 s budgets (4 Oct reliability work). The outline is the one call still sent as `medium` (S3).
- The single-call lesson package was split into a seed plus one call per activity with scoped repairs; repairs are bounded.
- `tutorial_v1` (450–800 words, ~5–8 minutes) replaced 1,900–4,200-word lessons, per the owner's preference.
- Planning has its own priority worker; generation is current-week-only and lesson-1-first.
- Unknown usage is reserved in full and the spend ledger is never reset.

---

## 2. Findings

### 2.1 Speed

**S1 — Mentor Lab blocks on four serial calls whose output it does not show.** Comparison and blueprint stream into the draft but only feed readiness checks and stage labels (`mentor_lab_step.dart:237-254`); the blueprint gates the plan job (`sessions.py:2909-2966`); the plan gates the screen. Nothing the learner sees requires the blueprint before the plan.

**S2 — Tutorial 1 needs six serial calls after the plan.** Inside it, prose waits for activities and preflight, and the final review waits for prose. Each stage removed or overlapped saves a full call (time to first token + reasoning + generation).

**S3 — Hidden reasoning on bounded, machine-validated calls.** Interview turns (≤ 55 words), the outline (titles and one-line descriptions), seed planning, dimension classification and text grading all pay reasoning time before their first visible token, though each has deterministic validators downstream. Reasoning is billed as completion tokens (`pricing.py:46`), and on GLM it shares the `max_tokens` ceiling with visible output (`config.py:69`, `package_builder.py:33-36`), which contributes to the 7 % `finish=length` rate (§1.4). The outline is the last call still sent as `medium`, which runs as high — the same mapping the 4 Oct reliability work removed from the plan calls.

**S4 — Output spent on fields no one reads, constants and clerical evidence.** Output length *is* the latency here: at ~75–120 tokens/s, every 1,000 output tokens costs roughly 8–13 s on a serial stage (§1.4). Activities emitted a p50 of 4.2K tokens in the last measured format; if `tutorial_v1` activities are still near that, halving it saves about 20 s on tutorial 1 alone.
- *Never rendered:* tutorial `substeps` — absent from every Flutter screen, yet required (1–3 actions of 20–60 words, `schemas.py:565-568`) and repaired by a separate call (`plans.py:1710-1720`); backbone and week `predicted_friction` / `friction_solution`, and week `primary_mission` (35–70 words), stored in item meta and plan JSON but never sent to the client (`plans.py:4639-4640`, `generator.py:1031-1046`); outline `definition_of_done` / `mental_model`, kept under `details_json.meta`.
- *Constants:* the outline makes the model emit `lesson_format` on the root and every step, and `content_markdown: null`, `ideas: []`, `canonical_hint`, `source_strategy` on every material (shape at `plan_item_tutorial_outline.txt:58-85`), although schema defaults cover the material fields (`schemas.py:352-362`). Week expansion repeats the roadmap thesis and anti-goals (`plan_week_generate.txt:53`).
- *Clerical evidence:* the content reviewer must write an entry for every numeric span — calculations, `literal_facts`, `math_roles` — with up to 8,000 output tokens (`lesson_review.py:2262`, `2308-2346`). Code can do this for exact matches against declared data.
- *Oversized budgets:* activities allow 4,000 characters of instructions and 4,000 of explanations (`tutorial_activity_generate.txt:173-174`) for a one-to-two-minute phase.
- *Background:* book `summary_json.promise`, `sections`, `ideas`, `grounding_notes` are never rendered and are even regenerated by a metadata repair; LLM-generated feed video items are dropped by the client (`feed.py:357-371`).

**S5 — Repairs are the hidden tail.** Each correction is a serial round trip, so the prompt-clarity work (Q1–Q3) is also a speed lever. In the last synthetic batch the median case needed 5 calls (max 13) and 157 s (p90 227 s); automated checks accepted 1 of 33 and independent review none. Seed and activity schema failures, duplicate keys and truncation each forced extra calls (§1.4).

**S6 — Queue topology serializes learners.** See §1.2. This is the largest tail-latency risk as soon as more than one learner onboards at once.

**S7 — Interview turns are buffered and reasoned.** Buffering is deliberate (the server validates the one-question contract before anything reaches the screen) and can stay; reasoning is hard to justify for a 25–40-word question.

**S8 — Template layout defeats prefix caching.** Several templates put learner data first and static rules after (e.g. learner data at `plan_item_tutorial_outline.txt:5-15`, CURRICULUM RULES only at `:26`). Providers report cached tokens (`openlux.py:335`), but only a byte-identical prefix is reusable. Static-first ordering is free while templates are being rewritten; the gain is mostly cost, partly time to first token.

**S9 — Reuse is off by default.** `LESSON_CATALOG_FIRST_ENABLED` and `CURRICULUM_ENABLED` default to false (`config.py:162`, `190`), although the owner wants verified blocks reused and only the personal adaptation generated. Production enablement is a deployment fact to confirm.

### 2.2 Quality

**Q1 — The tutorial prompts read as incident logs, not specifications.** `tutorial_activity_generate.txt` has 198 lines and 70 negations; `tutorial_package_seed.txt` 124 lines and 38; 24 identical lines are duplicated between them (SHORT RESPONSE CONTRACT, NARROW BROAD OUTLINES, the execution-contract block). Domain incident patches sit in universal prompts:
- "Distinguish current transactions from prior-period collections/payments" — `tutorial_package_seed.txt:70`, `tutorial_activity_generate.txt:46`, and the `lesson_*` twins;
- "Collection of prior-period debt cannot reduce this period's uncollected sales" — in the generic preflight reviewer (`package_preflight.py:99`);
- literary-tagging and "overdue rent" rules — `tutorial_package_seed.txt:111-116`, `tutorial_activity_generate.txt:185-190`.

Serialization rules that validators already enforce ("close the first object before starting the next", "never emit id_valid", no "(1)/(2)" labels in quoted answers) compete with pedagogy for attention. About 95 assertions in `test_prompt_quality_alignment.py`, `test_package_initial_prompt.py` and `test_activity_evidence_prompt_contract.py` pin exact sentences, so each incident has added a sentence plus a test pinning it. The results: weaker adherence on the rules that matter, accounting rules distracting writing lessons, and a prompt-hash change (and invalidated drafts) for every patch.

**Q2 — No positive exemplar anywhere in the tutorial chain.** The prompts show JSON shapes filled with "..." plus dozens of prohibitions; they never show one complete, good activity or tutorial. A compact gold exemplar per domain family is the strongest quality lever for small structured outputs, and it lets most prohibitions go.

**Q3 — Internal contradictions.**
- Outline: descriptions are "1-2 concise specific sentences" (`:30`) but the shape says "Two or three concrete sentences" (`:65`); the prompt says "aim for about twenty cumulative tutorials" for two hours (`:95`) while the retry says "Choose the smallest sufficient sequence" (`plans.py:1073`).
- Persona: `interview_question.txt:1` opens "You are {idol_name}" and `:37` says "Stay 100% in character"; `comparison_generate.txt:1,20` does the same — against the AI-portrayal boundary in `interview_system.xml` and `persona_system.txt`.
- The interview system prompt keeps a "Previous Conversation: {chat_history_json}" slot that is always rendered as `[]` (`sessions.py:1898`), directly before "Use this context to avoid repeating questions".
- `comparison_scores.txt` carries the shared "PLACEMENT AND INTERVIEW EVIDENCE" block, including "Explain a practical next learning step" — its JSON has no field for that.

**Q4 — Anchoring in the structured comparison.** The output example in `comparison_scores.txt:64-142` fills all five dimensions with concrete values — knowledge and habits `insufficient_user_evidence`, capital `different_basis`, network and clarity `comparable` at level 0/0. Models copy examples. The 25 Oct test showed one of five like-for-like dimensions; that may be honest, but with this example it cannot be told apart from anchoring. Fix the example, then measure both directions: no fabricated comparability, and fewer needless "insufficient" verdicts when evidence exists (BN-10).

**Q5 — The two open defects are only prompt pleas.** Unsupported Dickens anecdotes passed automatic review, and one transfer case leaked its answer (APP_GUIDE known gaps). "Never invent mentor anecdotes" appears in nearly every prompt, but nothing checks it. Numeric transfer independence is validated (`lesson_package.py:233`); qualitative independence is not.

**Q6 — Reviewers spend their attention on clerical work.** About 70 inline lines of the content-review prompt (`lesson_review.py:2287-2360`) are evidence-mapping procedure. The semantic judgments that failed in QA — is this mentor claim supported, does this explanation reveal the transfer answer — are one clause among dozens. The release audits show the cost: across v13–v22 the numeric proof/grounding gate was the largest rejection class — unverified values in a span ×75, formulas not derived from bound inputs ×20, invalid math roles ×19, incomplete coverage or fabricated span ids ×16, results absent from their span ×12 — and proof was unavailable in 7 of 30 cases. If the baseline shows this gate still dominates for `tutorial_v1`, Phase 2.5 moves to the front of Phase 2.

**Q7 — Prompts live in two places.** Preflight-review, content-review and tutorial-writer contracts are Python strings (`package_preflight.py:86-131`, `lesson_review.py:2287+`, `lesson_writer.py:109-165`). That is why `validation_identity` hashes 14 whole Python files (`lesson_package.py:545-551`): a refactor or a comment in any of them invalidates every in-flight private draft. Moving these prompts into `cmpys/prompts` and hashing prompts, schemas and explicit contract versions stops unrelated code changes from discarding paid work.

**Q8 — Grading feedback has guardrails but no quality bar.** `lesson_practice_review.txt` blocks gaming and answer dumping, but sets no structure (what worked, what to change, next step), no length bound, and no instruction to quote the learner's own words. The submit wait disables the whole exercise, so a bounded, structured contract improves both learning value and speed.

### 2.3 Business value

**B1 — The most personal payoff is generated first and shown last.** The comparison — the moment the product proves it listened — is produced at the start of Mentor Lab, hidden during the wait, and first visible on the Compare tab. The blueprint is first visible on a Plan-tab card. Showing the comparison while the plan builds would turn dead waiting into the activation moment (design decision D6).

**B2 — The first tutorial is hard to reach.** Today shows only daily habits; the first tutorial is at least three taps away and may still be generating behind a bare percentage. A "Your first tutorial" card on Today and a visible syllabus (outline titles and minutes) while tutorial 1 is prepared make progress tangible (README activation: time to the first usable tutorial).

**B3 — The comparison's "check this first" never reaches tutorial 1.** `comparison_generate.txt` rule 8 ends with an unresolved skill to check in the first lesson, but nothing extracts it or passes it to the outline. Closing the loop ("I said we'd test X — tutorial 1 tests X") is the cheapest proof of personalization in the product, and it turns an honest "unknown" into a hook rather than a flat score.

**B4 — The mentor is the differentiator, but tutorials cannot use them safely.** Without checkable evidence binding, the safe choice keeps mentors out of tutorials (lessons feel generic); the unsafe choice produced the Dickens anecdotes. Evidence tokens (Phase 3) allow one verified "mentor lens" per tutorial.

**B5 — Twenty tutorials need an arc.** The outline asks for about 20 six-minute tutorials per two-hour mission, but its only sequence design is "explanation, application, transfer and revision". An explicit arc — a quick-win tutorial 1, concept → worked example → guided → transfer cycles, a retrieval/interleaving checkpoint every few tutorials, a capstone that assembles the mission deliverable — applies the evidence-based techniques the owner asked for and makes first-week completion (README "useful learning") more likely.

**B6 — Feedback is the retention moment.** Specific, quoting, next-step feedback (Q8) makes practice feel like a tutor rather than a form.

**B7 — Cost follows speed.** Reasoning tokens, unread fields and repair calls are all billed, so every speed lever above also lowers cost per accepted tutorial (README "economics").

### 2.4 Measurement and change control

- **M1** — The baseline exists in telemetry, but no report reads it end to end (Task 0.1).
- **M2** — The 24-scenario set (6 domains × novice/experienced × evidence present/missing; `en` and `hy`; development/holdout split) and the promotion rule are the right gate. They lack checks for mentor-claim support and qualitative answer leaks, and a per-stage latency breakdown (Task 0.2).
- **M3** — Prompt edits carry no version note or changelog, and the history shows "patch the prompt after each incident". The house style (§6) and a changelog stop the drift.

---

## 3. Targets

Numeric targets follow the Phase 0 baseline (README: "Numeric targets should follow a measured baseline"). Tracked measures:

| Measure | Definition (source) | Direction |
|---|---|---|
| Mentor Lab wait | interview complete → "Enter CMPYS" enabled (plan job completion) | p50, p95 ↓ |
| Time to first usable tutorial | interview complete → `step_1` published (session + detail-job timestamps) | p50, p95 ↓ |
| Interview turn | `interview_stream` `duration_ms` | p95 ↓ |
| Hidden-reasoning share | (`first_content_ms` − `first_event_ms`) / `duration_ms`, per operation | ↓ on bounded calls |
| First-pass acceptance | per stage, no correction | ↑ |
| Repairs per accepted tutorial | correction and repair calls | ↓ |
| Unsupported mentor claims, answer leaks | eval checks + adjudication | 0 |
| Like-for-like honesty | comparable dimensions vs adjudicated truth | none fabricated; fewer needless "insufficient" |
| Cost per accepted tutorial | `estimated_cost_usd`, failed calls included | ↓ |

---

## 4. Roadmap

### Phase 0 — Baseline and eval readiness (no deploy)

- **0.1** Read-only latency/quality report over production telemetry (owner runs it or grants read access).
- **0.2** Eval checks for mentor-claim support and qualitative answer leaks, plus a per-stage latency/reasoning breakdown.
- **0.3** Baseline run of the current prompts on the development split (owner budget).

### Phase 1 — Core essentials (one batched deploy)

| Slice | Contents | Risk | Why |
|---|---|---|---|
| A — speed only | 1.1 reasoning control, 1.2 no constant or unread fields, 1.5 interview cleanup | low | no pedagogy change |
| **B — core essentials (recommended)** | A + 1.3 tutorial prompt rebuild + 1.4 scorer de-anchoring | medium | fixes the cause of repairs, not only their cost |
| C — full Phase 1 | B + 1.6 feedback contract + 1.7 reviewer focus (prompt part) | medium | adds learning value at the submit moment |

### Phase 2 — Shorten the critical path (design; own plan)

- **2.1 Unblock Mentor Lab** (owner decision D1). Dispatch the plan job as soon as the comparison is saved; generate the blueprint in parallel (or from the backbone, so the two never disagree); unlock "Enter CMPYS" on comparison + plan, and let the blueprint card fill in when ready. Removes the blueprint from the blocking wait (on 4 Oct, comparison plus blueprint took 26.6 s of the 89.8 s before the roadmap). Then test, in the eval, running the backbone in parallel with the comparison from the structured baseline, gaps and readiness, which would cut the blocking wait to roughly max(comparison, backbone + week 1).
- **2.2 Show progress the learner can use** (D6). Render the comparison as it streams in Mentor Lab (the SSE already carries it; the retired `analysis_step.dart` did this). Expose the mission outline as a syllabus before tutorial 1 is approved. Add a "Your first tutorial" card on Today.
- **2.2a Syllabus first — done 26 Oct (uncommitted).**
  - `api/v1/plans.py` `_syllabus_details` serves outline-only steps (lesson text stripped) while the owning job is still `generating` with no ready steps. Status stays `generating`, so nothing is readable or completable early.
  - Flutter `plan_item_detail_screen.dart` shows the step list while loading, plus each unready step's description.
  - Tests: `test_syllabus_before_first_tutorial.py` and the syllabus widget test in `tutorial_learning_test.dart`. Backend 4,772 passed; Flutter all green.
  - **Live check (26 Oct; local stack, Z.ai test key, iPhone 16 Plus simulator; $0.46 recorded).** Feynman mission: opened → outline after 21 s → 20-tutorial syllabus on screen within one poll → tutorial 1 readable at 67 s.
  - **Fixed during the live check (each with a test; backend 4,779 passed):**
    1. *Pre-existing, also in production:* opening a mission whose tutorial was an unopened prefetch returned 500. `_promote_prefetched_detail_job`'s bulk update expires `updated_at`, then `_detail_job_is_stale` reads it synchronously (`MissingGreenlet`). The fix refreshes the job after each commit. Test: `test_detail_job_promotion_integration.py`, opt-in real Postgres.
    2. *Regression from the substeps removal:* the private checkpoint store rejects `substeps: []` ("invalid lesson actions"), so every tutorial job failed at its first section save. `save_sections_checkpoint` now drops the empty list (hashed `private_checkpoint.py` untouched). Test: validating store in `test_tutorial_without_substeps.py`.
    3. *Flutter never fetched the syllabus:* the screen polled the job endpoint and refetched details only on ready-lesson or checkpoint changes. It now refetches once at `outline_ready`. Widget test added.
  - **Open findings (not fixed):**
    - ~~At the default `medium` (sent as high), the outline timed out twice at the 45 s cap for a 3 h mission (23–36 lessons).~~ **Resolved 26 Oct — outline eval and fix, uncommitted:**
      - **Eval:** `pilot_generation.py --outline` sends the production outline request at medium and low in parallel. It ran 2 h, 2.5 h and 3 h missions × 2 repeats for $0.18.
        - Medium: 4/6 met the contract, 3/6 within 45 s; median 38.4 s, max 52.7 s. The two misses broke the contract (`id_step_16`; nine lessons with no resources).
        - Low: 6/6 within 45 s; median 24.7 s, max 30.9 s; same lesson count (23.7 vs 23.8), 31% cheaper. Arcs, visuals and transfer were comparable; descriptions shorter (≈ 22 vs 30 words, matching the prompt).
      - **Fix:** `_outline_client_options` (`tasks/plans.py`) defaults tutorial outlines to `low`, and `ZAI_REASONING_OVERRIDES` can still change it. The cap is 1.5 s per allowed lesson within [45 s, 90 s], so it changes only above 30 lessons (3 h → 54 s); a live low outline took 38 s for 30 lessons. Long-lesson outlines are unchanged. Tests: `test_tutorial_outline_request.py` and `test_outline_pilot.py`.
      - **Note:** a blank `ZAI_REASONING_OVERRIDES=` (like a blank `LLM_ADMISSION_LIMITS=`) fails settings load at startup. Unset the variable instead of blanking it.
    - ~~In both missions, lookahead tutorials 2–3 failed the numeric-fact gate (for example "steady 20 km/h" in a qualitative span), and that marked the whole job `failed`.~~ **Resolved 26 Oct, uncommitted:**
      - **Backend (`tasks/plans.py`):** in an ordinary tutorial batch, a rejected lookahead tutorial no longer fails the job. The batch returns the existing continuation, the job requeues, and the rejected tutorial becomes the next batch's priority. So each tutorial gets at most two full attempts, and failing as the priority still stops the job. Revalidation sets and long-lesson outlines are unchanged. Test: `test_tutorial_lookahead_failures.py`.
      - **App:** if a job does stop, the mission-level "Generate again" card stays hidden while the learner's current tutorial is readable (`PlanItemDetailed.currentStepReadable`). It appears when they reach the missing tutorial. Tests: `plan_item_detail_error_test.dart`.
      - The gate itself is unchanged: how often lookahead tutorials hit it is a content-quality question (Phase 2.5).
    - Local seed mentors have no timeline or achievements, so the comparison says the mentor's record is empty (local data only).
    - `.env` sets `LLM_PROVIDER=openlux`; `test_interview_streaming.py` fails, and the suite makes seven OpenLux calls, unless tests pin `LLM_PROVIDER=gemini`.
- **2.2b Page-first (owner-approved 26 Oct; next).**
  - **Lead call:** one fast call writes page 1 (`why_this_matters` + `core_framework` with its comparison visual) from the outline and context only, in parallel with seed/activities.
  - **Cheap checks:** section floors, `tutorial_visual_issues`, requested language, the unsupported-mentor-claim screen. Accepted text is saved as the step's `lead_markdown` plus `_generation.lead_ready_step_ids`.
  - **Full write:** the writer receives the lead sections verbatim as fixed and writes the other five sections bound to the approved package; the final review covers the whole tutorial. A lead is never edited in place: if review requires changing it, the tutorial restarts.
  - **API:** `StepDetail.lead_content` is set only for lead-ready, unpublished steps. It never counts toward progress or completion, and practice stays locked.
  - **Flutter:** the card shows "Start reading"; the reader shows page 1 with "the next pages are being prepared"; polling swaps in the full lesson.
- **2.3 Outline from the backbone.** Start the first mission's outline from the backbone's week-1 mission (title, outcome, success metric), in parallel with week-1 expansion; the expansion may enrich the description but not rename the mission.
- **2.4 Parallel tutorial build.** The seed declares the public field contract (activity and field ids, labels, kinds), so prose is written alongside the activities; preflight runs alongside prose; one final review covers both. A preflight repair that changes ids or labels re-binds prose, on the failure path only. Removes two serial stages from tutorial 1 — on the order of a minute at the last measured stage p50s (preflight 25 s; long-lesson section drafts 34–53 s).
- **2.5 Deterministic evidence mapping.** Code assigns exact numeric matches to declared data; the LLM reviewer judges a short, prioritized rubric (claims supported, no transfer-answer exposure, worked example correct, workload realistic, clear in locale) and returns issues only.
  - **Evidence (26 Oct eval, `tutorial_v1`):** "Lesson package preflight unavailable" was the largest failure on both sides (8 of 14 and 6 of 12 failures in the first 16 runs). One accounting tutorial took 12 provider calls, six of them `ReviewEvidencePatch`; after one repair the preflight hit its request budget, and a cancelled call held its full reservation.
  - **Offline measurement on 5 saved packages:** of 58 spans still needing model evidence after the compiler, 38 (66%) resolve deterministically (span numbers ⊆ the owning case's data ∪ computed results ∪ {0, 1, 2, 100}). Only one in ten evidence calls disappears entirely, because most activities keep one or more spans code can't match.
  - **What remains unmatched:** workload hints such as "(2–3 sentences)", and retyped explanation equations such as "9000 − 6100 = 2900".
  - **Design:**
    1. Literal-fact and result matching in code.
    2. Pattern classification of workload metadata.
    3. An arithmetic checker for `a ± b = c` chains whose operands resolve to data, results or sums of data.
    4. The model is called only for leftover spans, and not at all when none are left.
  - **Verification:** the offline replay above on saved packages, then a small paid screen.
  - **Built, unwired:** `app/services/planning/evidence_resolver.py`, with 7 tests. Offline, the real gate (`_scope_failures`) accepted 37 of 38 proposals on the saved packages; the one rejection is a sentence that derives an effect in words.
  - **Wiring, after the eval:**
    - In `package_preflight.review_package`, propose literal facts, validate them with `_scope_failures`, and drop rejected claims from the resolved set.
    - Shrink `remaining_groups` to the spans still unresolved, and skip the model call for groups with none left.
    - Merge the accepted facts into the union gate.
    - Hoist `grounded_failures`' `calculation_signal` into a module-level constant shared with the resolver.
- **2.6 Prompts out of Python.** Move the inline contracts into `cmpys/prompts`; hash prompts, schemas and explicit contract versions instead of 14 Python files.
- **2.7 First-value queue** (D4). A dedicated queue for `step_1` jobs with at least two worker processes (prefork) and provider admission limits raised to match.

### Phase 3 — Business value (design; own plan)

- **3.1 Mentor evidence tokens.** `[[evidence:<id>]]` bound to supplied mentor evidence and rendered as citations, with a deterministic check for untokened mentor claims, enabling one optional verified "mentor lens" per tutorial.
- **3.2 Tutorial arc in the outline.** Quick-win `step_1`, retrieval/interleaving checkpoints, a capstone that assembles the mission deliverable.
- **3.3 First-lesson check loop.** The scorer returns `first_lesson_check`; the outline makes `step_1` test it; practice evidence updates the matching Compare dimension.
- **3.4 Exemplar library** per domain family, rotated so an exemplar never shares the learner's topic.
- **3.5 Catalog-first evaluation** where published modules exist: time to first tutorial and quality vs bespoke.

### Deferred (named, not dropped)

- Curriculum-factory prompts (background; the research stage alone runs 30–40 minutes).
- Book guides: stop generating unread `promise` / `sections` / `ideas` / `grounding_notes` and their metadata repair, or render them (`book_module_generate.txt`, `book_writer_system.txt`).
- Feeds: stop generating video items the client drops (`discover_feed.txt`, `feed.py:357-371`).
- Mentor suggestion copy: `relevance_summary` appears twice on the discovery card (`discovery_step.dart:583,611`).
- Ingestion prompts (`achievements_extract`, `extractor_system`, `profile_extract`, `timeline_normalize`, `milestones_by_age`), guided-learning chat, `persona_pack.txt`, `image_generate.txt`.
- Streaming-parse of the outline so `step_1` starts before the outline completes.
- Prompts with no mobile caller: `learning_materials_*.txt`, `daily_feed_generate.txt` (`/sessions/{id}/feed`), `comparison_analyze.txt` (`/comparison/ai`). Retirement candidates after verification: `plan_generate.txt` (only the dummy-client fixture router names it, `client.py:381`), `plan_item_details.txt`, `thinking_plan.txt`, `thinking_task.txt`.

---

## 5. Phase 0–1 implementation tasks

### Task 0.1: Generation latency report (read-only)

**Files:**
- Create: `cmpys/backend/scripts/generation_latency_report.py`
- Test: `cmpys/backend/tests/test_generation_latency_report.py`

**Interfaces:**
- Produces: `summarize_usage(rows: list[dict]) -> dict` — per operation: `n`, `p50_ms`/`p95_ms` of `duration_ms`, `p50_reasoning_ms` of `first_content_ms − first_event_ms`, mean `completion_tokens`, mean reasoning tokens, cached-prompt share, `first_pass_rate`, `correction_calls`. Reuses `percentile` from `evaluation.py`.
- Produces: `critical_path(job_rows: list[dict], usage_rows: list[dict]) -> list[dict]` — per learner: interview complete, comparison saved, blueprint saved, plan ready, `step_1` published, `step_3` published.
- CLI: `--database-url` (read-only role), `--since`; JSON to stdout; the transaction is opened `READ ONLY`.

- [ ] **Step 1:** Write failing tests `test_summarize_usage_reasoning_share` (rows with `first_event_ms=200`, `first_content_ms=1200`, `duration_ms=3000` → `p50_reasoning_ms == 1000`), `test_summarize_usage_counts_corrections` (metadata `correction: true` counted, excluded from first-pass rate), `test_critical_path_orders_stages`.
- [ ] **Step 2:** `cd cmpys/backend && .venv/bin/python -m pytest tests/test_generation_latency_report.py -q` → FAIL (module missing).
- [ ] **Step 3:** Implement the pure functions, then the CLI select over `LLMUsageEvent`, `PlanGenerationJob`, `PlanItemDetailJob`.
- [ ] **Step 4:** Same command → PASS.
- [ ] **Step 5:** Commit `feat: add read-only generation latency report`.
- [ ] **Step 6 (owner, D3):** run against production and paste the JSON into §1.4.

### Task 0.2: Eval checks for mentor claims, qualitative leaks and stage latency

**Files:**
- Modify: `cmpys/backend/app/services/llm/evaluation.py`
- Test: `cmpys/backend/tests/test_generation_evaluation_checks.py`

**Interfaces:**
- Produces: `qualitative_leak_spans(public_text: str, private_answer: str, *, min_words: int = 8) -> list[str]` — shared word spans of at least `min_words` between a transfer field's private answer and any public text.
- Produces: `unsupported_mentor_sentences(text: str, mentor_names: list[str], evidence_texts: list[str]) -> list[str]` — sentences naming the mentor that carry a factual claim with no overlapping evidence; screening for adjudication, not a production gate.
- Changes: `summarize_runs` adds `stage_latency_ms` (p50/p95 per stage), `unsupported_mentor_claim_runs`, `answer_leak_runs`; `promotion_decision` refuses a candidate with either count above 0.

- [ ] **Step 1:** Failing tests `test_leak_detects_copied_model_answer`, `test_leak_ignores_short_common_phrases`, `test_mentor_sentence_without_evidence_flagged`, `test_mentor_sentence_with_evidence_passes`, `test_promotion_rejects_answer_leak_runs`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** The new tests and the existing evaluation tests → PASS.
- [ ] **Step 5:** Commit `feat: add leak and mentor-claim eval checks`.

### Task 0.3: Baseline eval run (owner budget)

- [ ] **Step 1 (owner, D2):** approve a USD ceiling for the baseline and candidate runs. Sizing: the promotion rule needs all 24 scenarios three times — 72 runs per arm. At the last measured p50 of USD 0.134 per case (max 0.405; older lesson format) that is about USD 10 per arm, USD 29 worst case; baseline plus one candidate ≈ USD 20 expected.
- [ ] **Step 2:** `cd cmpys/backend && PYTHONPATH=. .venv/bin/python scripts/pilot_generation.py --max-usd <approved>` over the development split with current prompts; keep the ledger.
- [ ] **Step 3:** Adjudicate quality blind with the rubric fields in `generation_scenarios.json`; save `baseline.jsonl`.

### Task 1.1: Per-operation reasoning control

**Files:**
- Modify: `cmpys/backend/app/services/llm/zai.py:12-44`
- Modify: `cmpys/backend/app/core/config.py` (add `zai_reasoning_overrides: dict[str, str] = {}`)
- Modify call sites: `gemini.py:253` (interview), `sessions.py:2863-2867` (scores), `plans.py:1061-1066` (outline), `practice/generation.py:67-71` (grading), `package_builder.py:581-582` (seed only)
- Test: `cmpys/backend/tests/test_zai.py`

**Interfaces:**
- `ZaiLLMClient(thinking_level="off")` sends `extra_body={"thinking": {"type": "disabled"}}`, omits `reasoning_effort`, and does not add `zai_reasoning_token_reserve` to `max_tokens`. `low` / `high` / `max` are unchanged.
- Produces: `operation_thinking_level(operation: str, default: str) -> str` in `app/services/llm/routing.py`, reading `settings.zai_reasoning_overrides`. Overrides default to empty, so behavior is unchanged until the eval approves an operation.

- [ ] **Step 1:** Failing tests `test_zai_off_disables_thinking_and_reserve`, `test_zai_low_request_unchanged`, `test_override_applies_only_to_named_operation`.
- [ ] **Step 2:** `.venv/bin/python -m pytest tests/test_zai.py -q` → FAIL.
- [ ] **Step 3:** Implement the `off` level and the lookup; route the five call sites through `operation_thinking_level`.
- [ ] **Step 4:** Tests PASS; full `pytest -q` green.
- [ ] **Step 5 (owner budget):** one bounded request per model with thinking disabled, to confirm GLM-5.3 and GLM-5.3-Flash accept it.
- [ ] **Step 6:** Eval matrix on the development split — interview, scores, outline (off / low / high), grading, seed (off vs low). Adopt an override per operation only where `promotion_decision` passes for that stage.
- [ ] **Step 7:** Commit `feat: per-operation reasoning control for Z.ai`.

### Task 1.2: Stop generating constant and unread fields

**Files:**
- Modify: `cmpys/prompts/plan_item_tutorial_outline.txt` (drop constant fields from the shape at `:58-85` and the "All content_markdown values are null" rule; resolve the 1–2 vs 2–3 sentence contradiction)
- Modify: `cmpys/backend/app/tasks/plans.py` around `1081-1090` (inject constants before validation)
- Modify: `cmpys/prompts/plan_week_generate.txt` (drop `roadmap_thesis`, `anti_goals`, `predicted_friction`, `friction_solution` from the shape; shorten `primary_mission` to one sentence or drop it)
- Modify: `cmpys/prompts/plan_backbone_generate.txt` (drop `predicted_friction`, `friction_solution`)
- Modify: `cmpys/backend/app/services/planning/generator.py` (week merge, `826-1048`) and `cmpys/backend/app/services/llm/schemas.py` (make the dropped fields optional; tutorial `substeps` optional with empty default, relaxing `565-568` for `tutorial_v1` only)
- Modify: `cmpys/backend/app/services/planning/lesson_writer.py` (no substeps request for tutorials) and `plans.py:1710-1720` (no substeps repair for tutorials)
- Test: `test_outline_resume_contract.py`, plus new tests below

**Interfaces:**
- Produces: `_inject_outline_constants(payload: dict, *, tutorial: bool) -> dict` — sets root and step `lesson_format`; material fields keep schema defaults.
- Week merge copies `roadmap_thesis` and `anti_goals` from the backbone when absent. Tutorials store `substeps: []`, which the client already parses (`plan_models.dart`).

- [ ] **Step 1:** Failing tests `test_outline_without_constants_matches_stored_shape` (an accepted outline fixture with constants stripped → identical `model_dump`), `test_week_without_thesis_inherits_backbone`, `test_tutorial_sections_valid_without_substeps`, `test_long_lesson_still_requires_substeps`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement; edit the three templates.
- [ ] **Step 4:** Run → PASS; `test_prompt_placeholders.py` and the full suite green.
- [ ] **Step 5:** Commit `perf: stop generating constant and unread plan fields`.

### Task 1.3: Tutorial prompt rebuild — layered contract and exemplars

**Files:**
- Create: `cmpys/prompts/tutorial_contract.txt` (shared rules, target ≤ 40 lines, each hard rule tagged with a stable id such as `[R-TRANSFER]`)
- Create: `cmpys/prompts/tutorial_domain_quantitative.txt`, `cmpys/prompts/tutorial_domain_qualitative.txt`
- Create: `cmpys/prompts/tutorial_exemplar_quantitative.txt`, `cmpys/prompts/tutorial_exemplar_qualitative.txt`
- Modify: `cmpys/prompts/tutorial_package_seed.txt`, `cmpys/prompts/tutorial_activity_generate.txt`
- Modify: `cmpys/backend/app/services/llm/prompt_loader.py` (resolve `{{include:<file>}}` at load; register placeholders)
- Modify: `cmpys/backend/app/services/planning/package_builder.py:726-743` (the seed receives both domain packs; an activity receives the quantitative pack when `seed.teaching_cases` is non-empty or its brief needs numeric fields, otherwise the qualitative pack)
- Modify: `cmpys/backend/app/services/planning/lesson_package.py:536-539` (add the new files to `validation_identity`)
- Modify tests: `test_prompt_quality_alignment.py`, `test_package_initial_prompt.py`, `test_activity_evidence_prompt_contract.py` — assert rule ids and invariants on the *rendered* prompt instead of exact sentences
- Test: `cmpys/backend/tests/test_tutorial_prompt_layers.py`

**Rewrite spec:**
- Order: role (one line) → what a great `tutorial_v1` phase is (positive spec, ≤ 12 lines) → inputs and trust boundary (3 lines) → `{{include:tutorial_contract.txt}}` → domain pack → exemplar (different topic, marked "illustrative — do not reuse its content") → output shape → five-line self-check. Static text first, data last.
- Keep the intent of every current hard rule: transfer independence; raw data plus expressions with + − × ÷, parentheses, sqrt; one or two fields per phase; honest minutes from actual work; self-contained in-app execution; requested locale; no invented quotations or mentor facts.
- Move to the quantitative pack: accounting-period rule, thresholds as raw data, rounding/tolerance, sign handling. Move to the qualitative pack: literary classification, "overdue rent", tagging narrowing, model answers inside instructions.
- Drop from prompts (validators enforce them): JSON-mechanics reminders beyond one line, `id_valid`, the parenthesized-label rule — add a normalizer if the validator does not strip those labels already.
- Budgets: rendered activity system prompt ≤ 60 % of today's characters; ≤ 20 negations; tutorial activities target ≤ 1,500 characters of instructions and ≤ 1,500 of explanations, validated in the eval rather than assumed.

- [ ] **Step 1:** Failing tests `test_includes_resolve_and_render`, `test_contract_appears_once_per_rendered_prompt`, `test_activity_selects_domain_pack`, `test_rendered_prompt_budget`, `test_validation_identity_changes_when_included_file_changes`, plus rule-id assertions replacing the phrase pins.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement includes and pack selection; write the new prompt files from the spec.
- [ ] **Step 4:** Targeted tests plus `test_staged_package_builder.py` → PASS; full suite green.
- [ ] **Step 5:** Candidate eval run; promote only if `promotion_decision` passes with zero leak or claim runs (Task 0.2).
- [ ] **Step 6:** Commit `refactor: layered tutorial prompt contract with exemplars`.

### Task 1.4: Comparison scorer de-anchoring

**Files:**
- Modify: `cmpys/prompts/comparison_scores.txt:64-142`; remove the scorer-inapplicable bullet from its PLACEMENT block
- Test: `cmpys/backend/tests/test_comparison_scoring.py`

- [ ] **Step 1:** Failing test `test_scores_prompt_example_has_no_concrete_statuses` (example values are `<one of: …>` placeholders).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Edit the prompt. **Step 4:** Run → PASS.
- [ ] **Step 5:** Eval: adjudicate statuses on all 24 scenarios before and after — fabricated comparability must stay 0; needless `insufficient_user_evidence` should fall on `evidence_status: present` scenarios.
- [ ] **Step 6:** Commit `fix: remove anchoring example from comparison scoring prompt`.

### Task 1.5: Interview prompt cleanup

**Files:**
- Modify: `cmpys/prompts/interview_system.xml` (remove the Previous Conversation slot), `cmpys/prompts/interview_question.txt:1,37` (portrayal wording: "Speak as the CMPYS portrayal of {idol_name}"); the same wording fix in `comparison_generate.txt:1,20`
- Modify: `cmpys/backend/app/api/v1/sessions.py:1860-1899` (stop passing `chat_history_json` to the system template) and the placeholder registry in `prompt_loader.py`
- Test: `test_interview_streaming.py`, `test_interview_response_ui.py`, `test_prompt_placeholders.py`

- [ ] **Step 1:** Failing test `test_interview_system_prompt_has_no_history_slot`. **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Interview tests PASS.
- [ ] **Step 5:** Commit `fix: align interview prompts with portrayal boundary`.

### Task 1.6: Feedback contract (slice C)

**Files:** Modify `cmpys/prompts/lesson_practice_review.txt`; test via render and eval.

Per text field: a verdict per criterion; feedback = what worked (quoting ≤ 12 words of the learner's text), the single most important fix, the next step; ≤ 60 words on a fail, ≤ 35 on a pass; never the full model answer on a first failed attempt (existing rule). The eval adds an adjudicated "feedback specificity" score.

### Task 1.7: Reviewer focus, prompt part (slice C)

**Files:** Modify `lesson_review.py:2287-2360` and `package_preflight.py:86-131`. Put the judgment rubric first (claims supported by supplied evidence; no transfer-answer exposure; worked example correct; workload realistic; clear in the locale), evidence procedure second; move the accounting sentence into the quantitative pack. These files are hashed (Q7), so they ship in the same batch.

---

## 6. Prompt house style (every future edit)

1. One job per prompt; name the job and the reader in two lines.
2. Positive spec first — describe a great output — then at most about ten hard constraints, each traceable to a validator or a reviewer rubric item and tagged with a rule id.
3. Rules code can check belong in code; the prompt gets one line, not a paragraph.
4. Domain lessons learned go into domain packs injected only when relevant, never into universal prompts.
5. Static text first, per-request data last, inside labeled untrusted-data blocks.
6. One compact exemplar per output family, on a different topic, marked illustrative.
7. Never ask the model for constants, copies of inputs, fields the server computes, or fields no screen renders.
8. Bound learner-visible length where the UI or the time budget needs it.
9. Tests pin rule ids and rendered invariants, not sentences.
10. Every change gets a changelog line (which incident, which metric), an eval run, and a batched deploy.

## 7. Rollout and risk

- One deploy per phase, after the eval passes, in a window with no running or queued detail/curriculum jobs (each would be invalidated).
- Rollback: keep the previous tutorial prompt files as `*_v1.txt` behind a `TUTORIAL_PROMPT_VERSION` setting, so rollback is a config change plus restart.
- Main risks: reasoning off lowers accuracy on numeric seeds (gated per operation); exemplars get copied (topic distance plus an originality check); unblocking Mentor Lab changes when the blueprint appears (owner decision); parallel prose needs re-binding after a package repair (failure path only); dropping unread fields closes options for future UI (owner decision D7); eval spend (capped ledger).

## 8. Decisions for the owner

- **D1** — Unblock Mentor Lab: plan job starts after the comparison; blueprint generated alongside and shown when ready (recommended), or keep today's order.
- **D2** — Eval budget for the Phase 0 baseline and Phase 1 candidate runs.
- **D3** — Read-only production telemetry for Task 0.1, or the owner runs the script.
- **D4** — First-value queue with at least two worker processes on the production host (CPU/memory headroom and Z.ai rate limits checked first).
- **D5** — Phase 1 slice: A, B (recommended) or C.
- **D6** — Waiting-screen content: keep the quote cards and add the streaming comparison, a syllabus, and a Today "first tutorial" card.
- **D7** — Fields generated but never shown (tutorial `substeps`, friction fields, week `primary_mission`, book `sections`/`ideas`): stop generating them (recommended) or add UI for them.

---

## Appendix A — prompt-by-prompt actions (first-value path)

| Prompt | Used by | Main issues | Action | Phase |
|---|---|---|---|---|
| `interview_system.xml` / `interview_question.txt` | `sessions.py:1860-1915` | always-empty history slot; "You are / 100 % in character" vs portrayal; reasoning on | 1.5, 1.1 | 1 |
| `comparison_generate.txt` | `sessions.py:2792` | "You are {idol_name}"; hidden during the wait; "check first" not extracted | 1.5 wording; 2.2; 3.3 | 1–3 |
| `comparison_scores.txt` | `sessions.py:2861`, `scoring.py` | anchoring example; inapplicable bullet | 1.4; 3.3 adds `first_lesson_check` | 1 / 3 |
| `blueprint_generate.txt` | `sessions.py:2892` | gates the plan job; not shown during the wait | 2.1 | 2 |
| `plan_backbone_generate.txt` | `generator.py:587` | waits for the blueprint; unread friction fields | 1.2; 2.1 | 1 / 2 |
| `plan_week_generate.txt` | `generator.py:826` | repeats thesis/anti-goals; unread friction and `primary_mission` | 1.2; 2.3 | 1 / 2 |
| `plan_item_tutorial_outline.txt` | `plans.py:1035` | constants; contradictions; high reasoning; no arc; hidden until tutorial 1 | 1.1, 1.2; 2.2; 3.2 | 1–3 |
| `tutorial_package_seed.txt` | `package_builder.py:726` | patch accretion; duplicates; no exemplar | 1.3; 2.4 declares the field contract | 1 / 2 |
| `tutorial_activity_generate.txt` | `package_builder.py:742` | 70 negations; domain patches; oversized budgets | 1.3 | 1 |
| `lesson_explanation_ownership.txt` | `package_builder.py:798` | rare path | keep; re-check after 1.3 | — |
| `_TUTORIAL_CONTRACT` (Python) | `lesson_writer.py:109` | inline; hashed with code; asks for unread substeps | 1.2; 2.6; 3.1 evidence tokens | 1–3 |
| preflight `_SEMANTIC_PROMPT` (Python) | `package_preflight.py:86` | accounting patch; inline | 1.7; 2.4; 2.6 | 1 / 2 |
| content review (Python) | `lesson_review.py:2287` | clerical evidence output; judgment buried | 1.7; 2.5 | 1 / 2 |
| `lesson_practice_review.txt` | `practice/generation.py:140` | no feedback quality bar | 1.6 | 1 |
| `planner_system.txt` | plan and outline system prompt | sound; data-first templates around it | static-first ordering with 1.3 | 1 |
