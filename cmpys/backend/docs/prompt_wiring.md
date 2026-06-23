# CMPYS Prompt Wiring Documentation

This document describes all prompt template files, their required parameters, and which endpoints/services use them.

## Overview

Prompts are stored as `.txt` files in the `/prompts` directory. The backend renders these templates by substituting `{placeholder}` variables with runtime values.

**Key Files:**
- `app/services/llm/prompt_loader.py` - Loads and renders prompts with validation
- `app/services/ingestion/extract.py` - Extraction pipeline using prompts
- `app/services/chat/responder.py` - Chat service using prompts
- `app/services/planning/generator.py` - Plan generation using prompts

---

## Prompt Registry

### 1. `extractor_system.txt`

**Purpose:** System prompt for all extraction operations.

**Placeholders:** NONE (pure system prompt)

**Used by:**
- All extraction functions in `app/services/ingestion/extract.py`
- Plan generation in `app/services/planning/generator.py`
- Milestones queries

**Endpoint mapping:**
- Background: Ingestion job via `run_idol_ingestion()` Celery task
- `POST /plans/generate` (when LLM mode enabled)

---

### 2. `profile_extract.txt`

**Purpose:** Extract canonical idol profile from Wikipedia/source content.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{selected_name}` | string | Idol name to extract |
| `{provider}` | string | Source provider (e.g., "wikidata", "wikipedia") |
| `{external_id}` | string | External identifier (e.g., Wikidata QID) |
| `{wikipedia_url}` | string | Wikipedia URL hint (or "null") |
| `{sources_json_array}` | JSON string | Array of source chunks |

**Used by:**
- `run_profile_extraction()` in `app/services/ingestion/extract.py`

**Endpoint mapping:**
- Background: Ingestion job (Step 2: extracting_profile)

---

### 3. `achievements_extract.txt`

**Purpose:** Extract actionable achievements/milestones from sources.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{idol_name}` | string | Name of the idol |
| `{sources_json_array}` | JSON string | Array of source chunks |

**Used by:**
- `run_achievements_extraction()` in `app/services/ingestion/extract.py`

**Endpoint mapping:**
- Background: Ingestion job (Step 3: extracting_achievements)

---

### 4. `timeline_normalize.txt`

**Purpose:** Normalize, deduplicate, and compute ages for achievement candidates.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{idol_birth_date}` | string | Birth date "YYYY-MM-DD" or "null" |
| `{candidates_json}` | JSON string | Array of achievement candidates |

**Used by:**
- `run_timeline_normalization()` in `app/services/ingestion/extract.py`

**Endpoint mapping:**
- Background: Ingestion job (Step 4: normalizing_timeline)

---

### 5. `milestones_by_age.txt`

**Purpose:** Select relevant milestones for a target age from normalized timeline.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{target_age}` | string | Target age as integer string |
| `{mode}` | string | "exact" or "up_to" |
| `{timeline_json}` | JSON string | Array of timeline events |

**Used by:**
- `run_milestones_by_age()` in `app/services/ingestion/extract.py`

**Endpoint mapping:**
- Not directly exposed (internal use for comparison/planning)

---

### 6. `plan_generate.txt`

**Purpose:** Generate personalized 12-week development plan inspired by idol's journey.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{user_goal}` | string | User's primary goal |
| `{hours_per_week}` | string | Weekly time commitment |
| `{target_age}` | string | User's target age |
| `{user_context}` | string | User context (age, interests, achievements) |
| `{idol_name}` | string | Name of the idol |
| `{idol_profile_json}` | JSON string | Idol profile data |
| `{idol_persona_json}` | JSON string | Idol persona (voice, principles) |
| `{idol_milestones_json}` | JSON string | Idol's milestones at target age |
| `{gaps_json}` | JSON string | Array of category gaps |
| `{readiness_by_gap_json}` | JSON string | User readiness per gap category |

