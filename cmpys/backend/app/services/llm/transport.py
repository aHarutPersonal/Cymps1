"""One pooled SDK client per provider credential and event loop.

A new SDK client per request pays a fresh TCP+TLS handshake. The pool is bound
to the event loop that opened it, so a worker that switches loops gets a new
one. Each request then applies its own timeout through ``with_options``, which
wraps the same pool without changing another in-flight request's timeout.
"""

import asyncio
import weakref
from collections.abc import Callable, Hashable
from typing import Any

_pools: "weakref.WeakKeyDictionary[asyncio.AbstractEventLoop, dict[Hashable, Any]]" = weakref.WeakKeyDictionary()


def pooled_client(key: Hashable, build: Callable[[], Any], *, timeout: float) -> Any:
    loop = asyncio.get_running_loop()
    clients = _pools.setdefault(loop, {})
    client = clients.get(key)
    if client is None or client.is_closed():
        client = clients[key] = build()
    return client.with_options(timeout=timeout)


def reset_pools_for_tests() -> None:
    _pools.clear()
