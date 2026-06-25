## 2026-06-25 - Pagination Count Query Optimization
**Learning:** Using `select(func.count()).select_from(stmt.subquery())` in SQLAlchemy creates a full subquery just to count rows, which is inefficient.
**Action:** Use `stmt.with_only_columns(func.count(Model.id)).order_by(None)` instead to perform a direct count on the main query without generating a subquery, and remember to include inline comments for optimization context to meet Bolt's strict tracking guidelines.