**Content Depth Requirements (P0-C):**
- Mission task descriptions must be >= 50 words with specific books, chapters, exercises
- Daily rhythm descriptions must be >= 30 words with specific, measurable actions
- `primary_mission` must be >= 30 words referencing specific skill/deliverable
- `daily_instructions` must be 3-5 sentences (40-80 words)
- `estimated_hours` and `daily_instructions` are now preserved in the schema (not dropped)

**Schema:** `BinaryTask` now includes `estimated_hours: float` and `daily_instructions: str | None`

**Used by:**
- `_generate_llm_items()` in `app/services/planning/generator.py`

**Endpoint mapping:**
- `POST /api/v1/plans/generate` (when PLAN_GENERATOR_MODE=llm)

**Contract:** Production rendering is strict. If any required variable is missing or an unresolved `{placeholder}` remains after rendering, plan generation falls back instead of sending a broken prompt to the LLM.

---

### 7. `plan_item_details.txt`

**Purpose:** Generate detailed steps, lessons, and materials for a specific plan item.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{task_title}` | string | Plan item title |
| `{user_goal}` | string | User's primary goal |
| `{learning_preferences}` | string | User's learning preferences |
| `{idol_name}` | string | Idol/mentor name |
| `{idol_domain}` | string | Idol/mentor field or domain |

**Content Depth Requirements (P0-B):**
- Each step's `lesson_content` must be 500-1,200 words (800+ if step claims 60+ min)
- Each material's `content_markdown` must be 600-1,000 words (for book and in_app_lesson types)
- Steps must TEACH, not advise — no "practice regularly" or "read this book"
- Anti-filler-language rule: no "Let's dive in", "It's important to note"
- Each step includes: opening context, core concept explanation, real-world example, practice guide, reflection

**Endpoint mapping:**
- `Job: regenerate_plan_item_details` (Celery background task)

**Storage and UI consumers:** The normalized details are stored in `PlanItem.details_json` and rendered by task detail, in-app lessons, materials, and Library links.

---

### 8. `book_module_generate.txt`

**Purpose:** Generate a reusable 15-minute book summary module with substantial learning content.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{book_title}` | string | Book title |
| `{author}` | string | Author name |
| `{user_goal}` | string | User's primary goal |
| `{source_context}` | string | Source context or "No source context available." |

**Content Depth Requirements (P0-A):**
- `content_markdown` must be 2,500-4,000 words
- Each section must have `summary` of 80-150 words and `exercise` of 40-80 words
- Each idea card must have `content` of 40-80 words with specific example + actionable takeaway
- Content must include: opening hook, ## headings, ### exercise subheadings, **bold** key terms, concrete examples per section, closing synthesis
- Quality rule: "Every claim must reference a specific event, quote, or decision from {author}'s life"

**Validation:** Backend validates word count >= 1,500 and retries once with stronger prompt if too thin.

**Endpoint mapping:**
- `services.content_resources.generate_book_module()` (called during content resource creation)

---

### 9. `chat_system.txt`

**Purpose:** System prompt for idol persona chat simulation.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{idol_name}` | string | Name of the idol |
| `{voice_style}` | string | Voice/tone description |
| `{principles}` | string | Newline-separated principles |
| `{dos}` | string | Things the persona should do |
| `{donts}` | string | Things the persona should avoid |
| `{signature_phrases}` | string | Characteristic phrases |
| `{topics_of_strength}` | string | Topics they excel at |
| `{grounding_facts_json}` | JSON string | Verified facts (milestones/themes) |
| `{user_context_json}` | JSON string | User context (age/interests/progress) |
| `{disclaimer}` | string | Safety disclaimer text |

**Used by:**
- `generate_reply()` in `app/services/chat/responder.py`

**Endpoint mapping:**
- `POST /api/v1/chat/threads/{thread_id}/messages`

---

### 8. `chat_reply.txt`

**Purpose:** Generate assistant reply for a chat turn.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{user_profile_json}` | JSON string | User profile data |
| `{idol_profile_json}` | JSON string | Idol profile data |
| `{idol_persona_json}` | JSON string | Idol persona pack |
| `{target_age}` | string | User's target age |
| `{comparison_json}` | JSON string | Comparison summary (or "null") |
| `{milestones_json}` | JSON string | Idol milestones at target age |
| `{evidence_snippets_json}` | JSON string | Evidence snippets (or "[]") |
| `{conversation_history_json}` | JSON string | Array of conversation messages |
| `{user_message}` | string | Current user message |

