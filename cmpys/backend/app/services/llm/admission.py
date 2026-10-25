"""Cross-worker provider permits with expiring leases and foreground reserve."""
import asyncio
import hashlib
import time
from contextlib import asynccontextmanager, contextmanager
from contextvars import ContextVar
from uuid import uuid4
from functools import wraps

from app.core.config import settings

_scope = ContextVar("llm_workload", default=("foreground", None))

# Redis TIME avoids worker clock skew. All three keys share a Redis hash slot.
ACQUIRE = """
local t = redis.call('TIME')
local now = t[1] * 1000 + math.floor(t[2] / 1000)
for _, key in ipairs(KEYS) do redis.call('ZREMRANGEBYSCORE', key, '-inf', now) end
if ARGV[5] == 'background' then redis.call('ZADD', KEYS[4], 'NX', now + ARGV[7], ARGV[1]) end
local oldest = redis.call('ZRANGE', KEYS[4], 0, 0, 'WITHSCORES')
if ARGV[5] == 'foreground' and #oldest > 0 and tonumber(oldest[2]) - now < tonumber(ARGV[7]) - 5000
   and redis.call('ZCARD', KEYS[2]) == 0 and redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[2]) - 1 then return 0 end
if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[2]) then return 0 end
if ARGV[5] == 'background' and redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[3]) then return 0 end
if redis.call('ZCARD', KEYS[3]) >= tonumber(ARGV[4]) then return 0 end
redis.call('ZADD', KEYS[1], now + ARGV[6], ARGV[1])
if ARGV[5] == 'background' then redis.call('ZADD', KEYS[2], now + ARGV[6], ARGV[1]) end
redis.call('ZADD', KEYS[3], now + ARGV[6], ARGV[1])
redis.call('ZREM', KEYS[4], ARGV[1])
for _, key in ipairs(KEYS) do redis.call('PEXPIRE', key, ARGV[6] + 1000) end
return 1
"""
RELEASE = "for _, key in ipairs(KEYS) do redis.call('ZREM', key, ARGV[1]) end return 1"


@contextmanager
def admission_scope(workload, user_id=None):
    token = _scope.set((workload, user_id))
    try:
        yield
    finally:
        _scope.reset(token)


def background_generation(function):
    @wraps(function)
    async def run(*args, **kwargs):
        with admission_scope("background"):
            return await function(*args, **kwargs)
    return run


@asynccontextmanager
async def provider_permit(provider, model, *, timeout):
    limit = settings.llm_admission_limits.get(f"{provider}:{model}", 0)
    if not limit:
        yield 0.0
        return
    if limit <= settings.llm_admission_foreground_reserve:
        raise ValueError("Provider capacity must exceed foreground reserve")
    from redis.asyncio import Redis
    client = Redis.from_url(settings.redis_url, socket_connect_timeout=2, socket_timeout=2)
    workload, user = _scope.get()
    # Never put account identifiers or endpoint credentials in Redis keys.
    route = hashlib.sha256(f"{provider}:{model}".encode()).hexdigest()[:20]
    owner = hashlib.sha256(str(user or uuid4()).encode()).hexdigest()[:20]
    prefix = "llm:admission:{" + route + "}"
    keys = [prefix + ":all", prefix + ":background", prefix + ":user:" + owner, prefix + ":waiting"]
    token = str(uuid4())
    started = time.monotonic()
    acquired = False
    try:
        async with asyncio.timeout(settings.llm_admission_wait_seconds):
            while not acquired:
                acquired = bool(await client.eval(ACQUIRE, len(keys), *keys, token, limit,
                    limit - settings.llm_admission_foreground_reserve,
                    settings.llm_admission_per_user, workload, round((timeout + 15) * 1000),
                    round(settings.llm_admission_wait_seconds * 1000)))
                if not acquired:
                    await asyncio.sleep(.1)
        yield (time.monotonic() - started) * 1000
    finally:
        if client is not None:
            try:
                async with asyncio.timeout(2):
                    await client.eval(RELEASE, len(keys), *keys, token)
            except Exception:
                pass  # The lease bounds crash/disconnect recovery.
        await client.aclose()
