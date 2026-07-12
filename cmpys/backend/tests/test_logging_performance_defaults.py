from app.core.config import settings
from app.core.middleware import ResponseBodyLoggerMiddleware


async def _app(scope, receive, send):
    return None


def test_production_http_logger_does_not_capture_bodies_by_default() -> None:
    middleware = ResponseBodyLoggerMiddleware(_app)

    assert middleware.capture_bodies is (
        settings.debug or settings.http_body_logging_enabled
    )
    if not settings.debug:
        assert middleware.capture_bodies is False


def test_successful_job_polls_are_not_logged_but_failures_are() -> None:
    path = "/api/v1/jobs/job-123"

    assert ResponseBodyLoggerMiddleware.should_log(path, 200) is False
    assert ResponseBodyLoggerMiddleware.should_log(path, 404) is True
    assert ResponseBodyLoggerMiddleware.should_log("/api/v1/plans/current", 200) is True
