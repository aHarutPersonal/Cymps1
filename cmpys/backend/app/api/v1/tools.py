import asyncio
import urllib.parse
from typing import List, Optional

import feedparser
import httpx
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

router = APIRouter()


class NewsArticle(BaseModel):
    title: str
    link: str
    source: str
    published_at: Optional[str] = None


@router.get("/news", response_model=List[NewsArticle])
async def get_news(query: str = Query(..., min_length=1, max_length=300)):
    """Fetch a bounded news feed without blocking other API requests."""
    encoded_query = urllib.parse.quote(query)
    rss_url = f"https://news.google.com/rss/search?q={encoded_query}&hl=en-US&gl=US&ceid=US:en"
    try:
        async with asyncio.timeout(10):
            async with httpx.AsyncClient(timeout=8, follow_redirects=True) as client:
                async with client.stream("GET", rss_url) as response:
                    response.raise_for_status()
                    content = bytearray()
                    async for chunk in response.aiter_bytes():
                        content.extend(chunk)
                        if len(content) > 1_000_000:
                            raise ValueError("News feed is too large")
            feed = await asyncio.to_thread(feedparser.parse, bytes(content))
        return [
            NewsArticle(
                title=entry.get("title", "No title"),
                link=entry.get("link", ""),
                source=entry.get("source", {}).get("title", "Google News"),
                published_at=entry.get("published", ""),
            )
            for entry in feed.entries[:10]
        ]
    except (TimeoutError, httpx.TimeoutException):
        raise HTTPException(status_code=504, detail="News is taking too long. Try again.") from None
    except (httpx.HTTPError, ValueError):
        raise HTTPException(status_code=502, detail="News is temporarily unavailable.") from None
