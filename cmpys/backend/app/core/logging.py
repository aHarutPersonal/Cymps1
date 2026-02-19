"""
Comprehensive logging configuration for the application.

Features:
- Console output for development
- File-based logging to logs/cmpys.log
- Request/response logging in curl format
- Structured log format with timestamps
"""
import logging
import os
import sys
from datetime import datetime
from logging.handlers import RotatingFileHandler
from pathlib import Path

from app.core.config import settings

# Log directory (relative to backend folder)
LOG_DIR = Path(__file__).parent.parent.parent / "logs"
LOG_FILE = LOG_DIR / "cmpys.log"
REQUEST_LOG_FILE = LOG_DIR / "requests.log"

# Ensure log directory exists
LOG_DIR.mkdir(exist_ok=True)


class CurlFormatter(logging.Formatter):
    """Custom formatter that outputs request logs in a readable format."""
    
    def format(self, record: logging.LogRecord) -> str:
        # Add timestamp
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        
        # Check if this is a request/response log
        if hasattr(record, "curl_command"):
            return f"\n{'='*80}\n[{timestamp}] {record.curl_command}\n{'='*80}"
        elif hasattr(record, "response_log"):
            return f"[{timestamp}] {record.response_log}\n{'-'*80}\n"
        
        return super().format(record)


def setup_logging() -> None:
    """
    Configure comprehensive logging for the application.
    
    Creates two log files:
    - logs/cmpys.log: All application logs
    - logs/requests.log: HTTP request/response logs in curl format
    """
    log_level = logging.DEBUG if settings.debug else logging.INFO
    
    # Root logger configuration
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    
    # Clear existing handlers
    root_logger.handlers.clear()
    
    # Console handler (stdout)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)
    console_format = logging.Formatter(
        "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    console_handler.setFormatter(console_format)
    root_logger.addHandler(console_handler)
    
    # File handler for all logs (rotating, max 10MB, keep 5 backups)
    file_handler = RotatingFileHandler(
        LOG_FILE,
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5,
        encoding="utf-8",
    )
    file_handler.setLevel(log_level)
    file_format = logging.Formatter(
        "%(asctime)s | %(levelname)-8s | %(name)s | %(funcName)s:%(lineno)d | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    file_handler.setFormatter(file_format)
    root_logger.addHandler(file_handler)
    
    # Request logger (separate file for HTTP requests/responses)
    request_logger = logging.getLogger("cmpys.requests")
    request_logger.setLevel(logging.INFO)
    request_logger.propagate = False  # Don't send to root logger
    
    request_handler = RotatingFileHandler(
        REQUEST_LOG_FILE,
        maxBytes=50 * 1024 * 1024,  # 50 MB (requests can be verbose)
        backupCount=10,
        encoding="utf-8",
    )
    request_handler.setLevel(logging.INFO)
    request_handler.setFormatter(CurlFormatter())
    request_logger.addHandler(request_handler)
    
    # Also log requests to console if debug mode
    if settings.debug:
        request_console = logging.StreamHandler(sys.stdout)
        request_console.setLevel(logging.DEBUG)
        request_console.setFormatter(CurlFormatter())
        request_logger.addHandler(request_console)
    
    # Reduce noise from third-party libraries
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("openai").setLevel(logging.WARNING)
    
    # Log startup info
    app_logger = logging.getLogger("cmpys")
    app_logger.info(f"Logging initialized. Log files: {LOG_DIR}")
    app_logger.info(f"Log level: {logging.getLevelName(log_level)}")


def get_logger(name: str) -> logging.Logger:
    """Get a logger instance with the given name."""
    return logging.getLogger(name)


def get_request_logger() -> logging.Logger:
    """Get the request logger for HTTP request/response logging."""
    return logging.getLogger("cmpys.requests")


def log_request(
    method: str,
    url: str,
    headers: dict,
    body: str | None = None,
    query_params: str | None = None,
) -> None:
    """
    Log an HTTP request in curl format.
    
    Example output:
    curl -X POST 'http://localhost:8000/api/v1/auth/login' \
      -H 'Content-Type: application/json' \
      -d '{"email": "test@example.com", "password": "..."}'
    """
    logger = get_request_logger()
    
    # Build curl command
    full_url = url
    if query_params:
        full_url = f"{url}?{query_params}"
    
    curl_parts = [f"curl -X {method} '{full_url}'"]
    
    # Add headers (skip some internal ones)
    skip_headers = {"host", "content-length", "connection", "accept-encoding"}
    for key, value in headers.items():
        if key.lower() not in skip_headers:
            # Mask sensitive headers
            if key.lower() == "authorization":
                value = "Bearer ***" if value.startswith("Bearer ") else "***"
            curl_parts.append(f"  -H '{key}: {value}'")
    
    # Add body
    if body:
        # Mask sensitive fields in body
        masked_body = _mask_sensitive_data(body)
        curl_parts.append(f"  -d '{masked_body}'")
    
    curl_command = " \\\n".join(curl_parts)
    
    # Log with custom attribute
    record = logger.makeRecord(
        name=logger.name,
        level=logging.INFO,
        fn="",
        lno=0,
        msg="",
        args=(),
        exc_info=None,
    )
    record.curl_command = f"REQUEST:\n{curl_command}"
    logger.handle(record)


def log_response(
    status_code: int,
    headers: dict,
    body: str | None = None,
    duration_ms: float = 0,
) -> None:
    """
    Log an HTTP response.
    
    Example output:
    RESPONSE: 200 OK (125.3ms)
    Content-Type: application/json
    {"accessToken": "***"}
    """
    logger = get_request_logger()
    
    # Build response log
    response_parts = [f"RESPONSE: {status_code} ({duration_ms:.1f}ms)"]
    
    # Add relevant headers
    include_headers = {"content-type", "x-request-id", "x-process-time"}
    for key, value in headers.items():
        if key.lower() in include_headers:
            response_parts.append(f"  {key}: {value}")
    
    # Add body (truncated if too long)
    if body:
        masked_body = _mask_sensitive_data(body)
        # Truncate very long responses
        if len(masked_body) > 2000:
            masked_body = masked_body[:2000] + "... [truncated]"
        response_parts.append(f"  Body: {masked_body}")
    
    response_log = "\n".join(response_parts)
    
    # Log with custom attribute
    record = logger.makeRecord(
        name=logger.name,
        level=logging.INFO,
        fn="",
        lno=0,
        msg="",
        args=(),
        exc_info=None,
    )
    record.response_log = response_log
    logger.handle(record)


def _mask_sensitive_data(data: str) -> str:
    """Mask sensitive fields in JSON data."""
    import re
    
    # Mask password fields
    data = re.sub(
        r'"password"\s*:\s*"[^"]*"',
        '"password": "***"',
        data,
        flags=re.IGNORECASE,
    )
    
    # Mask token fields
    data = re.sub(
        r'"(access_?token|accessToken|token|refresh_?token)"\s*:\s*"[^"]*"',
        r'"\1": "***"',
        data,
        flags=re.IGNORECASE,
    )
    
    # Mask API keys
    data = re.sub(
        r'"(api_?key|apiKey|secret)"\s*:\s*"[^"]*"',
        r'"\1": "***"',
        data,
        flags=re.IGNORECASE,
    )
    
    return data
