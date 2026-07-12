from datetime import date
from types import SimpleNamespace

from app.services.ingestion.dates import (
    apply_computed_timeline_ages,
    compute_event_age,
)
from app.services.llm.schemas import (
    DatePrecision,
    ExtractedProfile,
    ProfileExtractionResponse,
    TimelineEvent,
    TimelineNormalizationResponse,
)


def _evidence(snippet: str):
    return [SimpleNamespace(snippet=snippet)]


def test_day_precision_computes_exact_age() -> None:
    assert compute_event_age(
        birth_date=date(1990, 8, 30),
        event_date=date(2015, 5, 1),
        date_precision="day",
    ) == 24


def test_month_precision_uses_known_month() -> None:
    assert compute_event_age(
        birth_date=date(1990, 8, 30),
        event_date=date(2015, 5, 1),
        date_precision="month",
    ) == 24


def test_year_precision_uses_conservative_later_age() -> None:
    assert compute_event_age(
        birth_date=date(1990, 8, 30),
        event_date=date(2015, 1, 1),
        date_precision="year",
    ) == 25


def test_verbatim_source_age_wins_over_partial_date() -> None:
    assert compute_event_age(
        birth_date=date(1930, 8, 30),
        event_date=date(1942, 1, 1),
        date_precision="year",
        evidence=_evidence("Buffett bought his first stock at age 11"),
    ) == 11


def test_value_phrase_is_not_misread_as_an_age() -> None:
    assert compute_event_age(
        birth_date=date(1990, 8, 30),
        event_date=date(2015, 1, 1),
        date_precision="year",
        evidence=_evidence("The company was valued at 100 million dollars."),
    ) == 25


def test_when_person_was_age_is_recognized() -> None:
    assert compute_event_age(
        birth_date=None,
        event_date=None,
        date_precision="unknown",
        evidence=_evidence("She published the work when she was 19."),
    ) == 19


def test_unknown_date_without_source_age_stays_unknown() -> None:
    assert compute_event_age(
        birth_date=date(1990, 8, 30),
        event_date=None,
        date_precision="unknown",
    ) is None


def test_timeline_postprocessing_replaces_model_age_math() -> None:
    profile = ProfileExtractionResponse(
        profile=ExtractedProfile(
            display_name="Example",
            birth_date=date(1990, 8, 30),
            confidence=0.9,
        )
    )
    response = TimelineNormalizationResponse(
        timeline=[
            TimelineEvent(
                canonical_title="Published work",
                canonical_description="Published documented work.",
                date=date(2015, 1, 1),
                date_precision=DatePrecision.YEAR,
                age_at_event=3,
                importance_score=0.8,
                confidence=0.9,
            )
        ]
    )

    apply_computed_timeline_ages(profile, response)

    assert response.timeline[0].age_at_event == 25
