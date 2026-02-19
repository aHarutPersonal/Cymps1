# CMPYS Agent Rules - Main System Documentation

> **Version:** 2.0
> **Last Updated:** 2026-02-02
> **Purpose:** Master rules file for any AI/LLM agent working on the CMPYS codebase.

---

## 🎯 APPLICATION MISSION

**CMPYS ("CoMPare Your Success")** is a **life-changing personal development application** that helps users achieve their goals by comparing their life progress against historical role models ("Idols").

### Core Philosophy
> *"What had Elon Musk achieved by the time he was your age?"*

### Quality Standards
This application MUST be built to the **HIGHEST QUALITY** because it will:
- Help real people achieve their life goals
- Provide skills and knowledge required for success
- Guide users toward becoming similar to their idols
- Offer **small but 100% sure steps** toward achievement

**THERE IS NO ROOM FOR BUGS, REGRESSIONS, OR HALF-IMPLEMENTED FEATURES.**

---

## 📋 MANDATORY AGENT WORKFLOW

### Before ANY Change

1. **ANALYZE** - Fully understand the request
   - Read all related code files
   - Understand current implementation
   - Identify all affected components

2. **PLAN** - Create explicit implementation plan
   - List files to modify
   - List new files to create
   - Identify potential regressions
   - Document verification steps

3. **ASK QUESTIONS** - If ANY ambiguity exists:
   - Implementation approach unclear? ASK.
   - Multiple valid solutions? ASK which preferred.
   - Breaking change potential? ASK for confirmation.
   - **DO NOT GUESS. DO NOT ASSUME.**

### During Change

4. **IMPLEMENT** - Make changes carefully
   - One logical change at a time
   - Keep existing comments/code unless explicitly removing
   - Match project conventions exactly

### After EVERY Change

5. **VERIFY** - Double-check everything:
   - [ ] Code compiles/builds without errors
   - [ ] No TypeScript/Dart/Python linting errors
   - [ ] Related tests still pass
   - [ ] No functionality regression
   - [ ] API contracts still match (backend ↔ frontend)
   - [ ] Changes work as expected

6. **SYNC CHECK** - Critical for full-stack changes:
   - **IF BACKEND CHANGE:** Verify Flutter `fromJson`/`toJson` models match
   - **IF FRONTEND CHANGE:** Verify Backend endpoint exists with correct parameters
   - **IF PROMPT CHANGE:** Verify code that uses prompt handles new/changed fields

---

## 🏗️ PROJECT STRUCTURE

```
cmpys/
├── .agent/rules/           # Agent rules (THIS DIRECTORY)
│   ├── main.md             # Main rules (this file)
│   ├── backend.md          # Backend-specific rules
│   ├── frontend.md         # Frontend-specific rules
│   └── prompts.md          # LLM prompt rules
├── backend/                # Python FastAPI backend
│   ├── app/
│   │   ├── api/v1/         # API endpoints
│   │   ├── models/         # SQLAlchemy models
│   │   ├── schemas/        # Pydantic schemas
│   │   ├── services/       # Business logic
│   │   └── core/           # Config, security, celery
│   └── prompts/            # LLM prompt templates
├── fe/cmpys/               # Flutter frontend (SEPARATE REPO)
│   └── lib/
│       ├── features/       # Feature modules
│       ├── core/           # Shared utilities
│       └── app/            # App config, routing
└── infra/                  # Docker infrastructure
```

---

## 🔐 CORE FEATURES OVERVIEW

| Feature | Purpose | Key Endpoints |
|---------|---------|---------------|
| **Auth** | User registration, login, JWT tokens | `/auth/*` |
| **Profile** | User data, interests, birth date | `/me` |
| **Idols** | Role model discovery, import, data | `/idols/*` |
| **Comparison** | User vs idol achievement comparison | `/comparison` |
| **Plans** | 12-week personalized development plans | `/plans/*` |
| **Chat** | AI persona conversations | `/chat/*` |
| **Notes** | User note-taking | `/notes/*` |
| **Achievements** | User milestone logging | `/achievements/*` |
| **Jobs** | Async background processing | `/jobs/*` |

See domain-specific rule files for detailed documentation.

---

## ⚠️ CRITICAL RULES

### 1. Naming Conventions (NEVER VIOLATE)
| Layer | Convention | Example |
|-------|------------|---------|
| Python | `snake_case` | `user_id`, `birth_date` |
| Dart | `camelCase` | `userId`, `birthDate` |
| API JSON | `snake_case` | `{"user_id": "..."}` |
| Dart Models | `@JsonKey(name: 'snake_case')` | Required for all fields |

### 2. Era-Appropriate Language
Historical idol chat responses MUST NOT use modern jargon:
- **BANNED for pre-1980 idols:** "pivot", "scale", "KPIs", "leverage", "synergy"
- **USE worldview_adapter:** "startup" → "venture", "customers" → "patrons"

### 3. Realistic Comparison Scoring
- Early-stage user = **0-10%**, NOT 100%
- $40K savings ≠ Warren Buffett's millions
- Use AI comparison for honest assessments

### 4. Async Operations
- Long operations use Celery background jobs
- Return `jobId` immediately
- Frontend polls for status
- Show thinking streams for user feedback

### 5. User Data Privacy
- Users can ONLY access their own data
- Verify `user_id` in all queries
- Idols are shared; achievements/notes are private

---

## 🧪 VERIFICATION CHECKLIST

After EVERY change, mentally verify:

```
□ Does it build? (flutter build / python imports)
□ Does it run? (no runtime crashes)
□ Does it work? (feature functions correctly)
□ Did anything break? (test related features)
□ Are types correct? (no dynamic, proper null handling)
□ Are names synced? (snake_case ↔ camelCase)
□ Is the UX smooth? (no jank, proper loading states)
```

---

## 📚 RELATED RULE FILES

- **[backend.md](./backend.md)** - Python/FastAPI rules, API design, database
- **[frontend.md](./frontend.md)** - Flutter/Dart rules, state management, UI
- **[prompts.md](./prompts.md)** - LLM prompt engineering rules

---

## 🚀 THE CMPYS PROMISE

Every feature we build must serve the mission:
> **Help users achieve their dreams through small, guaranteed steps toward becoming like their idols.**

Build with care. Build with quality. Build with purpose.
