# CMPYS v3 Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Claude Design project "CMPYS v3" in the Flutter app, screen for screen. Back it with the backend contracts it needs: richer intake controls and questions, the design's comparison dimensions, half-hour weekly capacity, structured tutorial visuals, AI illustrations, and numeric/multi-select practice.

**Architecture:** The backend changes are additive and versioned: new interview control kinds, new answer keys, comparison `version: 3`, `weekly_minutes`, and new tutorial fences. Sessions, plans and lessons written before the change keep rendering. The Flutter work starts with a v3 design-system layer (tokens, fonts, primitives, tab bar). Each screen task then restyles its existing, already-wired screen to the design, keeps its providers and repositories, and adds the interactions the design shows.

**Tech Stack:** FastAPI + SQLAlchemy + Alembic (`cmpys/backend/migrations`), Celery, Pydantic v2, Gemini `imagen-4.0-generate-001`; Flutter 3 / Dart 3.10, Riverpod 2, go_router 14, google_fonts 6.3, flutter_markdown.

**Spec:** Claude Design project `495fa88f-8b41-4e06-8275-e4fb1aa1da4e`, entry `CMPYS v3.html`, sources `v3/*.jsx`. Read them with the `DesignSync` tool (`method: get_file`). Each task names the design file and component it implements. Copy design strings verbatim unless the task says otherwise. `ios-frame.jsx` and `tweaks-panel.jsx` are prototype chrome and are not built. The owner's decisions on 2026-10-26:

| # | Decision |
|---|---|
| D1 | Compare uses the design's five dimensions: `knowledge` "Knowledge base", `practice` "Practice volume", `capital` "Capital & resources", `network` "Network", `judgment` "Written judgment". |
| D2 | Tutorials get native structured visuals **and** one Imagen 4 illustration each (no text in image). |
| D3 | Intake grows to the full set (12 answer keys, about 11 visible questions after the kickoff), using all five control kinds. |
| D4 | Weekly capacity is the design's 1–15 h in 0.5 h steps. Store it as minutes (60–900, step 30) and let the planner support 1–2.5 h weeks. |

Defaults chosen while planning (the owner can veto any of them in plan review):
- `guided_practice` is no longer generated for new `tutorial_v1` lessons. The design moves guided work into Practice's "Guided" activity. Legacy lessons still render it.
- The illustration is shown as a 16:9 hero under the tutorial title, with the caption "Illustration · AI-generated".
- The centre tab is labelled "Mentor", as in the design (currently "Chat").
- Notes, saved items, reported wins, idea comments, reflections and settings toggles stay on the device, as the design copy states ("on this device").
- Comparison is not re-scored automatically from later practice. That is deferred; see the end of this plan.

## Global Constraints

- **No commits or pushes without the owner's explicit go-ahead.** A push to `main` deploys the backend to production.
- The working tree already holds uncommitted slice-B, D1, D7 and syllabus-first backend work (`docs/superpowers/plans/2026-10-26-prompt-quality-and-generation-speed.md`). Build on it and never revert it.
- Run backend tests from `cmpys/backend` with every provider key blanked and `LLM_PROVIDER=dummy`: `env -u GEMINI_API_KEY -u ZAI_API_KEY -u OPENAI_API_KEY LLM_PROVIDER=dummy pytest -q`. DB integration tests need a local pgvector/pg16 container and `RUN_POSTGRES_INTEGRATION=1`.
- New prompt placeholders must be registered in `PROMPT_PLACEHOLDERS` (`app/services/llm/prompt_loader.py`). Batch all prompt edits; a deploy resets in-flight curriculum jobs.
- No paid LLM or Imagen calls without owner approval. The live verification in Task G2 is capped at USD 1.
- Every new API field is optional for readers. Old app builds must keep working (unknown control kinds fall back to text; unknown fences render as plain text).
- Flutter: run `flutter analyze` and `flutter test` from `fe/cmpys`. Respect reduced motion (`MotionConfig`). Tap targets must be at least 44 pt. Motion should feel calm: springs only where the design uses `--spring`.
- v3 tokens (from `CMPYS v3.html :root`): paper `#F5F2EC`, paper2 `#EDE8DF`, card `#FFFDF9`, ink `#17151A`, ink2 `#5D5962`, ink3 `#7E7983`, hair `#E6E0D6`, hair2 `#D8D1C5`, night `#0E0C14`, night2 `#191622`, night3 `#252131`; ember/iris/sage/gold/danger as the OKLCH values in the file (convert to sRGB hex once in Task B1); radii `r` 22 and `r2` 28.
- v3 fonts: Geist for UI (bundled asset; it is not in google_fonts 6.3), Instrument Serif for display, Literata for reading.

## Review Focus

1. **Sessions from before the deploy:** a session whose interview used the 8 legacy keys must still reach results and must not get a 409 `interview_profile_incomplete`. Stored v2 comparison scores must still render. Tests are in Tasks A2 and A5.
2. **Typed numbers:** blank, out-of-range or comma-decimal input ("4,5") in the intake hours control or a practice field is clamped or parsed, and is never sent invalid or silently zeroed. Tests are in Tasks C5 and D6.
3. **Malformed or missing v3 fences:** older lessons and generator drift must not blank a reader section. The prose still shows, and a bad fence degrades to plain lines. Tests are in Tasks A6 and D5.
4. **Illustration disabled, failed or capped:** the tutorial still publishes and reads normally without an image, and nothing retries in a loop. Test is in Task A7.
5. **Low capacity (60–150 min/week):** the plan fits the capacity, the capacity validators accept it, and the old raise to 3 h is gone. Test is in Task A4.

---

## Part A — Backend contracts (cmpys/backend, prompts in cmpys/prompts)

Run A1→A8 in order; A1 and A2 share `sessions.py`/`interview_inputs.py`.

### Task A1: Interview control kinds v3

**Files:** Modify `app/schemas/session.py` (`InterviewResponseInput`, `InterviewMessageRequest`), `app/api/v1/sessions.py` (`_response_input_for_answer_key`, interview handler persistence). Test: `tests/test_interview_response_ui.py`.

**Interfaces — Produces:**
- `InterviewResponseInput.kind: Literal["text","single_choice","multi_choice","scale","number"]`. `version` stays `1`, so old clients fall back to text.
- `option_details: list[InterviewOptionDetail]`. This is either empty or the same length as `options`. `InterviewOptionDetail{description: str|None ≤90, icon: Literal["list","book","edit","headphones","clock","target","users","layers","calendar","sparkle"]|None}`. `options` stays `list[str]` so old clients still parse.
- `suggestions: list[str]` (≤4, each 1–60 chars; text only) and `missing_option: str|None` (≤60; text only).
- `low_label`, `high_label: str|None` (≤40; scale only). A scale forces `min=1, max=5, step=1`, and `initial` is None.
- `min_selected: int = 1`, `max_selected: int|None` (multi only; 2–6 options).
- `presets: list[float]` (≤4; number only; each in range and aligned to step).
- `daily_hint: bool = False` (number only).
- `InterviewMessageRequest.missing_evidence: bool = False`. It is persisted on the user answer as `response_ui_json = {"missing_evidence": true}`.

