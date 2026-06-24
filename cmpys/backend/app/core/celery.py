from celery import Celery

from app.core.config import settings

celery_app = Celery(
    "cmpys",
    broker=settings.redis_url,
    backend=settings.redis_url,
    include=["app.tasks.ingestion", "app.tasks.plans"],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=600,  # 10 minutes max
    worker_prefetch_multiplier=1,
    task_default_queue="default",
    task_routes={
        "app.tasks.ingestion.run_generate_idea_cards": {"queue": "low_priority"},
    },
)
