# Tasks: Agentic Persona Workflow

## Current Canonical Status

This file contains the original task ledger plus historical duplicate rows from the agentic refactor. For roadmap decisions, the canonical product direction is now:

- **Product Strategy Agent:** agentic activation is the primary first-run path; the 12-week plan is the execution artifact; the blueprint is the strategic verdict, not a competing roadmap.
- **UX/IA Agent:** main navigation is Today, Plan, Mentor, Library, Profile; Discover/Ideas is a secondary Library/Today entry.
- **Prompt Contract Agent:** `plan_generate.txt` and `plan_item_details.txt` use strict placeholder contracts with idol context and unresolved-placeholder tests.
- **Backend Learning Loop Agent:** daily instructions prefer `meta_json.daily_instructions`, then `details_json.daily_instructions`; reflections reuse Notes v1.
- **Flutter Experience Agent:** Today is the daily retention surface after activation; Mentor quick actions deep-link into current work.
- **QA Agent:** focused prompt, daily focus, and content-threshold regression tests cover the current implementation pass.
- **Documentation Agent:** product strategy, UX spec, prompt contracts, and API contract docs are the source of truth for this pass.

Historical duplicate rows below are preserved only as implementation provenance; when a duplicate task has both checked and unchecked versions, the checked row plus current source code/tests take precedence.

