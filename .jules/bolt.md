## 2024-05-22 - Prevent N+1 query in bulk item generation

**Learning:** When validating or deduplicating AI generated items (like feed posts) against the database, looping through the items and issuing an individual `SELECT` query for each item results in an N+1 query bottleneck. This occurs prominently when LLM returns arrays of new content.
**Action:** Always pre-calculate uniquely identifying features (like `content_hash`) for all AI-generated items and execute a single `SELECT ... WHERE column IN (...)` batch query before iterating to insert the new items.