# CMPYS API Reference

Base URL: `/api/v1`. All endpoints except auth require
`Authorization: Bearer <access_token>`. SSE endpoints respond with
`text/event-stream`; each line is `data: {json}`.

## Auth — `/auth`

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/register` | `{email, password, fullName}` | `{accessToken, refreshToken, …}` |
| POST | `/login` | `{email, password}` | tokens |
| POST | `/refresh` | `{refreshToken}` | tokens |

## Sessions — `/sessions`

| Method | Path | Notes |
|---|---|---|
| POST | `` | Create from `{age, financial_status, interests}`. → `idol_selection`. **409** if an active session exists. |
| POST | `/{id}/suggest-idols` | LLM mentor suggestions: `{suggestions:[{name, era, relevance_summary, confidence, wikidata_id, domains}]}`. |
| POST | `/{id}/select-idol` | `{idol_name, wikidata_id?}` → `interview`. |
| POST | `/{id}/interview` | **SSE.** Body `{content}`. Events: `status`, `chunk{content}`, `done{turn, max_turns, phase_transition}`, `error{message}`. |
| POST | `/{id}/generate-results` | **SSE.** Events: `status`, `section{section: comparison\|blueprint}`, `chunk{section, content}`, `done`, `error`. |
| POST | `/{id}/guided-learning` | **SSE.** Body `{content}`. Events: `chunk{content}`, `done`, `error`. |
| GET | `/{id}/feed` | Per-session daily insight cards. |
| GET | `/current` | Most recent non-completed session, or `null`. |
| GET | `/latest` | Most recent session including completed, or `null`. |
| DELETE | `/current` | Abandons (force-completes) active session(s). `{abandoned: bool}`. |
| GET | `/{id}` | Full session state. |

### Session response shape

```jsonc
{
  "id": "uuid",
  "phase": "interview",
  "user_age": 25,
  "user_financial_status": "early_career",
  "user_interests": ["Building a startup", "Reading"],
  "selected_idol": { "id": "uuid", "name": "Benjamin Graham", "era": "…" },
  "interview_turn_count": 3,
  "comparison_output": "…markdown…",   // after generate-results
  "blueprint_output": "…markdown…",    // after generate-results
  "interview_thread_id": "uuid",
  "created_at": "…", "updated_at": "…"
}
```

## Feed — `/feed`

| Method | Path | Notes |
|---|---|---|
| GET | `` | `?page,page_size,refresh` — LLM idea cards. Item: `{id, type: quote\|video, title, content, category, source, like_count, comment_count, is_liked}`. For a quote, `content` is the quote text and `source` the author. |
| POST | `/{post_id}/like` | Toggle like. |
| GET/POST | `/{post_id}/comments` | List / add comments. |

## Other routers

`me`, `idols`, `jobs`, `achievements`, `comparison`, `content_resources`,
`plans` (+ `/plan-items`), `notes`, `idea_cards`, `chat`, `intake`,
`daily_tasks`, `tools`, `debug` — these back legacy/auxiliary flows. The
CMPYS mobile client today uses **auth**, **sessions**, and **feed**.
