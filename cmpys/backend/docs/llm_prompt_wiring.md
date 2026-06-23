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
| `Job: regenerate_details` | `tasks.plans.regenerate_plan_item_details` | `plan_item_details.txt` | Generates steps and materials for a specific item. **Now validates content depth and retries once if lesson_content < 300 words or content_markdown < 400 words.** |
| Content resource creation | `services.content_resources.generate_book_module` | `book_module_generate.txt` | Generates 15-minute book summary module. **Now requires 2,500-4,000 word content_markdown and validates word count with retry.** |

### 4. Chat
**Context**: 1-on-1 first-person messaging.

| Endpoint | Logic Location | Prompt File | Description |
| :--- | :--- | :--- | :--- |
| `POST /chat/.../message` | `services.chat.responder.generate_reply` | `chat_system.txt` | System prompt defining the persona and constraints. |
| `POST /chat/.../message` | `services.chat.responder.generate_reply` | `chat_reply.txt` | User prompt containing history and current message. |

### 5. Content Resources
**Context**: Generating and deduplicating learning materials.

| Endpoint / Job | Logic Location | Prompt File | Description |
| :--- | :--- | :--- | :--- |
| Content creation | `services.content_resources.generate_book_module` | `book_module_generate.txt` | Generates book module with content_markdown (2,500-4,000 words). Validates word count >= 1,500 and retries once if too thin. |
| Content creation | `services.content_resources.get_or_create_book_module_resource` | (uses above) | Orchestrates book module creation with public domain lookup fallback. |

### Content Quality Pipeline

The content generation pipeline now includes validation and retry:

1. **Plan Generation** (`plan_generate.txt`):
   - `BinaryTask` schema enforces `description` min_length=10
   - `estimated_hours` and `daily_instructions` preserved from LLM output
   - `daily_instructions` requires 3-5 sentences (40-80 words)
   - Rendering is strict and includes structured idol profile, persona, milestones, gaps, readiness, user context, and target age.

2. **Plan Item Details** (`plan_item_details.txt`):
   - Each `lesson_content` must be 500-1,200 words (800+ if step claims 60+ min)
   - Each material `content_markdown` must be 600-1,000 words
   - Backend validates word counts and retries once if content is too thin
   - Idol name and idol domain are passed into the prompt so examples stay mentor-specific.

3. **Book Modules** (`book_module_generate.txt`):
   - `content_markdown` must be 2,500-4,000 words
   - Backend validates word count >= 2,500 and retries once with stronger prompt
   - `duration_minutes` calculated from word count (words / 200) instead of hardcoded

4. **Duration Accuracy**:
   - All `duration_minutes` values calculated from actual word count using formula `max(5, round(word_count / 200))`
   - No hardcoded duration values remain
To verify prompt validity and placeholder completeness:

```bash
cd backend
pytest tests/test_prompt_placeholders.py
```
