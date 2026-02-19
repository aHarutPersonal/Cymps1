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
| `{idol_name}` | string | Name of the idol |
| `{idol_profile_json}` | JSON string | Idol profile data |
| `{idol_milestones_json}` | JSON string | Idol's milestones at target age |
| `{user_profile_json}` | JSON string | User profile data |
| `{target_age}` | string | User's target age |
| `{gaps_json}` | JSON string | Array of category gaps |
| `{allowed_resources_json}` | JSON string | Array of allowed resources (or "[]") |

**Used by:**
- `_generate_llm_items()` in `app/services/planning/generator.py`

**Endpoint mapping:**
- `POST /api/v1/plans/generate` (when PLAN_GENERATOR_MODE=llm)

---

### 7. `chat_system.txt`

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
