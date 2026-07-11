# Content Quality Specification

**Version:** 2.1
**Last Updated:** 2026-07-11
**Owner:** CMPYS Engineering

---

## 1. Problem Statement

CMPYS claims to provide 15-90 minute learning experiences, but the actual content was producing 1-5 minutes of reading. This mismatch between claimed and actual duration is the root cause of user disengagement — users who expect deep learning but receive shallow content lose trust and churn.

### Audit Findings

| Prompt | Claims | Actually Produces | Gap |
|--------|--------|-------------------|-----|
| `book_module_generate.txt` | "15-minute module" | 200-800 words (1-4 min) | No minimum word count on `content_markdown` |
| `plan_item_details.txt` | "40-60 minute lessons" | 200-400 word `lesson_content` per step | Floor too low; time claim is not auditable |
| `plan_generate.txt` | "2-8 hour missions" | No min on `description`; backend drops `estimated_hours` and `daily_instructions` | Duration claim is unenforceable |
| `duration_minutes` | Calculated from content | Hardcoded to 15 for all book modules | UI shows "15 min" for 200 words |

---

## 2. Content Depth Requirements

### 2.1 Book Modules (`book_module_generate.txt`)

| Field | Minimum | Target | Rationale |
|-------|---------|--------|-----------|
| `content_markdown` | 3,200 words | 3,600 words | More than 15 min at a 200 wpm learning pace |
| Each `section.summary` | 80 words | 120 words | Substantial enough to give a takeaway on skim |
| Each `section.exercise` | 40 words | 60 words | Specific, measurable action with tool/time/success criteria |
| Each `idea.content` | 40 words | 60 words | Must include specific example + actionable takeaway |
| `sections` | 5 | 6-7 | Enough sections for genuine learning |
| `ideas` | 6 | 8-10 | Sufficient idea cards for discovery |

**Quality Rules:**
- Every claim must reference a specific event, quote, or decision from the author's life
- Generic advice like "stay focused" or "work hard" is forbidden
- Each section must have a "Practice This" exercise block with 2-4 numbered steps
- Content must include opening hook, core concept explanation, real example, and closing synthesis

**Validation:** The backend requires 3,200-4,500 words plus the expected section, exercise, idea-card, anti-filler, and grounding checks; failures retry once with a focused correction prompt.

### 2.2 Plan Item Details (`plan_item_details.txt`)

| Field | Minimum | Target | Rationale |
|-------|---------|--------|-----------|
| `lesson_content` per step | 1,200 words | 1,200-1,800 words | 6-9 minutes of teaching at 200 wpm |
| Timed guided practice | 30 minutes | 30-45 minutes | Makes the total session honestly 40-60 minutes |
| `content_markdown` for materials | 350 words | 400-600 words | Supporting in-app lessons need useful depth |
| Each `substep` | 20 words | 35 words | Specific practice exercise with tool/time/criteria |
| Each `material.idea.content` | 40 words | 60 words | Specific example + actionable takeaway |

**Quality Rules:**
- Steps must TEACH, not advise. "Practice regularly" is forbidden.
- Each step must include: why it matters, core framework, worked example, failure modes, guided practice, knowledge check, and references
- `estimate_minutes` must equal derived `reading_minutes` plus timed `practice_minutes`
- Lessons progress sequentially: completing the active lesson unlocks the next
- Filler phrases like "Let's dive in" or "It's important to note" are forbidden

**Validation:** Backend checks each step's `lesson_content` >= 1,200 words and each material's `content_markdown` >= 350 words. If any fail, it retries once with a stronger prompt. Existing short lessons are queued for regeneration when opened.

### 2.3 Plan Generation (`plan_generate.txt`)

| Field | Minimum | Rationale |
|-------|---------|-----------|
| Mission task `description` | 50 words | Must include specific books, chapters, exercises |
| Daily rhythm `description` | 30 words | Must be specific and measurable |
| `primary_mission` | 30 words | Must reference specific skill, deliverable, or outcome |
| `daily_instructions` | 40 words (3-5 sentences) | Must tell user EXACTLY what to do today |

