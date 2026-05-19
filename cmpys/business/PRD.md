# CMPYS Product Requirements Document

**Product:** CMPYS (Compare Your Success)  
**Last Updated:** 2026-05-13  
**Status:** Active Development

---

## 1. Product Overview

CMPYS is a mobile app that compares a user's life progress against historical idols (role models). Users select an idol, see a "brutal truth" comparison of where the idol was at their age, and receive a personalized 12-week development plan grounded in the idol's actual methods and trajectory.

### Canonical Product Spine

The primary product flow is **agentic activation -> 12-week execution -> daily retention**:

1. **Agentic activation:** minimal intake, three mentor suggestions, live diagnostic interview, Mirror comparison, and strategic blueprint.
2. **12-week execution:** the strategic blueprint becomes the actionable schedule with weekly missions, daily rhythm tasks, lessons, resources, and completion criteria.
3. **Daily retention:** Today shows the user's daily focus, streak, continue-reading item, reflection prompt, and mentor support.

The strategic blueprint is the mentor's verdict. The 12-week plan is the execution artifact users follow every day.

### Core Value Proposition

**"See where you stand. Learn what they did. Close the gap."**

The app transforms idol worship into actionable growth by:
1. Showing users exactly how they compare to their idol at the same age
2. Breaking the idol's trajectory into learnable skills and habits
3. Providing daily, domain-specific learning tasks that close the user's gaps
4. Creating genuine 15-60 minute learning experiences, not 2-minute reads labeled as 30-minute sessions

---

## 2. User Personas

### Primary: The Aspiring Achiever (25-35)
- Has a specific idol or domain they want to master
- Wants structured, progressive learning — not random tips
- Willing to spend 20-60 min/day on deliberate practice
- Values authenticity: real books, real techniques, real milestones

### Secondary: The Curious Explorer (18-24)
- Exploring different fields and role models
- Needs engaging content to stay motivated
- Shorter attention span; needs quick wins and streaks
- Wants to feel like they're making progress from Day 1

---

## 3. Core Business Requirements

### BR-01: Authentic Content Depth
**Requirement:** All learning content must match its claimed duration. A "15-minute module" must provide 15 minutes of genuine reading/learning material (2,500-4,000 words). A "60-minute mission" must have 500-1,200 word lessons per step with actionable exercises.

**Rationale:** The #1 reason users churn from learning apps is content that overpromises and underdelivers. Showing "60 min" next to a 200-word lesson destroys trust.

**Acceptance Criteria:**
- Book modules: `content_markdown` >= 2,500 words, `duration_minutes` = `word_count / 200`
- Plan item lessons: each `lesson_content` >= 500 words, steps claiming 60+ min must have 800+ words
- Daily rhythm tasks: `daily_instructions` >= 40 words with specific, measurable actions
- Plan item descriptions: mission tasks >= 50 words, daily rhythm >= 30 words
- Backend validates word counts and retries generation when content is too thin

### BR-02: Domain-Specific Learning Paths
**Requirement:** Every task, habit, and resource must be grounded in the specific idol's actual field. Generic self-help advice ("stay focused", "network more") is forbidden.

**Rationale:** Users chose a specific idol for a reason. A Buffett plan about "networking" misses the point — it should be about reading annual reports and understanding intrinsic value.

