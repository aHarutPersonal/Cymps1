from app.api.v1.idols import _timeline_date_precision
from app.models.idol_achievement import DatePrecision


def test_timeline_date_precision_accepts_enum_string_and_missing_values():
    assert _timeline_date_precision(DatePrecision.YEAR) == "year"
    assert _timeline_date_precision("MONTH") == "month"
    assert _timeline_date_precision("DatePrecision.DAY") == "day"
    assert _timeline_date_precision(None) == "unknown"