**Schema Requirements:**
- `estimated_hours` (float): Preserved from LLM output, not computed from week-level division
- `daily_instructions` (string, max 2000 chars): Stored in `meta_json` on the PlanItem

---

## 3. Duration Accuracy

### 3.1 Calculation Formula

```
duration_minutes = max(5, round(word_count / 200))
```

- Reading speed: 200 words per minute (industry standard for non-fiction)
- Minimum: 5 minutes (prevents "1 minute module" for short content)
- Applied to reading content. Lesson `estimate_minutes` is `reading_minutes + practice_minutes`.

### 3.2 Where Duration is Calculated

| Location | What | Formula |
|----------|------|---------|
| `content_resources.py` -> `generate_book_module()` | Book module `duration_minutes` | `max(5, round(word_count / 200))` after LLM generation |
| `content_resources.py` -> `material_to_resource_payload()` | Material duration from content | Same formula, using `content_markdown` word count |
| `content_resources.py` -> `get_or_create_book_module_resource()` | LLM book module resource | Same formula |
| `content_resources.py` -> `lookup_public_domain_book()` | Public domain book duration | Same formula |

### 3.3 Hardcoded Values Removed

All instances of `duration_minutes = 15` or `duration_minutes or 15` have been replaced with word-count-based calculations. No duration should be hardcoded.

---

## 4. Content Quality Validation Pipeline

### 4.1 Book Module Generation

```
generate_book_module()
  -> LLM generates content
  -> Validate: complete quality report passes at 3,200-4,500 words?
     -> YES: Calculate duration, return
     -> NO: Retry once with stronger prompt
        -> Validate again
        -> Use whichever version has more words
```

### 4.2 Plan Item Detail Generation

```
regenerate_plan_item_details()
  -> LLM generates steps + materials
  -> _normalize_plan_item_details()
  -> Derive reading_minutes from word count
  -> Validate: any step lesson_content < 1,200 words or material content_markdown < 350 words?
     -> YES: Retry once with stronger prompt
        -> Validate again
        -> Use retry if all pass
     -> NO: Proceed with original
```

### 4.3 Plan Generation

```
_generate_llm_items()
  -> LLM generates weeks with binary_tasks
  -> BinaryTask schema validates:
     - description: min_length=10 (was: no minimum)
     - estimated_hours: float (was: dropped)
     - daily_instructions: optional string (was: dropped)
  -> generator.py stores:
     - estimated_hours: from LLM output (was: computed division)
     - daily_instructions: in meta_json (was: dropped)
```

---

## 5. Pydantic Schema Changes

### 5.1 `BinaryTask` (schemas.py)

**Before:**
```python
class BinaryTask(BaseModel):
    title: str = Field(max_length=300)
    description: str = Field(max_length=1000)
    type: str = Field(default="project", max_length=50)
```

**After:**
```python
class BinaryTask(BaseModel):
    title: str = Field(max_length=300)
    description: str = Field(min_length=10, max_length=1000)
    type: str = Field(default="project", max_length=50)
    estimated_hours: float = Field(default=1.0, ge=0.1, le=40.0)
    daily_instructions: str | None = Field(default=None, max_length=2000)
```

### 5.2 `PlanItemCreate` (schemas.py)

**Before:**
```python
class PlanItemCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=1)
    ...
```

**After:**
```python
class PlanItemCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=10)
    ...
    dailyInstructions: str | None = Field(default=None, max_length=2000)
```

---

## 6. Verification Checklist

- [ ] Generate a plan for a test user. Open a plan item's details. Verify each `lesson_content` is 1,200-1,800 words with the required sections and timed practice.
- [ ] Open a book module in the dedicated reader. Verify `content_markdown` is >= 3,200 words with multiple sections, examples, boundaries, and exercises.
- [ ] Verify `duration_minutes` reflects actual word count (words / 200), not a hardcoded value.
- [ ] Send a deliberately shallow prompt output through the pipeline. Verify the backend retries with a stronger prompt.
- [ ] Verify a 3,200-word book module shows `duration_minutes=16`.
- [ ] Verify each lesson shows separate reading/practice time and a 40-60 minute total.