- [ ] Step 1: Write failing tests:
  - `test_multi_choice_requires_2_to_6_unique_options`
  - `test_scale_forces_one_to_five`
  - `test_option_details_length_must_match_options`
  - `test_number_presets_must_align_to_step`
  - `test_text_suggestions_dropped_for_choice_kinds`
  - `test_unknown_kind_falls_back_to_text`
  - `test_missing_evidence_flag_persisted_on_answer`
- [ ] Step 2: Run `pytest tests/test_interview_response_ui.py -q`. Expect the new tests to FAIL.
- [ ] Step 3: Extend the validators in `validate_kind_fields`. Each kind clears the fields that belong to other kinds, exactly as the current code does.
- [ ] Step 4: Re-run. Expect PASS, and `tests/test_interview_streaming.py` to stay green.

### Task A2: Intake v3 question set (D3)

**Files:**
- Modify `app/services/interview_inputs.py`: keys, instructions, fallbacks, `collect_interview_answers`, `missing_interview_answer_keys`, `next_interview_answer_key`, `build_interview_plan_inputs`, `compact_placement_context`.
- Modify `app/api/v1/sessions.py`: `_response_input_for_answer_key`, `MAX_INTERVIEW_TURNS`.
- Modify `cmpys/prompts/interview_system.xml` and `cmpys/prompts/interview_question.txt`.
- Tests: `tests/test_interview_plan_inputs.py`, `tests/test_interview_streaming.py`, `tests/test_previous_release_read_compatibility.py`.

