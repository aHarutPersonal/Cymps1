"""Safe bridge from synchronous Celery tasks into async application code."""

import asyncio
from collections.abc import Coroutine
from typing import Any, TypeVar


T = TypeVar("T")


def run_async(coro: Coroutine[Any, Any, T]) -> T:
    """Run a coroutine on a persistent worker-local event loop.

    Python 3.11 does not guarantee that synchronous Celery child processes
    have a current loop. Retaining a loop per worker also keeps async database
    connections on the loop where they were created.
    """
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    if loop.is_closed():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    return loop.run_until_complete(coro)
