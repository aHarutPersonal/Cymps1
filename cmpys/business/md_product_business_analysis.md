# CMPYS Product and Business Analysis from Markdown Docs

**Date:** 2026-05-13  
**Scope:** All 35 Markdown files in the workspace, excluding generated/vendor folders.  
**Method:** Main review plus three separate specialist agents:
- Business Analyst
- UI/UX Designer
- Product Analyst and Prompt Engineer

Private workspace identity and agent-continuity Markdown files were read for operating context only. They are not used as product/business evidence in this report.

---

## Executive Summary

CMPYS has a strong product idea: help users compare themselves against admired role models at the same age, reveal the gap clearly, and turn that emotional moment into concrete daily learning. The core promise is crisp: "See where you stand. Learn what they did. Close the gap."

The product is most compelling when it is specific, grounded, and daily:
- Specific idol/domain comparison, not generic self-improvement.
- Grounded historical facts, resources, and learning materials.
- Daily focus, streaks, and actionable instructions that convert motivation into habit.

The largest problem is coherence. The docs describe two overlapping products:
- A classic compare -> 12-week plan -> chat -> daily learning app.
- A newer 5-phase agentic mentor flow: intake -> idol selection -> interview -> comparison -> blueprint.

These should not remain parallel experiences. The recommended product model is:

1. Use the agentic flow as activation: fast intake, mentor selection, short interview, age-matched comparison.
2. Convert the output into the existing 12-week plan and daily focus system.
3. Make daily focus, reading, reflection, and mentor chat the retention loop.

The second major issue is documentation and contract drift. The business docs, UI docs, API docs, prompt docs, and implementation task docs disagree in several places. Some differences are product-level, such as 12-week plan versus quarterly blueprint. Others are technical and likely affect quality, such as prompt variables and `daily_instructions` not lining up cleanly across prompt, schema, storage, and API.

---

## Markdown Inventory Reviewed

The review covered:
- Product/business docs: `APP_DOCUMENTATION.md`, `cmpys/business/PRD.md`, `content_quality_spec.md`, `architecture_decisions.md`, `implementation_changelog.md`.
- Planning docs: `cmpys/implementation_plan.md`, `cmpys/task.md`, `cmpys/PROMPT_CHANGELOG.md`.
- Agentic workflow specs: `specs/001-agentic-refactor/*`.
- Backend docs: `cmpys/backend/README.md`, `cmpys/backend/docs/*`.
- Frontend docs: `fe/cmpys/README.md`, `fe/cmpys/user-guide.md`, `fe/cmpys/api-reference.md`, `fe/cmpys/build_instructions.md`, `fe/cmpys/docs/UI_DESIGN_PROMPT.md`.
- Workspace/operator docs: `AGENTS.md`, `SOUL.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`, `IDENTITY.md`.

---

## Product Understanding

### What CMPYS Is

CMPYS is a B2C AI self-improvement and learning app. Users choose or discover a role model, compare their current life trajectory against that person at the same age, and receive a personalized growth plan.

Core product pillars:
- Idol discovery and import.
- Age-matched milestone comparison.
- "Brutal truth" gap analysis.
- Personalized 12-week plan.
- Daily focus and streak loop.
- Long-form learning resources.
- AI mentor chat in the idol's persona.
- Notes, saved ideas, and reflection.

The agentic refactor adds a more emotional activation path:
- Intake.
- Three AI-recommended idols.
- Live in-character interview.
- Harsh first-person comparison.
- Quarterly blueprint.
- Session continuity.

### Target Users

Primary user:
- Ambitious 25-35 year old.
- Has a specific idol or domain they want to master.
- Will spend 20-60 minutes per day on deliberate practice.
- Cares about authentic resources and real techniques.

Secondary user:
- 18-24 explorer.
- Still discovering fields and role models.
- Needs quick wins, motivation, streaks, and a visible sense of progress.

The product is not broadly for "people who want motivation." It is strongest for people with aspirational identity: "I want to become more like Buffett, Einstein, Jobs, Alexander, Marie Curie, etc. in the domain they mastered."

---

## Business Analyst Findings

### Core Business Value

CMPYS attacks the gap between idol worship and disciplined growth. Users often admire high performers but do not know what to copy, what to practice, or how far behind they are. CMPYS turns admiration into:
- A benchmark.
- A gap diagnosis.
- A daily learning path.
- A mentor-style feedback loop.

This is more differentiated than generic AI coaching when the product stays grounded in actual idol timelines, domain-specific skills, and real resources.

