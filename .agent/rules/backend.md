# CMPYS Backend Rules

> **Stack:** Python 3.11+ | FastAPI | SQLAlchemy 2.0 | Celery | PostgreSQL | Redis

---

## 🏗️ ARCHITECTURE

### Directory Structure
```
backend/
├── app/
│   ├── api/v1/           # API endpoints (one file per domain)
│   │   ├── auth.py       # Registration, login, token refresh
│   │   ├── idols.py      # Idol CRUD, import, discovery
│   │   ├── comparison.py # User vs idol comparison
│   │   ├── plans.py      # Plan generation and tracking
│   │   ├── chat.py       # AI persona chat
│   │   ├── notes.py      # User notes
│   │   ├── achievements.py # User achievements
│   │   ├── jobs.py       # Background job status
│   │   ├── me.py         # User profile
│   │   └── intake.py     # Onboarding flow
│   ├── models/           # SQLAlchemy ORM models
│   ├── schemas/          # Pydantic request/response schemas
│   ├── services/         # Business logic services
│   │   └── llm/          # LLM client and utilities
│   ├── tasks/            # Celery background tasks
│   └── core/             # Config, security, database, celery setup
├── migrations/           # Alembic database migrations
├── prompts/              # LLM prompt templates
└── tests/                # Pytest tests
```

### Key Files
- `app/main.py` - FastAPI app initialization
- `app/core/config.py` - Environment configuration (Settings class)
- `app/core/database.py` - Async SQLAlchemy session
- `app/core/security.py` - JWT token creation/validation
- `app/core/celery.py` - Celery app configuration

---

## 📝 CODING STANDARDS

### Python Style
- **PEP 8** compliant
- **Type hints** required on all functions
- **Pydantic** for all API schemas
- **SQLModel** preferred for models (SQLAlchemy + Pydantic)
- **async/await** for all database operations

### Naming Conventions
```python
# Variables, functions, fields: snake_case
user_id = "uuid"
def get_user_by_id(user_id: str) -> User: ...

# Classes: PascalCase
class UserResponse(BaseModel): ...

# Constants: UPPER_SNAKE_CASE
MAX_RETRY_COUNT = 3
```

### Import Order
```python
# 1. Standard library
import os
from datetime import datetime

# 2. Third-party
from fastapi import APIRouter, Depends
from sqlalchemy import select

# 3. Local
from app.models import User
from app.schemas import UserResponse
```

---

## 🔌 API DESIGN

### Endpoint Pattern
```python
router = APIRouter(prefix="/domain", tags=["Domain"])

@router.get("/{id}", response_model=DomainResponse)
async def get_domain_item(
    id: str,
    db: AsyncSession = Depends(get_async_session),
    current_user: User = Depends(get_current_user),
) -> DomainResponse:
    """Get a single domain item."""
    # Implementation
```

### Response Schema Rules
- Use `response_model` on all endpoints
- Response fields: `snake_case` (matches JSON)
- Optional fields: `Optional[Type] = None`
- Lists: Return object with items array + metadata

```python
class ItemListResponse(BaseModel):
    items: List[ItemResponse]
    total: int
    has_next: bool = False
```

### Error Handling
```python
from fastapi import HTTPException

# 400 - Bad Request (validation)
raise HTTPException(status_code=400, detail="Invalid input")

# 401 - Unauthorized
raise HTTPException(status_code=401, detail="Invalid or expired token")

# 403 - Forbidden
raise HTTPException(status_code=403, detail="Access denied")

# 404 - Not Found
raise HTTPException(status_code=404, detail="Resource not found")

# 500 - Server Error (let exceptions bubble, logged automatically)
```

---

## 🗄️ DATABASE

### Model Pattern
```python
from sqlmodel import SQLModel, Field
from app.models.base import TimestampMixin
from uuid import uuid4

class MyModel(SQLModel, TimestampMixin, table=True):
    __tablename__ = "my_models"
    
    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    name: str = Field(max_length=255)
    status: str = Field(default="pending")
```

### Query Pattern (Async)
```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

async def get_user_with_profile(db: AsyncSession, user_id: str) -> User | None:
    result = await db.execute(
        select(User)
        .options(selectinload(User.profile))
        .where(User.id == user_id)
    )
    return result.scalar_one_or_none()
```

### Relationship Loading
- Use `selectinload()` for eager loading in async context
- NEVER use lazy loading in async (causes greenlet errors)
- Always load relationships explicitly in queries

### Migration Commands
```bash
# Create migration
alembic revision --autogenerate -m "description"

# Apply migrations
alembic upgrade head

# Rollback one
alembic downgrade -1
```

---

## ⚡ BACKGROUND JOBS (Celery)

### Task Pattern
```python
from app.core.celery import celery_app

@celery_app.task(bind=True, max_retries=3)
def process_idol_import(self, idol_id: str, job_id: str):
    """Background task for idol import."""
    try:
        # Use sync database session in Celery tasks
        with sync_session_maker() as db:
            # Processing logic
            update_job_progress(db, job_id, step="processing", progress=50)
    except Exception as e:
        update_job_status(job_id, status="failed", error=str(e))
        raise
```

### Job Status Updates
- Update `step` and `progress_percent` regularly
- Use `thinking_stream` for user-visible progress
- Set `status = "completed"` or `status = "failed"` at end

### Running Celery
```bash
celery -A app.core.celery worker --loglevel=info
```

---

## 🤖 LLM INTEGRATION

### LLM Client Usage
```python
from app.services.llm.client import LLMClient

client = LLMClient()
response = await client.generate_json(
    prompt_file="prompts/my_prompt.txt",
    variables={"name": "Warren Buffett"},
    response_schema=MyResponseModel,
)
```

### Prompt Template Variables
```
# In prompts/my_prompt.txt
You are analyzing {idol_name}.
Based on: {sources_json}
```

### Handling LLM Responses
- Always validate with Pydantic schema
- Handle `json.JSONDecodeError` gracefully
- Log LLM errors for debugging
- Have fallback behavior if LLM fails

---

## ✅ VERIFICATION CHECKLIST

After backend changes:

```
□ Code has type hints
□ Imports are correct
□ Database queries use async properly
□ Relationships are eagerly loaded
□ API response matches schema
□ Errors return proper HTTP codes
□ Tests pass (if applicable)
□ Migration created (if model changed)
□ Celery task handles errors
□ LLM responses validated
```

---

## 🔄 SYNC WITH FRONTEND

When changing API:

1. **New/changed endpoint?**
   - Update `response_model` schema
   - Document in API docs

2. **Changed response fields?**
   - Flutter model MUST be updated:
   ```dart
   @JsonKey(name: 'new_field')
   final String newField;
   ```

3. **Changed request body?**
   - Flutter repository MUST be updated
   - Ensure field names match exactly

**ALWAYS verify Flutter code after backend API changes.**
