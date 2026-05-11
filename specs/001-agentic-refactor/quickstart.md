# Quickstart: Agentic Persona Workflow

**Feature**: `001-agentic-refactor`

## Prerequisites

- Existing CMPYS backend running (`uvicorn app.main:app --reload`)
- PostgreSQL + Redis running (`docker compose -f infra/docker-compose.yml up -d`)
- `GEMINI_API_KEY` set in `backend/.env`
- Existing Flutter frontend configured and running

## Run After Refactoring

### 1. Apply migrations

```bash
cd backend
alembic upgrade head
```

### 2. Verify Gemini connectivity

```bash
curl http://localhost:8000/api/v1/debug/llm
```

Expected: `gemini_configured: true`

### 3. Test the 5-Phase flow

```bash
# Phase 1: Create session with intake data
curl -X POST http://localhost:8000/api/v1/sessions \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"age": 28, "financial_status": "$6k/month", "interests": ["leadership"]}'

# Phase 2: Get idol suggestions
curl -X POST http://localhost:8000/api/v1/sessions/<id>/suggest-idols \
  -H "Authorization: Bearer <token>"

# Phase 2: Select idol
curl -X POST http://localhost:8000/api/v1/sessions/<id>/select-idol \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"idol_name": "Alexander the Great", "wikidata_id": "Q8409"}'

# Phase 3: Interview (repeat 3-5 times)
curl -X POST http://localhost:8000/api/v1/sessions/<id>/interview \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"content": "I make $6,000/month and lead a team of 2"}'

# Phase 4+5: Generate results
curl -X POST http://localhost:8000/api/v1/sessions/<id>/generate-results \
  -H "Authorization: Bearer <token>"
```

### 4. Run tests

```bash
cd backend
pytest tests/ -v
```
