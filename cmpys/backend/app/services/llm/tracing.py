"""Privacy-safe attempt traces that survive an enclosing generation deadline."""
import asyncio
from contextvars import ContextVar
from functools import wraps
from uuid import uuid4

trace_context: ContextVar[dict | None] = ContextVar("generation_trace", default=None)


def traced_operation(operation):
    def decorate(function):
        @wraps(function)
        async def run(*args, **kwargs):
            parent = trace_context.get()
            metadata = kwargs.get("metadata") or kwargs.get("telemetry_context") or {}
            token = trace_context.set(parent or {
                "trace_id": kwargs.get("trace_id") or metadata.get("curriculum_job_id") or str(uuid4()),
                "operation": kwargs.get("operation") or operation,
                **{k: metadata[k] for k in ("curriculum_job_id", "plan_item_id") if k in metadata},
            })
            try:
                return await function(*args, **kwargs)
            finally:
                trace_context.reset(token)
        return run
    return decorate


async def record_attempt(response, *, schema_name=None, cancelled=False, started=False):
    context = trace_context.get()
    if not context:
        return
    from app.services.llm.telemetry import record_llm_response
    response.trace_id = context["trace_id"]
    response.attempt_id = response.attempt_id or str(uuid4())
    try:
        async with asyncio.timeout(2):
            saved = await record_llm_response(
                operation=context["operation"], response=response,
                result_status="started" if started else "cancelled" if cancelled else "transport_failed" if response.error else "transport_completed",
                metadata={**context, "subtask": schema_name, "attempt_id": response.attempt_id},
            )
            response.trace_recorded = saved is True
    except Exception:
        # Caller still records the attempt if this best-effort write fails.
        pass
