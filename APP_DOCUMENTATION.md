# CMPYS (CoMPare Your Success) - Application Documentation

## Overview
**CMPYS** is a comprehensive, AI-powered mobile application designed to help users compare their life journey, achievements, and milestones against historical or contemporary "idols" (famous personalities, entrepreneurs, scientists, artists). By establishing a user's current baseline and mapping it against an idol's trajectory at the exact same age, the app delivers highly personalized, actionable 12-week growth plans, socratic mentorship, and microlearning resources.

---

## Core Functionalities

### 1. User Onboarding & Profiling
* **Authentication**: Secure sign-up/sign-in flows supporting email/password and social OAuth.
* **Intake Wizard**: A detailed, multi-step assessment covering the user's skills, experience, financial status, goals, and core interests.
* **Profile Management**: Settings to adjust personal data, focus areas, and timezone to contextualize plan generation.

### 2. Idol Discovery & Import (AI-Driven Pipeline)
* **Search & Suggestions**: Users can search for specific idols manually or rely on AI-powered suggestions tailored to their profile and interests.
* **Data Enrichment Pipeline**: Once selected, a Celery-backed worker automatically fetches data from Wikidata and utilizes LLMs to extract timelines, generate personas, and complete the idol's historical profile.
* **Lazy-Loading Generation**: Avatars and deep timelines are progressively enriched and stored in the PostgreSQL database, updating the frontend smoothly as data becomes ready.

### 3. Comparison Engine (The "Brutal Truth")
* **Age-Matched Milestones**: The app identifies exactly what the selected idol had achieved at the user's *current* age.
* **Gap Analysis**: A visual comparison showcasing strengths, areas for improvement, and missing milestones using scorecards and percentage metrics across categories (Career, Education, Skills, Personal, Creativity).

### 4. 12-Week Plan Generation (AI Blueprint)
* **Goal Scaffolding**: Utilizing the gap analysis, the LLM constructs an immutable 12-week actionable development plan designed to bridge the difference.
* **Interactive Task Tracking**: Weekly goal cards with progress rings, detailed task steps, and learning resources. Task completions are driven by haptic feedback and dynamic animations.
* **Guided Learning (Socratic Method)**: Dedicated interfaces offering curated reading materials and active, contextual learning interactions via AI to deeply understand required topics rather than simply receiving direct answers.

### 5. Chat & Mentorship (Idol Persona)
* **Persona Generation**: Each idol comes with a specifically tailored "Persona Pack" defining their voice, principles, do's, don'ts, and signature phrases.
* **Real-time Interaction**: A text-based chat interface allowing the user to converse with the AI simulating the idol. Features include dynamic streaming responses and suggested quick-prompts for guidance.
* **Strict Safety Rails**: Enforced guards against modern jargon and out-of-character behavior to maintain historical purity.

### 6. Achievements & Notes (Personal Stash)
* **Achievements Tracker**: Allows the user to manually log their real-world milestones (with dates, notes, and evidence) to continuously update their comparison score.
* **Personal Stash**: A dedicated section to save, categorize, and organize microlearning insights, notes, and ideas discovered during the learning process.

### 7. Daily Insights Feed (Microlearning)
* **Bite-Sized Ideas**: A swipeable, vertical feed (TikTok-style) of short knowledge snippets (< 200 words) attributed to various idols.
* **TTS (Text-to-Speech)**: Audio playback capabilities to listen to the insights on the go.

---

## Documentation Index

The following specific Markdown documentation files are available across the repository for deep technical and architectural context:

### Backend Documentation
* **[Backend Readme](file:///Users/harutantonyan/work/cmpys/backend/README.md)**: Main entry point for backend context.
* **[User Guide](file:///Users/harutantonyan/work/cmpys/backend/docs/user_guide.md)**: Comprehensive guide for setup, infrastructure (Docker, Redis, PostgreSQL), API commands, and application usage flows.
* **[API Reference](file:///Users/harutantonyan/work/cmpys/backend/docs/api_reference.md)**: Detailed endpoint schemas and routing maps.
* **[Prompt Wiring](file:///Users/harutantonyan/work/cmpys/backend/docs/prompt_wiring.md)** & **[LLM Prompt Wiring](file:///Users/harutantonyan/work/cmpys/backend/docs/llm_prompt_wiring.md)**: Details on how local/cloud LLMs are structured to extract data and build personas without breaking formatting.
* **[FE Thinking Stream](file:///Users/harutantonyan/work/cmpys/backend/docs/fe_thinking_stream.md)**: Information related to the streaming logic implemented for the UI chat responses and plan generation states.

### Frontend Documentation (Flutter)
* **[Frontend Readme](file:///Users/harutantonyan/work/fe/cmpys/README.md)**: Root documentation for the Flutter application.
* **[UI Design Prompt](file:///Users/harutantonyan/work/fe/cmpys/docs/UI_DESIGN_PROMPT.md)**: Comprehensive design guidelines, screen breakdowns, aesthetic notes (Deepstash UI inspiration), and navigation maps.
* **[Frontend User Guide](file:///Users/harutantonyan/work/fe/cmpys/user-guide.md)**: User flows specific to the Flutter app.
* **[Frontend API Reference](file:///Users/harutantonyan/work/fe/cmpys/api-reference.md)**: Client-side integration details for networking and Dio usage.
* **[Build Instructions](file:///Users/harutantonyan/work/fe/cmpys/build_instructions.md)**: Commands and requirements for compiling and running the iOS/Android targets.

---

## System Architecture Reference
* **Backend Framework**: Python 3.11+, FastAPI, SQLModel (Pydantic + SQLAlchemy).
* **Database & Queues**: PostgreSQL (Main Storage), Redis (Caching), Celery (Background Workers).
* **Frontend Framework**: Flutter (Stable), Riverpod (State Management), GoRouter (Navigation).
* **Design Pattern Alignment**: The backend provides exactly mapped JSON via REST. Python handles `snake_case` serialization which the Dart models meticulously parse into `camelCase` for client logic.