### Competitive Positioning

Best positioning:

"Duolingo-like daily progression meets AI mentor roleplay meets age-matched achievement benchmarking."

The wedge is emotional:
- "See what your idol had done by your age."
- "Hear the brutal gap."
- "Get the plan to close it."

The defensible layer is not chat alone. The moat is the structured combination of:
- Idol timelines.
- Persona packs.
- User achievements.
- Gap analysis.
- Plan history.
- Daily completions.
- Content/resource library.
- Reflection and notes.

### Business Model Gaps

The docs do not define:
- Pricing.
- Free versus paid boundaries.
- Subscription tiers.
- Trials.
- Usage limits.
- LLM cost budget per user.
- Gross margin assumptions.
- Entitlements for generated plans, deep lessons, chat, or grounded search.

The implied model is freemium/subscription:
- Free hook: idol suggestion and initial comparison.
- Paid conversion: full blueprint, 12-week plan, detailed lessons, daily coaching, mentor chat, and advanced tracking.

This should be made explicit before adding much more scope, because the product depends on expensive AI generation.

### Retention Analysis

Strong retention foundations:
- Daily focus.
- Streak tracking.
- Continue reading.
- Notifications.
- Plan item completion.
- Mentor chat.
- Reflection prompts.

Still weak or pending:
- Notification settings UI.
- Chat-to-content linking.
- Reflections API/UI.
- Weekly summaries.
- Feed relevance scoring.
- Plan item to idea/resource linking.
- Better profile/settings polish.

Recommendation: make `Today` the retention spine. Every day should answer:
- What should I do today?
- Why does it matter for my chosen idol/domain?
- How will I know I am done?
- What did I learn?

### GTM Implications

Lead with the activation hook, not the full app:
- "Find out what your idol had achieved by your age."
- "Get a brutal comparison and a plan to close the gap."

Likely early channels:
- Productivity and biography creators.
- Ambitious student and young professional communities.
- Domain-specific campaigns, for example Buffett/investing, Einstein/physics, Jobs/product, Alexander/leadership.
- Shareable comparison snippets with strong safety controls.

The current long onboarding path is bad for GTM. The agentic flow should reduce time-to-value.

---

## UI/UX Designer Findings

### UX Strengths

The docs define many expected surfaces:
- Authentication.
- Onboarding.
- Idol search/suggestions.
- Enrichment loading.
- Home dashboard.
- Comparison.
- Plans.
- Chat.
- Notes/stash.
- Achievements.
- Profile/settings.
- Daily feed.
- Agentic workflow.

The design intent is energetic and mobile-native:
- Dark premium UI.
- Deepstash-style content cards.
- TikTok/Reels-style daily feed.
- Typewriter thinking streams.
- Haptics and micro-interactions.
- Progress rings and streaks.

The thinking stream is a good UX pattern because it turns long AI/background work into visible progress.

### Main UX Problem: Split Information Architecture

The docs currently define two first-run flows:

Classic flow:
1. Auth.
2. Profile setup.
3. Idol search/suggest.
4. Idol confirm.
5. Enriching.
6. Intake wizard.
7. Home.

Agentic flow:
1. Age/financial status/interests.
2. Three idol suggestions.
3. Select mentor.
4. Interview.
5. Comparison and blueprint.
6. Guided learning.

The PRD says onboarding compression is pending and the agentic flow should become primary. The UI prompt still treats it as alternative. This needs one canonical UX.

Recommended canonical navigation:
- First-run: Agentic Intake -> Idol Pick -> Interview -> Comparison -> Plan Generation -> Today.
- Main tabs: `Today`, `Plan`, `Mentor`, `Library`, `Profile`.
- Secondary routes: comparison, achievements, notes, task detail, reader, settings.

### Design Improvements Needed

1. Make the long-form reader a first-class screen.
   - The product now promises 2,500+ word book modules and 500+ word lessons.
   - The UI needs progress, section navigation, resume, save insight, reflection, estimated time, and accessible typography.

2. Use large immersive cards only where they fit.
   - Daily Feed can be immersive.
   - Plan, Today, Library, Settings, and Profile should be denser and easier to scan.

3. Add trust cues to AI-heavy screens.
   - Source/confidence labels for historical claims.
   - "AI simulation" disclosure.
   - Clear explanation before collecting financial/life status.
   - Tone control for brutal feedback.

