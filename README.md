# CMPYS — purpose and business requirements

Updated: 25 October 2026.

CMPYS (CoMPare Your Success) helps people develop practical skills through a personalized learning plan inspired by a chosen role model. It connects a learner's goal and starting capabilities to focused tutorials, worked examples, in-app practice, feedback, and evidence of progress.

This is one of **three maintained application documents**:

| Document | Responsibility |
|---|---|
| **This README** | Business purpose, user needs, scope, priorities, and acceptance criteria |
| [Application guide](docs/APP_GUIDE.md) | Complete user journeys, functionality, navigation, persistence, and known limitations |
| [Technical guide](docs/TECHNICAL_GUIDE.md) | Architecture, generation, all 94 v1 API routes, development, deployment, and asset attribution |

## Product purpose

The application should turn an aspiration such as “learn to write better” into work the learner can actually complete and assess. A mentor supplies a relevant perspective and documented methods; the plan translates them into a sequence of practical skills.

The central product loop is:

**Goal and context → mentor → capability baseline → personal plan → tutorial → practice and feedback → saved evidence → subsequent learning.**

The mentor is an AI interpretation of a real person's perspective. It is not the person, and generated narration is not their real voice. CMPYS does not guarantee success, certify overall ability, or rank a person's worth.

## People and problems served

| Learner need | Product response |
|---|---|
| “I have a goal but do not know what to do next.” | A concrete current-week focus, mission deliverables, and one active tutorial |
| “Advice is too generic.” | Intake captures existing work, capability, constraints, and learning preferences |
| “I can only study for a limited time.” | Weekly capacity shapes the plan; workload includes actual reading and practice |
| “I need explanations and examples, not just tasks.” | Focused teaching, visuals, worked examples, and self-contained exercises |
| “I cannot tell whether I understand.” | In-app answer entry, assessment criteria, feedback, revision, and saved attempts |
| “I want to learn from someone I admire.” | Mentor discovery, documented methods, contextual coaching, and source-aware comparison |
| “I lose progress between sessions.” | Persisted plans, completed tutorials, practice work, conversation, and reading progress |
| “I want to read more deeply.” | A dedicated book reader, guides/original-source access where available, notes, and listening |

The initial audience is self-directed learners seeking personal or professional skill development. Age is context for comparison, not an excuse to invent milestones or equate unlike circumstances.

## Business requirements and acceptance criteria

These requirements describe the intended product standard. A requirement is not a claim that every part is already complete; current implementation and gaps are documented in the application guide.

| ID | Requirement | Acceptance criterion |
|---|---|---|
| BN-01 | Personalized starting point | Intake preserves the learner's goal, evidence of current capability, constraints, preferences, and weekly capacity; missing evidence is labeled as missing |
| BN-02 | Relevant mentorship | The learner can discover/select a mentor; claimed historical methods or facts carry appropriate support and fictional cases are identified |
| BN-03 | Actionable plan | The plan identifies the current week, mission outcome, work sequence, materials, and completion criteria |
| BN-04 | Useful short tutorials | Each tutorial teaches a specific skill through an explanation, visual where appropriate, worked example, and small practice sequence |
| BN-05 | Honest workload | Displayed time reflects accepted content and practice; required workload fits the allocation within the documented tolerance |
| BN-06 | Fast first value | The first accepted tutorial becomes usable without waiting for every later tutorial; accepted work survives retries |
| BN-07 | Demonstrated learning | Required practice is completed inside the app, checked against criteria, and retained with feedback and attempt history |
| BN-08 | Valid independent practice | A transfer case is distinguishable from the teaching example; its answer is not exposed before the intended assessment |
| BN-09 | Clear progression | The server enforces prerequisites; accepted completion unlocks the next unit and persists after reopening |
| BN-10 | Honest comparison | Precise comparison is shown only for compatible evidence; unknown dimensions do not become fabricated scores |
| BN-11 | Transparent reading access | The UI distinguishes a study guide, complete original, excerpt, and unavailable title; a recommendation does not imply access |
| BN-12 | Reliable continuity | Saved answers, plan completion, reading position, and supported account data restore correctly; local-only collections are not advertised as synchronized |
| BN-13 | Useful mentor support | Chat restores history, streams replies, and provides explicit failure/retry states |
| BN-14 | Quality-preserving cost control | Reuse approved content and checkpoints, use bounded repairs and suitable model routing, and record usage/reservations without hiding failed-call costs |
| BN-15 | Accessible, understandable interface | Primary flows have readable layouts, labeled controls, clear statuses, and reader typography options; placeholder actions are identified |
| BN-16 | Trustworthy data handling | Private work is associated with its owner; account transitions do not expose another user's state; credentials are excluded from documentation and artifacts |

