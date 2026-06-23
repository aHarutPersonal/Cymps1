# Research: Agentic Persona Workflow Refactoring

**Feature**: `001-agentic-refactor`
**Date**: 2026-02-20
**Status**: Complete

## R1: Gemini Web Search Grounding in Existing Codebase

**Decision**: Extend the existing `gemini.py` service — do NOT add a new provider.

**Rationale**: `app/services/gemini.py` already imports `google.genai` and has a working
`stream_with_grounding()` function that enables `GoogleSearch` tool via
`types.Tool(google_search=types.GoogleSearch())`. This is exactly the mechanism
needed for factual idol achievement retrieval and resource discovery. No new SDK
installation required (`google-genai` is already a dependency).

**Alternatives considered**:
- Adding Gemini as a `BaseLLMClient` subclass in `llm/client.py` — rejected because
  the existing client interface is designed for structured JSON generation, not
  streaming grounded chat. Gemini's grounding tool returns inline citations that
  don't fit the `generate_json()` → Pydantic validation flow.
- Using OpenAI for all phases — rejected because the user explicitly requires Gemini
  with Google Search grounding for factual accuracy.

## R2: State Machine for the 5-Phase Agentic Workflow

**Decision**: Add a new `SessionPhase` enum and `phase` column to the existing
`IntakeSession` model. Extend `ChatThread` with `session_id` FK to link the
interview chat to the session's state machine.

**Rationale**: The existing `IntakeSession` model already tracks `user_id`, `idol_id`,
`status`, and `questions_json`. It's the natural home for phase tracking. The existing
`ChatThread` model handles message persistence. Linking them via FK creates the
context chain: Session → (Intake + Idol + Interview Chat + Comparison + Blueprint).

**Alternatives considered**:
- Separate `AgenticSession` model — rejected (violates YAGNI; `IntakeSession` already
  has the right relationships).
- Client-side-only state — rejected (session must survive app restarts per FR-009).

## R3: FlintK12-Style XML System Prompt Architecture

**Decision**: Create a new prompt file `prompts/interview_system.xml` containing the
full XML-structured system prompt. The `prompt_loader.py` already supports loading
any `.txt` file — extend it to also load `.xml` files. The prompt will be injected
into Gemini's `system_instruction` parameter.

**Rationale**: The existing `chat_system.txt` is a flat text persona prompt suited for
general conversation. The new interview workflow needs a fundamentally different
prompt structure with XML directives for phase-specific behavior (interrogation,
reality check, blueprint). Keeping it as a separate prompt file preserves the
existing chat functionality and follows the "prompts in `/prompts/`" constitution rule.

**Alternatives considered**:
- Modifying `chat_system.txt` in-place — rejected (would break existing general chat).
- Hardcoded inline prompt — rejected (violates Constitution Principle V: LLM Isolation).

## R4: Turn-Count Enforcement

**Decision**: Backend enforces turn count, not frontend. The interview endpoint
returns a `phase_transition` field when `turn_count >= 3` and the AI signals
completion (or hard cap at 5). Frontend reads this flag and transitions UI.

**Rationale**: Server-side enforcement is authoritative and prevents manipulation.
The existing `send_message_stream` SSE response can include metadata in the
`done` event payload. Frontend already handles SSE `done` events.

**Alternatives considered**:
- Frontend-only enforcement — rejected (can be bypassed, violates state consistency).
- Separate "check-phase" endpoint — rejected (adds unnecessary round-trip).

## R5: Context Passing for Comparison & Blueprint

**Decision**: The comparison/blueprint endpoint receives `session_id` only. The
backend loads all context (intake, idol, interview messages) from the database.
No client-side context assembly.

**Rationale**: Full interview history is already persisted in `ChatMessage` rows.
Loading from DB is simpler, more reliable, and prevents payload size issues. This
follows Constitution Principle I (PostgreSQL Is Truth).

**Alternatives considered**:
- Client sends full chat history in request body — rejected (large payload, data
  duplication, potential inconsistency with DB state).

## R6: Flutter State Management

**Decision**: Extend existing Riverpod providers with a `SessionNotifier` that tracks
`SessionPhase` and wraps existing providers (intake, chat, comparison, plans).

**Rationale**: The Flutter app already uses Riverpod. Adding a coordinating notifier
preserves existing provider logic while adding phase-aware transitions. No state
management library change needed.

**Alternatives considered**:
- Switching to BLoC — rejected (unnecessary migration, Riverpod already in use).
- Single monolithic provider — rejected (would violate Riverpod best practices).