4. Define accessibility before polish.
   - WCAG AA color pairs.
   - Dynamic text scaling.
   - Reduced motion alternatives.
   - Screen reader labels for progress rings and swipe actions.
   - Tap target minimums.
   - Non-color-only category indicators.

5. Replace broad UI prompt with buildable UX spec.
   - Screen state matrix.
   - Navigation rules.
   - Empty/loading/error states.
   - Component acceptance criteria.
   - Copy examples for sensitive moments.

---

## Product Analyst Findings

### How Plans Are Useful for Users

The plans are useful when they are:
- Domain-specific.
- Idol-specific.
- Binary and completable.
- Progressive across weeks.
- Connected to actual resources.
- Broken into daily actions.
- Honest about time required.

The PRD and content quality docs correctly identify the key trust failure: a "15-minute" module that contains 200 words feels fake. The recent direction toward word-count-backed duration and content validation is the right move.

### Where Plan Usefulness Can Break

1. The plan and blueprint may become competing artifacts.
   - A quarterly blueprint is strategic.
   - A 12-week plan is executable.
   - Users should not receive two roadmaps with unclear relationship.

   Recommendation: make the blueprint the mentor's strategic diagnosis, then generate the 12-week plan as the execution layer.

2. Daily work can become invisible if instructions do not reach the UI.
   - The product promise depends on `daily_instructions`.
   - If these are missing from today's task view, the daily loop becomes generic again.

3. Content depth without UX support can backfire.
   - Long lessons are valuable only if the reader is comfortable.
   - Without progress, summaries, resume, and reflection, users may bounce from deep content.

4. "Brutal truth" can activate or alienate.
   - It should always end with agency: the next concrete action.
   - Consider intensity settings and recovery copy.

### Product Metrics to Instrument

Activation:
- Intake started.
- Idol suggestions generated.
- Idol selected.
- Interview completed.
- Comparison generated.
- Blueprint viewed.
- First plan generated.

Retention:
- Day-1 and Day-7 return.
- Daily focus viewed.
- Daily focus completed.
- Continue reading opened.
- Lesson completed.
- Reflection saved.
- Weekly summary viewed.

Quality:
- Content accepted below target.
- Retry rate.
- Unresolved prompt placeholders.
- Historical claim confidence.
- Resource URL validity.
- LLM cost per activated user.

---

## Prompt Engineer Findings

### What Good Prompting Should Achieve

The ideal prompt system should produce:
- Plans grounded in the idol's real domain.
- Tasks that are binary and completable.
- Daily rhythm tasks with exact instructions.
- Long-form lessons that teach, not advise.
- Resources with canonical titles/authors.
- Accurate duration based on content length.
- Historical claims grounded in reliable evidence.
- Persona voice without sacrificing clarity or safety.

### Prompt/Contract Risks

1. Prompt variable drift.
   - `plan_generate.txt` expects structured variables such as idol profile, persona, milestones, gaps, readiness, and target age.
   - The prompt registry and generator path still need to consistently pass and validate all of them.
   - Strict rendering should fail if placeholders remain unresolved.

2. `daily_instructions` storage/read mismatch.
   - Docs say these are stored in `meta_json`.
   - Some daily task response code reads from `details_json`.
   - This can prevent the daily UI from showing the specific daily script.

3. Validation thresholds are below product promises.
   - Business docs require 2,500+ words for book modules and 500+ words per lesson step.
   - Retry thresholds documented in some places are 1,500 and 300.
   - If the business promise is the minimum, validation should match it.

4. API examples under-specify rich learning payloads.
   - Detailed plan item docs should include `lessonContent`, `substeps`, `definitionOfDone`, `mentalModel`, `contentMarkdown`, resource IDs, and `dailyInstructions`.

5. Provider strategy is inconsistent.
   - PRD names OpenAI GPT-4o.
   - Agentic spec requires Gemini with Google Search grounding.
   - Backend README still documents OpenAI/dummy as the main LLM configuration.

### Prompt System Recommendations

1. Add a single prompt contract table.
   - Prompt name.
   - Required variables.
   - Producer service.
   - Output schema.
   - Validation thresholds.
   - UI consumer.

2. Enforce strict placeholder rendering in all production paths.
   - Missing variables should fail before calling the model.
   - Add tests for unresolved `{placeholder}` strings in rendered prompts.

3. Align output schemas with frontend needs.
   - Plan item details should explicitly support teaching content, practice steps, completion criteria, source resources, and reflection prompts.

4. Raise validation thresholds or rename the business promise.
   - If a "15-minute module" must be 2,500+ words, validation should not accept 1,500 words as success unless explicitly labeled degraded.