**Interfaces — Produces:**
- `INTERVIEW_ANSWER_KEYS_V2`, in this order:

  | Key | Control | Server-owned? |
  |---|---|---|
  | `achievement_inventory` | text + 3 suggestions | yes |
  | `work_sample` | text + `missing_option` "I don’t have one yet" | yes |
  | `foundation_check` | diagnostic `single_choice` (unchanged) | |
  | `application_check` | diagnostic `single_choice` (unchanged) | |
  | `self_check_method` | `single_choice` + descriptions | |
  | `skill_confidence` | `scale`, labels from the goal domain | |
  | `practice_volume` | `number` 0–50 step 1, unit "pieces of work" | yes |
  | `resources_capital` | `single_choice` + descriptions, must include "Prefer not to say" | |
  | `network_support` | `number` 0–20 step 1, unit "people" | yes |
  | `learning_preferences` | `multi_choice` + icons (the design's five learning modes) | yes |
  | `weekly_hours` | `number` min 1, max 15, step 0.5, initial 4, presets [2,4,6,8], unit "hours / week", `daily_hint` true | yes |
  | `target_outcome` | text + suggestions | |

- `INTERVIEW_ANSWER_KEYS_V1` = today's 8-key tuple, kept for reading.
- `interview_key_set(messages) -> tuple[str, ...]`. It returns V1 when any assistant message's `response_ui_json.answer_key` is in V1 minus V2 (`current_capability`, `constraints_resources`, `learning_habits_support`), and V2 otherwise. Every function that iterates keys takes its set from this.
- The `answer_key` Literal in `InterviewResponseInput` becomes the union of V1 and V2.
- `learner_baseline` gains `missing_evidence_keys: list[str]` (answers sent with `missing_evidence`) and `learning_preferences: list[str]`.
- `weekly_capacity_minutes` replaces `weekly_capacity_hours`. The provider-safe copy exposes both, with hours as a float, until Task A4 lands.
- Prompt rule: the model may only choose the control kind and option wording for non-server-owned keys. Every option set ends with an honest "don’t know / not yet" choice when the question is factual.

- [ ] Step 1: Write failing tests:
  - `test_v2_key_order_and_next_key`
  - `test_legacy_session_keeps_v1_key_set_and_completes` (Review Focus 1)
  - `test_work_sample_missing_option_records_missing_evidence`
  - `test_weekly_hours_v2_control_bounds`
  - `test_learning_preferences_multi_parsed_from_comma_list`
  - `test_max_turns_is_v2_len_plus_one`
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the key sets, the server-owned controls in `_response_input_for_answer_key`, the instructions and fallbacks for the new keys (one sentence each, ≤55 words, exactly one "?"), and the prompt edits. The edits teach the five kinds with one JSON example each.
- [ ] Step 4: Run the full interview suites. Expect PASS. `tests/test_prompt_placeholders.py` must be green.

### Task A3: Session context from onboarding

**Files:**
- Modify `app/schemas/session.py` (`SessionCreate`) and `app/models/intake.py` (`IntakeSession`).
- Create the migration `migrations/versions/<rev>_intake_session_context.py`.
- Modify `app/api/v1/sessions.py` (create handler, `user_profile` assembly near the comparison/blueprint prompts).
- Test: `tests/test_session_context.py` (new).

**Interfaces — Produces:**
- `SessionCreate.situation: list[str] = []` (≤8 items, each 1–60 chars). The design's chips are: "I work full-time", "I’m a student", "Mornings are best", "Evenings are best", "I commute", "Limited budget for books"; any string is accepted.
- `SessionCreate.situation_note: str|None` (≤500).
- `IntakeSession.situation_json: JSONB|None`, storing `{"situation": [...], "note": str|None}`.
- `user_profile["situation"]` and `user_profile["situation_note"]` go into the comparison, blueprint, backbone and week prompt contexts. Register the placeholder if a template references it.
- `goal` becomes free text up to 200 characters (it already is). `financial_status` stays required for older clients; new clients send `"not_specified"`.

- [ ] Step 1: Write failing tests:
  - `test_create_session_persists_situation`
  - `test_situation_reaches_user_profile`
  - `test_old_client_without_situation_still_creates`
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the change and the migration, with a down-revision equal to the current head (`alembic heads` must show one head).
- [ ] Step 4: Run `pytest tests/test_session_context.py -q`. Expect PASS.

### Task A4: Weekly minutes and low-capacity planning (D4)

**Files:**
- Models: `app/models/plan.py`, `app/models/plan_job.py`, `app/models/user_profile.py`.
- Migration `migrations/versions/<rev>_weekly_minutes.py`. It adds `weekly_minutes INTEGER` and backfills it as `weekly_hours*60`.
- Code: `app/services/interview_inputs.py` (`parse_weekly_hours_answer` → `parse_weekly_minutes_answer`), `app/api/v1/sessions.py`, `app/api/v1/jobs.py`, `app/api/v1/plans.py` (response `weeklyMinutes`), `app/tasks/plans.py` (remove the raise to 3 h near line 2633), `app/services/planning/generator.py` (capacity split), `app/services/planning/catalog_lessons.py`.
- Prompts: `cmpys/prompts/plan_backbone_generate.txt`, `plan_week_generate.txt`, `blueprint_generate.txt`.
- Tests: `tests/test_weekly_minutes.py` (new) plus the existing capacity suites.

**Interfaces — Produces:**
- `parse_weekly_minutes_answer(text: str) -> int | None`. Values are in 60–900 and multiples of 30. It accepts "4.5 hours a week", "4,5 h", "4 h 30" and "270 minutes". Anything outside the range raises the existing 409 `invalid_interview_answer`.
- `@dataclass(frozen=True) CapacitySplit(rhythm_minutes: int, mission_minutes: int, mission_count: int)`.
- `capacity_split(weekly_minutes: int) -> CapacitySplit`:
  - At 180 or above, it reproduces today's integer-hour rule exactly (×60).
  - Below 180: `mission_count = 1` and `rhythm = max(15, (weekly_minutes // 4) // 15 * 15)`, with the rest going to the mission. So 60 → (15, 45, 1) and 120 → (30, 90, 1).
- `weekly_hours` keeps being written as `ceil(weekly_minutes/60)` for legacy readers. Every planner and capacity check reads `weekly_minutes`.
- The plan API returns `weeklyMinutes: int` next to `weeklyHours`.

- [ ] Step 1: Write failing tests:
  - `test_parse_weekly_minutes_variants` (including the comma decimal, Review Focus 2)
  - `test_capacity_split_matches_legacy_rule_at_or_above_3h` (parametrised 180–900)
  - `test_capacity_split_low_capacity` (60, 90, 120, 150)
  - `test_low_capacity_plan_passes_capacity_validators` (Review Focus 5)
  - `test_job_below_3h_not_raised`
  - `test_plan_response_includes_weekly_minutes`
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the change. Then grep `weekly_hours` (79 sites) and convert every capacity computation to minutes.
- [ ] Step 4: Run the full backend suite. Expect PASS, including `test_capacity_approval_reuse.py`, `test_package_split_preflight.py` and the named-activity-duration and pending-capacity tests.

### Task A5: Comparison dimensions v3 (D1)

**Files:**
- Modify `app/services/comparison/scoring.py` (`FIXED_DIMENSIONS`, answer bindings near lines 342–357, payload `version`).
- Modify `cmpys/prompts/comparison_scores.txt`, `comparison_analyze.txt` and `comparison_generate.txt` (dimension vocabulary).
- Modify `app/tasks/comparison.py`.
- Test: `tests/test_comparison_scoring.py`.

**Interfaces — Produces:**
- `FIXED_DIMENSIONS` = `knowledge` "Knowledge base", `practice` "Practice volume", `capital` "Capital & resources", `network` "Network", `judgment` "Written judgment".
- The payload is `version: 3`, with the same methodology and status vocabulary.
- Answer bindings:

  | Dimension | Answer keys |
  |---|---|
  | knowledge | `achievement_inventory`, `foundation_check`, `application_check`, `skill_confidence` |
  | practice | `practice_volume`, `achievement_inventory` |
  | capital | `resources_capital` |
  | network | `network_support` |
  | judgment | `work_sample`, `self_check_method` |

  An answer key listed in `missing_evidence_keys` forces `insufficient_user_evidence` for its dimension. A capital answer of "Prefer not to say" gives `insufficient_user_evidence`.
- V1-key sessions are scored with the V2 dimensions through a legacy binding: `knowledge←current_capability`, `practice←achievement_inventory`, `capital←constraints_resources`, `network←learning_habits_support`, `judgment←target_outcome`. Stored v2 payloads are never rewritten.

- [ ] Step 1: Write failing tests:
  - `test_v3_dimension_ids_and_labels`
  - `test_missing_work_sample_marks_judgment_insufficient`
  - `test_prefer_not_to_say_capital_not_scored`
  - `test_v1_session_scored_with_legacy_binding`
  - `test_stored_v2_payload_untouched_on_read` (Review Focus 1)
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the change and the prompt edits.
- [ ] Step 4: Run `pytest tests/test_comparison_scoring.py -q`. Expect PASS.

### Task A6: Tutorial structured blocks

**Files:**
- Modify `app/services/planning/tutorial_visuals.py`.
- Modify `app/services/llm/schemas.py`: `PlanTutorialLessonSectionsOutput`, `TUTORIAL_SECTION_MIN_WORDS`, the tutorial heading list, and the word range in `plan_detail_step_quality_issues`.
- Modify `app/services/planning/lesson_writer.py` (`_TUTORIAL_CONTRACT`, section join).
- Modify `app/services/planning/lesson_package.py` (`render_package_results` must also render inside fences).
- Modify the prompts `tutorial_contract.txt`, `tutorial_domain_quantitative.txt`, `tutorial_domain_qualitative.txt`, `tutorial_exemplar_*.txt` and `plan_item_tutorial_outline.txt`.
- Tests: `tests/test_tutorial_visuals.py` (new), `tests/test_short_tutorial_pipeline.py`, `tests/test_tutorial_reading_budget.py`.

**Interfaces — Produces:** four new line-based fences. Braces, semicolons and HTML stay banned. `$`, `%`, `×` and `÷` are allowed.

- **`formula`**: the first line is `title: <≤60>`. It is followed by 2–6 term lines `<sign> <label ≤60>`, with sign in `= + − - ± × ÷`. The first term's sign is `=`.
- **`chart`**:
  - Header lines: `type: waterfall|bars`, `title: <≤80>`, optional `unit: <≤12>`.
  - Then 2–8 rows `<label ≤24> | <number>`.
  - In a waterfall, the last row starts with `= ` and its value must equal the running sum within 0.5%.
- **`steps`**:
  - Header lines: `title: <≤80>`, optional `unit:`.
  - Then 2–6 rows `<label ≤60> | <number or empty> | <note ≤160>`, plus an optional final `= <label> | <number>` that must equal the sum of the row values.
- **`check`**:
  - `Q: <≤240>`.
  - Then either 2–4 options `- [ ] text` / `- [x] text` with at least one `[x]`, where more than one `[x]` renders as select-all, or a numeric answer `answer: <number> | unit: <≤12> | tolerance: <number>`.
  - Last line `Why: <≤280>`.

Values may be `[[result:id]]` tokens. They are validated after `render_package_results`.

Section contract for new `tutorial_v1` lessons:

| Section | Requirement |
|---|---|
| `core_framework` | exactly one primary visual fence: `formula`, `diagram` or `comparison` |
| `worked_example` | one `steps` fence, plus an optional `chart` fence |
| `check_your_understanding` | one `check` fence |
| `guided_practice` | removed from new generations; the field becomes optional, with `None` as the default |

The total word range becomes 380–740, and fence lines count. The required headings exclude `## Guided Practice` when the field is absent. `tutorial_visual_issues(markdown) -> list[str]` returns one issue per missing or invalid required fence.

- [ ] Step 1: Write failing tests:
  - `test_formula_fence_valid_and_invalid`
  - `test_waterfall_total_must_match_running_sum`
  - `test_steps_total_must_match`
  - `test_check_fence_single_multi_numeric`
  - `test_fence_values_rendered_from_result_tokens`
  - `test_new_tutorial_without_guided_practice_passes`
  - `test_legacy_tutorial_with_guided_practice_still_valid` (Review Focus 3)
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the parsers and validator. Use one parse function per fence that returns a dataclass or None. Then update the schema and prompts. Each prompt gets one example per fence, taken from the design's `LESSON` data.
- [ ] Step 4: Run the full tutorial suites with the dummy provider. Expect PASS. Run `scripts/pilot_generation.py` only with owner approval (paid).

### Task A7: Tutorial illustrations (D2)

**Files:**
- Create `app/services/planning/tutorial_illustration.py`.
- Modify `app/core/config.py`, adding `tutorial_illustrations_enabled: bool = False` and `tutorial_illustration_daily_cap: int = 200`.
- Modify `app/schemas/plan.py` (`StepDetail.illustration`).
- Modify `app/tasks/plans.py` to enqueue after a tutorial step is published, on the `default` queue.
- Create `cmpys/prompts/tutorial_illustration.txt`.
- Test: `tests/test_tutorial_illustration.py` (new).

**Interfaces — Produces:**
- `TutorialIllustration{url: str, alt: str ≤160, provider: Literal["gemini_imagen"], aspect: Literal["16:9"]}`, stored on the `StepDetail` in `details_json`.
- `build_illustration_prompt(title: str, concept: str, domain: str) -> str`. The constraints: an editorial illustration on warm paper tones, no text, letters, numbers, logos or real people.
- `async generate_tutorial_illustration(plan_item_id: str, step_id: str) -> TutorialIllustration | None`. It:
  - returns None when disabled, over the daily cap (counted from today's files in `media/tutorials/`), or on any provider error;
  - is idempotent by `sha256(title+concept)` filename;
  - writes `media/tutorials/<hash>.jpg` and the URL `/media/tutorials/<hash>.jpg`;
  - makes one attempt and no retries.
- Celery task `tasks.plans.illustrate_tutorial_step(plan_item_id, step_id)`. A missing illustration never changes item or job status.

- [ ] Step 1: Write failing tests with a fake Imagen client:
  - `test_disabled_returns_none_and_no_call`
  - `test_cap_reached_returns_none` (Review Focus 4)
  - `test_provider_error_leaves_step_published` (Review Focus 4)
  - `test_idempotent_by_hash`
  - `test_prompt_forbids_text`
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the module. Reuse the `google.genai` client construction from `app/api/v1/idols.py:960` with the same model and `aspect_ratio="16:9"`.
- [ ] Step 4: Run `pytest tests/test_tutorial_illustration.py -q`. Expect PASS. Turning the flag on in production is the owner's call at deploy time.

### Task A8: Practice v3 — multi-select, per-field hints, misconception feedback

**Files:**
- Modify `app/services/practice/contracts.py` (`AnswerField`, `grade_fixed`, `public_workbook`).
- Modify `app/services/practice/generation.py` and `app/api/v1/practice.py` (hint endpoint).
- Modify the prompts `lesson_practice_generate.txt`, `tutorial_activity_generate.txt` and `tutorial_package_seed.txt`.
- Test: `tests/test_lesson_practice.py`.

**Interfaces — Produces:**
- `AnswerField.kind` adds `"multi_choice"` with `correct_choices: list[str]`. There must be at least one, all must be valid ids, and the grade is an exact set match. The feedback names the counts, for example "2 of 3 correct · 1 extra".
- `AnswerField.hint: str|None` (10–400). The fallback is the activity hint.
- `AnswerField.prefix: str = ""` (≤4, e.g. `$`). `unit` remains the suffix.
- `AnswerField.misconceptions: list[Misconception{expression: str, feedback: str 10–240}]` (≤3, numeric only). When an answer matches a misconception expression within tolerance, its feedback replaces the generic message. Misconceptions are private and stripped by `public_workbook`.
- `rubric_criterion` is required for new number/choice/multi fields. It is the criterion label shown in the result panel. The legacy default is `label`.
- `POST /plan-items/{item}/steps/{step}/practice/hint?field_id=<act.field>` reveals that field's hint and records `"act.field"` in `hints`.
- Generation rule: every activity has at least one `number` or `multi_choice` field, and at most one `text` field (an answer of ≤40 words). Text is never the only field.

- [ ] Step 1: Write failing tests:
  - `test_multi_choice_exact_set_grading`
  - `test_multi_choice_partial_feedback_counts`
  - `test_field_hint_endpoint_records_field_key`
  - `test_misconception_feedback_overrides_generic`
  - `test_public_workbook_strips_misconceptions_and_correct_choices`
  - `test_generation_rejects_text_only_activity`
- [ ] Step 2: Run them. Expect FAIL.
- [ ] Step 3: Implement the change and the prompt edits.
- [ ] Step 4: Run `pytest tests/test_lesson_practice.py -q`, then the full suite. Expect PASS.

---

## Part B — Flutter v3 foundation (fe/cmpys)

Run B1→B4 in order. Every Part C–F task consumes them.

### Task B1: Tokens, fonts and theme

**Files:**
- Modify `lib/app/design_tokens.dart` and `lib/app/theme.dart`.
- Add the Geist 400/500/600/700 TTF files under `assets/fonts/geist/`, declared in `pubspec.yaml` with family `Geist`.
- Append the license to `THIRD_PARTY_ASSETS.md`.
- Test: `test/white_first_design_tokens_test.dart` (rewrite to v3 values).

**Interfaces — Produces:**
- `AppColors`: `paper paper2 card ink ink2 ink3 hair hair2 night night2 night3 nink2 nink3 ember ember2 emberSoft iris iris2 irisSoft sage sage2 sageSoft gold gold2 goldSoft danger dangerSoft`. Legacy aliases (`green`, `brandAccent`, `primary`, …) are re-pointed: brand → ember, success → sage2.
- `AppTypography`: `display(size)` (Instrument Serif, letter-spacing −0.01em, height 1.02), `displayItalic(size)`, `read(size)` (Literata), `sans(size, weight)` (Geist), `kick` (11 / w600 / 0.12em / uppercase / ink3), `tnum` (tabular figures).
- `AppRadii.r` = 22, `AppRadii.r2` = 28.
- `AppMotion.out = Cubic(.16,1,.3,1)`, `AppMotion.spring = Cubic(.34,1.42,.5,1)`, `AppMotion.io = Cubic(.65,0,.35,1)`.
- `ReaderTheme{light, sepia, dark}`, with the `THEMES` values from `v3/tutorial.jsx`.

- [ ] Step 1: Rewrite the token test with the exact v3 hex values. Expect FAIL.
- [ ] Step 2: Fetch Geist from the `geist` npm package (`npm pack geist@1.3.1` into the scratchpad, then copy the TTFs). **This download needs the owner's OK; if it is declined, fall back to Inter and note it.**
- [ ] Step 3: Implement the tokens and the theme.
- [ ] Step 4: Run `flutter test test/white_first_design_tokens_test.dart`. Expect PASS. Run `flutter analyze`. Expect no new issues.

### Task B2: v3 primitives

**Files:**
- Create `lib/core/ui/v3/` with one file per group:
  - `buttons.dart`: `V3Button`, `V3IconButton`
  - `chips.dart`: `V3Chip`, `V3Tag`, `V3Seg`
  - `progress.dart`: `V3Ring`, `V3Bar`, `V3CountUp`
  - `feedback.dart`: `V3CheckDot`, `V3Burst`, `V3Confetti`, `showV3Toast`
  - `text.dart`: `V3Stream`, `V3Typing`, `V3Skel`
  - `field.dart`: `V3Field`
  - `surfaces.dart`: `V3Sheet` / `showV3Sheet`, `V3Section`, `v3Card`, `V3Avatar`, `V3Portrait`, `V3Cover`, `V3AccessBadge`
  - `icons.dart`: `V3Icon`, which renders the design's `IP` path set via `flutter_svg` path strings
- Export them all from `lib/core/ui/v3/v3.dart`.
- Test: `test/v3_primitives_test.dart`.

**Interfaces — Produces:** constructors mirror `v3/core.jsx` props:
- `V3Button({kind: V3ButtonKind{primary,dark,light,soft,glass,ghost,line,iris,sage}, size: V3Size{lg54,md44,sm36}, icon, iconRight, child, onPressed, loading, full})`
- `V3Sheet` supports drag-to-dismiss past 90 px and an optional title row with a close button
- `V3AccessBadge(type: AccessType{guide,original,excerpt,web,video,none})`, with the `ACCESS` copy

- [ ] Step 1: Write widget tests:
  - `disabled_button_ignores_tap`
  - `seg_moves_thumb_on_change`
  - `sheet_dismisses_on_drag_over_90`
  - `checkdot_bursts_only_on_mark_done`
  - `stream_reveals_text_then_calls_onDone`
  - `access_badge_labels_match_design`
- [ ] Step 2: Implement the primitives.
- [ ] Step 3: Run `flutter test test/v3_primitives_test.dart`. Expect PASS.

### Task B3: Tab bar and shell

**Files:** Modify `lib/core/ui/app_shell.dart` and `lib/core/ui/cmpys/cmpys_nav_icons.dart`. Test: `test/app_shell_test.dart`.

**Must match `v3/app.jsx` `TabBar`:**
- a dark glass pill with the centre notch mask
- the mentor-avatar centre tab labelled "Mentor"
- a sliding indicator with an ember top tick
- a tap ripple
- the Today badge showing the count of undone habits
- compact mode (height 50, labels hidden) when scrolling down more than 60 px, restored on scroll up
- hidden while a detail route is pushed
- the bottom paper fade

Routes stay `/home /plan /chat /vault /profile`.

- [ ] Step 1: Update the tests:
  - `centre_tab_shows_mentor_label`
  - `today_badge_counts_undone_habits`
  - `tab_bar_compacts_on_scroll_down_and_restores_on_up`
- [ ] Step 2: Implement the shell.
- [ ] Step 3: Run `flutter test test/app_shell_test.dart`. Expect PASS.

### Task B4: Celebration overlay and achievement sheet

**Files:**
- Create `lib/core/ui/v3/celebration.dart` (`showCelebration(context, Celebration{kind: tutorial|day, title, sub, stat, statLabel, achievement?})`).
- Modify `lib/features/plan/presentation/achievement_sheet.dart` to the design's "Suggested achievement" sheet.
- Test: `test/celebration_test.dart`.

**Design:** `v3/app.jsx` `Celebration` and `AchievementSheet`. This covers the confetti, the count-up stat, "Add to your record" / "Continue", and the confirm button that stays disabled below 6 characters.

- [ ] Step 1: Write the tests:
  - `tutorial_celebration_offers_add_to_record`
  - `achievement_confirm_disabled_under_6_chars`
- [ ] Step 2: Implement the overlay and sheet.
- [ ] Step 3: Run the tests. Expect PASS.

---

## Parts C–F — Screens

Every screen task has the same shape:
- **Files** to modify.
- **Design** file and component.
- **Data**: the existing providers and repositories to keep.
- **Must-haves**: behaviour and copy the current screen lacks.
- **Tests**: widget tests named after each must-have.
- Steps: (1) write the failing widget tests, (2) implement with the B-layer primitives, (3) run the tests until they pass and `flutter analyze` is clean.

When the design shows data the backend has no field for, keep it on the device in `cmpysStore` and use the design's "on this device" wording; do not invent server fields. Screen tasks touch disjoint files, so once Part B is done they can run in parallel.

### Part C — Onboarding

**C1 Splash.** File: `lib/features/auth/presentation/splash_screen.dart`. Design: `v3/onboard.jsx` `Splash`.
- Must-haves: the orbiting grey mentor avatars (60 s orbit with counter-rotation), "cmpys" / "COMPARE YOUR SUCCESS", copy that reveals after 1.5 s, and the buttons "Get started" and "I already have an account".
- Tests: `copy_appears_after_delay`, `buttons_route_to_signup_and_signin`.

**C2 Auth and recovery.** Files: `auth_screen.dart`, `forgot_password_screen.dart` (becomes a sheet). Design: `Auth`, `Recovery`, `CodeBoxes`.
- Must-haves:
  - the Create account / Sign in `V3Seg`, with the name field collapsing when switching
  - show/hide password
  - inline validation copy ("Tell us your name", "Enter a valid email", "At least 8 characters")
  - "Forgot password?" opening the 3-step recovery sheet: send code, 6 code boxes plus new password ×2 with "Passwords don’t match", then success. "Resend code" is a button.
  - the AI-interpretation disclaimer
- Keep `password_recovery` API wiring. Drop "Fill demo".
- Tests: `validation_messages`, `recovery_sheet_three_steps`, `code_boxes_accept_digits_only`.

**C3 Personal context.** File: `onboarding/personalize_step.dart`. Design: `Context`, `AgeWheel`.
- Must-haves:
  - 4 steps with the 4-segment progress bar and a "N / 4" counter
  - the horizontal snapping age wheel, 14–80, with the "Age is context for comparison…" note
  - interest chips, using the design's 10 `INTERESTS`
  - free-text goal plus 3 suggestion cards (the `GOALS` list)
  - situation chips plus an optional note, sent through Task A3
  - the final button "Find my mentors"
- Tests: `continue_disabled_until_step_valid`, `age_wheel_snaps_and_updates`, `situation_sent_in_session_create`.

**C4 Discovery and preview.** Files: `onboarding/discovery_step.dart`, `onboarding/idol_preview_step.dart`. Design: `Discovery`, `MentorPreview`, `Expand`.
- Must-haves:
  - search, the "Best match" portrait card, the "Also relevant" list
  - the no-results card "“q” isn’t in the library yet" → "Prepare profile". Use the existing idol import/research endpoint; if none exists, show the queued state only and file it in Deferred.
  - the clip-path expand from the tapped card into the preview
  - the "AI interpretation · not X" tag, domains, the documented timeline with the age-24 node highlighted, and "Begin intake with X"
- Tests: `empty_search_shows_prepare_profile`, `preview_shows_timeline_and_cta`.

**C5 Intake.** Files:
- `onboarding/intake_step.dart`, `onboarding/intake_answer_composer.dart`
- `lib/features/session/models/interview_response_ui.dart`, which parses every Task A1 field plus `answer_key`
- `lib/features/session/data/session_repository.dart`, which sends `missing_evidence`

Design: `v3/onboard2.jsx` `Intake`, `Bubble`.
- Must-haves:
  - chat bubbles with streamed mentor text and typing dots
  - the header "Intake with X" / "Question n of N", and a ring around the mentor avatar
  - "Answers are saved to your session as you go."
  - a kicker per kind with its icon: "Type or pick a starting point", "Choose one", "Choose any that fit", "Rate 1 to 5", "Set a number"
  - **text:** suggestion chips that fill the field; the missing chip sends immediately with `missing_evidence` and tags the bubble "Recorded as missing evidence"
  - **single choice:** rows with descriptions and a radio dot → "Send answer"
  - **multi:** a 2-column icon grid with square checks → "Send N selected" / "Select at least one"
  - **scale:** five 56 pt tiles with lo/hi labels; tiles below the pick are tinted ember-soft
  - **number:** −/+ 48 pt buttons, an editable big number, a slider, the presets row, the unit, and when `daily_hint` is set, "About N min a day · your plan’s workload will fit this"
  - finishing → "Open the mentor lab"
- Data: the existing `session_controller` SSE flow and `question_id` retry.
- Tests:
  - `missing_chip_sends_with_flag_and_tags_bubble`
  - `multi_send_label_counts_selection`
  - `scale_requires_pick`
  - `number_typed_out_of_range_clamps` (Review Focus 2)
  - `number_comma_decimal_parsed`
  - `daily_hint_shows_minutes`
  - `unknown_kind_falls_back_to_text`

**C6 Mentor lab.** File: `onboarding/mentor_lab_step.dart`. Design: `Lab`.
- Must-haves:
  - the avatar with halo rings and an orbiting ember dot
  - the 5-stage list (Written comparison / Dimension assessment / Strategic blueprint / Plan backbone / Tutorial 1), with run, done and fail states and "Retry"
  - streamed "From your comparison" and "Blueprint direction" cards and the 12-week grid as stages land
  - the sticky "Tutorials 2–N keep preparing in the background", plus "Go to Today" and "See the full plan"
- Map the stages to the existing SSE events: `section` comparison/blueprint, `plan_job`, and the first tutorial readiness from job polling.
- Tests: `stage_fail_shows_retry_and_keeps_done_stages`, `previews_appear_in_order`.

### Part D — Learning

**D1 Today.** File: `cmpys/presentation/today_screen.dart`. Design: `v3/today.jsx` (`TodayTab`, `NextUp`, `Reflection`, `BookShelf`).
- Must-haves:
  - the date kicker; the idea-reels button with a badge; the mentor avatar opening Mentor
  - "Good morning, Name." with the greeting by local hour
  - the tags "Day d of 84" and "Week w · Mentor"
  - the night NextUp card: tutorial progress segments, the pulsing play button, "n min read · n min practice"
  - preparing and failed states, the failed state with "Try again"
  - the habits card: ring, minutes left, `V3CheckDot`, expandable instructions with "Open habit", line-through when done, and the celebration when all are done
  - the streak card with its 7-day grid (the `/streak` endpoint)
  - the compare card ("n of 5 comparable")
  - Reflection autosave with "Unsaved", "Saving" and "Saved for today", stored locally
  - the "Idea for today" card
  - Your books: continue reading with Listen, and "For this week’s mission" covers with access badges
- Data: `todayViewProvider`, `currentPlanProvider`, `cmpysIdeasProvider`, content-resources continue-reading.
- Tests: `failed_state_retry_reloads`, `all_habits_done_triggers_celebration`, `reflection_autosaves`.

**D2 Plan tab.** Files: `cmpys/presentation/plan_screen.dart`, `plan/presentation/backend_plan_widgets.dart`. Design: `v3/plan.jsx` (`PlanTab`, `WeekPlan`, `HabitsView`).
- Must-haves:
  - the header "12 weeks with X" with the overall % ring
  - the tags "h / week" (from `weeklyMinutes`, with a 0.5 h display) and "Week w of 12"
  - the Roadmap / Daily habits seg
  - the week chip strip, where locked weeks show the toast "Week n unlocks after week n−1"
  - the expandable blueprint (priorities and "Why this order")
  - This week: the summary ring, "About x h of tutorials · y h budget", mission cards with tutorial rows in done, current, locked (with shake and toast) and preparing (with skeleton) states, "Show all n tutorials", and the next mission locked
  - the All weeks list with its unlock note
  - the habits view with per-habit 7-day grids
- Tests: `locked_tutorial_shakes_and_toasts`, `preparing_row_shows_skeleton`, `weekly_minutes_shows_half_hours`.

**D3 Habit detail.** Files: `plan_item_detail_screen.dart` (habit branch) or `detail_screens.dart` (`TaskDetail`), whichever currently opens habits. Design: `HabitScreen`.
- Must-haves:
  - the night focus timer ring (start, pause, resume, reset; "Time’s up")
  - "How to do it" plus the "Why it matters this week" panel
  - the reflection prompt with autosave
  - the "This week" 7-day grid
  - "Mark done for today" / "Mark as not done" with a burst
- Tests: `timer_counts_down_and_resets`, `mark_done_toggles_daily_toggle_api`.

**D4 Mission detail and materials.** File: `plan/presentation/plan_item_detail_screen.dart`. Design: `MissionScreen`, `MaterialRow`, `MaterialSheet`.
- Must-haves:
  - "Week w · Mission m of M"
  - the workload bar split into Reading, Practice and Deliverable minutes, with a legend
  - the tutorial timeline with its progress line and states, current one with "Continue"
  - the deliverable plus "Definition of done"
  - the night "Mental model" card
  - the materials list with access badges, and the material sheet ("Why it’s here", the access note, the CTA or "Not available to read")
  - "Required practice is solvable inside CMPYS…"
- Tests: `material_sheet_cta_by_access_type`, `workload_bar_sums_to_allocated`.

**D5 Tutorial reader.** Files:
- `plan/presentation/lesson_reader_screen.dart`
- Create `lib/core/ui/v3/lesson_blocks/`, one widget each: `formula_stack.dart`, `waterfall_chart.dart` (also bars), `worked_steps.dart`, `quick_check.dart`, `illustration_hero.dart`
- `lib/core/reading/lesson_fences.dart`, the parsers mirroring Task A6
- `cmpys_markdown.dart`, which routes the new fences

Design: `v3/tutorial.jsx`.
- Must-haves:
  - **one continuous scroll**, replacing the PageView, with sections Why this skill / The idea / Seeing it / Worked example / Common errors / Check yourself / References, and the kicker heading with an ember rule
  - the top progress bar
  - the title fading into the top bar after 4% scroll
  - the Contents sheet (jump to section) and the Reading settings sheet (A / A+ / A++ and the light, sepia and dark themes), persisted
  - "Completed · score" when done
  - "Tutorial n of N · Week w"; the read and practice minute tags
  - the illustration hero when `illustration` is present
  - the formula stack and waterfall animating in on first view
  - worked steps revealed one at a time with a running total and the final summary line
  - common errors as ✕ cards
  - the quick check: single choice (a 2×2 grid), select-all (square checks plus "Check"), or numeric (an input plus "Check"); then shake or pop feedback, the explanation, and "Quick checks aren’t graded."
  - references as `MaterialRow`s
  - the bottom CTA "Open practice · n min" or "Review practice & attempts"
- Legacy lessons: `guided_practice` renders as a "Try it" section, the old `diagram` and `comparison` fences render in "Seeing it", and a bad fence renders as plain lines (Review Focus 3).
- Tests:
  - `sections_in_design_order`
  - `toc_jumps_to_section`
  - `theme_switch_persists`
  - `worked_steps_running_total`
  - `quick_check_multi_requires_all_correct`
  - `quick_check_numeric_tolerance`
  - `malformed_fence_renders_plain_lines`
  - `legacy_lesson_shows_try_it`
  - `no_illustration_no_hero`

**D6 Practice workbook.** Files: `plan/presentation/lesson_practice_screen.dart`, `plan/models/practice_models.dart` (`multi_choice`, `hint`, `prefix`, `rubric_criterion`), `plan/data/practice_repository.dart` (`field_id` hint). Design: `v3/practice.jsx`.
- Must-haves:
  - the draft-status pill ("Draft saved", "Saving", "Unsaved")
  - the Guided → Independent case stepper, with a lock until the guided activity passes
  - the activity tag, title and intro
  - the data table, with indented "…" rows
  - "Your answers" field cards: per-field "Hint" / "Hint used" with a gold hint panel, and numeric inputs with prefix and suffix
  - choice as 2-column buttons; multi as a check grid; text as a textarea
  - the result panel: a night "Checking against criteria" panel with criteria ticking one by one, then a ring with score, "Accepted" or "n of m criteria met", per-criterion feedback, and field borders turning sage or danger
  - attempt chips "#n · s/m"
  - "Show worked solution", gated as in the design; the lock note on the independent case
  - the CTA set: Submit for checking / Checking / Revise answer / Continue to independent case / Finish tutorial
  - the "Leave practice?" sheet when unsaved
  - finishing → Task B4 celebration with an achievement
- Tests:
  - `submit_disabled_until_all_filled`
  - `numeric_field_parses_comma_decimal` (Review Focus 2)
  - `field_hint_calls_api_with_field_id`
  - `criteria_tick_sequentially`
  - `independent_locked_until_guided_passed`
  - `leave_sheet_when_unsaved`
  - `finish_shows_celebration`

### Part E — Reading and listening

**E1 Library.** File: `plan/presentation/reading_library_screen.dart`. Design: `v3/library.jsx` `LibraryScreen`.
- Must-haves: search; the night "Continue reading" hero with Continue and Listen; the All / Saved / Completed seg; the count; rows with cover, chapters, access badges, a progress ring or ✓, and a saved bookmark; the empty states.
- Tests: `filter_saved_empty_state`, `search_filters_by_author`.

**E2 Book reader.** File: `plan/presentation/book_reader_screen.dart`. Design: `BookReader`.
- Must-haves:
  - chrome that hides on scroll-down
  - the study-guide banner
  - tap a paragraph → the Highlight / Note / Quote popover, with the note sheet
  - the narration paragraph marker plus "Position follows audio approximately…"
  - "Next: Chapter n"
  - the menu sheet (Contents, Notes & highlights · n, Save, Read original book, Reading settings)
  - the Listen FAB
- Data: keep the existing highlights API, narration and progress.
- Tests: `paragraph_tap_shows_actions`, `menu_save_toggles`.

**E3 Player and dock.** Files: `plan/presentation/book_narration_dock.dart`, `book_narration.dart`. Design: `FullPlayer`, `Dock`, `Waves`.
- Must-haves:
  - the full-screen night player: cover, waves, a seek bar with elapsed and −remaining time, ±15 s, play/pause, speed cycling 1 → 1.25 → 1.5 → 2 → 0.75, Chapters, Stop, and "AI-generated voice. Not X’s voice."
  - the dock above the tab bar with a progress hairline
- Tests: `speed_cycles_in_design_order`, `dock_opens_full_player`.

**E4 Web and video viewers.** Files: `plan/presentation/material_reader_screen.dart`, the video lesson screen. Design: `WebViewer`, `VideoViewer`.
- Must-haves: the URL pill with a lock; the load progress hairline; the access banner (excerpt, original or opened-from copy); the bottom toolbar; the video 16:9 player with the "Why it’s here" card.
- Tests: `excerpt_banner_copy`.

### Part F — Mentor, compare, record and profile

**F1 Mentor chat.** File: `cmpys/presentation/chat_screen.dart`. Design: `v3/chat.jsx`.
- Must-haves:
  - the header: mentor avatar with the online dot opening the Mentor context screen, the thread title, and the History, New chat and Report a win buttons
  - the empty state with halo and 4 prompt cards
  - "Conversation restored · when"
  - the typing → streamed reply; the failed reply with "Retry reply"
  - "Tap a reply to save it as a note" → the save sheet
  - suggestion chips
  - the history sheet: search, Current, This week / Last week / Earlier groups, delete, new
  - the 4-step `WinSheet`: rotating examples, the 120-character counter, dimension rows with tints (the Task A5 ids), the size bars, evidence plus link, the fly-out send, "Added to your record", and the mentor reply in chat
- Data: the guided-learning SSE and messages endpoint. Threads are local if the API has no thread list.
- Tests: `failed_reply_retry_resends`, `win_sheet_four_steps_then_reply`, `history_search_filters`.

**F2 Compare.** File: `cmpys/presentation/compare_screen.dart`, plus `dimsFromScores` in `cmpys_store.dart` (accept versions 2 and 3; use server labels and never hard-code ids). Design: `v3/compare.jsx` `CompareTab`, `DimRow`, `DimDetail`.
- Must-haves:
  - "You and X, both at age."
  - the overlapping initials, age and mentor avatar
  - "n of 5 dimensions compared like for like", with solid and dashed segments and "…not a zero."
  - the night "Written perspective" card → the full sheet with the AI disclaimer
  - dimension rows with Like for like / Not comparable / Evidence missing tags, the two bars and count-ups
  - the detail sheet: Your evidence / X at age / Uncertainty or "Why there’s no score"
  - the "Your record" and "Plan" buttons
- Status mapping: comparable → Like for like; different_basis → Not comparable; insufficient_* → Evidence missing.
- Tests: `v2_payload_renders_with_server_labels` (Review Focus 1), `v3_payload_counts_comparable`, `dim_sheet_uncertainty_copy`.

**F3 Record.** File: `cmpys/presentation/record_screen.dart`. Design: `RecordScreen`.
- Must-haves:
  - "Log a win" (a `WinSheet` in record mode)
  - dimension filter chips
  - the legend
  - the "n new entries waiting. Reassess on this device" banner with its overlay
  - the dual timeline by age with the current age highlighted
  - the entry sheet with source copy, the mentor note, "Claim a similar milestone", and "Delete entry" for local entries
  - the claim sheet, with a 10-character minimum
- Tests: `claim_requires_10_chars`, `delete_only_for_local`.

**F4 You.** Files: `cmpys/presentation/you_screen.dart`, `cmpys/presentation/detail_screens.dart` (`EditProfile`, `MentorPicker`, `Settings`). Design: `v3/you.jsx` `YouTab`, `EditProfile`.
- Must-haves:
  - the profile header with the edit sheet; the unsaved-changes guard offers Save / Discard / Keep editing
  - the 3 stat cards
  - the mentor portrait with "Change", opening a sheet with the "changes the mentor shown on this device" note
  - Library rows
  - Settings toggles with the "saved on this device" note
  - "Privacy & data · Coming soon" (toast)
  - "About CMPYS"
  - the Log out sheet
- Tests: `edit_profile_guard_on_dirty_close`, `logout_sheet_confirms`.

**F5 Idea reels.** File: `cmpys/presentation/reels_screen.dart`. Design: `ReelsScreen`.
- Must-haves:
  - vertical snap pages with the provenance tag (Verified quotation / Exact quotation / Sourced attribution / Generated insight)
  - the big quote mark
  - double-tap → the heart burst and a like
  - the side rail: like, comments sheet (local), save (which adds to Saved), share
  - the top progress segments, up/down buttons and "Ideas for week w"
  - the loading skeleton
- Tests: `double_tap_likes`, `save_adds_to_saved_list`.

**F6 Notes, Saved and Mentor context.** Files: `detail_screens.dart` (Notes, Saved), `cmpys/presentation/idol_detail_screen.dart`. Design: `ListScreen`, `MentorScreen`.
- Must-haves: "Library · on this device"; the empty states with CTAs (Open chat / Browse ideas); delete; the night mentor context screen with the disclaimer and the timeline highlighting the user's age.
- Tests: `empty_notes_cta_opens_chat`.

---

## Part G — Verification

### Task G1: Full suites

- [ ] Run the backend tests with the dummy-provider command from Global Constraints. Expect 0 failures.
- [ ] Run `flutter analyze` and `flutter test` from `fe/cmpys`. Expect 0 errors and 0 failures.
- [ ] Update `test/no_legacy_design_copy_test.dart` and `test/primary_screens_responsive_test.dart` for v3. Retire the tests that only cover the unused `analysis_step` / `plan_gen_step`, and delete those two files.

### Task G2: Live run (owner-approved, ≤ USD 1)

- [ ] Start the local stack using the recipe in memory `cmpys-prompt-speed-plan-2026-10-26`. That means pg/redis containers, uvicorn, and one Celery worker per queue. Pass the test key only through env, and set `TUTORIAL_ILLUSTRATIONS_ENABLED=true` with `TUTORIAL_ILLUSTRATION_DAILY_CAP=3`.
- [ ] In the iOS simulator, go through sign-up → context → discovery → intake. Exercise each control kind, including the missing-evidence chip and 4.5 h. Continue through the lab, Today, the first tutorial (every fence renders, the illustration appears, the quick check works) and practice (numeric, multi, hint, revise, accept, celebration). Then check Compare (v3 dimensions).
- [ ] Screenshot every screen in the design index into `docs/releases/assets/v3/` and compare each side by side with the design.

---

## Deferred (named, not dropped)

- Re-scoring the comparison automatically from later in-app evidence (accepted practice, worksheets). The design copy implies it ("Your week 3 worksheet will count as first evidence"), but no trigger exists.
- Server-side sync for notes, saved items, reported wins, idea comments and settings. The design labels them "on this device".
- Mentor research/import ("Prepare profile"), if Task C4 finds no backend endpoint.
- The design's accent tweak (Ember/Iris/Sage) and its state toggles. These are prototype controls, not product settings.
