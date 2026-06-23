# Implementation Plan: Agentic Persona Workflow

> Canonical update: this historical implementation plan is superseded for product direction by `cmpys/business/product_strategy.md`, `fe/cmpys/docs/UX_SPEC.md`, and `cmpys/backend/docs/prompt_contracts.md`. The current product spine is agentic activation -> 12-week execution -> daily retention.

**Branch**: `001-agentic-refactor` | **Date**: 2026-02-20 | **Spec**: [spec.md](file:///Users/harutantonyan/work/specs/001-agentic-refactor/spec.md)
**Input**: Feature specification from `/specs/001-agentic-refactor/spec.md`

## Summary

Refactor the existing CMPYS Python backend and Flutter frontend to implement a
5-Phase Agentic Workflow (Intake → Idol Selection → Live Interview → Brutal
Comparison → Quarterly Blueprint). The backend gains a `SessionPhase` state
machine in the existing `IntakeSession` model, new Gemini-powered endpoints with
Google Search grounding for factual accuracy, and a FlintK12-style XML system
prompt for deep persona immersion. The Flutter frontend gains a coordinating
`SessionNotifier` in Riverpod and refactored screens for the interview chat loop
and Markdown-rendered blueprint display.

**Critical constraint**: This is a refactoring of an existing, functional
application. No new tech stack. No boilerplate generation. Every change targets
specific existing files.

## Technical Context

**Language/Version**: Python 3.11+ (Backend), Dart/Flutter latest stable (Frontend)
**Primary Dependencies**: FastAPI, SQLAlchemy 2.x, google-genai, Celery, Riverpod, Dio
**Storage**: PostgreSQL 16 + Redis 7
**Testing**: pytest (backend), existing test suite
**Target Platform**: Mobile (Flutter) + REST API server
**Project Type**: Mobile + API
**Constraints**: All LLM calls server-side; Gemini API key never exposed to client

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. PostgreSQL Is Truth | ✅ PASS | Session state, interview history, comparison/blueprint all persisted in PG |
| II. Async-by-Default | ✅ PASS | Interview is streaming SSE; comparison+blueprint generation is streaming; idol suggestion may use background task |
| III. Historical Purity | ✅ PASS | Jargon guard remains active; new prompts include explicit jargon ban directives |
| IV. Serialization Contract | ✅ PASS | New session schemas use snake_case in Python; Flutter models use @JsonKey |
| V. LLM Isolation | ✅ PASS | All Gemini calls go through `app/services/gemini.py`; new prompts in `/prompts/` |
| VI. Test-First for Contracts | ✅ PASS | New prompt files registered in PROMPT_PLACEHOLDERS; test_prompt_placeholders covers them |
| VII. Simplicity & YAGNI | ✅ PASS | Reuses existing IntakeSession, ChatThread, ChatMessage models; no new abstractions |

## Project Structure

### Documentation (this feature)

```text
specs/001-agentic-refactor/
├── spec.md              # Feature specification
├── research.md          # Phase 0 research decisions
├── data-model.md        # Phase 1 data model changes
├── quickstart.md        # Verification quickstart
├── contracts/
│   └── api.md           # API endpoint contracts
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── plan.md              # This file
```

### Source Code (repository root)

```text
backend/
├── app/
│   ├── api/v1/
│   │   ├── sessions.py          [NEW] Session management + interview + results endpoints
│   │   └── idols.py             [MODIFY] Minor: idol import may be reused for suggest
│   ├── models/
│   │   ├── intake.py            [MODIFY] Add SessionPhase enum + new columns
│   │   └── chat.py              [VERIFY] No changes expected, confirm FK compatibility
│   ├── schemas/
│   │   ├── session.py           [NEW] Pydantic schemas for session endpoints
│   │   └── chat.py              [VERIFY] Confirm SSE metadata schema
│   ├── services/
│   │   ├── gemini.py            [MODIFY] Add interview_stream(), comparison_stream(), blueprint_stream()
│   │   ├── chat/responder.py    [VERIFY] Existing chat unchanged; interview uses separate flow
│   │   └── llm/
│   │       ├── schemas.py       [MODIFY] Add InterviewQuestionResponse, ComparisonResponse, etc.
│   │       └── prompt_loader.py [MODIFY] Register new prompt placeholders
│   └── tasks/
│       └── sessions.py          [NEW] Optional: background idol suggestion task
├── migrations/
│   └── versions/
│       └── xxx_add_session_phase.py  [NEW] Alembic migration
└── prompts/
    ├── interview_system.xml     [NEW] FlintK12-style XML system prompt
    ├── interview_question.txt   [NEW] Per-turn user prompt template
    ├── comparison_generate.txt  [NEW] Reality check generation prompt
    ├── blueprint_generate.txt   [NEW] Q1–Q4 blueprint generation prompt
    └── idol_suggest.txt         [MODIFY] Update for session-based flow

frontend/ (Flutter - outside current workspace but documented)
├── lib/
│   ├── providers/
│   │   └── session_provider.dart     [NEW] SessionNotifier for 5-phase state
│   ├── models/
│   │   └── session.dart              [NEW] Session model with fromJson/toJson
│   ├── screens/
│   │   ├── intake_screen.dart        [MODIFY] Wire to session creation
│   │   ├── idol_selection_screen.dart [MODIFY] Wire to suggest-idols + select-idol
│   │   ├── interview_screen.dart     [NEW] Chat UI with turn counter + auto-transition
│   │   ├── comparison_screen.dart    [NEW] Reality check display with rich text
│   │   └── blueprint_screen.dart     [NEW] Markdown-rendered Q1–Q4 blueprint
│   └── services/
│       └── session_api.dart          [NEW] Dio client for session endpoints
```

**Structure Decision**: Mobile + API architecture. Backend at `backend/`, Flutter
frontend expected at a separate workspace path. Changes are additive — no existing
files deleted.

---

## Proposed Changes

### Backend — LLM Core (Milestone 1)

#### [NEW] [interview_system.xml](file:///Users/harutantonyan/work/cmpys/prompts/interview_system.xml)
FlintK12-style XML system prompt with `<persona>`, `<core_directives>`, and
`<workflow_rules>` sections. Injected into Gemini's `system_instruction` parameter.
Includes explicit jargon ban, one-question-per-turn rule, and persona voice directives.

#### [NEW] [interview_question.txt](file:///Users/harutantonyan/work/cmpys/prompts/interview_question.txt)
Per-turn user prompt template. Placeholders: `{idol_name}`, `{user_age}`,
`{user_financial_status}`, `{user_interests_json}`, `{chat_history_json}`,
`{turn_count}`, `{max_turns}`, `{idol_facts_json}`.

#### [NEW] [comparison_generate.txt](file:///Users/harutantonyan/work/cmpys/prompts/comparison_generate.txt)
Comparison prompt. Receives full interview transcript + idol facts at user's age.
Instructs first-person, emotionally intense comparison. Placeholder for web-searched
achievements.

#### [NEW] [blueprint_generate.txt](file:///Users/harutantonyan/work/cmpys/prompts/blueprint_generate.txt)
Blueprint prompt. Generates Q1–Q4 Markdown. Instructs Gemini to use Google Search
for real resource URLs. Includes 21st-century adaptation directive.

#### [MODIFY] [gemini.py](file:///Users/harutantonyan/work/cmpys/backend/app/services/gemini.py)
Add three new async generator functions:
- `interview_stream()` — Gemini + Google Search, uses interview_system.xml as
  system_instruction, returns single question + emotional reaction per turn.
- `comparison_stream()` — Gemini + Google Search, generates reality check.
- `blueprint_stream()` — Gemini + Google Search, generates Q1–Q4 blueprint.

All three use the existing `_gemini_client()` helper and same `GoogleSearch` tool
pattern as the existing `stream_with_grounding()`.

#### [MODIFY] [prompt_loader.py](file:///Users/harutantonyan/work/cmpys/backend/app/services/llm/prompt_loader.py)
Register new prompt files in `PROMPT_PLACEHOLDERS` dict. Add `.xml` file
extension support to `load_prompt()`.

#### [MODIFY] [schemas.py](file:///Users/harutantonyan/work/cmpys/backend/app/services/llm/schemas.py)
Add `InterviewQuestionResponse`, `ComparisonResponse`, `BlueprintResponse`,
`IdolSuggestion`, `IdolSuggestionsResponse` Pydantic models.

---

### Backend — API Flow (Milestone 2)

#### [MODIFY] [intake.py](file:///Users/harutantonyan/work/cmpys/backend/app/models/intake.py)
Add `SessionPhase` enum. Add columns: `phase`, `user_age`, `user_financial_status`,
`user_interests`, `interview_thread_id`, `interview_turn_count`,
`comparison_output`, `blueprint_output`, `idol_facts_json`.

#### [NEW] [session.py (schema)](file:///Users/harutantonyan/work/cmpys/backend/app/schemas/session.py)
Pydantic request/response schemas: `SessionCreate`, `SessionResponse`,
`IdolSuggestionResponse`, `SelectIdolRequest`, `InterviewMessageRequest`.

#### [NEW] [sessions.py (API)](file:///Users/harutantonyan/work/cmpys/backend/app/api/v1/sessions.py)
New router with endpoints:
- `POST /sessions` — Create session (Phase 1→2)
- `POST /sessions/{id}/suggest-idols` — Gemini idol suggestions (Phase 2)
- `POST /sessions/{id}/select-idol` — Select idol, create interview thread (Phase 2→3)
- `POST /sessions/{id}/interview` — SSE interview stream (Phase 3, enforces turn count)
- `POST /sessions/{id}/generate-results` — SSE comparison + blueprint (Phase 4→5)
- `GET /sessions/{id}` — Get session state (resume support)

#### [NEW] Alembic migration
`alembic revision --autogenerate -m "add session phase and agentic columns"`

---

### Frontend — State (Milestone 3)

#### [NEW] `session_provider.dart`
Riverpod `StateNotifier<SessionState>` tracking `SessionPhase`, wrapping Dio calls
to session endpoints. Manages phase transitions and holds transient UI state
(current turn count, streaming status).

#### [NEW] `session.dart` (model)
Dart model with `@JsonKey(name: 'snake_case')` annotations matching
`SessionResponse` schema. Includes `SessionPhase` enum.

#### [NEW] `session_api.dart`
Dio service class with methods: `createSession()`, `suggestIdols()`,
`selectIdol()`, `sendInterviewMessage()` (SSE), `generateResults()` (SSE).

---

### Frontend — UI (Milestone 4)

#### [MODIFY] `intake_screen.dart`
Wire Age, Financial Status, Interests form to `createSession()` instead of
existing intake flow.

#### [MODIFY] `idol_selection_screen.dart`
Display 3 idol suggestion cards from `suggestIdols()`. On tap →
`selectIdol()` → navigate to interview.

#### [NEW] `interview_screen.dart`
Chat-style UI with SSE message streaming. Shows turn counter (e.g., "Question 2/5").
Locks input while AI is responding. On `phase_transition: true` in SSE `done` event →
auto-navigate to comparison screen.

#### [NEW] `comparison_screen.dart`
Full-screen display of the brutal reality check. Rich text rendering with
emotional emphasis. "Continue to Blueprint" CTA.

#### [NEW] `blueprint_screen.dart`
`flutter_markdown` rendering of Q1–Q4 blueprint. Section headers, bullet points,
clickable resource URLs. Share/export functionality.

---

## Complexity Tracking

No constitution violations to justify.

---

## Verification Plan

### Automated Tests

**Existing tests to preserve** (must still pass after refactoring):

```bash
cd /Users/harutantonyan/work/cmpys/backend
pytest tests/test_prompt_placeholders.py -v   # Validates all prompt placeholders resolve
pytest tests/test_jargon_guard.py -v           # Validates jargon filtering
pytest tests/test_plan_completion.py -v        # Validates plan logic
pytest tests/test_wikidata.py -v               # Validates Wikidata integration
pytest tests/test_wikipedia.py -v              # Validates Wikipedia integration
```

**New tests to add**:

1. `tests/test_session_phase.py` — Unit tests for `SessionPhase` state transitions:
   - Valid transitions (INTAKE→IDOL_SELECTION→INTERVIEW→COMPARISON→BLUEPRINT→COMPLETED)
   - Invalid transitions (e.g., INTAKE→COMPARISON) raise error
   - Turn count enforcement (transition at 3–5, reject at <3)

2. `tests/test_interview_prompt.py` — Validate new prompt file placeholders:
   - `interview_system.xml` loads without error
   - `interview_question.txt` renders with all required variables
   - `comparison_generate.txt` renders with all required variables
   - `blueprint_generate.txt` renders with all required variables

3. `tests/test_session_api.py` — Integration tests for session endpoints:
   - Create session → returns `phase: intake`
   - Suggest idols → returns 3 suggestions
   - Select idol → transitions to `phase: interview`
   - Full interview flow mock (3 turns) → transitions to comparison

Run all tests:
```bash
cd /Users/harutantonyan/work/cmpys/backend
pytest tests/ -v
```

### Manual Verification

1. **Gemini connectivity**: After setting `GEMINI_API_KEY`, run:
   ```bash
   curl http://localhost:8000/api/v1/debug/llm
   ```
   Verify `gemini_configured: true` in the response.

2. **Full 5-phase flow via curl**: Follow the steps in [quickstart.md](file:///Users/harutantonyan/work/specs/001-agentic-refactor/quickstart.md).

3. **Flutter UI testing**: User manually tests on a device/emulator:
   - Enter intake data → see 3 idol cards → select one → interview chat opens
   - Answer 3–5 questions → chat auto-locks → comparison appears
   - Tap "Continue" → blueprint renders with Q1–Q4 headers and clickable URLs
