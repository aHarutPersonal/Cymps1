"""GET /achievements pages over a total order, so offset paging never skips rows."""
from sqlalchemy.dialects import postgresql

from app.api.v1.achievements import ACHIEVEMENT_LIST_ORDER


def test_list_order_breaks_date_ties_by_creation_then_id():
    # The app restores the Record page by page and never sends a date, so
    # every row ties on achievement_date; without a tiebreaker offset paging
    # can skip a row between pages.
    rendered = [str(clause.compile(dialect=postgresql.dialect())) for clause in ACHIEVEMENT_LIST_ORDER]
    assert rendered == [
        "user_achievements.achievement_date DESC NULLS LAST",
        "user_achievements.created_at DESC",
        "user_achievements.id",
    ]
