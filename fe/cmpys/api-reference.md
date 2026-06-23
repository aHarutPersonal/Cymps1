# CMPYS API Reference

Complete API documentation for the CMPYS (Compare Yourself) backend service.

**Base URL:** `http://localhost:8000/api/v1`

**Authentication:** Most endpoints require a Bearer token in the `Authorization` header:
```
Authorization: Bearer <access_token>
```

---

## Table of Contents

1. [Authentication](#authentication)
2. [User Profile](#user-profile)
3. [Idols](#idols)
4. [Jobs](#jobs)
5. [Achievements](#achievements)
6. [Comparison](#comparison)
7. [Plans](#plans)
8. [Plan Items](#plan-items)
9. [Intake](#intake)
10. [Chat](#chat)
11. [Notes](#notes)
12. [Debug](#debug)

---

## Authentication

### Register

Create a new user account.

```
POST /auth/register
```

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "your_password"
}
```

**Response:** `201 Created`
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Errors:**
- `400 Bad Request` - Email already registered

---

### Login

Authenticate with email and password.

```
POST /auth/login
```

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "your_password"
}
```

**Response:** `200 OK`
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Errors:**
- `401 Unauthorized` - Invalid email or password

---

## User Profile

### Get Current User

Get the authenticated user's information.

```
GET /me
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "profile": {
    "id": "uuid",
    "fullName": "John Doe",
    "birthDate": "1995-03-15",
    "focusAreas": ["business", "technology"],
    "timezone": "America/New_York"
  }
}
```

---

### Update Current User Profile

Update the authenticated user's profile.

```
PATCH /me
```

**Auth Required:** Yes

**Request Body:** (all fields optional)
```json
{
  "fullName": "John Doe",
  "birthDate": "1995-03-15",
  "focusAreas": ["business", "investing"],
  "timezone": "America/New_York"
}
```

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "profile": {
    "id": "uuid",
    "fullName": "John Doe",
    "birthDate": "1995-03-15",
    "focusAreas": ["business", "investing"],
    "timezone": "America/New_York"
  }
}
```

---

## Idols

### Search Idols

Search for idols by name or alias in the local database.

```
GET /idols/search
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `q` | string | "" | Search query for name or alias |
| `limit` | int | 20 | Max results (1-100) |
| `offset` | int | 0 | Pagination offset |

**Response:** `200 OK`
```json
{
  "idols": [
    {
      "id": "uuid",
      "name": "Warren Buffett",
      "birthDate": "1930-08-30",
      "domain": "finance",
      "aliases": [
        {"id": "uuid", "alias_text": "Oracle of Omaha"}
      ],
      "tags": [
        {"id": "uuid", "name": "investing", "type": "domain"}
      ]
    }
  ],
  "total": 1
}
```

---

### Suggest Idols (Hybrid)

Get idol suggestions based on interests. Combines local database with LLM suggestions.

```
GET /idols/suggest
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `interests` | string | "" | Comma-separated interests (e.g., "business,investing") |
| `limit` | int | 20 | Max suggestions (1-50) |
| `source` | string | "auto" | Source: "local", "llm", or "auto" |

**Response:** `200 OK`
```json
{
  "interests": ["business", "investing"],
  "suggestions": [
    {
      "source": "local",
      "id": "uuid",
      "name": "Warren Buffett",
      "birthDate": "1930-08-30",
      "domain": "finance",
      "aliases": [],
      "tags": [],
      "relevanceScore": 0.85
    },
    {
      "source": "web",
      "provider": "llm",
      "externalId": "llm:charlie_munger",
      "name": "Charlie Munger",
      "description": "American investor and vice chairman of Berkshire Hathaway",
      "birthDate": "1924-01-01",
      "wikipediaUrl": "https://en.wikipedia.org/wiki/Charlie_Munger",
      "occupations": ["investor", "businessman"],
      "confidence": 0.9
    }
  ],
  "sourceMix": {
    "local": 1,
    "web": 1,
    "total": 2
  }
}
```

---

### Discover Idols

Discover idols by name from Wikidata. Best for exact name searches.

```
GET /idols/discover
```

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q` | string | Yes | Search query (e.g., "Elon Musk") |
| `limit` | int | No | Max results (1-20, default: 10) |

**Response:** `200 OK`
```json
{
  "query": "Elon Musk",
  "candidates": [
    {
      "externalId": "Q317521",
      "name": "Elon Musk",
      "description": "South African-born American entrepreneur",
      "birthDate": "1971-06-28",
      "wikipediaUrl": "https://en.wikipedia.org/wiki/Elon_Musk",
      "occupations": ["entrepreneur", "engineer"],
      "confidence": 0.95
    }
  ]
}
```

---

### Import Idol

Import an idol from an external provider. Creates a background job for data extraction.

```
POST /idols/import
```

**Request Body:**
```json
{
  "provider": "wikidata",
  "externalId": "Q317521",
  "name": "Elon Musk",
  "birthDate": "1971-06-28",
  "wikipediaUrl": "https://en.wikipedia.org/wiki/Elon_Musk",
  "occupations": ["entrepreneur"]
}
```

**Response:** `201 Created`
```json
{
  "idolId": "uuid",
  "jobId": "uuid",
  "status": "queued"
}
```

**Description:** This endpoint:
1. Creates or retrieves an existing idol record
2. Queues a background job for data extraction (profile, achievements, timeline, persona)
3. Returns immediately with job ID for status polling

---

### Get Idol Details

Get detailed information about a specific idol.

```
GET /idols/{idol_id}
```

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "name": "Warren Buffett",
  "birthDate": "1930-08-30",
  "domain": "finance",
  "createdAt": "2025-01-01T00:00:00Z",
  "aliases": [],
  "tags": [],
  "externalIds": [
    {
      "id": "uuid",
      "provider": "wikidata",
      "externalId": "Q47345",
      "wikipediaUrl": "https://en.wikipedia.org/wiki/Warren_Buffett"
    }
  ]
}
```

---

### Get Idol Profile

Get the extracted profile for an idol.

```
GET /idols/{idol_id}/profile
```

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "idolId": "uuid",
  "displayName": "Warren Buffett",
  "shortDescription": "American investor and philanthropist",
  "birthDate": "1930-08-30",
  "deathDate": null,
  "nationality": ["American"],
  "domains": ["finance", "investing", "business"],
  "primaryRoles": ["investor", "CEO", "philanthropist"],
  "eraTags": ["20th century", "21st century"],
  "notableThemes": ["value investing", "long-term thinking"],
  "wikipediaUrl": "https://en.wikipedia.org/wiki/Warren_Buffett",
  "confidence": 0.95,
  "evidence": [],
  "createdAt": "2025-01-01T00:00:00Z"
}
```

**Errors:**
- `404 Not Found` - Profile not found (idol not yet imported)

---

### Get Idol Timeline

Get the timeline of events for an idol with optional filtering.

```
GET /idols/{idol_id}/timeline
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `age` | int | null | Filter by age at event (0-150) |
| `mode` | string | "up_to" | Filter mode: "exact" or "up_to" |
| `category` | string | null | Filter by category |
| `limit` | int | 50 | Max events (1-200) |

**Response:** `200 OK`
```json
{
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "events": [
    {
      "id": "uuid",
      "idolId": "uuid",
      "canonicalTitle": "First stock purchase",
      "canonicalDescription": "Bought first stock at age 11",
      "eventDate": "1941-01-01",
      "datePrecision": "year",
      "ageAtEvent": 11,
      "category": "finance",
      "importanceScore": 0.8,
      "confidence": 0.9,
      "evidence": [],
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ],
  "totalEvents": 25,
  "filteredBy": {"age": 30, "mode": "up_to"}
}
```

---

### Get Idol Persona

Get the chat persona for an idol (used for AI conversations).

```
GET /idols/{idol_id}/persona
```

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "idolId": "uuid",
  "voiceStyle": "Folksy, down-to-earth wisdom with occasional humor",
  "principles": [
    "Be fearful when others are greedy",
    "Invest in what you understand",
    "Long-term thinking beats short-term speculation"
  ],
  "dos": ["Use simple language", "Reference historical examples"],
  "donts": ["Don't give specific stock tips", "Avoid complex jargon"],
  "signaturePhrases": ["Rule No. 1: Never lose money"],
  "topicsOfStrength": ["value investing", "business analysis"],
  "tabooTopics": ["cryptocurrency", "day trading"],
  "groundingEvidence": [],
  "disclaimer": "This is an AI simulation and not financial advice",
  "createdAt": "2025-01-01T00:00:00Z"
}
```

---

## Jobs

### Get Job Status

Get the current status of an import job with AI thinking stream for loading UI.

```
GET /jobs/{job_id}
```

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "status": "running",
  "step": "extracting_achievements",
  "progressPercent": 45,
  "errorMessage": null,
  "thinkingStream": {
    "currentLine": "Found something interesting from their early career...",
    "completedLines": [
      "This is the exciting part - finding their achievements...",
      "I'm looking for concrete milestones, not just fame..."
    ],
    "insight": "Real milestones are things you could replicate.",
    "step": "extracting_achievements",
    "stepProgress": 50
  },
  "thinkingText": {
    "message": "Found something interesting from their early career...",
    "funFact": "Real milestones are things you could replicate.",
    "step": "extracting_achievements"
  },
  "previewAchievements": ["First stock purchase", "Founded Buffett Partnership"],
  "previewDomains": ["finance", "investing"]
}
```

**Job Statuses:**
- `queued` - Job waiting to start
- `running` - Job in progress
- `done` - Job completed successfully
- `failed` - Job failed with error

**Job Steps:**
- `collecting_sources` - Gathering data from Wikipedia
- `extracting_profile` - Extracting biographical profile
- `extracting_achievements` - Finding achievements
- `normalizing_timeline` - Organizing chronologically
- `generating_persona` - Creating chat persona
- `storing_data` - Saving to database
- `done` - Complete

---

### Start Job

Manually trigger a queued job to start.

```
POST /jobs/{job_id}/start
```

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "status": "queued",
  "step": "queued",
  "progressPercent": 0,
  "thinkingStream": {...},
  "thinkingText": {...}
}
```

---

## Achievements

### Create Achievement

Create a new user achievement.

```
POST /achievements
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "title": "Graduated with honors",
  "category": "learning",
  "achievementDate": "2020-05-15",
  "notes": "Completed BS in Computer Science",
  "evidenceLink": "https://example.com/diploma.pdf"
}
```

**Categories:** `career`, `learning`, `finance`, `impact`, `mindset`, `other`

**Response:** `201 Created`
```json
{
  "id": "uuid",
  "userId": "uuid",
  "title": "Graduated with honors",
  "category": "learning",
  "achievementDate": "2020-05-15",
  "notes": "Completed BS in Computer Science",
  "evidenceLink": "https://example.com/diploma.pdf",
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z"
}
```

---

### List Achievements

List user achievements with optional filters.

```
GET /achievements
```

**Auth Required:** Yes

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `category` | string | null | Filter by category |
| `q` | string | null | Search in title/notes |
| `fromDate` | date | null | From date filter |
| `toDate` | date | null | To date filter |
| `limit` | int | 50 | Max results (1-200) |
| `offset` | int | 0 | Pagination offset |

**Response:** `200 OK`
```json
{
  "achievements": [
    {
      "id": "uuid",
      "userId": "uuid",
      "title": "Graduated with honors",
      "category": "learning",
      "achievementDate": "2020-05-15",
      "notes": "...",
      "evidenceLink": null,
      "createdAt": "2025-01-01T00:00:00Z",
      "updatedAt": "2025-01-01T00:00:00Z"
    }
  ],
  "total": 10
}
```

---

### Get Achievement

Get a specific achievement.

```
GET /achievements/{achievement_id}
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "userId": "uuid",
  "title": "Graduated with honors",
  "category": "learning",
  "achievementDate": "2020-05-15",
  "notes": "...",
  "evidenceLink": null,
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z"
}
```

---

### Update Achievement

Update an existing achievement.

```
PATCH /achievements/{achievement_id}
```

**Auth Required:** Yes

**Request Body:** (all fields optional)
```json
{
  "title": "Graduated summa cum laude",
  "category": "learning",
  "achievementDate": "2020-05-15",
  "notes": "Updated notes",
  "evidenceLink": "https://example.com/new-link"
}
```

**Response:** `200 OK` (same as Get Achievement)

---

### Delete Achievement

Delete an achievement.

```
DELETE /achievements/{achievement_id}
```

**Auth Required:** Yes

**Response:** `204 No Content`

---

## Comparison

### Compare to Idol

Compare user achievements against idol milestones at a given age.

```
GET /comparison
```

**Auth Required:** Yes

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `idolId` | string | Yes | Idol UUID to compare against |
| `age` | int | Yes | Target age (1-150) |
| `mode` | string | No | "exact" or "up_to" (default: "up_to") |

**Response:** `200 OK`
```json
{
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "targetAge": 25,
  "mode": "up_to",
  "overallScore": 35.5,
  "categoryBreakdown": [
    {
      "category": "career",
      "percent": 50.0,
      "userCount": 2,
      "idolCount": 4
    },
    {
      "category": "finance",
      "percent": 25.0,
      "userCount": 1,
      "idolCount": 4
    }
  ],
  "missingVsIdol": [
    {
      "id": "uuid",
      "title": "First business venture",
      "description": "...",
      "category": "career",
      "ageAtEvent": 13,
      "eventDate": "1943-01-01",
      "importanceScore": 0.8
    }
  ],
  "countedUserAchievements": [
    {
      "id": "uuid",
      "title": "Started freelancing",
      "category": "career",
      "achievementDate": "2020-06-01",
      "matchedMilestones": ["uuid"]
    }
  ],
  "idolMilestonesAtAge": [...],
  "completeness": 0.85,
  "totalIdolMilestones": 10,
  "totalUserAchievements": 5,
  "matchedCount": 3
}
```

---

## Plans

### Generate Plan

Generate a personalized development plan based on comparison gaps.

```
POST /plans/generate
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "idolId": "uuid",
  "targetAge": 30,
  "durationWeeks": 12,
  "weeklyHours": 6
}
```

**Response:** `201 Created`
```json
{
  "id": "uuid",
  "userId": "uuid",
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "targetAge": 30,
  "durationWeeks": 12,
  "weeklyHours": 6,
  "items": [
    {
      "id": "uuid",
      "planId": "uuid",
      "title": "Read 'The Intelligent Investor'",
      "type": "study",
      "description": "Foundation of value investing principles",
      "weekStart": 1,
      "weekEnd": 2,
      "successMetric": "Complete all chapters and take notes",
      "estimatedHours": 10,
      "status": "not_started",
      "progressPercent": 0,
      "notes": null,
      "resourceTitle": "The Intelligent Investor",
      "resourceUrl": "https://example.com/book",
      "createdAt": "2025-01-01T00:00:00Z",
      "updatedAt": "2025-01-01T00:00:00Z"
    }
  ],
  "createdAt": "2025-01-01T00:00:00Z",
  "totalItems": 9,
  "completedItems": 0,
  "overallProgress": 0
}
```

**Description:** Uses LLM to generate personalized plan items based on:
- User's identified gaps vs idol
- Idol's persona and principles
- User's available time and constraints

---

### Get Current Plan

Get the user's most recent plan.

```
GET /plans/current
```

**Auth Required:** Yes

**Response:** `200 OK` (same as Generate Plan response, or `null` if no plan exists)

---

### Get Week Summary

Get progress summary for a specific week.

```
GET /plans/{plan_id}/weeks/{week}/summary
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "week": 1,
  "completed_items": 2,
  "total_items": 3,
  "percent": 66.7
}
```

---

## Plan Items

### Get Plan Item

Get a specific plan item.

```
GET /plan-items/{plan_item_id}
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "planId": "uuid",
  "title": "Read 'The Intelligent Investor'",
  "type": "study",
  "description": "Foundation of value investing principles",
  "weekStart": 1,
  "weekEnd": 2,
  "successMetric": "Complete all chapters",
  "estimatedHours": 10,
  "status": "not_started",
  "progressPercent": 0,
  "notes": null,
  "resourceTitle": "The Intelligent Investor",
  "resourceUrl": "https://example.com/book",
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z"
}
```

---

### Get Plan Item with Details

Get a plan item with steps, materials, and progress information.

```
GET /plan-items/{item_id}/detailed
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "item": {
    "id": "uuid",
    "planId": "uuid",
    "title": "Read 'The Intelligent Investor'",
    "type": "study",
    "description": "...",
    "weekStart": 1,
    "weekEnd": 2,
    "successMetric": "...",
    "estimatedHours": 10,
    "status": "in_progress",
    "progressPercent": 50,
    "notes": null,
    "resourceTitle": null,
    "resourceUrl": null,
    "createdAt": "2025-01-01T00:00:00Z",
    "updatedAt": "2025-01-01T00:00:00Z"
  },
  "details": {
    "steps": [
      {
        "id": "step_1",
        "title": "Read Part 1: Investment vs. Speculation",
        "description": "Understand the core philosophy",
        "expected_output": "A one-page margin-of-safety note",
        "estimate_minutes": 45,
        "order": 1,
        "resources": ["resource-uuid"],
        "substeps": [
          "Read the assigned section and underline every definition of investment versus speculation.",
          "Write three examples of decisions that would violate Graham's rule."
        ],
        "lesson_content": "500+ words of teaching content with context, real example, practice guide, and reflection prompt."
      }
    ],
    "materials": [
      {
        "title": "The Intelligent Investor",
        "url": "https://example.com/book",
        "type": "in_app_lesson",
        "content_resource_id": "resource-uuid",
        "canonical_key": "book:benjamin_graham:the_intelligent_investor",
        "author_or_creator": "Benjamin Graham",
        "license_status": "llm_summary",
        "content_markdown": "600+ words for in-app lesson material, or 2,500+ words for reusable book modules.",
        "duration_minutes": 13,
        "reason": "Builds the foundation for Week 1 value-investing analysis.",
        "ideas": [
          {
            "title": "Margin of Safety",
            "content": "A specific, actionable idea card with an example.",
            "category": "Investing"
          }
        ]
      }
    ],
    "generated_from_prompt_version": "v1.0",
    "generated_at": "2025-01-01T00:00:00Z"
  },
  "progress": {
    "completed_steps": 1,
    "total_steps": 2,
    "percent": 50.0
  },
  "completed": false,
  "details_status": "available",
  "job_id": null
}
```

**`details_status` values:**
- `available` - Details are ready
- `pending` - Details are being generated (check `job_id`)

---

### Update Plan Item

Update a plan item's status, progress, or notes.

```
PATCH /plan-items/{plan_item_id}
```

**Auth Required:** Yes

**Request Body:** (all fields optional)
```json
{
  "status": "in_progress",
  "progressPercent": 50,
  "notes": "Making good progress"
}
```

**Status values:** `not_started`, `in_progress`, `completed`, `skipped`

**Response:** `200 OK` (same as Get Plan Item)

---

### Toggle Item Complete

Toggle completion status for a plan item.

```
POST /plan-items/{item_id}/toggle-complete
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "completed": true,
  "progress": {
    "completed_steps": 3,
    "total_steps": 3,
    "percent": 100.0
  }
}
```

**Description:** 
- If marking complete, also marks all steps as complete
- If uncompleting, does NOT automatically uncheck steps

---

### Toggle Step Complete

Toggle completion status for a specific step within an item.

```
POST /plan-items/{item_id}/steps/{step_id}/toggle
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "step_id": "step_1",
  "completed": true,
  "progress": {
    "completed_steps": 2,
    "total_steps": 3,
    "percent": 66.7
  },
  "item_completed": false
}
```

**Description:**
- Auto-marks item complete if ALL steps are now complete
- Auto-uncompletes item if any step is unchecked

---

### Regenerate Item Details

Trigger regeneration of item details (steps + materials) via LLM.

```
POST /plan-items/{item_id}/regenerate-details
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "job_id": "celery-task-uuid"
}
```

---

## Intake

### Start Intake Session

Start a new intake questionnaire session for an idol.

```
POST /intake/start
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "idol_id": "uuid",
  "target_age": 30
}
```

**Response:** `201 Created`
```json
{
  "session_id": "uuid",
  "questions": [
    {
      "id": "q_weekly_hours",
      "title": "Weekly Commitment",
      "prompt": "How many hours per week can you dedicate to growth?",
      "type": "number",
      "required": true,
      "options": null,
      "placeholder": "e.g., 6",
      "validation": {"min": 1, "max": 40},
      "category": "commitment",
      "mapping_hint": "weekly_hours"
    },
    {
      "id": "q_goals",
      "title": "Your Goals",
      "prompt": "What are your top 3 goals for the next year?",
      "type": "multiline",
      "required": true,
      "options": null,
      "placeholder": "Enter your goals...",
      "validation": null,
      "category": "goals",
      "mapping_hint": "goals"
    }
  ]
}
```

**Question types:** `text`, `multiline`, `number`, `select`, `multiselect`, `date`, `boolean`

---

### Submit Answer

Submit an answer to a question in the intake session.

```
POST /intake/{session_id}/answer
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "question_id": "q_weekly_hours",
  "answer": 6
}
```

**Response:** `200 OK`
```json
{
  "ok": true
}
```

---

### Finish Intake

Complete the intake session and trigger plan generation.

```
POST /intake/{session_id}/finish
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "job_id": "uuid"
}
```

**Description:** This endpoint:
1. Validates all required questions are answered
2. Normalizes answers via LLM
3. Updates user profile with extracted data
4. Stores structured achievements
5. Generates a personalized plan
6. Returns the plan ID (same as job_id)

**Errors:**
- `400 Bad Request` - Required questions not answered
- `400 Bad Request` - Session already completed

---

### Get Intake Session

Get the current state of an intake session.

```
GET /intake/{session_id}
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "session_id": "uuid",
  "idol_id": "uuid",
  "status": "in_progress",
  "questions": [...],
  "answers": [
    {
      "question_id": "q_weekly_hours",
      "answer": 6,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ],
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

**Status values:** `in_progress`, `completed`

---

## Chat

### Create Thread

Create a new chat thread with an idol.

```
POST /chat/threads
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "idolId": "uuid"
}
```

**Response:** `201 Created`
```json
{
  "id": "uuid",
  "userId": "uuid",
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "createdAt": "2025-01-01T00:00:00Z",
  "messageCount": 0,
  "lastMessage": null
}
```

---

### List Threads

List user's chat threads.

```
GET /chat/threads
```

**Auth Required:** Yes

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 20 | Max results (1-100) |
| `offset` | int | 0 | Pagination offset |

**Response:** `200 OK`
```json
{
  "threads": [
    {
      "id": "uuid",
      "userId": "uuid",
      "idolId": "uuid",
      "idolName": "Warren Buffett",
      "createdAt": "2025-01-01T00:00:00Z",
      "messageCount": 5,
      "lastMessage": {
        "id": "uuid",
        "threadId": "uuid",
        "role": "assistant",
        "content": "That's a great question about investing...",
        "createdAt": "2025-01-01T01:00:00Z"
      }
    }
  ],
  "total": 3
}
```

---

### Get Thread

Get a chat thread with all messages.

```
GET /chat/threads/{thread_id}
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "userId": "uuid",
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "createdAt": "2025-01-01T00:00:00Z",
  "messages": [
    {
      "id": "uuid",
      "threadId": "uuid",
      "role": "user",
      "content": "What's your best investment advice?",
      "createdAt": "2025-01-01T00:30:00Z"
    },
    {
      "id": "uuid",
      "threadId": "uuid",
      "role": "assistant",
      "content": "The most important investment advice I can give...",
      "createdAt": "2025-01-01T00:30:05Z"
    }
  ]
}
```

---

### Send Message

Send a message and receive an AI response.

```
POST /chat/threads/{thread_id}/messages
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "content": "What's your advice for a young investor?"
}
```

**Response:** `200 OK`
```json
{
  "userMessage": {
    "id": "uuid",
    "threadId": "uuid",
    "role": "user",
    "content": "What's your advice for a young investor?",
    "createdAt": "2025-01-01T00:00:00Z"
  },
  "assistantMessage": {
    "id": "uuid",
    "threadId": "uuid",
    "role": "assistant",
    "content": "When I was your age, I had already been investing for years...",
    "createdAt": "2025-01-01T00:00:02Z"
  },
  "disclaimer": "This is an AI simulation and not financial advice"
}
```

**Errors:**
- `503 Service Unavailable` - LLM not configured

---

## Daily Focus

### Get Daily Focus

Get today's focus task, a reflection prompt, and current streak count.

```
GET /daily-focus
```

**Auth Required:** Yes

**Response:** `200 OK`
```json
{
  "focusItem": {
    "id": "uuid",
    "title": "Read chapters 1-3 of 'The Intelligent Investor'",
    "type": "practice",
    "estimatedHours": 0.5,
    "dailyInstructions": "Open 'The Intelligent Investor' to Chapter 1. Read pages 3-25, focusing on Graham's distinction between investment and speculation. After each chapter, write a 2-sentence summary of the key argument. You're done when you have summaries for all three chapters."
  },
  "reflectionPrompt": "What's one thing you learned today that changed how you think about risk?",
  "streak": 5
}
```

**Note:** `dailyInstructions` is sourced from `PlanItem.meta_json.daily_instructions` first, then `PlanItem.details_json.daily_instructions`.

---

## Notes

### Create Note

Create a new note.

```
POST /notes
```

**Auth Required:** Yes

**Request Body:**
```json
{
  "title": "Investment Ideas",
  "content": "Some thoughts on value investing...",
  "attachments": [
    {
      "idolId": "uuid",
      "planItemId": null,
      "achievementId": null
    }
  ]
}
```

**Response:** `201 Created`
```json
{
  "id": "uuid",
  "userId": "uuid",
  "title": "Investment Ideas",
  "content": "Some thoughts on value investing...",
  "attachments": [
    {
      "id": "uuid",
      "idolId": "uuid",
      "planItemId": null,
      "achievementId": null
    }
  ],
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z"
}
```

---

### List Notes

List user notes with optional search.

```
GET /notes
```

**Auth Required:** Yes

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `q` | string | null | Search in title/content |
| `limit` | int | 50 | Max results (1-200) |
| `offset` | int | 0 | Pagination offset |

**Response:** `200 OK`
```json
{
  "notes": [...],
  "total": 10
}
```

---

### Get Note

Get a specific note.

```
GET /notes/{note_id}
```

**Auth Required:** Yes

**Response:** `200 OK` (same as Create Note response)

---

### Update Note

Update a note.

```
PATCH /notes/{note_id}
```

**Auth Required:** Yes

**Request Body:** (all fields optional)
```json
{
  "title": "Updated Title",
  "content": "Updated content...",
  "attachments": [...]
}
```

**Response:** `200 OK` (same as Create Note response)

---

### Delete Note

Delete a note.

```
DELETE /notes/{note_id}
```

**Auth Required:** Yes

**Response:** `204 No Content`

---

## Debug

### Get LLM Status

Get LLM configuration status (development only).

```
GET /debug/llm
```

**Response:** `200 OK`
```json
{
  "provider": "openai",
  "model": "gpt-4o",
  "configured": true
}
```

---

### Get Prompts

Get list of available prompt templates (development only).

```
GET /debug/prompts
```

**Response:** `200 OK`
```json
{
  "available": [
    "chat_reply.txt",
    "chat_system.txt",
    "plan_generate.txt",
    "intake_questions_generate.txt"
  ],
  "loaded": ["chat_system.txt", "chat_reply.txt"],
  "registry": {
    "chat": {
      "reply": ["chat_system.txt", "chat_reply.txt"]
    },
    "planning": {
      "generate_plan": ["extractor_system.txt", "plan_generate.txt"]
    }
  }
}
```

---

## Error Responses

All endpoints may return these common error responses:

### 400 Bad Request
```json
{
  "detail": "Error message describing what went wrong"
}
```

### 401 Unauthorized
```json
{
  "detail": "Not authenticated"
}
```

### 403 Forbidden
```json
{
  "detail": "You do not have access to this resource"
}
```

### 404 Not Found
```json
{
  "detail": "Resource not found"
}
```

### 422 Validation Error
```json
{
  "detail": [
    {
      "loc": ["body", "email"],
      "msg": "value is not a valid email address",
      "type": "value_error.email"
    }
  ]
}
```

### 500 Internal Server Error
```json
{
  "detail": "Internal server error"
}
```

### 503 Service Unavailable
```json
{
  "detail": "LLM not configured. Set LLM_PROVIDER=openai and OPENAI_API_KEY to enable this feature."
}
```

---

## Rate Limiting

Currently, there are no rate limits implemented. Future versions may include:
- Per-user request limits
- LLM endpoint throttling

---

## Webhooks

Webhooks are not currently implemented. Job status should be polled via `GET /jobs/{job_id}`.

---

## API Versioning

All endpoints are prefixed with `/api/v1`. Future versions will use `/api/v2`, etc.
