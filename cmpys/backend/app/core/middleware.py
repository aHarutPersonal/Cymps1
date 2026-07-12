"""
HTTP middleware for request/response logging and processing.

Logs all requests in curl format and responses with timing information.
"""
import time
from collections.abc import Callable
from typing import Any

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

from app.core.config import settings
from app.core.logging import get_logger, log_request, log_response

logger = get_logger("cmpys.middleware")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """
    Middleware that logs all HTTP requests and responses.
    
    Features:
    - Logs requests in curl format
    - Logs response status and timing
    - Masks sensitive data (passwords, tokens)
    - Skips health check endpoints to reduce noise
    """
    
    # Endpoints to skip logging (noisy health checks)
    SKIP_PATHS = {"/health", "/ready", "/favicon.ico"}
    
    def __init__(self, app: ASGIApp, log_request_body: bool = True, log_response_body: bool = True):
        super().__init__(app)
        self.log_request_body = log_request_body
        self.log_response_body = log_response_body
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Skip logging for noisy endpoints
        if request.url.path in self.SKIP_PATHS:
            return await call_next(request)
        
        start_time = time.perf_counter()
        
        # Log request
        await self._log_request(request)
        
        # Process request
        response = await call_next(request)
        
        # Calculate duration
        duration_ms = (time.perf_counter() - start_time) * 1000
        
        # Log response
        await self._log_response(request, response, duration_ms)
        
        # Add timing header
        response.headers["X-Process-Time"] = f"{duration_ms:.2f}ms"
        
        return response
    
    async def _log_request(self, request: Request) -> None:
        """Log the incoming request in curl format."""
        try:
            # Get request details
            method = request.method
            url = str(request.url.path)
            query_params = str(request.url.query) if request.url.query else None
            
            # Get headers
            headers = dict(request.headers)
            
            # Get body (only for methods that typically have a body)
            body = None
            if self.log_request_body and method in {"POST", "PUT", "PATCH"}:
                try:
                    body_bytes = await request.body()
                    if body_bytes:
                        body = body_bytes.decode("utf-8")
                except Exception:
                    body = "[body read error]"
            
            # Build base URL
            base_url = f"{request.url.scheme}://{request.url.netloc}{url}"
            
            # Log it
            log_request(
                method=method,
                url=base_url,
                headers=headers,
                body=body,
                query_params=query_params,
            )
            
            # Also log to general logger
            logger.info(f"{method} {url} - Request received")
            
        except Exception as e:
            logger.warning(f"Failed to log request: {e}")
    
    async def _log_response(self, request: Request, response: Response, duration_ms: float) -> None:
        """Log the outgoing response."""
        try:
            # Get response details
            status_code = response.status_code
            headers = dict(response.headers)
            
            # Get response body (need to read and reconstruct)
            body = None
            if self.log_response_body:
                # For streaming responses, we can't easily get the body
                # Only log for regular responses
                if hasattr(response, "body"):
                    try:
                        body = response.body.decode("utf-8")
                    except Exception:
                        body = "[binary data]"
            
            # Log it
            log_response(
                status_code=status_code,
                headers=headers,
                body=body,
                duration_ms=duration_ms,
            )
            
            # Also log to general logger
            logger.info(
                f"{request.method} {request.url.path} - {status_code} ({duration_ms:.1f}ms)"
            )
            
        except Exception as e:
            logger.warning(f"Failed to log response: {e}")