**Used by:**
- `generate_reply()` in `app/services/chat/responder.py`

**Endpoint mapping:**
- `POST /api/v1/chat/threads/{thread_id}/messages`

---

### 9. `idol_discover.txt`

**Purpose:** Suggest notable people as role models based on interests.

**Placeholders:**
| Placeholder | Type | Description |
|-------------|------|-------------|
| `{interests_json_array}` | JSON string | Array of user interests |
| `{user_age}` | string | User's age (or "null") |
| `{limit}` | string | Max number of candidates |

**Used by:**
- `suggest_idols()` in `app/api/v1/idols.py`

**Endpoint mapping:**
- `GET /api/v1/idols/suggest?interests=...&source=llm`

---

### 10. `persona_pack.txt`

**Purpose:** Generate chat persona pack for idol simulation.

**Placeholders:** Uses f-string injection (not `render_prompt`)

**Used by:**
- `run_persona_pack()` in `app/services/ingestion/extract.py`

**Endpoint mapping:**
- Background: Ingestion job (Step 5: generating_persona)

---

## Parameter Rules

### JSON Parameters

Any placeholder ending with `_json` or `_json_array` must be passed as a JSON-serialized string:

```python
# Good
render_prompt(template, {
    "gaps_json": json.dumps(["career", "finance"]),
    "idol_profile_json": json.dumps(profile_dict, indent=2),
})

# Bad - will produce Python repr not JSON
render_prompt(template, {
    "gaps_json": ["career", "finance"],  # Wrong!
})
```

### Null Handling

- For optional string fields, use `"null"` (the string) not Python `None`
- The `render_prompt()` function automatically converts `None` to `"null"`

### Validation

The `render_prompt()` function can validate required placeholders:

```python
from app.services.llm.prompt_loader import render_prompt, PromptRenderError

try:
    result = render_prompt(
        template,
        variables,
        prompt_name="profile_extract.txt",  # Enable validation
        strict=True,
    )
except PromptRenderError as e:
    # e.missing_keys contains list of missing parameters
    logger.error(f"Missing params: {e.missing_keys}")
```

---

## Debugging

### Check which prompts are loaded

```python
from app.services.llm.prompt_loader import get_loaded_prompts
print(get_loaded_prompts())  # ['chat_reply.txt', 'chat_system.txt', ...]
```

### Get required placeholders for a prompt

```python
from app.services.llm.prompt_loader import get_required_placeholders
print(get_required_placeholders("plan_generate"))
# ['idol_name', 'idol_profile_json', ...]
```

### Validate before rendering

```python
from app.services.llm.prompt_loader import validate_prompt_params

missing = validate_prompt_params("chat_reply.txt", my_params)
if missing:
    raise ValueError(f"Missing: {missing}")
```

---

## Adding New Prompts

1. Create the `.txt` file in `/prompts/`
2. Add placeholder registry entry in `prompt_loader.py`:
   ```python
   PROMPT_PLACEHOLDERS = {
       ...
       "my_new_prompt.txt": [
           "required_param_1",
           "required_param_2_json",
       ],
   }
   ```
3. Add service registry entry if applicable:
   ```python
   PROMPT_REGISTRY = {
       "my_service": {
           "my_operation": ["extractor_system.txt", "my_new_prompt.txt"],
       },
   }
   ```
4. Update this documentation
