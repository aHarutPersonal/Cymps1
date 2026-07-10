from app.api.v1.sessions import router


def test_literal_session_routes_precede_dynamic_session_id_route():
    """FastAPI matches routes in declaration order.

    If the dynamic route comes first, ``/sessions/latest`` is interpreted as
    session_id="latest" and PostgreSQL rejects it as an invalid UUID.
    """
    get_paths = [
        route.path
        for route in router.routes
        if "GET" in getattr(route, "methods", set())
    ]

    dynamic_index = get_paths.index("/sessions/{session_id}")
    assert get_paths.index("/sessions/current") < dynamic_index
    assert get_paths.index("/sessions/latest") < dynamic_index
