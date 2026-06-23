# CMPYS Prompt Contracts

**Owner:** Prompt Contract Agent  
**Status:** Source of truth for prompt variables, validation, storage, and consumers  
**Last updated:** 2026-05-13

## Rules

- Production prompt rendering uses strict placeholder validation.
- Rendered prompts must not contain unresolved `{placeholder}` tokens.
- JSON inputs must be passed as JSON-serializable dicts/lists or JSON strings.
- Content-depth validation must match the PRD minimums unless a degraded response is explicitly labeled.

## Contracts

| Prompt | Required variables | Output schema | Validation | Storage | Consumer |
| --- | --- | --- | --- | --- | --- |
| `plan_generate.txt` | `user_goal`, `hours_per_week`, `target_age`, `user_context`, `idol_name`, `idol_profile_json`, `idol_persona_json`, `idol_milestones_json`, `gaps_json`, `readiness_by_gap_json` | `PlanGenerationResponse` | no unresolved placeholders; mission descriptions >= 50 words; daily instructions >= 40 words | `plans.roadmap_json`, `plan_items`, `plan_items.meta_json` | Plan, Today, Mentor |
| `plan_item_details.txt` | `task_title`, `user_goal`, `learning_preferences`, `idol_name`, `idol_domain` | plan item details JSON | step `lesson_content` >= 500 words; rich material `content_markdown` >= 600 words | `plan_items.details_json`, content resource links | Task detail, lessons, Library |
| `book_module_generate.txt` | `book_title`, `author`, `user_goal`, `source_context` | content resource module JSON | `content_markdown` >= 2,500 words; duration from words / 200 | `content_resources` | Library, in-app lesson |
| `chat_system.txt` + `chat_reply.txt` | persona, profile, comparison, milestones, evidence, history, message | chat response text | persona guardrails and context injection | `chat_messages` | Mentor |
| `interview_system.xml` + `interview_question.txt` | mentor persona, user intake, chat history, turn count, facts | SSE interview response | one question per turn, 3-5 turn flow | session + chat thread | Agentic interview |
| `comparison_generate.txt` | idol, user age/profile, interview transcript, facts | comparison text | factual grounding and user-specific references | session comparison output | Results |
| `blueprint_generate.txt` | idol, user profile, interview transcript, comparison summary, facts | strategic blueprint markdown | positions blueprint as strategy, not execution plan | session blueprint output | Results, Plan generation context |

## Provider Responsibilities

- Grounded historical/resource lookup: Gemini/Search path when available.
- Structured JSON generation: configured backend LLM provider.
- Thinking streams: fast, low-cost model or evidence-rich deterministic fallback.

## Quality Thresholds

- Book module `content_markdown`: 2,500 words minimum.
- Plan step `lesson_content`: 500 words minimum.
- Material `content_markdown`: 600 words minimum.
- Durations are calculated from actual word count at 200 words per minute, minimum 5 minutes.