5. Make thinking streams evidence-rich.
   - Use them to preview real discoveries, sources, milestones, and next steps.
   - Avoid generic "thinking" messages.

---

## Cross-Document Contradictions and Drift

### 1. Product Core

Problem:
- Some docs center the 12-week plan.
- Agentic docs center a 5-phase mentor session and quarterly blueprint.

Recommendation:
- Make the agentic flow the activation funnel.
- Make the 12-week plan the execution artifact.
- Treat the quarterly blueprint as a strategic summary, not a separate plan users must reconcile.

### 2. Onboarding

Problem:
- Classic onboarding is too long for consumer activation.
- PRD already marks onboarding compression as pending.

Recommendation:
- Minimum first-run fields: age, goal/interests, optionally life status.
- Generate 3 idols.
- Run 3-turn interview.
- Show comparison.
- Defer profile enrichment and achievement logging until after value delivery.

### 3. LLM Provider Strategy

Problem:
- Docs disagree between OpenAI and Gemini.

Recommendation:
- Define provider by use case:
  - Grounded historical/resource lookup: Gemini with Google Search, if that is the intended implementation.
  - Structured JSON generation: whichever provider is production standard.
  - Thinking stream: cheap/fast model.
- Update README, PRD, and prompt docs to match.

### 4. Task Status

Problem:
- `specs/001-agentic-refactor/tasks.md` has duplicate task IDs and contradictory checked/unchecked status.

Recommendation:
- Clean this file or replace it with one canonical implementation tracker.

### 5. API Documentation Drift

Problem:
- Backend API docs include newer content library/streak/daily focus endpoints.
- Frontend API docs appear older and omit some newer surfaces.

Recommendation:
- Generate or maintain one API source of truth and sync frontend docs from it.

---

## Prioritized Action Plan

### P0: Make the Product Coherent

1. Declare the primary product spine:
   - Agentic activation -> 12-week execution -> daily retention.

2. Rewrite the user journey:
   - First-run: intake -> idol pick -> interview -> comparison -> plan.
   - Daily use: Today -> plan task -> lesson/reflection -> mentor chat as support.

3. Rename/position blueprint:
   - "Strategic Blueprint" or "Mentor Verdict" as a summary.
   - 12-week plan as the actionable schedule.

### P1: Fix Prompt and Data Contracts

1. Register and pass every `plan_generate.txt` variable.
2. Make strict rendering fail on unresolved placeholders.
3. Ensure `daily_instructions` is read from the same place it is stored.
4. Update detailed plan item API docs to include the rich learning payload.
5. Align validation thresholds with business promises.

### P2: Strengthen Retention Loop

1. Make Today the main landing tab after activation.
2. Prioritize notification settings UI.
3. Add reflection capture.
4. Add weekly summary.
5. Add chat-to-content linking.
6. Add plan item -> ideas/resources linking.

### P3: Improve UX Trust and Safety

1. Add source/confidence labels for claims.
2. Add tone/intensity control for brutal feedback.
3. Add AI simulation disclosure.
4. Add data-use explanation before sensitive intake fields.
5. End every comparison with a concrete next action.

### P4: Create Source-of-Truth Docs

Create:
- `cmpys/business/product_strategy.md`
- `fe/cmpys/docs/UX_SPEC.md`
- `cmpys/backend/docs/prompt_contracts.md`
- One canonical API contract, preferably generated from backend schemas/OpenAPI.

---

## Suggested Next Documents

### `product_strategy.md`

Should define:
- Positioning.
- Personas.
- Activation loop.
- Retention loop.
- Monetization.
- Pricing/entitlement assumptions.
- Metrics.
- Roadmap priorities.

### `UX_SPEC.md`

Should define:
- Canonical IA.
- First-run flow.
- Main tabs.
- Screen-by-screen states.
- Component behavior.
- Loading/error/empty states.
- Accessibility rules.
- Trust/safety patterns.

### `prompt_contracts.md`

Should define:
- Prompt template.
- Required variables.
- Output schema.
- Validation rules.
- Retry behavior.
- Storage destination.
- API/UI consumer.

---

## Final Recommendation

Do not add broad new features yet. CMPYS is closest to being valuable when every layer obeys the same promise:

"A mentor-like idol comparison creates the emotional spark; a grounded 12-week plan turns it into daily progress."

The next best work is to unify the funnel, fix prompt/data contracts, and make the daily focus loop excellent.
