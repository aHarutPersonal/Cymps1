---
trigger: always_on
---

# CMPYS - Architectural Decisions & Contracts

## 1. Data Flow & Sync
- **Source of Truth:** PostgreSQL (Backend).
- **Transport:** REST API (JSON).
- **Serialization:**
  - Python: `snake_case` (DB & API output).
  - Flutter: `camelCase` (Internal Logic).
  - **Rule:** Flutter models MUST use `@JsonKey(name: 'snake_case_field')` to map fields.

## 2. Idol Import Pipeline (Async)
- **Trigger:** User requests import via `POST /idols/import`.
- **Immediate Response:** Returns `Idol` object with `is_ready: false`.
- **Background:** Celery worker fetches Wikidata -> LLM Extraction -> Updates DB `is_ready: true`.
- **Frontend polling:** Frontend polls `GET /idols/{id}` every 3s until `is_ready: true`.

## 3. Plan Generation (Scaffolding)
- **Input:** User Readiness Gap + Idol Timeline.
- **Output:** 12-Week Plan (JSON).
- **Constraint:** Plans are immutable once generated, except for "checkbox" states (completion).

## 4. Chat System
- **Persona:** Stored in `Idol.persona_pack` (JSON).
- **Guardrails:** Output must be filtered for "Modern Jargon" before sending to frontend.
- **UI:** Messages are strictly text. No markdown rendering in chat bubbles except strictly controlled links.