# Data Model: Agentic Persona Workflow Refactoring

**Feature**: `001-agentic-refactor`
**Date**: 2026-02-20

## Modified Entities

### IntakeSession (MODIFY `app/models/intake.py`)

Add phase tracking to the existing model:

| Field | Type | Change | Description |
|-------|------|--------|-------------|
| `phase` | `SessionPhase` (enum) | **ADD** | Current workflow phase (1–5) |
| `user_age` | `int` | **ADD** | User's age from intake |
| `user_financial_status` | `str` | **ADD** | User's financial/life status |
| `user_interests` | `JSONB` | **ADD** | User's interest keywords (list) |
| `interview_thread_id` | `UUID FK → chat_threads.id` | **ADD** | Links to the interview chat thread |
| `interview_turn_count` | `int` | **ADD** | Current turn count in Phase 3 (0–5) |
| `comparison_output` | `TEXT` | **ADD** | Generated reality check text |
| `blueprint_output` | `TEXT` | **ADD** | Generated Q1–Q4 blueprint Markdown |
| `idol_facts_json` | `JSONB` | **ADD** | Cached web-searched idol facts at user's age |

```python
class SessionPhase(str, Enum):
    INTAKE = "intake"                # Phase 1
    IDOL_SELECTION = "idol_selection" # Phase 2
    INTERVIEW = "interview"          # Phase 3
    COMPARISON = "comparison"        # Phase 4
    BLUEPRINT = "blueprint"          # Phase 5
    COMPLETED = "completed"
```

**State transitions**:
- `INTAKE` → `IDOL_SELECTION` (when intake data submitted)
- `IDOL_SELECTION` → `INTERVIEW` (when idol selected)
- `INTERVIEW` → `COMPARISON` (when `interview_turn_count` ≥ 3 and AI signals done, or hard cap at 5)
- `COMPARISON` → `BLUEPRINT` (auto after comparison generated)
- `BLUEPRINT` → `COMPLETED` (after blueprint generated and stored)

### ChatThread (MODIFY `app/models/chat.py`)

No model changes needed — the existing `ChatThread` links to `idol_id` and `user_id`.
The `IntakeSession.interview_thread_id` creates the reverse link.

### LLM Schemas (ADD to `app/services/llm/schemas.py`)

| Schema | Purpose |
|--------|---------|
| `InterviewQuestionResponse` | LLM output: single question + emotional_reaction |
| `ComparisonResponse` | LLM output: reality check text with cited idol achievements |
| `BlueprintResponse` | LLM output: Q1–Q4 Markdown with resource URLs |
| `IdolSuggestion` | LLM output for idol suggestion: name, era, relevance_summary |
| `IdolSuggestionsResponse` | Wrapper: list of 3 `IdolSuggestion` items |

## New Prompt Files

| File | Used By | Grounding |
|------|---------|-----------|
| `prompts/interview_system.xml` | Phase 3 interview endpoint | Gemini + Google Search |
| `prompts/interview_question.txt` | Phase 3 per-turn user prompt | — |
| `prompts/comparison_generate.txt` | Phase 4 comparison generation | Gemini + Google Search |
| `prompts/blueprint_generate.txt` | Phase 5 blueprint generation | Gemini + Google Search |
| `prompts/idol_suggest.txt` | Phase 2 idol suggestions | Gemini + Google Search |

## Unchanged Entities

The following existing models are NOT modified:
- `User`, `UserProfile`, `UserAchievement`
- `Idol`, `IdolProfile`, `IdolPersona`, `IdolTimelineEvent`, `IdolAchievement`
- `Plan`, `PlanItem` (existing plan system remains independent)
- `Note`, `NoteAttachment`
- `ChatMessage` (existing message model works as-is)
