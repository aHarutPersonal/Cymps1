from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from fastapi import FastAPI

from app.api.router import router as api_router
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

from fastapi.middleware.cors import CORSMiddleware

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

# Include routers
app.include_router(health_router)
app.include_router(api_router)
