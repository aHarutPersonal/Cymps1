# Feature Specification: Agentic Persona Workflow

**Feature Branch**: `001-agentic-refactor`
**Created**: 2026-02-20
**Status**: Draft
**Input**: User description: "Architectural Refactoring, Agentic Workflow, and Advanced Prompt Engineering — transform CMPYS into a stateful, multi-turn persona-driven mentoring experience powered by Gemini with Web Search Grounding."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Intake & Idol Discovery (Priority: P1)

A new user opens the app, enters their age, current financial/life status, and personal interests. The system processes these inputs and suggests three relevant historical or modern idols whose life trajectories align with the user's interests and ambitions. The user selects one idol to begin their mentoring session.

**Why this priority**: This is the entry point for the entire experience. Without intake and idol selection, no downstream states (interview, comparison, blueprint) can execute. This is the MVP gate.

**Independent Test**: Can be fully tested by submitting intake data and verifying that three relevant idol suggestions are returned with biographical summaries. Delivers standalone value as a "discover your mentor" feature.

**Acceptance Scenarios**:

1. **Given** the user has not started a session, **When** they submit age (e.g., 28), financial status (e.g., "$6,000/month salary"), and interests (e.g., "military strategy, leadership, empire building"), **Then** the system returns exactly 3 idol suggestions with name, era, one-sentence relevance summary, and a portrait.
2. **Given** the system has returned 3 suggestions, **When** the user selects one idol, **Then** the system transitions to the live interview state and the selected idol's persona is loaded.
3. **Given** the user submits incomplete intake data (e.g., missing age), **When** they attempt to proceed, **Then** the system displays a clear validation error and does not advance.

---

### User Story 2 - Live In-Character Interview (Priority: P1)

After selecting an idol, the AI fully adopts the idol's persona and begins a live, turn-by-turn interrogation. The AI speaks in the first person as the idol, asks exactly one sharp question per turn to expose the user's baseline (skills, resources, knowledge gaps), waits for the user's response, reacts emotionally in-character, and then asks the next question. The interview lasts 3–5 turns before automatically transitioning to the comparison.

**Why this priority**: This is the core emotional hook of the product — the live dialogue that differentiates CMPYS from static comparison tools. Without it, the comparison and blueprint lack personalization.

**Independent Test**: Can be tested by selecting an idol and verifying that: (a) the AI speaks as the idol in first person, (b) exactly one question is asked per turn, (c) the AI reacts to user answers before asking the next question, (d) the interview ends after 3–5 turns and transitions automatically.

**Acceptance Scenarios**:

1. **Given** the user has selected an idol (e.g., Alexander the Great), **When** the interview begins, **Then** the AI introduces itself in-character and asks exactly one targeted question about the user's current situation.
2. **Given** the user has answered a question, **When** the AI responds, **Then** it reacts emotionally to the answer in-character (e.g., expressing disappointment, surprise, or approval) and asks exactly one follow-up question — never multiple.
3. **Given** 3–5 interview turns have been completed, **When** the final answer is received, **Then** the system automatically transitions to the Brutal Comparison state without requiring user action.
4. **Given** the interview is in progress, **When** the user sends an off-topic message, **Then** the AI redirects back to the interview in-character without breaking persona.

---

### User Story 3 - Brutal Reality Comparison (Priority: P1)

After the interview, the AI (still fully in-character) delivers a harsh, first-person comparison. It uses verified factual data about what the idol had achieved at the user's exact age and contrasts it with the user's self-reported baseline from the interview. The comparison is emotionally intense, specific, and grounded in real historical facts.

**Why this priority**: This is the "moment of truth" that creates the emotional impact and viral shareability. The comparison must be factually grounded (via web search) and deeply personalized (using interview data).

**Independent Test**: Can be tested by providing a completed interview transcript and idol identity, then verifying the comparison references: (a) specific idol achievements at the user's age, (b) specific user responses from the interview, (c) first-person idol voice, (d) factual accuracy of historical claims.

**Acceptance Scenarios**:

1. **Given** the interview is complete, **When** the comparison is generated, **Then** it includes at least 3 specific achievements the idol had accomplished by the user's exact age, all verified via web search grounding.
2. **Given** the user reported specific details during the interview (e.g., salary, team size, skills), **When** the comparison is delivered, **Then** those exact details are referenced and contrasted with the idol's equivalent achievements.
3. **Given** the idol is a historical figure, **When** achievements are cited, **Then** all historical claims are factually accurate and sourced from web search results.

---

### User Story 4 - Quarterly Blueprint Generation (Priority: P2)

After the comparison, the AI generates a highly specific, actionable roadmap broken into four quarters (Q1–Q4). The blueprint translates the idol's historical trajectory into 21st-century actionable steps. Q1 focuses on closing foundational gaps with exact study materials (found via web search). Q2–Q4 focus on aggressive scaling. Each quarter includes tangible milestones.

**Why this priority**: The blueprint is the payoff — the actionable value that keeps users engaged long-term. It depends on all prior states (intake, interview, comparison) being complete and personalized.

**Independent Test**: Can be tested by providing completed interview + comparison context and verifying: (a) 4 distinct quarters with escalating complexity, (b) Q1 includes at least 3 specific study materials with real URLs found via search, (c) each quarter has measurable milestones, (d) the blueprint adapts ancient achievements to modern equivalents.

**Acceptance Scenarios**:

1. **Given** the comparison is complete, **When** the blueprint is generated, **Then** it contains exactly 4 quarters (Q1, Q2, Q3, Q4) with distinct focus areas and escalating ambition.
2. **Given** Q1 is generated, **When** study materials are recommended, **Then** each material is a real, currently available resource (book, course, platform) verified via web search — no fabricated URLs.
3. **Given** the idol is a historical figure (e.g., Alexander the Great), **When** their achievements are referenced in the blueprint, **Then** military/political achievements are translated into modern business equivalents (e.g., "conquering territories" → "aggressive market expansion").
4. **Given** the blueprint is generated, **When** the user views it, **Then** it is formatted in clean Markdown with clear Q1/Q2/Q3/Q4 headers, bullet points, and actionable milestones.

---

### User Story 5 - State Continuity & Context Preservation (Priority: P2)

The system maintains full conversational context across all five states. The exact Q&A from the interview, the web-searched facts about the idol, and the user's intake data are all seamlessly passed forward so that the comparison and blueprint are 100% consistent with everything discussed. If the user returns to the app, their session state is preserved.

**Why this priority**: Without state continuity, the comparison and blueprint become generic and disconnected from the interview. Context preservation is the technical backbone that makes personalization work.

**Independent Test**: Can be tested by completing a full 5-state flow and verifying that: (a) the comparison references exact interview answers, (b) the blueprint references exact comparison points, (c) returning to the app after closing it resumes the session at the correct state.

**Acceptance Scenarios**:

1. **Given** the user answered "I make $6,000/month and lead a team of 2" during the interview, **When** the comparison is generated, **Then** those exact figures appear in the comparison text.
2. **Given** the comparison mentioned "You need to master strategic thinking", **When** the Q1 blueprint is generated, **Then** it includes specific resources for strategic thinking.
3. **Given** the user closes the app mid-interview (after turn 2 of 5), **When** they reopen the app, **Then** the session resumes at interview turn 3 with full prior context preserved.

---

### Edge Cases

- What happens when web search returns no relevant results for an obscure idol's achievements at a specific age? → System uses best available biographical data and clearly states when data confidence is lower.
- How does the system handle a user who provides obviously false intake data (e.g., age: 5, salary: $10M)? → System proceeds without judgment — the idol persona handles skepticism in-character.
- What happens if the user tries to start a new session while one is in progress? → System prompts the user to complete or abandon the current session before starting a new one.
- What if the LLM breaks character during the interview? → The system prompt enforces character maintenance; if detected, the response is regenerated.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST implement a 5-state workflow: Intake → Idol Selection → Interview → Comparison → Blueprint, with enforced sequential transitions.
- **FR-002**: System MUST maintain full conversation context across all 5 states within a single session, including user intake data, interview Q&A pairs, web search results, and generated content.
- **FR-003**: During the Interview state, system MUST enforce exactly one question per AI turn and MUST track turn count (3–5 turns) before auto-transitioning.
- **FR-004**: System MUST use web search grounding to verify idol achievements at the user's exact age before generating the comparison.
- **FR-005**: System MUST use web search grounding to find real, currently available study materials (books, courses, platforms) for the blueprint.
- **FR-006**: All idol-facing AI output MUST maintain first-person persona voice throughout states 3, 4, and 5 — never breaking character.
- **FR-007**: System MUST translate historical achievements into 21st-century equivalents when the idol is a historical figure.
- **FR-008**: The Quarterly Blueprint MUST contain exactly 4 quarters with escalating complexity and at least 3 verifiable resource recommendations in Q1.
- **FR-009**: System MUST persist session state so users can resume interrupted sessions.
- **FR-010**: System MUST return idol suggestions within a reasonable time after intake submission.
- **FR-011**: System MUST gracefully degrade when web search returns insufficient data — proceeding with available information rather than failing.
- **FR-012**: All historical claims in the comparison and blueprint MUST be grounded in web-searched facts, not hallucinated.

### Key Entities

- **Session**: Represents a single end-to-end mentoring flow. Tracks current state (1–5), user intake data, selected idol, interview transcript, comparison output, and blueprint output.
- **Idol**: A historical or modern figure with biographical data, achievements timeline, and persona characteristics. Achievements are indexed by the age at which they occurred.
- **Interview Turn**: A single Q&A pair within State 3. Contains the AI's question, user's response, and the AI's emotional reaction. Ordered sequentially within a session.
- **Blueprint**: A structured quarterly plan generated in State 5. Contains 4 quarters, each with focus areas, specific resources, and measurable milestones.
- **User Profile**: The user's intake data — age, financial/life status, and interests — that persists across sessions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users complete the full 5-state flow (intake → blueprint) in a single session at least 70% of the time (no drop-off between states).
- **SC-002**: The interview phase enforces exactly one question per turn with 100% consistency — zero multi-question responses.
- **SC-003**: At least 90% of historical claims in comparisons are factually verifiable against public biographical sources.
- **SC-004**: At least 80% of Q1 resource recommendations (books, courses, URLs) are real and currently accessible.
- **SC-005**: Users who complete a session rate the experience as emotionally impactful (≥4/5 on impact scale) at least 60% of the time.
- **SC-006**: Interrupted sessions are resumable with full context within 24 hours of interruption at least 95% of the time.
- **SC-007**: The AI maintains consistent first-person persona voice throughout all in-character states (3, 4, 5) with zero character breaks in at least 95% of sessions.
