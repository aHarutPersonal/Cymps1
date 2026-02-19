# CMPYS Prompt Engineering Rules

> **Purpose:** Rules for creating and maintaining LLM prompts that power CMPYS features.

---

## 📁 PROMPT DIRECTORY

All prompts live in `/prompts/*.txt`:

| File | Purpose | Used By |
|------|---------|---------|
| `chat_system.txt` | System prompt for idol chat | `chat.py` |
| `chat_reply.txt` | Response format for chat | `chat.py` |
| `persona_pack.txt` | Generate idol chat persona | `idols.py` |
| `profile_extract.txt` | Extract structured profile from sources | `tasks/idols.py` |
| `achievements_extract.txt` | Extract timeline events | `tasks/idols.py` |
| `timeline_normalize.txt` | Normalize extracted events | `tasks/idols.py` |
| `milestones_by_age.txt` | Filter milestones by age | `comparison.py` |
| `comparison_analyze.txt` | AI-powered comparison analysis | `comparison.py` |
| `plan_generate.txt` | Generate 12-week development plans | `plans.py` |
| `plan_item_details.txt` | Generate item curriculum details | `plans.py` |
| `idol_discover.txt` | LLM-based idol suggestions | `idols.py` |
| `intake_questions_generate.txt` | Generate onboarding questions | `intake.py` |
| `intake_answers_normalize.txt` | Normalize user answers | `intake.py` |
| `thinking_*.txt` | Thinking stream narratives | `jobs.py` |
| `image_generate.txt` | Idol avatar generation | `idols.py` |

---

## 📝 PROMPT STRUCTURE

### Standard Template Format
```
[ROLE/CONTEXT SECTION]
You are a {role} helping with {task}.

[INPUT SECTION]
INPUT:
- Variable 1: {variable_1}
- Variable 2: {variable_2}

[INSTRUCTIONS SECTION]
INSTRUCTIONS:
1. Do X
2. Do Y
3. Do Z

[OUTPUT SECTION]
Return JSON matching this schema:
{
  "field1": "string",
  "field2": 0
}

[RULES/CONSTRAINTS SECTION]
RULES:
- Never do A
- Always do B
```

### Variable Placeholders
Use curly braces for variables:
```
{idol_name}
{sources_json}
{user_age}
```

These are replaced by Python before sending to LLM.

---

## 🎯 PROMPT QUALITY STANDARDS

### 1. Be Explicit
```
# ✅ GOOD
Return a JSON object with exactly 3 fields:
- "name": string (1-100 chars)
- "score": float (0.0-1.0)
- "items": array of strings (1-5 items)

# ❌ BAD
Return the data in JSON format.
```

### 2. Provide Examples
```
# ✅ GOOD
Example output:
{
  "category": "finance",
  "score": 0.75,
  "reasoning": "User has demonstrated..."
}

# ❌ BAD
Just output JSON.
```

### 3. Set Boundaries
```
# ✅ GOOD
RULES:
- Maximum 500 words
- Do NOT mention sources in the response
- If uncertain, say "I cannot determine..."

# ❌ BAD
(No constraints given)
```

### 4. Handle Edge Cases
```
# ✅ GOOD
If no sources are provided:
- Return confidence: 0.5
- Set "source_backed": false

If birth date is missing:
- Use null for age-related fields
```

---

## 🗣️ CHAT PERSONA RULES

### Era-Appropriate Language (CRITICAL)

Historical figures MUST NOT use modern jargon.

**lexicon_ban for pre-1980 figures:**
```
["value proposition", "market research", "pivot", "scale", 
 "growth hacking", "KPIs", "OKRs", "networking", "mentor/mentee",
 "stakeholders", "leverage (as verb)", "synergy", "disrupt", "iterate",
 "accelerator", "incubator", "runway", "burn rate", "MVP"]
```

**worldview_adapter mappings:**
```json
{
  "startup": "venture / undertaking / enterprise",
  "customers": "patrons / those we serve / the people",
  "market": "terrain / the field / the public sphere",
  "competitors": "rivals / adversaries / opposing forces",
  "product": "the offering / our work / the creation",
  "funding": "patronage / treasury / capital",
  "networking": "building alliances / making connections",
  "mentor": "elder advisor / master / teacher",
  "pitch": "proposal / presentation to council",
  "scale": "expand / grow / extend reach"
}
```

