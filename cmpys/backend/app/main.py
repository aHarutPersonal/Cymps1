from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
import os

from app.api.router import router as api_router
from app.api.v1.media import router as media_router
from app.core.config import settings
from app.core.health import router as health_router
from app.core.logging import setup_logging, get_logger
from app.core.middleware import ResponseBodyLoggerMiddleware

logger = get_logger("cmpys.main")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler."""
    setup_logging()
    logger.info(f"Starting {settings.app_name} application")
    logger.info(f"Debug mode: {settings.debug}")
    logger.info(f"LLM provider: {settings.llm_provider}")
    logger.info(f"LLM configured: {settings.llm_configured}")
    yield
    logger.info(f"Shutting down {settings.app_name} application")


app = FastAPI(
    title=settings.app_name,
    debug=settings.debug,
    lifespan=lifespan,
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add request/response logging middleware
# This logs all HTTP requests in curl format and responses with timing
app.add_middleware(ResponseBodyLoggerMiddleware)

# Compress JSON/text responses over ~1KB. Large list payloads (feed,
# content library, session outputs) typically shrink 60-85% on the wire.
# Added last so it sits OUTERMOST: the body logger above still sees the
# uncompressed body, while the client receives the gzipped response.
app.add_middleware(GZipMiddleware, minimum_size=1024)

# Include routers
app.include_router(health_router)
app.include_router(api_router)

# Mount media directory for static files (e.g. generated avatars)
# Create media directory if it doesn't exist to prevent StaticFiles exception on startup
os.makedirs("media", exist_ok=True)

# Important: Add the media router BEFORE StaticFiles so it intercepts 404s
app.include_router(media_router, prefix="/media", tags=["media"])

# Fallback to StaticFiles for anything not captured by the router (though the router handles /{filename})
app.mount("/media", StaticFiles(directory="media"), name="media")
