## 2024-06-20 - Optimize SQLAlchemy Count Queries
**Learning:** Pagination count queries using `select(func.count()).select_from(stmt.subquery())` generate inefficient SQL with expensive nested subqueries and redundant `ORDER BY` operations.
**Action:** Replace with `stmt.with_only_columns(func.count(Model.id)).order_by(None)` to generate a much faster `SELECT COUNT(...) FROM ...` query directly, stripping out unnecessary sorting operations.
