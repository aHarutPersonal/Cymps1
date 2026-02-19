# LLM Prompt Wiring

This document maps the prompt templates in `prompts/` to the backend endpoints and jobs that verify and use them.

## Overview

All prompts are loaded via `app.services.llm.prompt_loader`, which handles:
1.  Loading the `.txt` template.
2.  Interpolating placeholders (raising error if missing).
3.  Injecting into the LLM context.

## Mappings

### 1. Idol Discovery & Import
**Context**: Finding idols and extracting data from Wikipedia.

| Endpoint / Job | Logic Location | Prompt File | Description |
| :--- | :--- | :--- | :--- |
| `GET /idols/suggest` | `api.v1.idols.suggest_idols` | `idol_suggest.txt` | Suggests idols based on user interests. |
| `Job: run_idol_ingestion` | `services.ingestion.extract.run_profile_extraction` | `profile_extract.txt` | Extracts structured profile from Wiki chunks. |
| `Job: run_idol_ingestion` | `services.ingestion.extract.run_achievements_extraction` | `achievements_extract.txt` | Extracts achievement candidates from Wiki chunks. |
| `Job: run_idol_ingestion` | `services.ingestion.extract.run_timeline_normalization` | `timeline_normalize.txt` | Normalizes and dedupes achievements into timeline. |
| `Job: run_idol_ingestion` | `services.ingestion.extract.run_persona_pack` | `persona_pack.txt` | Generates persona traits (voice, principles) from profile. |

### 2. Intake & Onboarding
**Context**: Gathering user info to personalize the plan.

| Endpoint | Logic Location | Prompt File | Description |
| :--- | :--- | :--- | :--- |
| `POST /intake/start` | `api.v1.intake._generate_questions` | `intake_questions_generate.txt` | Generates 5-10 personalized questions for the user. |
| `POST /intake/{id}/finish` | `api.v1.intake._normalize_answers` | `intake_answers_normalize.txt` | Analyzes answers to output profile patch and readiness. |

### 3. Plan Generation
**Context**: Creating the 12-week schedule.

| Endpoint / Job | Logic Location | Prompt File | Description |
| :--- | :--- | :--- | :--- |
| `POST /plans/generate` | `services.planning.generator.generate_plan` | `extractor_system.txt` | System prompt for JSON extraction constraint. |
| `POST /plans/generate` | `services.planning.generator.generate_plan` | `plan_generate.txt` | Generates high-level 12-week plan items. |
| `Job: regenerate_details` | `tasks.ingestion.regenerate_plan_item_details` | `plan_item_details.txt` | Generates steps and materials for a specific item. |

### 4. Chat
**Context**: 1-on-1 first-person messaging.

| Endpoint | Logic Location | Prompt File | Description |
| :--- | :--- | :--- | :--- |
| `POST /chat/.../message` | `services.chat.responder.generate_reply` | `chat_system.txt` | System prompt defining the persona and constraints. |
| `POST /chat/.../message` | `services.chat.responder.generate_reply` | `chat_reply.txt` | User prompt containing history and current message. |

## Verification
To verify prompt validity and placeholder completeness:

```bash
cd backend
pytest tests/test_prompt_placeholders.py
```
