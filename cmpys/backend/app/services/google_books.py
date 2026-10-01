"""Shared Books lookup with private credentials and cross-worker quota cooldown."""

import hashlib
import json
import logging
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import httpx
from redis.asyncio import Redis
from redis.exceptions import RedisError

from app.core.config import settings

logger = logging.getLogger(__name__)
GOOGLE_BOOKS_URL = "https://www.googleapis.com/books/v1/volumes"
CACHE_TTL = 86400


def _cache_client():
    return Redis.from_url(settings.redis_url, socket_connect_timeout=1, socket_timeout=1)


def _cooldown_seconds(response: httpx.Response) -> int:
    """Daily quotas need a long pause; honor bounded Retry-After when present."""
    seconds = 3600 if response.status_code == 403 else 900
    try:
        details = response.json().get("error", {}).get("details", [])
        if any("day" in str(d.get("metadata", {}).get("quota_limit", "")).lower()
               or "/d/" in str(d.get("metadata", {}).get("quota_unit", ""))
               for d in details):
            seconds = 86400
    except (ValueError, AttributeError, TypeError):
        pass
    retry = response.headers.get("Retry-After")
    if retry:
        try:
            seconds = max(seconds, int(retry))
        except ValueError:
            try:
                seconds = max(seconds, int((parsedate_to_datetime(retry) - datetime.now(timezone.utc)).total_seconds()))
            except (ValueError, TypeError, OverflowError):
                pass
    return min(max(seconds, 60), 86400)


async def search_volumes(params: dict, *, client: httpx.AsyncClient | None = None) -> dict | None:
    key = settings.google_books_api_key
    # Isolate cache/cooldown by credential so fixing configuration takes effect immediately.
    scope = hashlib.sha256((key or "anonymous").encode()).hexdigest()[:20]
    fingerprint = hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()
    prefix = f"google-books:v1:{scope}"
    cache_key, cooldown_key = f"{prefix}:query:{fingerprint}", f"{prefix}:cooldown"
    cache = _cache_client()
    try:
        if cache is not None:
            try:
                cached = await cache.get(cache_key)
                if cached:
                    data = json.loads(cached)
                    if isinstance(data, dict) and isinstance(data.get("items", []), list):
                        return data
                if await cache.get(cooldown_key):
                    return None
            except (RedisError, ValueError, TypeError):
                logger.warning("Google Books cache unavailable; using bounded direct lookup")

        async def request(active_client):
            kwargs = {"params": params}
            if key:
                kwargs["headers"] = {"X-Goog-Api-Key": key}
            return await active_client.get(GOOGLE_BOOKS_URL, **kwargs)

        try:
            if client is None:
                # Never forward credentials to a redirect destination.
                async with httpx.AsyncClient(timeout=10.0, follow_redirects=False) as owned:
                    response = await request(owned)
            else:
                response = await request(client)
            status = getattr(response, "status_code", 200)
            if status in (403, 429):
                pause = _cooldown_seconds(response)
                if cache is not None:
                    try:
                        await cache.set(cooldown_key, "1", ex=pause)
                    except RedisError:
                        logger.warning("Google Books quota cooldown could not be persisted")
                logger.warning("Google Books unavailable: HTTP %s; cooldown_seconds=%s", status, pause)
                return None
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, dict) or not isinstance(data.get("items", []), list):
                logger.warning("Google Books returned an invalid response shape")
                return None
        except (httpx.HTTPError, ValueError, TypeError) as exc:
            # Raw exceptions can contain request URLs, provider text, or credentials.
            logger.warning("Google Books lookup failed: %s", type(exc).__name__)
            return None
        if cache is not None:
            try:
                await cache.set(cache_key, json.dumps(data), ex=CACHE_TTL)
            except RedisError:
                logger.warning("Google Books result cache could not be persisted")
        return data
    finally:
        if cache is not None:
            try:
                await cache.aclose()
            except RedisError:
                logger.warning("Google Books cache connection cleanup failed")
