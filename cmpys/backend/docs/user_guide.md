# CMPYS User Guide

Complete guide for running and using the CMPYS backend API.

---

## Table of Contents

1. [Setup & Installation](#setup--installation)
2. [Running the Application](#running-the-application)
3. [User Journey Overview](#user-journey-overview)
4. [API Reference](#api-reference)
   - [Authentication](#1-authentication)
   - [User Profile](#2-user-profile)
   - [Idol Discovery & Import](#3-idol-discovery--import)
   - [Job Monitoring](#4-job-monitoring)
   - [User Achievements](#5-user-achievements)
   - [Comparison](#6-comparison)
   - [Plan Generation](#7-plan-generation)
   - [Chat](#8-chat)
   - [Notes](#9-notes)
   - [Debug](#10-debug)

---

## Setup & Installation

### Prerequisites

- Python 3.11+
- Docker (for PostgreSQL and Redis)
- OpenAI API key (optional, for LLM features)

### Step 1: Start Infrastructure

```bash
# From project root
cd infra
docker-compose up -d

# Verify services are running
docker-compose ps
# Should show postgres and redis as "running"
```

### Step 2: Set Up Python Environment

```bash
cd backend

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### Step 3: Configure Environment Variables

Create a `.env` file in the `backend` directory:

```env
# Required
DATABASE_URL=postgresql+psycopg://cmpys:cmpys@localhost:5432/cmpys
REDIS_URL=redis://localhost:6379/0

# Optional - for LLM features
LLM_PROVIDER=openai
OPENAI_API_KEY=sk-your-key-here
OPENAI_MODEL=gpt-4o

# Optional - plan generation mode
PLAN_GENERATOR_MODE=llm  # or "deterministic" (default)

# Optional
DEBUG=false
SECRET_KEY=your-secret-key-for-jwt
```

### Step 4: Run Database Migrations

```bash
cd backend
alembic upgrade head
```

### Step 5: Start the API Server

```bash
# Development mode (with auto-reload)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Step 6: Start Celery Worker (for background jobs)

In a **separate terminal**:

```bash
cd backend
source .venv/bin/activate
celery -A app.core.celery worker --loglevel=info
```

### Step 7: Verify Everything is Running

```bash
# Health check
curl http://localhost:8000/health

# Readiness check (verifies DB connection)
curl http://localhost:8000/ready

# Check LLM configuration
curl http://localhost:8000/api/v1/debug/llm
```

**API Documentation:** Once running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

---

## Running the Application

### Quick Start Commands

```bash
# Terminal 1: Infrastructure
cd infra && docker-compose up -d

# Terminal 2: API Server
cd backend && source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Terminal 3: Celery Worker (required for idol import)
cd backend && source .venv/bin/activate
celery -A app.core.celery worker --loglevel=info
```

### Stopping Everything

```bash
# Stop Celery: Ctrl+C in Terminal 3
# Stop API: Ctrl+C in Terminal 2

# Stop infrastructure
cd infra && docker-compose down

# To also remove data volumes:
docker-compose down -v
```

---

## User Journey Overview

A typical user flow through CMPYS:

```
1. Register/Login → Get auth token
       ↓
2. Update Profile → Set birth date, interests
       ↓
3. Discover Idols → Search for role models
       ↓
4. Import Idol → Start background extraction job
       ↓
5. Monitor Job → Wait for extraction to complete
       ↓
6. Log Achievements → Record your own milestones
       ↓
7. Compare → See how you stack up against idol at your age
       ↓
8. Generate Plan → Get personalized 12-week plan
       ↓
9. Track Progress → Update plan items, add notes
       ↓
10. Chat → Get advice from idol persona
```

---

## API Reference

**Base URL:** `http://localhost:8000`

**Authentication:** Most endpoints require `Authorization: Bearer <token>` header.

---

### 1. Authentication

#### Register a New User

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword123"
}
```

**Response (201):**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs..."
}
```

#### Login

```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword123"
}
```

**Response (200):**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs..."
}
```

---

### 2. User Profile

#### Get Current User

```http
GET /api/v1/me
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "uuid-here",
  "email": "user@example.com",
  "profile": {
    "id": "profile-uuid",
    "fullName": "John Doe",
    "birthDate": "1995-06-15",
    "focusAreas": ["investing", "entrepreneurship"],
    "timezone": "America/New_York"
  }
}
```

#### Update Profile

```http
PATCH /api/v1/me
Authorization: Bearer <token>
Content-Type: application/json

{
  "fullName": "John Doe",
  "birthDate": "1995-06-15",
  "focusAreas": ["investing", "entrepreneurship"],
  "timezone": "America/New_York"
}
```

**Response (200):** Updated user object (same as above)

---

### 3. Idol Discovery & Import

#### Search Local Idols

Search for idols already in the database.

```http
GET /api/v1/idols/search?q=buffett&limit=10
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "idols": [
    {
      "id": "uuid",
      "name": "Warren Buffett",
      "birthDate": "1930-08-30",
      "domain": "investing",
      "aliases": [{"id": "...", "alias_text": "Oracle of Omaha"}],
      "tags": [{"id": "...", "name": "value_investing", "type": "theme"}]
    }
  ],
  "total": 1
}
```

#### Get Idol Suggestions (Hybrid: Local + LLM)

Get personalized suggestions based on interests.

```http
GET /api/v1/idols/suggest?interests=investing,entrepreneurship&limit=20&source=auto
Authorization: Bearer <token>
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| interests | string | required | Comma-separated interests |
| limit | int | 20 | Max results (1-50) |
| source | string | "auto" | "local", "llm", or "auto" |

**Response (200):**
```json
{
  "interests": ["investing", "entrepreneurship"],
  "suggestions": [
    {
      "source": "local",
      "id": "uuid",
      "name": "Warren Buffett",
      "birthDate": "1930-08-30",
      "domain": "investing",
      "aliases": [],
      "tags": [],
      "relevanceScore": 0.85
    },
    {
      "source": "web",
      "provider": "llm",
      "externalId": "llm:ray_dalio",
      "name": "Ray Dalio",
      "description": "American billionaire investor and founder of Bridgewater Associates",
      "birthDate": "1949-01-01",
      "wikipediaUrl": "https://en.wikipedia.org/wiki/Ray_Dalio",
      "occupations": ["investing", "finance"],
      "confidence": 0.9
    }
  ],
  "sourceMix": {
    "local": 5,
    "web": 10,
    "total": 15
  }
}
```

#### Discover from Wikidata

Search Wikipedia/Wikidata for people to import.

```http
GET /api/v1/idols/discover?q=Elon%20Musk&limit=5
```

**Response (200):**
```json
{
  "query": "Elon Musk",
  "candidates": [
    {
      "provider": "wikidata",
      "externalId": "Q317521",
      "name": "Elon Musk",
      "description": "American entrepreneur and businessman",
      "birthDate": "1971-06-28",
      "wikipediaUrl": "https://en.wikipedia.org/wiki/Elon_Musk",
      "occupations": ["entrepreneur", "engineer", "investor"]
    }
  ]
}
```

#### Import an Idol

Import from Wikidata or LLM suggestion.

**From Wikidata:**
```http
POST /api/v1/idols/import
Authorization: Bearer <token>
Content-Type: application/json

{
  "provider": "wikidata",
  "externalId": "Q317521"
}
```

**From LLM suggestion:**
```http
POST /api/v1/idols/import
Authorization: Bearer <token>
Content-Type: application/json

{
  "provider": "llm",
  "externalId": "llm:ray_dalio",
  "name": "Ray Dalio",
  "description": "American billionaire investor",
  "birthDate": "1949-08-08",
  "wikipediaUrl": "https://en.wikipedia.org/wiki/Ray_Dalio",
  "occupations": ["investing", "finance"]
}
```

**Response (201):**
```json
{
  "idolId": "uuid-of-created-idol",
  "jobId": "uuid-of-background-job",
  "status": "queued"
}
```

#### Get Idol Details

```http
GET /api/v1/idols/{idol_id}
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "uuid",
  "name": "Warren Buffett",
  "birthDate": "1930-08-30",
  "domain": "investing",
  "createdAt": "2024-01-15T10:30:00Z",
  "aliases": [...],
  "tags": [...],
  "externalIds": [
    {
      "id": "uuid",
      "provider": "wikidata",
      "externalId": "Q47244",
      "wikipediaUrl": "https://en.wikipedia.org/wiki/Warren_Buffett"
    }
  ]
}
```

#### Get Idol Profile (Extracted)

```http
GET /api/v1/idols/{idol_id}/profile
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "profile-uuid",
  "idolId": "idol-uuid",
  "displayName": "Warren Buffett",
  "shortDescription": "American investor and philanthropist",
  "birthDate": "1930-08-30",
  "deathDate": null,
  "nationality": ["American"],
  "domains": ["investing", "business", "philanthropy"],
  "primaryRoles": ["investor", "businessman", "philanthropist"],
  "eraTags": ["modern_era"],
  "notableThemes": ["value investing", "long-term thinking", "philanthropy"],
  "wikipediaUrl": "https://en.wikipedia.org/wiki/Warren_Buffett",
  "confidence": 0.92,
  "evidence": [...],
  "createdAt": "2024-01-15T10:35:00Z"
}
```

#### Get Idol Timeline

```http
GET /api/v1/idols/{idol_id}/timeline?age=30&mode=up_to&category=finance&limit=50
Authorization: Bearer <token>
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| age | int | null | Filter by age at event |
| mode | string | "up_to" | "exact" or "up_to" |
| category | string | null | Filter by category |
| limit | int | 50 | Max events (1-200) |

**Response (200):**
```json
{
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "events": [
    {
      "id": "event-uuid",
      "idolId": "idol-uuid",
      "canonicalTitle": "First Stock Purchase",
      "canonicalDescription": "Purchased first stock at age 11",
      "eventDate": "1942-01-01",
      "datePrecision": "year",
      "ageAtEvent": 11,
      "category": "finance",
      "importanceScore": 0.85,
      "confidence": 0.9,
      "evidence": [...],
      "createdAt": "2024-01-15T10:35:00Z"
    }
  ],
  "totalEvents": 25,
  "filteredBy": {"age": 30, "mode": "up_to", "category": "finance"}
}
```

#### Get Idol Persona

```http
GET /api/v1/idols/{idol_id}/persona
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "persona-uuid",
  "idolId": "idol-uuid",
  "voiceStyle": "Calm, measured, with folksy wisdom and Midwestern directness",
  "principles": [
    "Be fearful when others are greedy",
    "Never invest in a business you cannot understand",
    "Price is what you pay, value is what you get"
  ],
  "dos": [
    "Use simple analogies to explain complex concepts",
    "Emphasize long-term thinking over short-term gains"
  ],
  "donts": [
    "Give specific stock recommendations",
    "Promise guaranteed returns"
  ],
  "signaturePhrases": [
    "Circle of competence",
    "Margin of safety"
  ],
  "topicsOfStrength": ["value investing", "business analysis", "capital allocation"],
  "tabooTopics": ["personal wealth details", "family matters"],
  "groundingEvidence": [...],
  "disclaimer": "AI simulation based on public sources; may be inaccurate.",
  "createdAt": "2024-01-15T10:35:00Z"
}
```

---

### 4. Job Monitoring

#### Get Job Status

Monitor background import job progress.

```http
GET /api/v1/jobs/{job_id}
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "job-uuid",
  "idolId": "idol-uuid",
  "status": "running",
  "step": "extracting_achievements",
  "progressPercent": 45,
  "errorMessage": null
}
```

**Job Statuses:**
- `queued` - Waiting to start
- `running` - Currently processing
- `completed` - Successfully finished
- `failed` - Error occurred (check `errorMessage`)

**Job Steps:**
1. `collecting_sources` (0-20%)
2. `extracting_profile` (20-35%)
3. `extracting_achievements` (35-55%)
4. `normalizing_timeline` (55-70%)
5. `generating_persona` (70-85%)
6. `storing_data` (85-100%)
7. `done` (100%)

#### Manually Start a Queued Job

```http
POST /api/v1/jobs/{job_id}/start
Authorization: Bearer <token>
```

**Response (200):** Job status object

---

### 5. User Achievements

#### Create Achievement

```http
POST /api/v1/achievements
Authorization: Bearer <token>
Content-Type: application/json

{
  "title": "Started first investment portfolio",
  "category": "finance",
  "achievementDate": "2023-06-15",
  "notes": "Opened brokerage account and made first $500 investment",
  "evidenceLink": "https://example.com/screenshot.png"
}
```

**Categories:** `career`, `learning`, `finance`, `impact`, `mindset`, `other`

**Response (201):**
```json
{
  "id": "achievement-uuid",
  "userId": "user-uuid",
  "title": "Started first investment portfolio",
  "category": "finance",
  "achievementDate": "2023-06-15",
  "notes": "Opened brokerage account...",
  "evidenceLink": "https://example.com/screenshot.png",
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:00:00Z"
}
```

#### List Achievements

```http
GET /api/v1/achievements?category=finance&limit=50&offset=0
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "achievements": [...],
  "total": 12
}
```

#### Get Single Achievement

```http
GET /api/v1/achievements/{achievement_id}
Authorization: Bearer <token>
```

#### Update Achievement

```http
PATCH /api/v1/achievements/{achievement_id}
Authorization: Bearer <token>
Content-Type: application/json

{
  "title": "Updated title",
  "notes": "Additional context added"
}
```

#### Delete Achievement

```http
DELETE /api/v1/achievements/{achievement_id}
Authorization: Bearer <token>
```

**Response (204):** No content

---

### 6. Comparison

#### Compare User vs Idol

```http
GET /api/v1/comparison?idolId={idol_id}&age=28&mode=up_to
Authorization: Bearer <token>
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| idolId | string | required | Idol to compare against |
| age | int | required | Target age (1-150) |
| mode | string | "up_to" | "exact" or "up_to" |

**Response (200):**
```json
{
  "idolId": "idol-uuid",
  "idolName": "Warren Buffett",
  "targetAge": 28,
  "mode": "up_to",
  "overallScore": 35.5,
  "categoryBreakdown": [
    {
      "category": "finance",
      "percent": 25.0,
      "userCount": 2,
      "idolCount": 8
    },
    {
      "category": "learning",
      "percent": 50.0,
      "userCount": 3,
      "idolCount": 6
    }
  ],
  "missingVsIdol": [
    {
      "id": "milestone-uuid",
      "title": "First Stock Purchase",
      "description": "Purchased first stock at age 11",
      "category": "finance",
      "ageAtEvent": 11,
      "eventDate": "1942-01-01",
      "importanceScore": 0.85
    }
  ],
  "countedUserAchievements": [
    {
      "id": "achievement-uuid",
      "title": "Started investing",
      "category": "finance",
      "achievementDate": "2023-06-15",
      "matchedMilestones": []
    }
  ],
  "idolMilestonesAtAge": [...],
  "completeness": 0.75,
  "totalIdolMilestones": 14,
  "totalUserAchievements": 5,
  "matchedCount": 2
}
```

---

### 7. Plan Generation

#### Generate a New Plan

```http
POST /api/v1/plans/generate
Authorization: Bearer <token>
Content-Type: application/json

{
  "idolId": "idol-uuid",
  "targetAge": 28,
  "durationWeeks": 12,
  "weeklyHours": 10
}
```

**Response (201):**
```json
{
  "id": "plan-uuid",
  "userId": "user-uuid",
  "idolId": "idol-uuid",
  "idolName": "Warren Buffett",
  "targetAge": 28,
  "durationWeeks": 12,
  "weeklyHours": 10,
  "items": [
    {
      "id": "item-uuid",
      "planId": "plan-uuid",
      "title": "Weekly Company Analysis",
      "type": "practice",
      "description": "Analyze one company's annual report per week...",
      "weekStart": 1,
      "weekEnd": 12,
      "successMetric": "Complete 12 detailed company analyses",
      "estimatedHours": 48,
      "status": "not_started",
      "progressPercent": 0,
      "notes": null,
      "resourceTitle": null,
      "resourceUrl": null,
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-15T10:00:00Z"
    }
  ],
  "createdAt": "2024-01-15T10:00:00Z",
  "totalItems": 8,
  "completedItems": 0,
  "overallProgress": 0.0
}
```

#### Get Current Plan

```http
GET /api/v1/plans/current
Authorization: Bearer <token>
```

**Response (200):** Plan object (or `null` if no plan exists)

#### Get Plan Item

```http
GET /api/v1/plan-items/{item_id}
Authorization: Bearer <token>
```

#### Update Plan Item

```http
PATCH /api/v1/plan-items/{item_id}
Authorization: Bearer <token>
Content-Type: application/json

{
  "status": "in_progress",
  "progressPercent": 50,
  "notes": "Completed first 6 analyses, learning a lot!"
}
```

**Statuses:** `not_started`, `in_progress`, `completed`, `skipped`

**Response (200):** Updated plan item

---

### 8. Chat

#### Create Chat Thread

```http
POST /api/v1/chat/threads
Authorization: Bearer <token>
Content-Type: application/json

{
  "idolId": "idol-uuid"
}
```

**Response (201):**
```json
{
  "id": "thread-uuid",
  "userId": "user-uuid",
  "idolId": "idol-uuid",
  "idolName": "Warren Buffett",
  "createdAt": "2024-01-15T10:00:00Z",
  "messageCount": 0,
  "lastMessage": null
}
```

#### List Chat Threads

```http
GET /api/v1/chat/threads?limit=20&offset=0
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "threads": [...],
  "total": 3
}
```

#### Get Thread with Messages

```http
GET /api/v1/chat/threads/{thread_id}
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "id": "thread-uuid",
  "userId": "user-uuid",
  "idolId": "idol-uuid",
  "idolName": "Warren Buffett",
  "createdAt": "2024-01-15T10:00:00Z",
  "messages": [
    {
      "id": "msg-uuid",
      "threadId": "thread-uuid",
      "role": "user",
      "content": "How should I start investing with limited capital?",
      "createdAt": "2024-01-15T10:01:00Z"
    },
    {
      "id": "msg-uuid-2",
      "threadId": "thread-uuid",
      "role": "assistant",
      "content": "I'd focus on building knowledge first...",
      "createdAt": "2024-01-15T10:01:05Z"
    }
  ]
}
```

#### Send Message (LLM Required)

```http
POST /api/v1/chat/threads/{thread_id}/messages
Authorization: Bearer <token>
Content-Type: application/json

{
  "content": "How should I start investing with limited capital?"
}
```

**Response (200):**
```json
{
  "userMessage": {
    "id": "user-msg-uuid",
    "threadId": "thread-uuid",
    "role": "user",
    "content": "How should I start investing with limited capital?",
    "createdAt": "2024-01-15T10:01:00Z"
  },
  "assistantMessage": {
    "id": "assistant-msg-uuid",
    "threadId": "thread-uuid",
    "role": "assistant",
    "content": "The foundation of successful investing isn't the size of your initial capital—it's the quality of your thinking...",
    "createdAt": "2024-01-15T10:01:05Z"
  },
  "disclaimer": "AI simulation based on public sources; may be inaccurate."
}
```

**Error (503):** If LLM is not configured:
```json
{
  "detail": "Chat requires LLM to be configured"
}
```

---

### 9. Notes

#### Create Note

```http
POST /api/v1/notes
Authorization: Bearer <token>
Content-Type: application/json

{
  "title": "Weekly Reflection - Week 3",
  "content": "Made progress on company analysis...",
  "attachments": [
    {"idolId": "idol-uuid"},
    {"planItemId": "item-uuid"}
  ]
}
```

**Response (201):**
```json
{
  "id": "note-uuid",
  "userId": "user-uuid",
  "title": "Weekly Reflection - Week 3",
  "content": "Made progress on company analysis...",
  "attachments": [
    {"id": "att-1", "idolId": "idol-uuid", "planItemId": null, "achievementId": null},
    {"id": "att-2", "idolId": null, "planItemId": "item-uuid", "achievementId": null}
  ],
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:00:00Z"
}
```

#### List Notes

```http
GET /api/v1/notes?limit=50&offset=0
Authorization: Bearer <token>
```

**Response (200):**
```json
{
  "notes": [...],
  "total": 10
}
```

#### Get Note

```http
GET /api/v1/notes/{note_id}
Authorization: Bearer <token>
```

#### Update Note

```http
PATCH /api/v1/notes/{note_id}
Authorization: Bearer <token>
Content-Type: application/json

{
  "content": "Updated content...",
  "attachments": [{"achievementId": "achievement-uuid"}]
}
```

#### Delete Note

```http
DELETE /api/v1/notes/{note_id}
Authorization: Bearer <token>
```

**Response (204):** No content

---

### 10. Debug

#### Check LLM Configuration

```http
GET /api/v1/debug/llm
```

**Response (200):**
```json
{
  "provider": "openai",
  "configured": true,
  "model": "gpt-4o",
  "planGeneratorMode": "llm"
}
```

---

## Complete Workflow Example

Here's a complete example of using CMPYS from start to finish:

```bash
# 1. Register
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' | jq -r '.accessToken')

# 2. Update profile with birth date
curl -X PATCH http://localhost:8000/api/v1/me \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"fullName":"John Doe","birthDate":"1995-06-15","focusAreas":["investing"]}'

# 3. Discover idol from Wikidata
curl "http://localhost:8000/api/v1/idols/discover?q=Warren%20Buffett"

# 4. Import idol
IMPORT=$(curl -s -X POST http://localhost:8000/api/v1/idols/import \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider":"wikidata","externalId":"Q47244"}')
IDOL_ID=$(echo $IMPORT | jq -r '.idolId')
JOB_ID=$(echo $IMPORT | jq -r '.jobId')

# 5. Monitor job until complete
while true; do
  STATUS=$(curl -s "http://localhost:8000/api/v1/jobs/$JOB_ID" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.status')
  PROGRESS=$(curl -s "http://localhost:8000/api/v1/jobs/$JOB_ID" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.progressPercent')
  echo "Status: $STATUS ($PROGRESS%)"
  [ "$STATUS" = "completed" ] && break
  [ "$STATUS" = "failed" ] && exit 1
  sleep 5
done

# 6. View extracted profile
curl "http://localhost:8000/api/v1/idols/$IDOL_ID/profile" \
  -H "Authorization: Bearer $TOKEN"

# 7. View timeline
curl "http://localhost:8000/api/v1/idols/$IDOL_ID/timeline?mode=up_to" \
  -H "Authorization: Bearer $TOKEN"

# 8. Add your own achievement
curl -X POST http://localhost:8000/api/v1/achievements \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Started investing","category":"finance","achievementDate":"2023-01-15"}'

# 9. Compare yourself to idol at age 28
curl "http://localhost:8000/api/v1/comparison?idolId=$IDOL_ID&age=28&mode=up_to" \
  -H "Authorization: Bearer $TOKEN"

# 10. Generate a 12-week plan
curl -X POST http://localhost:8000/api/v1/plans/generate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"idolId\":\"$IDOL_ID\",\"targetAge\":28,\"durationWeeks\":12,\"weeklyHours\":10}"

# 11. Start a chat thread
THREAD=$(curl -s -X POST http://localhost:8000/api/v1/chat/threads \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"idolId\":\"$IDOL_ID\"}")
THREAD_ID=$(echo $THREAD | jq -r '.id')

# 12. Ask for advice
curl -X POST "http://localhost:8000/api/v1/chat/threads/$THREAD_ID/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"What should I focus on this week to make the most progress?"}'
```

---

## Error Codes

| Status | Meaning |
|--------|---------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (successful delete) |
| 400 | Bad Request (invalid input) |
| 401 | Unauthorized (missing/invalid token) |
| 403 | Forbidden (not your resource) |
| 404 | Not Found |
| 409 | Conflict (duplicate) |
| 503 | Service Unavailable (LLM not configured) |

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| DATABASE_URL | Yes | - | PostgreSQL connection string |
| REDIS_URL | Yes | - | Redis connection string |
| SECRET_KEY | No | auto | JWT signing key |
| DEBUG | No | false | Enable debug mode |
| LLM_PROVIDER | No | dummy | "openai" or "dummy" |
| OPENAI_API_KEY | No* | - | Required if LLM_PROVIDER=openai |
| OPENAI_MODEL | No | gpt-4o | OpenAI model to use |
| PLAN_GENERATOR_MODE | No | deterministic | "llm" or "deterministic" |