Detailed behavior and navigation: [application guide](docs/APP_GUIDE.md). Workload, validation, provider, and storage implementation: [technical guide](docs/TECHNICAL_GUIDE.md).

## Functional scope

The application has five main tabs: **Today, Plan, Chat, Compare, and You**. Its functionality covers:

- Account creation, login, session restoration, logout, and configured email recovery.
- Personal context, mentor discovery/preview, adaptive intake, comparison, and strategic blueprint.
- Weekly plans, missions, daily habits/reflections, tutorial preparation, completion, and subsequent plan cycles.
- Tutorial reading, native diagrams/comparisons, examples, references, and integrated practice.
- Drafts, hints, assessment, feedback, revision, saved attempts, and sequential unlocking.
- Books/guides, excerpts, articles, videos, web resources, a reading library, reading progress, notes/highlights, and optional narration.
- Mentor chat, comparison dimensions, personal records, achievements, ideas, notes, and saved collections.
- Profile/settings surfaces and their current local-only or placeholder limitations.
- Background catalogs, optional reusable curriculum, research/review, job recovery, telemetry, and budget controls.

The [application guide](docs/APP_GUIDE.md) explains each feature and its availability. The [API inventory](docs/TECHNICAL_GUIDE.md#api-capability-inventory) separately identifies backend-only capabilities.

## Priorities and tradeoffs

1. **Instructional quality and valid assessment.** Do not sacrifice factual support, worked-example clarity, or assessment independence to make generation appear faster.
2. **User-visible speed.** Prepare the first useful tutorial early, continue later content in the background, and reuse accepted work.
3. **Affordable operation.** Prefer the least expensive suitable model and avoid repeated work, while retaining required review and quality gates.
4. **Clear product behavior.** Make current actions, prerequisites, time requirements, access limitations, and errors understandable.

Smaller tutorials should produce a suitable number of learning units for the available time; they do not require duplicating external references. More generated text or more model calls is not, by itself, better learning.

## Business measures

The following are product measures to track, not implemented dashboards or invented performance targets:

| Outcome | Suggested measure |
|---|---|
| Activation | Registration-to-intake completion and time to the first usable tutorial |
| Useful learning | First tutorial/week completion, successful independent practice, and revision outcomes |
| Continued use | Return rate, active learning days, and continued plan progress |
| Content quality | Unsupported claims, answer leaks, unusable exercises, and rejected publications |
| Reliability | Failed/recovered generations, lost drafts, restoration failures, and blocked progression |
| Workload accuracy | Required reading/practice minutes compared with the learner's allocation |
| Reading value | Book/guide opens, continued reading, notes, and completed reading sessions |
| Economics | Cost per activated learner, accepted tutorial, and completed mission, including retries and unknown-usage reserves |

Numeric targets should follow a measured baseline. Telemetry availability varies by measure; do not describe this table as an existing analytics implementation.

## Current delivery state and gaps

The latest documented iOS simulator test completed fresh registration and onboarding, generated a first mission with 20 tutorials, completed three tutorials, and verified that tutorial four unlocked. It also inspected a seven-chapter book guide. This does not establish completion of all assessments or an entire 12-week cycle.

Known gaps include unsupported historical anecdotes, an answer leak in a generated transfer case, incomplete access to recommended books, local-only profile/record/collection actions, notification preferences without established delivery, and placeholder sharing/privacy controls. These must remain visible when judging readiness.

See [current limitations and verification](docs/APP_GUIDE.md#known-gaps-and-verification-status) for the detailed, dated account. The evidence is not a blanket claim that all features are production-complete.

## Commercial scope and open decisions

No subscription checkout, paid entitlement system, or complete commercial ebook library is currently implemented. Prior free/paid tier ideas are proposals, not shipped behavior. Pricing, paid-access boundaries, target acquisition channels, and business-level performance targets remain decisions requiring explicit product direction.

Likewise, notification delivery, a complete privacy/data-management center, unified cross-device collections, and a fully server-integrated mentor-switching flow should not be promised until implemented and verified.

## Maintaining this documentation

Keep business decisions here, screen behavior in the application guide, and engineering/operations in the technical guide. Update these existing files rather than adding dated reports or another product overview. Required asset credits are included in the technical guide.

Operational agent rules, preferences, runtime prompts, build files, and tests are not additional application documentation. The removed obsolete application documents are recoverable from the cleanup backup outside the repository. Historical output files and supporting tooling remain pending a separately approved cleanup.
