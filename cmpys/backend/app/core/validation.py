"""Shared request-validation helpers."""
from uuid import UUID


def is_valid_uuid(value: str | None) -> bool:
    """Return True if ``value`` is a syntactically valid UUID string.

    Path parameters typed as ``str`` are passed straight to the database, and a
    Postgres UUID column raises (surfacing as HTTP 500) when handed a
    non-UUID string. Validate first so malformed ids resolve to a clean 404.
    """
    if not value:
        return False
    try:
        UUID(str(value))
        return True
    except (ValueError, AttributeError, TypeError):
        return False