class ResponseBodyLoggerMiddleware:
    """
    ASGI middleware to capture response body for logging.
    
    This middleware wraps the response to capture the body content
    for logging purposes while still streaming it to the client.
    """
    
    SKIP_PATHS = {"/health", "/ready", "/favicon.ico"}
    # Job status is polled every few seconds and historically dominates HTTP
    # traffic. Successful polls add little diagnostic value, so keep failures
    # while avoiding log formatting, queueing, and disk I/O for the hot path.
    QUIET_SUCCESS_PREFIXES = ("/api/v1/jobs/",)

    # Cap how much body we retain for logging. log_response truncates to
    # 2,000 chars anyway, so buffering multi-MB payloads (or entire SSE
    # streams) only burns memory and regex time on every request.
    MAX_CAPTURED_BODY = 8 * 1024

    def __init__(self, app: ASGIApp):
        self.app = app
        self.capture_bodies = settings.debug or settings.http_body_logging_enabled

    @classmethod
    def should_log(cls, path: str, status_code: int) -> bool:
        return status_code >= 400 or not path.startswith(cls.QUIET_SUCCESS_PREFIXES)
    
    async def __call__(self, scope: dict, receive: Any, send: Any) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        
        # Skip logging for noisy endpoints
        path = scope.get("path", "")
        if path in self.SKIP_PATHS:
            await self.app(scope, receive, send)
            return
        
        start_time = time.perf_counter()
        
        # Capture request body
        request_body = b""
        request_body_captured = False
        
        async def receive_wrapper():
            nonlocal request_body, request_body_captured
            message = await receive()
            if message["type"] == "http.request" and not request_body_captured:
                body = message.get("body", b"")
                if len(request_body) < self.MAX_CAPTURED_BODY:
                    request_body += body[: self.MAX_CAPTURED_BODY - len(request_body)]
                if not message.get("more_body", False):
                    request_body_captured = True
            return message

        # Capture response
        response_status = 0
        response_headers: dict = {}
        response_body = b""
        is_event_stream = False

        async def send_wrapper(message: dict) -> None:
            nonlocal response_status, response_headers, response_body, is_event_stream

            if message["type"] == "http.response.start":
                response_status = message["status"]
                response_headers = {
                    k.decode() if isinstance(k, bytes) else k:
                    v.decode() if isinstance(v, bytes) else v
                    for k, v in message.get("headers", [])
                }
                # Never buffer SSE bodies: a stream is long-lived, its content
                # is already logged at the source, and accumulating it here
                # holds the whole LLM output in memory per connection.
                is_event_stream = "text/event-stream" in response_headers.get(
                    "content-type", ""
                )
            elif (
                self.capture_bodies
                and message["type"] == "http.response.body"
                and not is_event_stream
            ):
                if len(response_body) < self.MAX_CAPTURED_BODY:
                    body = message.get("body", b"")
                    response_body += body[: self.MAX_CAPTURED_BODY - len(response_body)]

            await send(message)
        
        # Process request
        await self.app(
            scope,
            receive_wrapper if self.capture_bodies else receive,
            send_wrapper,
        )
        
        # Calculate duration
        duration_ms = (time.perf_counter() - start_time) * 1000

        if not self.should_log(path, response_status):
            return

        # Log request and response
        try:
            method = scope.get("method", "GET")
            query_string = scope.get("query_string", b"").decode()
            headers = {
                k.decode() if isinstance(k, bytes) else k:
                v.decode() if isinstance(v, bytes) else v
                for k, v in scope.get("headers", [])
            }
            
            # Build URL
            scheme = scope.get("scheme", "http")
            server = scope.get("server", ("localhost", 8000))
            host = f"{server[0]}:{server[1]}" if server else "localhost:8000"
            base_url = f"{scheme}://{host}{path}"
            
            # Log request
            request_body_str = None
            if request_body and method in {"POST", "PUT", "PATCH"}:
                try:
                    request_body_str = request_body.decode("utf-8")
                except Exception:
                    request_body_str = "[binary data]"
            
            log_request(
                method=method,
                url=base_url,
                headers=headers,
                body=request_body_str,
                query_params=query_string if query_string else None,
            )
            
            # Log response
            response_body_str = None
            if response_body:
                try:
                    response_body_str = response_body.decode("utf-8")
                except Exception:
                    response_body_str = "[binary data]"
            
            log_response(
                status_code=response_status,
                headers=response_headers,
                body=response_body_str,
                duration_ms=duration_ms,
            )
            
            # General log
            logger.info(f"{method} {path} - {response_status} ({duration_ms:.1f}ms)")
            
        except Exception as e:
            logger.warning(f"Failed to log request/response: {e}")
