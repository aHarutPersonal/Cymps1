# CMPYS — application flows and functionality

Updated: 25 October 2026.

[Business requirements](../README.md) · [Technical guide](TECHNICAL_GUIDE.md)

- [End-to-end flows](#end-to-end-flows)
- [Navigation and complete user journey](#navigation-and-complete-user-journey)
- [Accounts and session recovery](#accounts-and-session-recovery)
- [Personalization, mentor discovery, and intake](#personalization-mentor-discovery-and-intake)
- [Today](#today)
- [Plan, missions, and progression](#plan-missions-and-progression)
- [Short tutorials and lesson reading](#short-tutorials-and-lesson-reading)
- [Practice, assessment, and adaptation](#practice-assessment-and-adaptation)
- [Learning materials and book access](#learning-materials-and-book-access)
- [Reading library, book reader, and listening](#reading-library-book-reader-and-listening)
- [Mentor chat](#mentor-chat)
- [Comparison and achievement records](#comparison-and-achievement-records)
- [Ideas, notes, and saved items](#ideas-notes-and-saved-items)
- [Profile and settings](#profile-and-settings)
- [Persistence and account boundaries](#persistence-and-account-boundaries)
- [Interface and accessibility](#interface-and-accessibility)
- [Known gaps and verification status](#known-gaps-and-verification-status)

## End-to-end flows

| Journey | Entry and sequence | Expected result | Failure or availability boundary |
|---|---|---|---|
| First use | Register → personal context → discover/preview mentor → intake → mentor lab → Today | Saved session, comparison, blueprint, and a personal plan | Interrupted preparation resumes or offers retry; unavailable evidence stays unknown |
| Daily learning | Today → next action, or Plan → current week → mission → current tutorial → practice → feedback | Accepted work persists and the next required tutorial becomes available | A later tutorial stays locked; failed saves/reviews must not count as completion |
| Revision | Open practice → restore draft/attempt → revise → submit again | Feedback and attempt history remain available | Revision conflict offers reload; unsaved work warns before exit |
| Reading | You → Reading → search/select book → reader → contents/settings/notes | Readable chapters and saved progress | The item may be a guide; original text requires an available original-source action |
| Mission resources | Plan → mission → Materials → available action | Book reader, excerpt, article, video, or web source opens | A recommendation alone does not grant full-book access |
| Listening | Book → Listen → playback controls → another tab → return/resume | The session retains its owning reader and position | New audio depends on provider availability; alignment precision varies |
| Coaching | Chat → question or report a win → streamed reply → optionally save a note | Session conversation can be restored | Incomplete or failed replies expose retry; local notes/wins have separate persistence |
| Progress review | Compare → evidence/dimension details → written perspective → Your record | The learner can inspect supporting evidence and add context | Local record reassessment is not a fresh server assessment |
| Cycle completion | Finish required plan work → cycle summary → start next cycle | A subsequent plan can be prepared | This capability exists but a full cycle was not completed in the latest simulator test |
| Account recovery | Sign-in → account access → request code → enter code/new password → sign-in | Access is restored when configured delivery and validation succeed | Email availability, expiry, rate limits, and errors are explicit |

The sections below describe every identified current product surface and its limitations. A control visible in the UI is not automatically a completed backend integration.

## Navigation and complete user journey

The main application has five tabs. Nested screens retain their owning tab where appropriate, including the book reader and its listening session.

| Tab or destination | What the learner can do | How to reach it |
|---|---|---|
| Today | See the current plan state, next daily action, daily completions, and a comparison entry point | Bottom bar → Today |
| Plan | View the roadmap, current week, missions, daily habits, strategic blueprint, and progress | Bottom bar → Plan |
| Chat | Ask the selected mentor for help and report a win | Bottom bar → Chat |
| Compare | Review the written learning perspective, evidence coverage, dimensions, and milestone context | Bottom bar → Compare |
| You | Open profile, library, records, notes, saved items, mentor selection, settings, and logout | Bottom bar → You |
| Reading | Browse available book resources and resume reading | You → Library → Reading |
| Mission | Open its objectives, tutorials, resources, and completion criteria | Plan → current week → mission |
| Tutorial | Read a focused lesson and open its practice | Mission → current or completed tutorial |
| Practice | Enter work, save a draft, request help, submit, and inspect feedback | Tutorial → Open practice, or its practice action |
| Materials | Open supporting books, excerpts, articles, videos, courses, or tools when available | Mission → Materials, or tutorial references |
| Idea reels | Browse the idea feed and its interaction controls | You → Library → Idea reels, or Today → lightbulb button |
| Your record | Record and inspect personal wins alongside mentor milestones | You → Library → Your record, or Compare → Your record |

A new account follows registration, personal context, mentor discovery/preview, mentor-led intake, and an automatic preparation flow for comparison, blueprint, and plan. A returning account restores its authenticated session and saved onboarding or main-app state. The next actionable week and tutorial depend on completion, not simply elapsed calendar time.

## Accounts and session recovery

### Registration, login, and logout

- Create an account using a name, email, and password, or sign in with an existing account.
- Form validation, password visibility controls, loading states, and API errors are exposed by the authentication screens.
- The backend issues access and refresh tokens. The client uses secure token storage and refreshes authentication through its network layer.
- Logout is available from You. Session/account transitions reset application state to avoid carrying the previous account's private view into the next session.
- Splash routing restores authentication, decides whether onboarding is required, and can restore an active book-narration destination.

### Password recovery

The account-access screen first checks whether email recovery is available. When configured, the user can request a recovery code, enter the code and a matching new password, resend/request another code, and return to sign-in after success. Unavailable email delivery, invalid or expired codes, request failures, and retry states are shown explicitly. Email delivery requires configured backend infrastructure; a visible recovery screen alone does not establish that delivery is enabled in a deployment.

### Onboarding persistence

Session APIs retain the selected mentor, intake conversation, comparison, blueprint, and associated generation state. On reopening onboarding, the client restores the relevant stage. A failed restoration read offers recovery rather than silently replacing the saved session. The backend also supports abandoning an incomplete session and inspecting the newest session, including completed onboarding.

Source: [authentication screens](../fe/cmpys/lib/features/auth/presentation), [session controller](../fe/cmpys/lib/features/auth/controllers/session_controller.dart), [auth API](../cmpys/backend/app/api/v1/auth.py), and [session API](../cmpys/backend/app/api/v1/sessions.py).

## Personalization, mentor discovery, and intake

### Personal context

The flow collects the learner's name, age, interests, goal, and contextual information. The interview expands this into a reusable capability baseline: relevant achievements, examples of existing work, resources and constraints, learning preferences, and weekly learning capacity. Diagnostic work and explanations of how the learner checks that work inform planning; short checks are not certificates of overall ability.

### Mentor discovery

- Receive suggested mentors based on context and interests.
- Search people or fields, inspect mentor cards, and preview a mentor before selection.
- View available biographical context, portrait, domains, and timeline information through mentor details.
- Select the mentor for the session and proceed into their intake conversation.
- Backend discovery/import capabilities can resolve additional people, queue profile preparation, and expose import progress. Published shared profiles are reused.

### Mentor-led intake and automatic preparation

The intake presents an adaptive conversation and answer composer, including structured answer choices when supplied. Answers are persisted on the session. The preparation flow then produces the written comparison, structured dimension assessment, strategic blueprint, and executable plan, with streamed status and recovery controls.

The **blueprint** explains direction, priorities, and rationale. The **plan** organizes the work into weeks, missions, daily habits, tutorials, and completion requirements. These are separate artifacts with different purposes.

Source: [onboarding flow](../fe/cmpys/lib/features/cmpys/presentation/onboarding/onboarding_flow.dart), [discovery](../fe/cmpys/lib/features/cmpys/presentation/onboarding/discovery_step.dart), [intake](../fe/cmpys/lib/features/cmpys/presentation/onboarding/intake_step.dart), and [mentor lab](../fe/cmpys/lib/features/cmpys/presentation/onboarding/mentor_lab_step.dart).

## Today

Today uses the current backend plan and its daily-task response. It displays:

- A greeting, learner/mentor context, and plan day when a creation date is available.
- Explicit loading, preparing, empty, and failed-plan states, with recovery actions.
- Today's completion count and progress, and the next unfinished daily item.
- The current week's daily habits/practice items, their instructions, and completion controls.
- Navigation into a task or the complete plan, and a nudge to review comparison context.

Daily habit completion is recorded for the date rather than permanently completing a recurring habit. The backend also provides current/longest streaks, a seven-day completion grid, and a daily-focus response with a reflection prompt. Daily task detail provides a saved reflection field. Not every backend daily-focus field is separately rendered on the current Today screen.

Source: [Today screen](../fe/cmpys/lib/features/cmpys/presentation/today_screen.dart) and [daily-task API](../cmpys/backend/app/api/v1/daily_tasks.py).

## Plan, missions, and progression

### Roadmap and daily habits

Plans organize learning across weeks; the main product flow creates a 12-week plan. The screen displays the plan's actual duration and weekly hours. Roadmap and Daily habits are separate views. The current actionable week appears first, with supporting blueprint and progress information. Future weeks unlock sequentially as required work is completed.

Each mission can contain a purpose, deliverable, success criteria/definition of done, a mental model, estimated workload, a sequence of tutorials, and supporting materials. Mission detail shows completed/current/locked tutorial states and the count completed. A locked tutorial explains which prerequisite must be finished.

### Workload and readiness

- The outline chooses an appropriate tutorial count for the mission's workload; shorter tutorials do not imply more books or external references.
- Current-week content can be prepared in the background. Ready tutorials appear progressively while remaining work is prepared.
- Reading time is derived from actual accepted prose. Tutorial time adds the practice allocation; the interface shows these components separately.
- The capacity check allows a configured tolerance around mission minutes. The current implementation uses the larger of five minutes or 10% of the allocation.
- Unpublished tutorials receive an allocation from the remaining capacity. Rescoping or shortening must retain the instructional requirements and pass review.
- Tutorials with learner answers, hints, attempts, active review, or completion are protected from automatic capacity edits.
- A workload that cannot fit honestly fails/reschedules rather than reducing displayed minutes without changing the required work.

### Completion, achievements, and subsequent cycles

The backend enforces sequential step completion and required practice. Completion is persisted, so reopening the app retains progress. Completing a plan item can offer an editable achievement suggestion; the user can confirm the achievement or skip it. Weekly summaries report progress. At the end of a plan cycle, the app can request a narrative/capstone summary and start a subsequent plan cycle, with loading and failure recovery.

Backend APIs also support adding plan items and editing item notes. These capabilities should not be confused with a fully featured mobile plan editor: the primary UI follows the generated plan.

Source: [Plan screen](../fe/cmpys/lib/features/cmpys/presentation/plan_screen.dart), [mission detail](../fe/cmpys/lib/features/plan/presentation/plan_item_detail_screen.dart), [plan API](../cmpys/backend/app/api/v1/plans.py), [capacity rules](../cmpys/backend/app/services/planning/tutorial_capacity.py), and [cycle completion](../fe/cmpys/lib/features/plan/presentation/cycle_completion_screen.dart).

## Short tutorials and lesson reading

The new `tutorial_v1` format targets one concept, one visual explanation/comparison, one worked example, and a small practice sequence. Current validation accepts 450–800 words of tutorial prose and a planned total of approximately 5–8 minutes, subject to the accepted reading and practice content. Reading minutes use the ceiling of words divided by 200. Older lesson formats retain their separate, longer-content validation contract; they do not automatically become short tutorials by changing a label.

Tutorial content includes the reason for the skill, explanation/framework, worked example, common errors or boundaries, practice guidance, a check, and references. Native diagrams/comparison layouts support visual explanations. A visual may be a structured diagram or comparison rather than a separately generated raster image. Availability of a visual does not imply a paid image-generation call for each tutorial.

The lesson reader provides readable typography, a contents navigator, reading settings, tutorial references, and a direct practice action. The app keeps the teaching passage and the answer-entry workbook distinct. A completed tutorial remains readable, while the next incomplete tutorial becomes the active one.

The generation pipeline checkpoints an outline and accepted individual tutorials, validates identifiers and linked materials, and preserves accepted work during retries. Quality checks cover structure, content, practice alignment, source references, and private solution integrity. Failed review prevents publication until a bounded repair succeeds or the job reports failure.

Source: [lesson reader](../fe/cmpys/lib/features/plan/presentation/lesson_reader_screen.dart), [tutorial outline prompt](../cmpys/prompts/plan_item_tutorial_outline.txt), [quality rules](../cmpys/backend/app/services/content_quality.py), and [lesson package](../cmpys/backend/app/services/planning/lesson_package.py).

## Practice, assessment, and adaptation

Practice happens inside CMPYS. The active workbook can contain teaching/guided activities followed by a distinct independent case. Its schema supports text and structured/numeric answer fields, choices, and instructional visuals when present in the activity.

The learner can:

1. Open the current activity and read its task, data, and success criteria.
2. Enter answers and save draft work.
3. Return later and restore the saved draft.
4. Request a hint when the activity allows it.
5. Submit work for checking and see preparation/review progress.
6. Read criterion-level feedback, the result, and permitted worked-solution help.
7. Revise the answer and retain earlier saved attempts.
8. Continue to the next case when prerequisites pass.
9. Finish the tutorial after its required practice is accepted.

The interface handles save failures, stale revisions, reload conflicts, pending assessments, retries, and leaving with unsaved changes. Blank or incomplete required responses do not enable a valid submission. The backend owns progression and checks the learner, plan item, step, artifact, and workbook revision, preventing a UI-only bypass.

Practice outcomes can inform later lesson personalization. Required work is intended to be solvable from the in-app case, without buying a supporting book or using a separate editor. Private grading data and answer keys are separate from public prompts. A known answer-leak issue remains in one generated tutorial; the existence of these checks must not be read as proof that every published example is free of leaks.

Source: [practice screen](../fe/cmpys/lib/features/plan/presentation/lesson_practice_screen.dart), [practice API](../cmpys/backend/app/api/v1/practice.py), and [practice services](../cmpys/backend/app/services/practice).

## Learning materials and book access

Mission materials and tutorial references support books, videos, articles, courses, and tools. Each material explains its relationship to the learning objective where supplied. The application chooses a viewer from the actual available content:

| Available material | Behavior |
|---|---|
| Published book resource | Open the dedicated in-app book reader |
| Verified original-book source | Offer **Read original** or **Read original book**, depending on the entry point |
| Verified excerpt | Offer **Read excerpt** and identify its limited scope |
| In-app article/material text | Open the material reader |
| Supported video identity | Open the video material screen |
| Valid direct source URL | Open the in-app web viewer |
| No readable source or approved resource | Display an unavailable state; do not imply that the complete book is included |

The web viewer displays source context where provided, loading progress, and page-navigation controls. Known excerpt sources can open near the relevant heading. Direct-link validation prevents treating a generic search-result page as the actual learning resource.

Book metadata, a generated study guide, a chapter excerpt, and an original book are different forms of access. A title in a mission does not mean that CMPYS has the full text. Availability checks and catalog jobs may resolve or prepare a guide; rejected or exhausted jobs should report a terminal unavailable state rather than endlessly claim to be preparing.

In the latest tested writing mission, *Self-Editing for Fiction Writers* offered the coauthor's Chapter 12 excerpt, explicitly excluding the full book. *Techniques of the Selling Writer* and *The Emotional Craft of Fiction* showed no readable edition available. This is a dated account example, not a fixed universal catalog.

Source: [material access repository](../fe/cmpys/lib/features/plan/data/plan_repository.dart), [material web viewer](../fe/cmpys/lib/features/plan/presentation/material_web_screen.dart), [video viewer](../fe/cmpys/lib/features/plan/presentation/material_video_screen.dart), and [content-resource API](../cmpys/backend/app/api/v1/content_resources.py).

## Reading library, book reader, and listening

### Library

Open **You → Library → Reading**. The library lists available published book resources, supports title/author search, and has All, Saved, and Completed filters. A Continue reading card appears when a valid recent resource exists. It shows book counts and empty, loading, error, and pull-to-refresh states. A stale resume entry should not hide the rest of the library.

### Book reader

The dedicated reader provides:

- Chaptered text, a current-chapter heading, next-chapter navigation, and a Contents menu.
- Progress persistence and reading continuation.
- Font-size controls and light, sepia, and dark reading themes.
- Text selection, quote-based notes, highlights, and a Notes & highlights menu.
- Saving/removing a saved book.
- A **Read original book** menu item when an original source is available.
- Source fallback and retry when content cannot load.
- Scroll-sensitive navigation chrome to preserve reading space.

Generated book guides have a separate long-form quality contract, currently 3,200–4,500 words, with chapter structure, exercises, and grounded content checks. That contract does not make a guide the original author's complete book. Public-domain originals and legitimate excerpts can be available through separate source resolution.

On 25 October, the tested account's library contained *The Art of War*. Opening it displayed a seven-chapter guide, with chapter text, reading settings, Listen, and the book menu visible. Original-text availability must be checked through the menu/source rather than inferred from the title.

### Listen aloud

The Listen control starts a narration session. The reader and shared listening dock implement play/pause, playback position, speed, chapter/session controls, and access to the app menu while retaining the session. The reader can remain in its Plan or You navigation branch while other tabs are selected. Account-scoped checkpoints support resuming a narration destination after a restart.

Narration is independent of the text-generation model. The configured default provider in source is direct Gemini TTS; legacy provider adapters and a device-voice fallback also exist. Playback of cached audio can work without creating a new recording. New audio requires a configured, working speech provider.

The UI discloses AI-generated voice. Text tracking depends on provider alignment: exact word synchronization must not be promised for audio without word timestamps. The implementation can play valid audio with estimated progress when precise timing is unavailable. Gemini narration currently does not supply word timestamps in this integration.

Source: [reading library](../fe/cmpys/lib/features/plan/presentation/reading_library_screen.dart), [book reader](../fe/cmpys/lib/features/plan/presentation/book_reader_screen.dart), [narration](../fe/cmpys/lib/features/plan/presentation/book_narration.dart), [listening dock](../fe/cmpys/lib/features/plan/presentation/book_narration_dock.dart), and [resume checkpoints](../fe/cmpys/lib/features/plan/presentation/book_narration_checkpoint.dart).

## Mentor chat

Chat restores the session's saved conversation and streams real backend replies. It provides suggested prompts, a text composer, an in-progress reply state, and explicit retry when history or a reply fails. An incomplete previous reply can be retried. An account without the needed session is directed back to onboarding.

The mentor's name/avatar opens mentor context. A message can be saved into the local Notes collection. A report-a-win action captures a personal win; the mentor's response is generated through the chat backend and can be retained as the win's mentor note. The win-record UI is local state, distinct from server achievement records created through the plan-completion flow.

The backend also supports topic-based learning-material requests and session-specific idea generation. These endpoints are listed below even where there is no standalone current tab for them. Chat is an AI simulation, not communication with the named person.

Source: [Chat screen](../fe/cmpys/lib/features/cmpys/presentation/chat_screen.dart) and [session API](../cmpys/backend/app/api/v1/sessions.py).

## Comparison and achievement records

### Evidence-based comparison

Compare presents the learner's context at their age, starting checks, written mentor perspective, and a structured assessment across five dimensions. It reports how many dimensions have like-for-like evidence. Dimension details explain evidence, comparability, and uncertainty. The written perspective can be opened in full, and the screen links back to the learning plan and personal record.

No comparable evidence can legitimately produce **0/5 like-for-like dimensions**. This means the evidence is insufficient or incompatible; it is not an overall ability score of zero. A written comparison can be available while its structured dimension assessment is still preparing or has failed. Loading, failure, missing-score, and retry states are distinct.

The backend also exposes comparison endpoints using achievement/timeline evidence and an AI-assisted comparison route. The active mobile comparison is hydrated from the learner's session. In the latest test, one of five dimensions had supported like-for-like evidence.

### Your record

The record screen organizes personal wins and mentor milestones by age, with dimension filters. It supports logging a win with contextual evidence, claiming a milestone with an explanatory statement, viewing details/mentor notes, deleting a local win, and reassessing pending local entries.

The current record reassessment is a local presentation flow. It must not be described as a newly completed independent backend assessment. Similarly, locally recorded wins and claims are not proof of verified achievements or guaranteed improvement in a dimension.

### Server achievements

The separate achievements API supports creating, listing/filtering, reading, updating, and deleting owner-scoped achievement records. The plan-completion achievement sheet uses this server path and allows review of the suggested title before confirmation. Do not assume every local record action uses the achievements API.

Source: [Compare screen](../fe/cmpys/lib/features/cmpys/presentation/compare_screen.dart), [record screen](../fe/cmpys/lib/features/cmpys/presentation/record_screen.dart), [achievement sheet](../fe/cmpys/lib/features/plan/presentation/achievement_sheet.dart), [comparison API](../cmpys/backend/app/api/v1/comparison.py), and [achievements API](../cmpys/backend/app/api/v1/achievements.py).

## Ideas, notes, and saved items

### Idea reels

The full-screen vertical feed loads idea cards from the backend feed, supports refresh/retry, and provides swipe and previous/next navigation. Cards show author/context and source metadata where supplied. Like/double-tap, comment, save, and share controls appear on the cards.

The current reels implementation stores its like/comment/save interactions in local application state. The backend separately implements persistent likes and comments, but those endpoints should not be mistaken for complete client wiring. The **Share idea** action currently displays “Link copied” without actually implementing a clipboard/share operation; this remains a placeholder.

Feed generation prefers stored content and sourced quotations. Quote ingestion retains provenance and verification status, rejects unsuitable attributed/disputed material, and can use bounded independent verification. An exact quotation, a sourced attribution, a verified quotation, and a generated insight carry different evidence strengths.

### Notes

**You → Library → Notes** lists locally saved notes, including mentor-message and reading notes created by the relevant local flows. The user can open the note and remove it. Empty-state navigation helps start a note-producing activity.

Book-reader notes/highlights use the content-resource API and are available inside that book's menu. The backend also has a general Notes CRUD API. The local Notes screen is not a unified cross-device view of every server note/highlight.

### Saved items

**You → Library → Saved** displays locally bookmarked ideas and supported local content/task items, with open/remove actions where implemented. Dedicated book saves are server-backed and feed the Reading library's Saved filter. These two collections have different persistence paths; they are not interchangeable views of one fully synchronized list.

Source: [reels](../fe/cmpys/lib/features/cmpys/presentation/reels_screen.dart), [ideas provider](../fe/cmpys/lib/features/cmpys/data/cmpys_ideas_provider.dart), [Notes/Saved screens](../fe/cmpys/lib/features/cmpys/presentation/detail_screens.dart), [feed API](../cmpys/backend/app/api/v1/feed.py), and [notes API](../cmpys/backend/app/api/v1/notes.py).

## Profile and settings

You displays learner identity, mentor context, summary counters, library links, account actions, and app version.

| Action | Current behavior |
|---|---|
| Edit profile | Edit name, age, and interests; save or handle unsaved changes with save/discard/keep-editing options |
| Change mentor | Open the mentor picker and change the local selected-mentor presentation |
| Daily reminder | Toggle a locally stored preference |
| Reminder time | Display the fixed 8:00 AM label; no working time picker |
| Mentor messages | Toggle a locally stored preference |
| Weekly comparison digest | Toggle a locally stored preference |
| Sound & haptics | Toggle a locally stored preference |
| Privacy & data | Show a placeholder toast; no implemented privacy-management center |
| About CMPYS | Show the version information toast |
| Log out | End the authenticated app session and return to authentication |

Profile edits and mentor changes in these screens currently update the local store. Backend `/me` and idol-selection APIs exist, but these screen actions do not by themselves perform a server profile update, replace the session mentor, or regenerate the learning plan. Notification preferences do not establish working notification scheduling or delivery. There is no implemented subscription checkout, account-data export, or account-deletion screen in this navigation.

Source: [You screen](../fe/cmpys/lib/features/cmpys/presentation/you_screen.dart), [detail/settings/profile screens](../fe/cmpys/lib/features/cmpys/presentation/detail_screens.dart), and [local store](../fe/cmpys/lib/features/cmpys/state/cmpys_store.dart).

## Persistence and account boundaries

| Data | Primary storage and practical meaning |
|---|---|
| Authentication tokens | Client secure storage; access/refresh validation on the backend |
| Onboarding answers, selected session mentor, comparison, blueprint | Backend session records |
| Plan, mission/tutorial completion, daily completion/reflection | Backend plan and progress records |
| Practice drafts, hints, attempts, grading state | Backend learner-specific practice records with revision checks |
| Guided-learning conversation | Backend session conversation history |
| Shared mentor profiles, published guides, reusable curriculum | Shared catalog/database content, subject to publication gates |
| Book progress, saves, highlights | Backend content-resource records associated with the user |
| Narration resume information | Account-scoped local checkpoints, with cached audio/provider resources where available |
| Local wins/reassessment, general Notes/Saved screens, reels interactions, profile/settings edits | Persisted local CMPYS store; do not promise cross-device synchronization |

The backend authenticates private data access and checks ownership. Shared published content is separate from user-private answers and plan context. Failed network reads must not be represented as successful saves. A local success toast is not evidence that a server record was updated. Offline caches and recovery exist in specific flows, but the full onboarding/generation/assessment experience requires the backend and relevant provider services.

## Interface and accessibility

The Flutter interface uses shared design tokens, typography, cards, sheets, motion, and a labeled five-tab navigation bar. Larger text and wider screens receive adaptive layouts; interactive elements expose semantic labels in the principal flows. Readers use native comparison/diagram layouts, selectable text, and adjustable typography. Motion respects the app's motion configuration, and scrolling can hide/reveal bottom controls.

Skeletons, loading indicators, explicit empty states, save status, retries, and conflict dialogs distinguish preparation from failure. These are implementation features, not a claim of a completed accessibility certification. Reader-specific dark/sepia themes do not imply an application-wide appearance-settings feature.

## Known gaps and verification status

This section is part of the product description because it prevents unfinished or optional behavior from being presented as complete.

| Area | Current limitation or evidence |
|---|---|
| Generated content accuracy | Latest manual QA found unsupported Dickens anecdotes; automatic review did not catch every historical claim |
| Independent assessment | One generated tutorial exposed an answer to its own independent transfer case; unresolved in the latest run |
| Book access | Recommended titles may offer only an excerpt or no readable edition; a guide is not the full original |
| Catalog coverage | The tested account had one Reading-library book; this is not a complete commercial ebook library |
| Profile and mentor switching | Current profile/picker screens update local state, without a complete backend-plan transition |
| Record reassessment | Current record overlay performs a local reassessment presentation |
| Notes, saves, reactions | Local collections and backend content-resource collections are not unified across all screens |
| Share idea | Toast-only placeholder; clipboard/share action is missing |
| Notifications/digests | Preferences exist; delivery/scheduling is not established by these controls |
| Privacy center and reminder time | Placeholder privacy action and fixed reminder-time text |
| Monetization | No implemented subscription/payment entitlement flow |
| Full offline use | Live generation, assessment, and new provider audio require network services |
| All platforms | Flutter platform targets exist; the latest end-to-end verification described here was iOS simulator verification |

### Latest completed verification

The 25 October 2026 fresh-account test exercised registration, onboarding, comparison/blueprint/plan generation, and the first mission. Twenty tutorials were generated and readable; three were completed, and tutorial four was unlocked. Saved answers, a 4/4 assessment result, and two attempts persisted. The current/locked progression and native visual/worked-example rendering were inspected. The mission's measured required workload was 132 minutes against a 120-minute allocation plus its 12-minute tolerance. Compare showed one of five dimensions with supported evidence.

A subsequent navigation check opened **You → Reading → The Art of War** and displayed the seven-chapter guide. That check did not verify every chapter, the external original text, or a fresh narration generation. Completing three tutorials is not evidence that all twenty assessments were submitted or that a full 12-week cycle was completed.

The deployed source baseline for that test was commit `657463d99b329e7968d1053116e71dce91ed49ec`. Its full backend CI run reported 4,696 passing tests and six skips. Those results describe that baseline, not an assertion that every uncommitted local change or future release has passed the same suite. The content-quality findings above remain unresolved unless a later change and verification explicitly close them.