**Acceptance Criteria:**
- Plan generator prompt enforces domain-specificity (Rule #1)
- Anti-goals reference specific domain traps (e.g., "Don't jump to quantum mechanics before mastering classical mechanics")
- Resources reference specific books, techniques, and methods used by the idol

### BR-03: Accurate Duration Display
**Requirement:** The duration shown to users must reflect actual reading time, not aspirational labels.

**Rationale:** If a user clicks a "15 min" module and finishes it in 3 minutes, they lose trust and won't engage with future content.

**Acceptance Criteria:**
- `duration_minutes` calculated from `word_count / 200` (average reading speed), minimum 5 minutes
- No hardcoded duration values (previously all book modules defaulted to 15 min)
- Frontend displays calculated duration consistently

### BR-04: Daily Engagement Loop
**Requirement:** Users must have a reason to return every day — streak tracking, daily focus tasks, and notification reminders.

**Rationale:** A learning app without daily engagement mechanics dies. Users need both the habit trigger (notification) and the habit loop (streak + focus task + reflection).

**Acceptance Criteria:**
- Streak API returns consecutive days with completions
- Daily focus API returns today's primary habit/practice item with a reflection prompt
- Notification scheduling at user-chosen time (default 9am)
- Streak badge visible on home screen
- Continue reading card on home screen for in-progress content

### BR-05: Content Progression (Not Just Time-Bucketing)
**Requirement:** Learning paths must progress from foundation to mastery, not just bucket tasks by week number.

**Rationale:** Week-based grouping is organizational, not pedagogical. Users need prerequisite chains — you can't understand intrinsic value without first understanding financial statements.

**Acceptance Criteria:**
- Plan prompt enforces 3-phase structure: Foundation (Wk 1-3), Core Skills (Wk 4-6), Applied Practice (Wk 7-9), Integration (Wk 10-12)
- Daily rhythm tasks progress across weeks (simpler -> more complex -> creative output)
- Each week's tasks reference prior weeks' skills

### BR-06: Binary Mission Completion
**Requirement:** Mission tasks must be unambiguously completable — either 100% done or not done.

**Rationale:** "Study physics" is vague and uncompletable. "Complete problems 1-15 in Chapter 3 of Goldstein" is binary and actionable.

**Acceptance Criteria:**
- Every mission task has a clear deliverable or measurable outcome
- `estimated_hours` preserved from LLM output (not computed from week-level division)
- `daily_instructions` field provides 3-5 sentences of specific, daily guidance

---

## 4. Feature Requirements by Priority

### P0: Content Depth & Quality (COMPLETE)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P0-A | Book modules >= 2,500 words | Done | Users get real 15-min learning modules |
| P0-B | Lesson content >= 500 words per step | Done | Each learning step is substantive |
| P0-C | Plan generator preserves `estimated_hours` and `daily_instructions` | Done | Duration claims are enforceable |
| P0-D | Backend content quality validation + retry | Done | Thin content caught before reaching users |
| P0-E | `duration_minutes` from word count | Done | UI shows accurate reading times |
| P0-INFRA | Content library, streak, daily focus, chat context, continue reading | Done | Core infrastructure for content consumption |

### P1: Daily Engagement (PARTIALLY COMPLETE)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P1-01 | Streak API + badge | Done | Daily habit trigger |
| P1-02 | Daily focus API | Done | Focused daily task |
| P1-03 | Notification service | Done | Re-engagement mechanism |
| P1-04 | Notification settings UI | Pending | User control over reminders |

### P2: Chat Context Awareness (PARTIALLY COMPLETE)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P2-01 | Enhanced chat system prompt with plan context | Done | More relevant AI conversations |
| P2-02 | Dynamic quick actions | Done | Faster access to key features |
| P2-03 | Chat-to-content linking | Pending | Make chat insights actionable |

### P3: Agentic Activation (IN PROGRESS)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P3-01 | Make agentic flow primary | In progress | Reduce drop-off from 8-10 screens to 4-5 |
| P3-02 | Merge IdolSuggest + IdolConfirm | Pending | Fewer screens before value delivery |
| P3-03 | Position blueprint as strategic verdict | In progress | Prevent roadmap confusion; 12-week plan stays actionable |

### P4: Content Personalization (NOT STARTED)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P4-01 | Feed relevance scoring | Pending | Ideas connect to current learning |
| P4-02 | "Relevant to Week X" badge | Pending | Shows content is connected to plan |
| P4-03 | Plan item -> Ideas link | Pending | Cross-pollinate learning materials |

### P5: Reflection & Journaling (NOT STARTED)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P5-01 | Reflections API | Pending | Users can save insights |
| P5-02 | Reflection bottom sheet | Pending | Replace "Submit Insight -> chat" surprise |
| P5-03 | Weekly summary card | Pending | Progress visibility |

### P6: UI/UX Polish (NOT STARTED)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P6-01 | Accessibility (semantics, contrast) | Pending | WCAG AA compliance |
| P6-02 | Dark theme | Pending | High user expectation |
| P6-03 | Error handling consistency | Pending | Professional UX |

### P7: Profile & Settings (NOT STARTED)

| ID | Feature | Status | Business Impact |
|----|---------|--------|-----------------|
| P7-01 | Edit profile | Pending | User account management |
| P7-02 | Notification settings UI | Pending | Control over reminders |
| P7-03 | Appearance settings | Pending | Theme preference |
| P7-04 | Help center / legal pages | Pending | Compliance and support |

---

## 5. Key Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| Content depth ratio | >= 80% of modules meet word count minimums | Backend validation logs |
| Average content duration accuracy | Within 3 min of claimed duration | `word_count / 200` vs `duration_minutes` |
| Daily active users (DAU) | Track after P1 complete | Streak API + daily focus usage |
| Plan completion rate | >= 30% complete at least 1 week | Plan item status tracking |
| Day-7 retention | >= 25% | User activity tracking |
| Chat engagement | >= 2 messages per session | Chat thread message counts |

### Monetization Planning Assumptions

These assumptions guide roadmap decisions and are not implemented entitlements yet:

- Free activation can include mentor suggestions and a limited comparison preview.
- Paid value should center on the full strategic blueprint, 12-week plan, deep lessons, daily coaching, and extended mentor chat.
- Usage limits must protect LLM costs for grounded search, plan generation, detailed lessons, and chat.
- Upgrade prompts should appear after the emotional comparison and before deep execution value.

---

## 6. Technical Constraints

- **Frontend:** Flutter/Dart with Riverpod state management, GoRouter navigation
- **Backend:** Python FastAPI with SQLModel/SQLAlchemy, PostgreSQL, Celery + Redis for async tasks
- **LLM Pipeline:** OpenAI GPT-4o for content generation, GPT-4o-mini for thinking streams
- **Content Generation:** All learning content generated via prompt templates in `/prompts/`, validated by backend before storage
- **Mobile Platforms:** iOS and Android via Flutter
