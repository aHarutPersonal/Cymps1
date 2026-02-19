# cmpys Backend

FastAPI backend service for cmpys.

## Requirements

- Python 3.11+
- PostgreSQL
- Redis

## Setup

1. Create a virtual environment:

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Set environment variables (or create a `.env` file):

```bash
export DATABASE_URL=postgresql+psycopg://cmpys:cmpys@localhost:5432/cmpys
export REDIS_URL=redis://localhost:6379/0
```

Or create a `.env` file in the backend directory:

```env
DATABASE_URL=postgresql+psycopg://cmpys:cmpys@localhost:5432/cmpys
REDIS_URL=redis://localhost:6379/0
DEBUG=false
```

## Database Migrations

Run migrations to set up the database schema:

```bash
alembic upgrade head
```

Create a new migration after model changes:

```bash
alembic revision --autogenerate -m "description of changes"
```

Rollback the last migration:

```bash
alembic downgrade -1
```

## Running the Server

Development mode with auto-reload:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Production mode:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Basic health check |
| `/ready` | GET | Readiness check (verifies DB connection) |
| `/api/v1/` | GET | API v1 root |

### Authentication
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/auth/register` | POST | Register new user |
| `/api/v1/auth/login` | POST | Login and get token |
| `/api/v1/me` | GET | Get current user |
| `/api/v1/me` | PATCH | Update profile |

### Idols
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/idols/search` | GET | Search idols |
| `/api/v1/idols/suggest` | GET | Get idol suggestions |
| `/api/v1/idols/discover` | GET | Discover from Wikidata |
| `/api/v1/idols/import` | POST | Import idol |
| `/api/v1/idols/{id}` | GET | Get idol details |
| `/api/v1/idols/{id}/profile` | GET | Get extracted profile |
| `/api/v1/idols/{id}/timeline` | GET | Get timeline |
| `/api/v1/idols/{id}/persona` | GET | Get chat persona |

### User Achievements
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/achievements` | POST | Create achievement |
| `/api/v1/achievements` | GET | List achievements |
| `/api/v1/achievements/{id}` | GET | Get achievement |
| `/api/v1/achievements/{id}` | PATCH | Update achievement |
| `/api/v1/achievements/{id}` | DELETE | Delete achievement |

### Comparison
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/comparison` | GET | Compare user vs idol |

### Plans
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/plans/generate` | POST | Generate plan (LLM optional) |
| `/api/v1/plans/current` | GET | Get current plan |
| `/api/v1/plan-items/{id}` | GET | Get plan item |
| `/api/v1/plan-items/{id}` | PATCH | Update plan item |

### Notes
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/notes` | POST | Create note |
| `/api/v1/notes` | GET | List notes |
| `/api/v1/notes/{id}` | GET | Get note |
| `/api/v1/notes/{id}` | PATCH | Update note |
| `/api/v1/notes/{id}` | DELETE | Delete note |

### Chat
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/chat/threads` | POST | Create thread |
| `/api/v1/chat/threads` | GET | List threads |
| `/api/v1/chat/threads/{id}` | GET | Get thread |
| `/api/v1/chat/threads/{id}/messages` | POST | Send message (LLM required) |

### Debug
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/debug/llm` | GET | Check LLM config status |

## LLM Usage

The following endpoints use LLM:

| Endpoint | LLM Usage |
|----------|-----------|
| `POST /api/v1/idols/import` | **Indirect** - triggers background worker that uses LLM for extraction |
| `POST /api/v1/plans/generate` | **Optional** - uses LLM if `PLAN_GENERATOR_MODE=llm`, otherwise deterministic |
| `POST /api/v1/chat/threads/{id}/messages` | **Required** - returns 503 if LLM not configured |

All other endpoints are **database/public-API only** and do not require LLM.

### LLM Configuration

Set the following environment variables:

```env
# Provider: "dummy" (default) or "openai"
LLM_PROVIDER=openai

# Required for OpenAI
OPENAI_API_KEY=sk-your-key-here
OPENAI_MODEL=gpt-4o

# Plan generation: "deterministic" (default) or "llm"
PLAN_GENERATOR_MODE=deterministic
```

Verify configuration:
```bash
curl http://localhost:8000/api/v1/debug/llm
```

## API Documentation

Once the server is running, access the interactive API docs at:

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc
