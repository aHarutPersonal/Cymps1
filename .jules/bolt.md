## 2024-05-18 - Optimized Idol Search Pagination
**Learning:** Found a performance bottleneck in `cmpys/backend/app/api/v1/idols.py` where the total count of search results for pagination was calculated by fetching all IDs and running `len(count_result.all())`.
**Action:** Replaced it with an optimized database query: `select(func.count(func.distinct(Idol.id)))` to let PostgreSQL handle the counting efficiently without loading everything into Python memory.
