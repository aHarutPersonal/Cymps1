# CMPYS API Reference

Base URL: `/api/v1`. All endpoints except `/auth/*` require `Authorization: Bearer <token>`.
SSE endpoints respond with `text/event-stream`; each line is `data: {json}\n\n`.

## Auth — `/auth`

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/register` | `{email, password, fullName}` | `{accessToken, refreshToken, user}` |
| POST | `/login` | `{email, password}` | tokens |
| POST | `/refresh` | `{refreshToken}` | tokens |

## User — `/me`

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/me` | — | user profile |
| PATCH | `/me` | `{fullName?, ...}` | updated profile |

## Sessions — `/sessions`

The core agentic flow. Each session progresses through phases:
`intake > idol_selection > interview > comparison > blueprint > guided_learning > completed`

| Method | Path | Body/Params | Notes |
|---|---|---|---|
| POST | `` | `{age, financial_status, interests}` | Create session. **409** if active session exists. |
| POST | `/{id}/suggest-idols` | — | LLM mentor suggestions: `[{name, era, relevance_summary, confidence}]` |
| POST | `/{id}/select-idol` | `{idol_name, wikidata_id?}` | Set mentor > `interview` |
| POST | `/{id}/interview` | `{content}` | **SSE.** Events: `status`, `chunk{content}`, `done{turn, max_turns, phase_transition}`, `error` |
| POST | `/{id}/generate-results` | — | **SSE.** Events: `section{comparison\|blueprint}`, `chunk{section, content}`, `done`, `error` |
| POST | `/{id}/guided-learning` | `{content}` | **SSE.** Mentor chat. Events: `chunk{content}`, `done`, `error` |
| GET | `/{id}/feed` | — | Per-session daily insight cards |
| GET | `/{id}` | — | Full session state |
| GET | `/current` | — | Most recent non-completed session |
| GET | `/latest` | — | Most recent session (including completed) |
| DELETE | `/current` | — | Abandon (force-complete) active session |

### Session response shape

```json
{
  "id": "uuid",
  "phase": "interview",
  "user_age": 25,
  "user_financial_status": "early_career",
  "user_interests": ["Building a startup", "Reading"],
  "selected_idol": { "id": "uuid", "name": "Benjamin Graham", "era": "..." },
  "interview_turn_count": 3,
  "comparison_output": "...markdown...",
  "blueprint_output": "...markdown...",
  "created_at": "...",
  "updated_at": "..."
}
```

## Feed — `/feed`

| Method | Path | Body/Params | Notes |
|---|---|---|---|
| GET | `` | `?page,page_size,refresh` | LLM idea cards: `{id, type, title, content, category, source}` |
| POST | `/{post_id}/like` | — | Toggle like |
| GET | `/{post_id}/comments` | — | List comments |
| POST | `/{post_id}/comments` | `{content}` | Add comment |

## Idols — `/idols`

| Method | Path | Notes |
|---|---|---|
| GET | `/search?q=` | Search idols by name |
| GET | `/discover` | Discovery feed |
| POST | `/import` | Import an idol |
| GET | `/my` | User's selected idols |
| POST | `/{id}/select` | Select an idol |
| GET | `/{id}` | Idol detail |
| GET | `/{id}/profile` | Full profile |
| GET | `/{id}/timeline` | Life timeline |
| GET | `/{id}/persona` | Persona data |
| POST | `/{id}/generate-image` | Generate idol portrait |

## Achievements — `/achievements`

| Method | Path | Notes |
|---|---|---|
| POST | `` | Create achievement |
| GET | `` | List achievements |
| GET | `/{id}` | Get one |
| PATCH | `/{id}` | Update |
| DELETE | `/{id}` | Delete |

## Plans — `/plans`

| Method | Path | Notes |
|---|---|---|
| POST | `/generate` | Generate a plan (LLM) |
| GET | `/current` | Current active plan |
| POST | `/{id}/items` | Add plan item |
| GET | `/{id}/weeks/{week}/summary` | Weekly summary |

## Notes — `/notes`

| Method | Path | Notes |
|---|---|---|
| POST | `` | Create note |
| GET | `` | List notes |
| GET | `/{id}` | Get one |
| PATCH | `/{id}` | Update |
| DELETE | `/{id}` | Delete |

## Content Resources — `/content-resources`

| Method | Path | Notes |
|---|---|---|
| GET | `` | List resources |
| GET | `/vault` | Saved vault |
| GET | `/library` | User library |
| GET | `/continue-reading` | Resume reading |
| GET | `/{id}` | Get resource |
| POST | `/{id}/save` | Save to vault |
| DELETE | `/{id}/save` | Unsave |
| PATCH | `/{id}/progress` | Update progress |
| GET | `/{id}/highlights` | List highlights |
| POST | `/{id}/highlights` | Add highlight |
| DELETE | `/{id}/highlights/{hid}` | Remove highlight |

## Daily Tasks — `/daily-tasks`

| Method | Path | Notes |
|---|---|---|
| POST | `/generate` | Generate daily tasks |
| GET | `` | List tasks |
| GET | `/today` | Today's tasks |
| GET | `/streak` | Streak info |
| GET | `/daily-focus` | Daily focus |

## Comparison — `/comparison`

| Method | Path | Notes |
|---|---|---|
| GET | `` | Standard comparison |
| GET | `/ai` | AI-powered comparison |

## Debug — `/debug`

| Method | Path | Notes |
|---|---|---|
| GET | `/llm` | LLM provider status |
| GET | `/prompts` | Loaded prompts |