### Era Context Categories
```
ancient: before 500 CE (Greeks, Romans, etc.)
medieval: 500-1500 CE
early_modern: 1500-1800
modern: 1800-1980
contemporary: 1980-present
```

### Voice Authenticity
```
# ✅ GOOD - For military strategist
"Consider the terrain before advancing. Know your adversary's 
weaknesses, then strike with concentrated force."

# ❌ BAD - Modern jargon for ancient figure
"Let's pivot your strategy and leverage your network to 
disrupt the competitive landscape."
```

---

## 📊 COMPARISON SCORING RULES

The comparison prompt MUST enforce realistic scoring:

```
SCORING GUIDELINES (CRITICAL):

At 28 years old comparing to Warren Buffett:
- Having $40K in savings: 5-10% (not 100%)
- Reading 5 books on investing: 10-20%
- Making first stock purchase: 15-25%
- Managing $1M portfolio: 40-60%
- Running successful fund: 70-85%

SCALE:
0-10%: Just starting, foundational knowledge
10-30%: Competent, above average progress
30-50%: Strong achiever, notable accomplishments
50-70%: Exceptional, rare achievement level
70-90%: Comparable to idol at same age
90-100%: Exceeds idol (extremely rare)

NEVER inflate scores. Users need honest feedback 
to make real progress.
```

---

## 📋 PLAN GENERATION RULES

Plans must be:
1. **Actionable** - Specific, measurable steps
2. **Achievable** - Match user's available time
3. **Progressive** - Build skills incrementally
4. **Realistic** - Acknowledge user's starting point

### Plan Item Quality
```
# ✅ GOOD
{
  "title": "Weekly Company Analysis",
  "type": "practice",
  "description": "Analyze one company's annual report each week. 
    Focus on: revenue trends, profit margins, competitive moat.",
  "successMetric": "Complete 12 detailed analyses with written notes",
  "estimatedHours": 48,
  "weekStart": 1,
  "weekEnd": 12
}

# ❌ BAD
{
  "title": "Learn investing",
  "type": "learning",
  "description": "Study investing.",
  "successMetric": "Get better at investing"
}
```

---

## 🔍 EXTRACTION RULES

When extracting data from Wikipedia/sources:

### Profile Extraction
- Extract ONLY factual information from sources
- Set `confidence` based on source quality
- Include `evidence` array with citations

### Timeline Extraction
- Each event needs `ageAtEvent` calculated
- Use `datePrecision` (year/month/day) appropriately
- `importanceScore` based on significance
- Categorize into: career, learning, finance, impact, mindset, other

---

## ⚠️ ERROR HANDLING

### LLM Response Validation
```python
# In code that uses prompts:
try:
    response = await llm.generate_json(
        prompt_file="prompts/my_prompt.txt",
        variables={...},
        response_schema=MySchema
    )
except json.JSONDecodeError:
    # LLM returned invalid JSON
    logger.error("Invalid JSON from LLM")
    # Use fallback behavior
except ValidationError:
    # JSON valid but doesn't match schema
    logger.error("Schema validation failed")
    # Use fallback behavior
```

### Graceful Degradation
If LLM fails:
- Comparison → Use basic percentage calculation
- Chat → Return apologetic message
- Plan → Use deterministic template

---

## ✅ PROMPT CHANGE CHECKLIST

When modifying a prompt:

```
□ Tested with sample inputs
□ Output format still matches code expectations
□ Schema validation passes
□ Edge cases handled
□ Backend code updated if response structure changed
□ Frontend updated if data structure changed
□ No regressions in existing functionality
```

---

## 🧪 TESTING PROMPTS

### Manual Testing
```bash
# In Python REPL:
from app.services.llm.client import LLMClient

client = LLMClient()
response = await client.generate_json(
    prompt_file="prompts/test_prompt.txt",
    variables={"name": "Test"},
)
print(response)
```

### Validation
- Check JSON parses correctly
- Check required fields present
- Check field types match schema
- Check content quality (for chat prompts)

---

## 📚 THE CMPYS PROMISE IN PROMPTS

Every prompt should serve the mission:

> **Help users achieve their dreams through small, guaranteed steps 
> toward becoming like their idols.**

Prompts should generate:
- **Honest** assessments (not inflated scores)
- **Actionable** advice (not vague platitudes)
- **Achievable** plans (not overwhelming lists)
- **Authentic** personas (not generic coach speak)