**Input**: Design documents from `/specs/001-agentic-refactor/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Included — the existing test infrastructure demands new prompt and phase transition tests.

**Organization**: Tasks grouped by user story from spec.md. Backend tasks first (P1 core), then Flutter tasks (P2 state + UI).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prompt files, schema additions, and migration — the foundation all user stories depend on.

- [x] T001 Create FlintK12-style XML system prompt at `prompts/interview_system.xml` with `<persona>`, `<core_directives>` (Fact-Based Grounding, Interactive Interrogation Loop, Brutal Reality Check, 21st-Century Adaptation, Quarterly Blueprint), and `<workflow_rules>` sections. Include explicit jargon ban list and one-question-per-turn enforcement directive.
- [x] T002 [P] Create per-turn interview user prompt template at `prompts/interview_question.txt` with placeholders: `{idol_name}`, `{user_age}`, `{user_financial_status}`, `{user_interests_json}`, `{chat_history_json}`, `{turn_count}`, `{max_turns}`, `{idol_facts_json}`.
- [x] T003 [P] Create comparison generation prompt at `prompts/comparison_generate.txt` with placeholders: `{idol_name}`, `{user_age}`, `{user_profile_json}`, `{interview_transcript_json}`, `{idol_facts_json}`. Must instruct first-person, emotionally intense comparison with cited achievements.
- [x] T004 [P] Create blueprint generation prompt at `prompts/blueprint_generate.txt` with placeholders: `{idol_name}`, `{user_age}`, `{user_profile_json}`, `{interview_transcript_json}`, `{comparison_summary}`, `{idol_facts_json}`. Must instruct Q1–Q4 Markdown format with real resource URLs via Google Search.
- [x] T005 [P] Update idol suggestion prompt at `prompts/idol_suggest.txt` to accept `{user_age}`, `{user_financial_status}`, `{user_interests_json}` and return exactly 3 suggestions with name, era, relevance_summary, wikidata_id.

**Checkpoint**: All 5 prompt files exist and are syntactically valid.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Model changes, schemas, and service-layer functions that ALL user stories need.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T006 Add `SessionPhase` enum (`intake`, `idol_selection`, `interview`, `comparison`, `blueprint`, `completed`) to `backend/app/models/intake.py`. Add columns to `IntakeSession`: `phase` (SessionPhase, default=intake), `user_age` (int), `user_financial_status` (str), `user_interests` (JSONB), `interview_thread_id` (UUID FK → chat_threads.id, nullable), `interview_turn_count` (int, default=0), `comparison_output` (TEXT, nullable), `blueprint_output` (TEXT, nullable), `idol_facts_json` (JSONB, nullable).
- [ ] T007 Generate Alembic migration: run `alembic revision --autogenerate -m "add session phase and agentic columns"` from `backend/`, then `alembic upgrade head`. **⚠️ DEFERRED — requires live DB connection.**
- [x] T008 [P] Add new Pydantic LLM schemas
- [x] T009 [P] Register all 5 new prompt files
- [x] T010 [P] Create Pydantic request/response schemas at `backend/app/schemas/session.py`
- [x] T011 Add three new async generator functions to `backend/app/services/gemini.py` to `backend/app/services/llm/schemas.py`: `InterviewQuestionResponse` (fields: `question`, `emotional_reaction`, `should_continue`), `ComparisonResponse` (fields: `comparison_text`, `cited_achievements`), `BlueprintResponse` (fields: `blueprint_markdown`, `resources_cited`), `IdolSuggestion` (fields: `name`, `era`, `relevance_summary`, `wikidata_id`), `IdolSuggestionsResponse` (field: `suggestions: list[IdolSuggestion]`).
- [ ] T009 [P] Register all 5 new prompt files in `PROMPT_PLACEHOLDERS` dict and `PROMPT_REGISTRY` in `backend/app/services/llm/prompt_loader.py`. Add `.xml` file extension support to `load_prompt()` function (currently only supports `.txt`).
- [ ] T010 [P] Create Pydantic request/response schemas at `backend/app/schemas/session.py`: `SessionCreate` (age, financial_status, interests), `SessionResponse` (id, phase, user_age, user_financial_status, user_interests, selected_idol, interview_turn_count, comparison_output, blueprint_output, interview_thread_id, created_at, updated_at), `IdolSuggestionItem`, `IdolSuggestionsResponse`, `SelectIdolRequest` (idol_name, wikidata_id), `InterviewMessageRequest` (content).
- [ ] T011 Add three new async generator functions to `backend/app/services/gemini.py`: `interview_stream(system_prompt, user_message, conversation_history, idol_facts)` — uses Gemini 2.0 Flash + GoogleSearch tool, injects interview_system.xml as system_instruction; `comparison_stream(system_prompt, user_message)` — uses Gemini + GoogleSearch, generates reality check; `blueprint_stream(system_prompt, user_message)` — uses Gemini + GoogleSearch, generates Q1–Q4 blueprint. All follow the existing `stream_with_grounding()` pattern.

**Checkpoint**: Foundation ready — migration applied, schemas exist, Gemini service has all 3 new streaming functions, prompt loader supports new files. User story implementation can now begin.

---

## Phase 3: User Story 1 — Intake & Idol Discovery (Priority: P1) 🎯 MVP

**Goal**: User submits age/financial status/interests → receives 3 idol suggestions → selects one → session transitions to interview phase.

**Independent Test**: Create a session via API, receive 3 idol suggestions, select one, verify session phase transitions to `interview`.

### Implementation for User Story 1

- [x] T012 [US1] Create new API router at `backend/app/api/v1/sessions.py`.
- [x] T013 [US1] Implement `POST /api/v1/sessions/{session_id}/suggest-idols`
- [x] T014 [US1] Implement `POST /api/v1/sessions/{session_id}/select-idol`
- [x] T015 [US1] Implement `GET /api/v1/sessions/{session_id}` Implement `POST /api/v1/sessions` endpoint: validates `SessionCreate` body, creates `IntakeSession` with `phase=intake`, stores age/financial_status/interests, returns `SessionResponse`. Wire router into `backend/app/api/router.py`.
- [ ] T013 [US1] Implement `POST /api/v1/sessions/{session_id}/suggest-idols` endpoint in `backend/app/api/v1/sessions.py`: loads session, loads and renders `idol_suggest.txt` prompt with session intake data, calls `gemini.stream_with_grounding()` (or a new dedicated function) with Google Search enabled, parses response into 3 `IdolSuggestionItem` objects, returns `IdolSuggestionsResponse`. Transitions session phase to `idol_selection`.
- [ ] T014 [US1] Implement `POST /api/v1/sessions/{session_id}/select-idol` endpoint in `backend/app/api/v1/sessions.py`: accepts `SelectIdolRequest`, imports idol via existing import pipeline (or finds existing), creates `ChatThread` linked to session, updates `IntakeSession.interview_thread_id` and `IntakeSession.idol_id`, transitions phase to `interview`, returns updated `SessionResponse`.
- [ ] T015 [US1] Implement `GET /api/v1/sessions/{session_id}` endpoint in `backend/app/api/v1/sessions.py`: loads session with related idol data, returns `SessionResponse` (used for polling/resume).

**Checkpoint**: User Story 1 fully functional — intake data in, 3 idol suggestions out, idol selection transitions to interview. Testable independently via curl.

---

## Phase 4: User Story 2 — Live In-Character Interview (Priority: P1)

**Goal**: AI adopts idol persona, asks exactly ONE question per turn, reacts emotionally, tracks turn count, auto-transitions to comparison after 3–5 turns.

**Independent Test**: Select an idol, send 3–5 interview messages, verify one-question-per-turn enforcement, verify `phase_transition: true` in final SSE `done` event.

### Implementation for User Story 2

- [x] T016 [US2] Implement `POST /api/v1/sessions/{session_id}/interview` SSE endpoint
- [x] T017 [US2] Add turn-count enforcement logic
- [x] T018 [US2] Add phase validation guard to all session endpoints in `backend/app/api/v1/sessions.py`: validates session is in `interview` phase, loads interview_system.xml as system_instruction + renders interview_question.txt with session context + chat history, calls `gemini.interview_stream()`, persists AI response as `ChatMessage` in the session's `ChatThread`, increments `IntakeSession.interview_turn_count`. On first turn (turn_count == 0), fetch idol facts at user's age via Gemini + Google Search and cache in `IntakeSession.idol_facts_json`.
- [ ] T017 [US2] Add turn-count enforcement logic to the interview endpoint: if `interview_turn_count >= 3` and LLM response includes `should_continue: false` (or hard cap at `turn_count >= 5`), set `phase_transition: true` in SSE `done` event, transition session phase to `comparison`. If `turn_count < 3`, always set `phase_transition: false`.
- [ ] T018 [US2] Add phase validation guard to all session endpoints in `backend/app/api/v1/sessions.py`: reject requests with HTTP 409 if the session is not in the expected phase for that endpoint (e.g., interview endpoint rejects if phase != `interview`).

**Checkpoint**: Full interview loop works — AI asks one question per turn, reacts emotionally, auto-transitions after 3–5 turns. SSE stream delivers chunks + metadata.

---

## Phase 5: User Story 3 — Brutal Reality Comparison (Priority: P1)

**Goal**: AI (still in-character) delivers a harsh, first-person comparison using verified factual data about the idol's achievements at the user's exact age, contrasted with the user's interview answers.

**Independent Test**: After interview completion, call generate-results and verify the comparison text references both idol achievements and specific user interview answers.

### Implementation for User Story 3

- [x] T019 [US3] Implement `POST /api/v1/sessions/{session_id}/generate-results` SSE endpoint in `backend/app/api/v1/sessions.py` — **Part 1: Comparison**. Validates session phase is `comparison`. Loads full context from DB: intake data, selected idol profile/persona, all interview `ChatMessage` rows, cached `idol_facts_json`. Renders `comparison_generate.txt` with this context. Calls `gemini.comparison_stream()` with Google Search enabled. Streams comparison chunks with `{"type": "section", "section": "comparison"}` header. Persists completed comparison text in `IntakeSession.comparison_output`. Transitions phase to `blueprint`.

**Checkpoint**: Comparison generates with real idol facts at user's age, references interview answers, maintains first-person persona voice.

---

## Phase 6: User Story 4 — Quarterly Blueprint Generation (Priority: P2)

**Goal**: AI generates a detailed Q1–Q4 roadmap with real study materials found via Google Search, translating historical achievements into 21st-century action steps.

**Independent Test**: After comparison, verify blueprint contains 4 quarters with escalating complexity, and Q1 includes at least 3 resource recommendations with real URLs.

### Implementation for User Story 4

- [x] T020 [US4] Extend the `generate-results` endpoint (T019) — **Part 2: Blueprint**. After comparison is complete, renders `blueprint_generate.txt` with full context (intake + interview + comparison summary). Calls `gemini.blueprint_stream()` with Google Search for resource URLs. Streams blueprint chunks with `{"type": "section", "section": "blueprint"}` header. Persists blueprint Markdown in `IntakeSession.blueprint_output`. Transitions phase to `completed`. Sends final SSE `{"type": "done", "phase": "completed"}`.

**Checkpoint**: Full generate-results endpoint streams both comparison and blueprint sequentially. Blueprint has Q1–Q4 headers, bullet points, real resource URLs.

---

## Phase 7: User Story 5 — State Continuity & Context Preservation (Priority: P2)

**Goal**: Full session context persists across all phases. Users can resume interrupted sessions.

**Independent Test**: Close the app mid-interview, reopen, verify session resumes at the correct phase with full prior context.

### Implementation for User Story 5

- [ ] T021 [US5] Verify `GET /api/v1/sessions/{session_id}` (T015) returns complete state including `phase`, `interview_turn_count`, `comparison_output`, `blueprint_output`. Add `last_message` field from the interview thread if phase is `interview`. Frontend uses this to restore UI state on resume.
- [ ] T022 [US5] Add `GET /api/v1/sessions/current` endpoint in `backend/app/api/v1/sessions.py`: returns the user's most recent non-completed session (if any), allowing the frontend to detect and resume an in-progress session on app launch.

**Checkpoint**: Sessions survive app restarts. Resume endpoint works for in-progress sessions.

---

## Phase 8: Flutter — State Management (Milestone 3)

**Purpose**: Riverpod state + Dio API client for the 5-phase flow.

- [ ] T023 [P] Create `SessionPhase` enum and `Session` model in Flutter at `lib/models/session.dart` with `@JsonKey(name: 'snake_case')` annotations for all fields matching `SessionResponse` schema: `id`, `phase`, `userAge`, `userFinancialStatus`, `userInterests`, `selectedIdol`, `interviewTurnCount`, `comparisonOutput`, `blueprintOutput`, `interviewThreadId`, `createdAt`, `updatedAt`.
- [ ] T024 [P] Create `SessionApi` Dio service class at `lib/services/session_api.dart` with methods: `createSession(SessionCreate)`, `suggestIdols(sessionId)`, `selectIdol(sessionId, SelectIdolRequest)`, `sendInterviewMessage(sessionId, content)` (SSE stream), `generateResults(sessionId)` (SSE stream), `getSession(sessionId)`, `getCurrentSession()`.
- [ ] T025 Create `SessionNotifier` (Riverpod `StateNotifier<SessionState>`) at `lib/providers/session_provider.dart`. `SessionState` holds: `Session?`, `List<IdolSuggestion>?`, `bool isLoading`, `String? error`, `bool isStreaming`. Notifier methods wrap `SessionApi` calls and manage phase transitions. Expose providers: `sessionProvider`, `currentPhaseProvider` (derived).

**Checkpoint**: Flutter state layer complete — models, API client, and Riverpod notifier ready.

---

## Phase 9: Flutter — UI Screens (Milestone 4)

**Purpose**: Wire the 5-phase UI to the new state management layer.

- [ ] T026 [US1] Modify `lib/screens/intake_screen.dart`: wire Age, Financial Status, Interests form fields to `SessionNotifier.createSession()`. On success, navigate to idol selection screen.
- [ ] T027 [US1] Modify `lib/screens/idol_selection_screen.dart`: call `SessionNotifier.suggestIdols()` on mount, display 3 idol cards with name, era, relevance summary. On tap → `SessionNotifier.selectIdol()` → navigate to interview screen.
- [ ] T028 [US2] Create `lib/screens/interview_screen.dart`: chat-style UI consuming SSE from `SessionNotifier.sendInterviewMessage()`. Display turn counter ("Question 2 of 5"). Lock text input while AI is streaming. On `phase_transition: true` in SSE `done` event → auto-navigate to comparison screen with dramatic transition animation (Framer Motion equivalent: `flutter_animate` or custom `AnimatedSwitcher`).
- [ ] T029 [US3] Create `lib/screens/comparison_screen.dart`: full-screen rich text display of `session.comparisonOutput`. Emphasize emotional elements with bold/large typography. Add "Continue to Your Blueprint" CTA button → navigate to blueprint screen.
- [ ] T030 [US4] Create `lib/screens/blueprint_screen.dart`: render `session.blueprintOutput` using `flutter_markdown` package. Ensure Q1–Q4 headers, bullet points, and resource URLs are clickable (`url_launcher`). Add share/export button.
- [ ] T031 [US5] Add session resume logic to `lib/main.dart` or app initialization: on app launch, call `SessionNotifier.getCurrentSession()`. If a non-completed session exists, navigate directly to the screen matching the current phase instead of the home screen.

**Checkpoint**: All 5 phase screens functional. Interview auto-transitions. Blueprint renders Markdown. Resume works.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Tests, validation, and documentation updates.

- [x] T032 [P] Add new prompt files to `test_prompt_placeholders.py` test in `backend/tests/test_prompt_placeholders.py`: validate `interview_system.xml`, `interview_question.txt`, `comparison_generate.txt`, `blueprint_generate.txt`, `idol_suggest.txt` all load and render without missing placeholder errors.
- [x] T033 [P] Create `backend/tests/test_session_phase.py`: unit tests for `SessionPhase` state transitions — valid forward transitions pass, invalid transitions (e.g., intake → comparison) raise ValueError, turn count boundaries (transition at 3–5, reject at <3).
- [x] T034 [P] Add jargon guard coverage for new prompts: add sample outputs from comparison_generate and blueprint_generate to `backend/tests/test_jargon_guard.py` to verify the banned terms list catches jargon in interview/comparison/blueprint contexts.
- [x] T035 Update `backend/README.md` API endpoint table with new session endpoints: `POST /sessions`, `POST /sessions/{id}/suggest-idols`, `POST /sessions/{id}/select-idol`, `POST /sessions/{id}/interview`, `POST /sessions/{id}/generate-results`, `GET /sessions/{id}`, `GET /sessions/current`.
- [x] T036 Run full test suite and verify no regressions: `cd backend && pytest tests/ -v`. All existing tests (test_jargon_guard, test_plan_completion, test_prompt_placeholders, test_wikidata, test_wikipedia) plus new tests must pass.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 prompt files existing
- **User Stories (Phase 3–7)**: All depend on Phase 2 completion
  - US1 (Intake & Idol Discovery): Can start after Phase 2
  - US2 (Live Interview): Depends on US1 (needs session with selected idol)
  - US3 (Brutal Comparison): Depends on US2 (needs completed interview)
  - US4 (Quarterly Blueprint): Depends on US3 (needs comparison output)
  - US5 (State Continuity): Can start after US1, verifies all phases
- **Flutter State (Phase 8)**: Can start after Phase 2 (API contracts known)
- **Flutter UI (Phase 9)**: Depends on Phase 8 (state layer) + corresponding backend US phases
- **Polish (Phase 10)**: Depends on all user stories complete

### Within Each User Story

- Models/schemas before services
- Services before endpoints
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

```bash
# Phase 1 — All prompt files can be written in parallel:
T001, T002, T003, T004, T005

# Phase 2 — Independent foundation tasks:
T008 (schemas), T009 (prompt_loader), T010 (API schemas)

# Phase 8 — Flutter model and API client in parallel:
T023 (model), T024 (api client)

# Phase 10 — All tests in parallel:
T032, T033, T034
```

---

## Implementation Strategy

### MVP First (Backend Only — US1 + US2 + US3)

1. Complete Phase 1: Prompt files (T001–T005)
2. Complete Phase 2: Foundation (T006–T011)
3. Complete Phase 3: US1 Intake & Idol Discovery (T012–T015)
4. Complete Phase 4: US2 Interview (T016–T018)
5. Complete Phase 5: US3 Comparison (T019)
6. **STOP and VALIDATE**: Test full intake → interview → comparison flow via curl
7. Verify with `pytest tests/ -v`

### Incremental Delivery

1. MVP backend (US1–US3) → Test via curl → Working comparison
2. Add US4 Blueprint (T020) → Test → Full 5-phase backend complete
3. Add US5 Resume (T021–T022) → Test → Backend 100% done
4. Flutter State (T023–T025) → Flutter API layer ready
5. Flutter UI (T026–T031) → Full app functional
6. Polish & Tests (T032–T036) → Ship-ready

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US1–US3 are sequential dependencies (each needs the prior phase's output)
- US4 depends on US3; US5 is mostly verification of existing endpoints
- Flutter phases (8–9) can start in parallel with backend once API contracts are finalized (Phase 2)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
