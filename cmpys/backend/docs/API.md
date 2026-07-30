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
| POST | `` | `{age, financial_status, interests, goal?}` | Create session. **409** if active session exists. |
| POST | `/{id}/suggest-idols` | — | LLM mentor suggestions: `[{name, era, relevance_summary, confidence}]` |
| POST | `/{id}/select-idol` | `{idol_name, wikidata_id?}` | Set mentor > `interview` |
| POST | `/{id}/interview` | `{content, is_kickoff?, question_id?}` | **SSE.** Events: `status`, `chunk{content}`, `done{turn, max_turns, phase_transition, question_id?, response_ui?}`, `error` |
| POST | `/{id}/generate-results` | — | **SSE.** Events: `section{comparison\|blueprint}`, `chunk{section, content}`, `done`, `error` |
| POST | `/{id}/guided-learning` | `{content}` | **SSE.** Mentor chat. Events: `chunk{content}`, `done`, `error` |
| GET | `/{id}/feed` | — | Per-session daily insight cards |
| GET | `/{id}` | — | Full session state |
| GET | `/current` | — | Most recent non-completed session |
| GET | `/latest` | — | Most recent session (including completed) |
| DELETE | `/current` | — | Abandon (force-complete) active session |

For a non-final interview question, `done.response_ui` is a versioned hint for
the response composer. Version 1 supports `text`, `single_choice`, and `number`.
Clients must fall back to text for missing or unsupported metadata. Choice and
number selections are still submitted as natural-language `content`, so the
interview transcript remains the canonical record. The backend adds a trusted
`answer_key` to each persisted question and uses the question UUID to bind the
answer to one of six required plan inputs: achievement inventory, current
capability, weekly hours, target outcome, constraints/resources, and learning
habits/support. The interview cannot close until all six have an answer;
`"none yet"` is a valid achievement baseline.

Weekly capacity is a dedicated number question with an end-to-end range of
3–60 hours per week. A selected value, one bare integer, or one integer stated
explicitly as hours per week is stored as the session's confirmed plan capacity.
Ranges, fractions, and prose containing multiple numbers are not rounded or
guessed. Invalid custom capacity receives `409` with
`detail.code = invalid_interview_answer`; clients restore the same composer,
preserve the text for correction, and do not duplicate the mentor question. The
historical 10-hour default is used only for interviews created before semantic
answer keys.

At result generation, the exact self-reported achievement inventory and other
plan inputs are registered in the reusable user profile and passed as a
session-scoped learner baseline to comparison, blueprint, and plan generation.
Self-reported intake prose is not silently promoted to a verified achievement
record.

A repeated kickoff replays
the persisted question with the same `question_id` and `response_ui`. Current
clients return that `question_id` with their answer so a lost terminal SSE event
can replay the already-committed response without duplicating the turn. Answer
claims are serialized per interview thread; a concurrent retry receives `409`
with `detail.code = interview_turn_in_progress`, while a superseded question
uses `detail.code = stale_interview_question`.

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

When `POST /generate` includes `sessionId`, that session must belong to the
authenticated user and match `idolId`. The session's age, concrete target
outcome, and confirmed weekly capacity are authoritative; caller defaults cannot
replace them. Later week and lesson generation retain the source session and
learner-baseline snapshot recorded on the plan.

### Lesson artifact concurrency

`GET /plan-items/{item_id}/detailed` returns `artifact_job_id` whenever its
response contains current or partial lesson details. Clients should retain that
value with the rendered lesson and echo it as the `artifactJobId` query
parameter on both mutation endpoints:

- `POST /plan-items/{item_id}/toggle-complete`
- `POST /plan-items/{item_id}/steps/{step_id}/toggle`

The token is optional only for a currently rendered legacy lesson and a true
first-generation artifact. A first detail job that replaces an already usable
legacy lesson is marked as a replacement and also requires its token. Missing,
malformed, non-canonical, wrong-item, wrong-owner, or stale artifact identity
returns `409`; the client must refresh the detailed lesson before retrying. A
modern token is canonical lowercase hyphenated UUID text and its referenced
detail job is retained even after the job leaves the active queue.

Step and item completion rows are pinned to this exact artifact job. Historical
progress is retained, but it is not counted toward a replacement lesson, week,
or plan—even when both artifacts use a generic ID such as `step_1`.

For `partial`/`generating` details, only steps named by a valid
`_generation.ready_step_ids` checkpoint and containing complete reader content
are completion-eligible. Responses keep all strict steps in `total_steps`, so
progress stays below 100% until the artifact becomes ready.

Failed jobs that never published an artifact do not remove first-generation
token compatibility. Conversely, while a newer active job owns a replacement,
the prior artifact's completion is excluded from item, week, plan, and daily
execution summaries until the replacement publishes or the attempt terminates.

`PATCH /plan-items/{item_id}` is notes-only. Send `{ "notes": "..." }`;
`status` and `progressPercent` are rejected with validation status `422` because
those fields are derived from the artifact-scoped completion endpoints above.
`GET /plan-items/{item_id}` returns that authoritative derived progress rather
than trusting the denormalized item cache.

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
