import feedparser
import urllib.parse
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Optional

router = APIRouter()

class NewsArticle(BaseModel):
    title: str
    link: str
    source: str
    published_at: Optional[str] = None

@router.get("/news", response_model=List[NewsArticle])
async def get_news(query: str = Query(..., min_length=1)):
    """
    Fetch news articles from Google News RSS based on a query.
    """
    try:
        encoded_query = urllib.parse.quote(query)
        rss_url = f"https://news.google.com/rss/search?q={encoded_query}&hl=en-US&gl=US&ceid=US:en"
        
        feed = feedparser.parse(rss_url)
        
        articles = []
        for entry in feed.entries[:10]:  # Limit to 10 items
            articles.append(NewsArticle(
                title=entry.get('title', 'No Title'),
                link=entry.get('link', ''),
                source=entry.get('source', {}).get('title', 'Google News'),
                published_at=entry.get('published', '')
            ))
            
        return articles
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch news: {str(e)}")
