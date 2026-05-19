# API Contracts: Agentic Persona Workflow

> Canonical update: prompt/API ownership for the current roadmap lives in `cmpys/backend/docs/prompt_contracts.md` and `cmpys/backend/docs/api_reference.md`. Blueprint output is a strategic verdict; plan and daily endpoints are the execution contract.

**Feature**: `001-agentic-refactor`
**Date**: 2026-02-20
**Base Path**: `/api/v1`

All endpoints are additions or modifications to the existing API surface.
Existing endpoints not listed here remain unchanged.

---

## Session Management

### POST `/api/v1/sessions`
Create a new agentic session (enters Phase 1: Intake).

**Request**:
```json
{
  "age": 28,
  "financial_status": "$6,000/month salary, no investments",
  "interests": ["military strategy", "leadership", "empire building"]
}
```

**Response** (201):
```json
{
  "id": "uuid",
  "phase": "intake",
  "user_age": 28,
  "user_financial_status": "$6,000/month salary, no investments",
  "user_interests": ["military strategy", "leadership", "empire building"],
  "created_at": "2026-02-20T12:00:00Z"
}
```

---

### GET `/api/v1/sessions/{session_id}`
Get current session state (used for polling/resume).

**Response** (200):
```json
{
  "id": "uuid",
  "phase": "interview",
  "user_age": 28,
  "user_financial_status": "...",
  "user_interests": ["..."],
  "selected_idol": { "id": "uuid", "name": "Alexander the Great", "era": "Ancient" },
  "interview_turn_count": 2,
  "comparison_output": null,
  "blueprint_output": null,
  "interview_thread_id": "uuid",
  "created_at": "...",
  "updated_at": "..."
}
```

---

## Phase 2: Idol Suggestion

### POST `/api/v1/sessions/{session_id}/suggest-idols`
Generate 3 idol suggestions based on intake data. Uses Gemini + Google Search.

**Request**: None (data from session)

**Response** (200):
```json
{
  "suggestions": [
    {
      "name": "Alexander the Great",
      "era": "356–323 BC",
      "relevance_summary": "Conquered half the known world by age 30...",
      "image_url": "https://...",
      "wikidata_id": "Q8409"
    },
    { "...": "..." },
    { "...": "..." }
  ]
}
```

---

### POST `/api/v1/sessions/{session_id}/select-idol`
User selects an idol. Transitions session to Phase 3.

**Request**:
```json
{
  "idol_name": "Alexander the Great",
  "wikidata_id": "Q8409"
}
```

**Response** (200):
```json
{
  "session_id": "uuid",
  "phase": "interview",
  "selected_idol": { "id": "uuid", "name": "Alexander the Great" },
  "interview_thread_id": "uuid"
}
```

---

## Phase 3: Live Interview

### POST `/api/v1/sessions/{session_id}/interview`
Send a user answer and receive the next in-character question.
SSE streaming response.

**Request**:
```json
{
  "content": "I make $6,000/month and lead a team of 2."
}
```

**Response** (SSE stream):
```
data: {"type": "chunk", "content": "Only $6,000..."}
data: {"type": "chunk", "content": " while I had already..."}
data: {"type": "done", "turn_count": 2, "phase": "interview", "phase_transition": false}
```

When `turn_count >= 3` and AI signals completion (or hard cap at 5):
```
data: {"type": "done", "turn_count": 5, "phase": "comparison", "phase_transition": true}
```

---

## Phase 4 & 5: Comparison + Blueprint

### POST `/api/v1/sessions/{session_id}/generate-results`
Generates both the Brutal Reality Check (Phase 4) and the Quarterly Blueprint
(Phase 5) in a single streaming request. Uses full session context from DB.

**Request**: None (all context loaded from session + interview messages)

**Response** (SSE stream):
```
data: {"type": "section", "section": "comparison"}
data: {"type": "chunk", "content": "I am Alexander. By 28, I had..."}
...
data: {"type": "section", "section": "blueprint"}
data: {"type": "chunk", "content": "## Q1: Foundation & First Blood\n..."}
...
data: {"type": "done", "phase": "completed"}
```

---

## Error Responses

All endpoints return standard error format:

```json
{
  "detail": "Session not found" | "Invalid phase transition" | "LLM not configured"
}
```

| Code | Scenario |
|------|----------|
| 400 | Invalid intake data, wrong phase for action |
| 403 | Session belongs to another user |
| 404 | Session or idol not found |
| 409 | Phase transition conflict (e.g., trying to interview when already in comparison) |
| 503 | Gemini API not configured or unavailable |
