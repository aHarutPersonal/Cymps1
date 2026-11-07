from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Settings of the LLM gateways and MiniMax narration removed on 2026-11-07
# (openlux, Z.ai, Yunwu, OpenRouter). An old .env may still list them; they are
# ignored instead of failing the unknown-key check that catches typos.
_RETIRED_SETTING_PREFIXES = (
    "openlux_", "zai_", "yunwu_", "openrouter_", "lesson_llm_", "lesson_openai_",
    "openai_fast_model", "openai_quality_model", "book_narration_api_base_url", "book_narration_tts_model",
    "book_narration_voice_id", "book_narration_mentor_voice_id", "book_narration_subtitle_allowed_hosts",
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Application
    app_name: str = "cmpys"
    debug: bool = False
    # Full HTTP bodies are expensive to copy/mask and may contain private user
    # text. Production logs request metadata only unless explicitly enabled.
    http_body_logging_enabled: bool = False

    # Database
    database_url: str = "postgresql+psycopg://cmpys:cmpys@localhost:5432/cmpys"

    # Redis
    redis_url: str = "redis://localhost:6379/0"
    # Opt in only after provider quota/load measurement. Keys are provider:model.
    llm_admission_limits: dict[str, int] = {}
    llm_admission_foreground_reserve: int = Field(default=1, ge=1)
    llm_admission_per_user: int = Field(default=2, ge=1)
    llm_admission_wait_seconds: float = Field(default=30, gt=0, le=120)
    curriculum_parallel_reviews: bool = False
    google_books_api_key: str | None = Field(default=None, repr=False, exclude=True)
    google_books_secret_id: str | None = None
    google_books_secret_region: str = "us-east-1"
    # Shell/Compose worker settings also belong to the accepted dotenv schema.
    # Modeling them keeps typo detection (`extra=forbid`) without making the
    # checked-in .env.example impossible to load through BaseSettings.
    celery_default_pool: str = "solo"
    celery_default_concurrency: int = 1
    celery_high_pool: str = "solo"
    celery_high_concurrency: int = 1
    celery_low_pool: str = "solo"
    celery_low_concurrency: int = 1

    # JWT
    jwt_secret_key: str = "change-me-in-production-use-openssl-rand-hex-32"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7

    # Password recovery stays disabled until a verified SMTP sender is connected.
    recovery_smtp_host: str | None = None
    recovery_smtp_port: int = Field(default=587, ge=1, le=65535)
    recovery_smtp_username: str | None = Field(default=None, repr=False, exclude=True)
    recovery_smtp_password: str | None = Field(default=None, repr=False, exclude=True)
    recovery_smtp_tls: str = "starttls"
    recovery_email_sender: str | None = None

    # Extraction
    extractor_mode: str = "deterministic"  # "deterministic" or "llm"

    # LLM Configuration. "routed" sends each operation to its assigned model
    # (app/services/llm/routes.py); "dummy" returns fixtures for tests and dev.
    llm_provider: Literal["dummy", "routed"] = "dummy"
    # Direct providers (owner decision, 2026-11-07): Claude Haiku 5.5 and
    # gpt-6-luna, each the other's backup. Gemini serves only Google Search
    # grounding and audiobook narration.
    anthropic_api_key: str | None = Field(default=None, repr=False, exclude=True)
    anthropic_model: str = "claude-haiku-5-5"
    # Adaptive thinking shares max_tokens; reserve it on top of the visible budget.
    # 8192 is what the 2026-11-07 Haiku tutorial eval measured; at 2048, three of
    # four activity drafts in a smoke run stopped at the limit mid-thought.
    anthropic_reasoning_token_reserve: int = Field(default=8192, ge=0, le=8192)
    openai_api_key: str | None = Field(default=None, repr=False, exclude=True)
    openai_model: str = "gpt-6-luna"
    # Hidden reasoning shares max_completion_tokens; reserve it the same way.
    openai_reasoning_token_reserve: int = Field(default=2048, ge=0, le=8192)
    # Operation or stage name -> primary provider; the other provider becomes
    # its backup. Empty keeps the 2026-11-07 assignment, e.g.
    # LLM_ROUTE_OVERRIDES='{"books": "anthropic"}'.
    llm_route_overrides: dict[str, Literal["anthropic", "openai"]] = {}

    # Expressive in-reader narration. Recordings are content-addressed and
    # persisted; exact highlighting is exposed only when the provider supplies it.
    book_narration_enabled: bool = True
    book_narration_provider: Literal["gemini"] = "gemini"
    book_narration_gemini_model: str = "gemini-3.8-flash-tts"
    book_narration_gemini_voice: str = "Sulafat"
    book_narration_gemini_mentor_voice: str = "Gacrux"
    book_narration_media_dir: str = "media"
    book_narration_timeout_seconds: float = 60.0
    # The "subtitle" limits bound the Gemini word-timing transcription call.
    book_narration_subtitle_timeout_seconds: float = 10.0
    book_narration_max_audio_bytes: int = 20_000_000
    book_narration_max_subtitle_bytes: int = 1_000_000

    # Tavily (real-time web search for material URL resolution)
    tavily_api_key: str | None = None

    # Google Gemini: Google Search grounded lookups and narration only. The
    # tier models serve grounded calls (fast for bounded lookups).
    gemini_api_key: str | None = Field(default=None, repr=False, exclude=True)
    gemini_model: str = "gemini-3.6-flash"
    gemini_fast_model: str = "gemini-3.5-flash-lite"
    gemini_quality_model: str = "gemini-3.1-pro-preview"

    # Plan generation
    plan_generator_mode: str = "deterministic"  # "deterministic" or "llm"
    # Safe runtime pilot. A catalog miss or failed personal composition falls
    # through to the existing bespoke lesson generator.
    lesson_catalog_first_enabled: bool = False

    # One Imagen 4 hero illustration per published tutorial (no text in the image).
    # Off until the owner enables it: every image is a paid call. The cap counts
    # images written to media/tutorials/ today; reused images never count.
    tutorial_illustrations_enabled: bool = False
    tutorial_illustration_daily_cap: int = Field(default=200, ge=0)
    # Draft a fresh tutorial while its package preflight runs; the draft is used
    # only after an approval that leaves every writer input unchanged.
    tutorial_speculative_writer: bool = True
    # Exercise-package repairs per tutorial. A second repair runs only for
    # defects with validated repair targets and is followed by the full recheck.
    tutorial_package_repairs: int = Field(default=1, ge=1, le=2)
    # Fresh whole-tutorial attempts after a failed one, within the same job
    # deadline (plan Phase 4.1); each starts from new private checkpoints.
    # Off by default, like a second package repair; enable with the env var.
    tutorial_fresh_attempts: int = Field(default=0, ge=0, le=2)
    # Two focused accuracy critics beside the full tutorial review, for
    # tutorials with few numeric spans. Built for GLM; the 2026-11-07 model
    # eval ran without them, so they stay off unless re-evaluated.
    tutorial_focused_accuracy_review: bool = False
    # Numerals allowed in tutorial prose outside native fences (0 = no limit);
    # also asks seed, activity and writer prompts to keep numbers in data and steps.
    tutorial_numeric_budget: int = Field(default=0, ge=0, le=20)

    # Local LLM (Spec 2 — inert until then)
    local_llm_base_url: str | None = None  # e.g. http://gpu-box:8000/v1 (Spec 2)
    local_llm_model: str | None = None  # e.g. qwen2.5-32b-instruct (Spec 2)
    embedding_model: str = "bge-m3"  # used by Spec 2 ingestion

    # 24/7 catalog scheduler. Conservative defaults keep a small deployment
    # within a predictable LLM budget while still draining demand continuously.
    catalog_scheduler_enabled: bool = True
    catalog_tick_seconds: int = 60
    catalog_dispatch_per_tick: int = 1
    catalog_worker_pool: str = "solo"
    catalog_worker_concurrency: int = 1
    catalog_control_pool: str = "solo"
    catalog_daily_job_limit: int = 50
    catalog_seed_per_tick: int = 25
    catalog_max_attempts: int = 3
    catalog_stale_job_minutes: int = 20
    catalog_quotes_per_idol_limit: int = 30
    catalog_quote_min_confidence: float = 0.84
    catalog_quote_verification_enabled: bool = True
    catalog_quote_verification_batch_size: int = 4
    catalog_quote_verification_daily_limit: int = 2

    # Evidence-based curriculum factory. It is intentionally off until the
    # deterministic pilot taxonomy has been reviewed and seeded. Curriculum
    # spend is accounted separately from the general background catalog.
    curriculum_enabled: bool = False
    curriculum_control_interval_seconds: int = 60
    curriculum_max_dispatch_per_tick: int = 1
    curriculum_max_running_jobs: int = 2
    curriculum_lease_seconds: int = 20 * 60
    curriculum_max_repairs: int = 2
    curriculum_daily_budget_usd: float = 0.20
    curriculum_job_budget_usd: float = 0.60
    curriculum_daily_job_limit: int = 8
    curriculum_durable_spacing_scheduler_enabled: bool = False
    curriculum_research_model_tier: str = "fast"
    curriculum_writing_model_tier: str = "balanced"
    curriculum_review_model_tier: str = "quality"
    # Deployment-only worker knobs are still modeled because Settings rejects
    # unknown keys when developers copy the complete .env.example locally.
    curriculum_worker_pool: str = "prefork"
    curriculum_worker_concurrency: int = 1
    curriculum_control_pool: str = "solo"

    # When every user-facing generation queue and tracked catalog job is idle,
    # discover at most one new book or idol candidate on this slower cadence.
    # The kinds alternate by UTC time bucket and still pass through the normal
    # catalog budget, retry, evidence, and publication-quality gates.
    catalog_idle_discovery_enabled: bool = True
    catalog_idle_discovery_interval_seconds: int = 15 * 60
    catalog_idle_discovery_daily_limit: int = 6
    catalog_idle_discovery_recent_user_minutes: int = 10
    catalog_idle_discovery_priority: int = 10
    catalog_idle_discovery_interactive_queues: str = (
        "high_priority,default,low_priority"
    )

    # Persist model usage and downstream quality outcomes. Recording failures
    # never fail the user-facing operation.
    llm_usage_telemetry_enabled: bool = True

    # Autonomous catalog spend guard. The default caps background generation
    # at roughly $15/month while leaving user-triggered requests untouched.
    # At the soft threshold only zero-LLM-cost source imports continue; the
    # remaining headroom protects against in-flight calls and retries.
    llm_background_daily_budget_usd: float = 0.50
    llm_background_budget_soft_ratio: float = 0.85
    llm_budget_include_search_overage: bool = False
    llm_unknown_input_price_usd_per_million: float = 1.25
    llm_unknown_output_price_usd_per_million: float = 10.00
    catalog_book_budget_reserve_usd: float = 0.06
    catalog_idol_budget_reserve_usd: float = 0.12
    catalog_quote_verification_budget_reserve_usd: float = 0.04

    # Conservative adaptive routing: production may enable a small Fast-Lite
    # canary; quality-gated operations fall back to the balanced tier.
    adaptive_routing_enabled: bool = False
    adaptive_routing_lookback_days: int = 30
    adaptive_routing_min_samples: int = 20
    adaptive_routing_canary_percent: int = 10
    adaptive_routing_min_success_rate: float = 0.90
    adaptive_routing_min_quality_score: float = 0.90

    @model_validator(mode="before")
    @classmethod
    def ignore_retired_settings(cls, data):
        if isinstance(data, dict):
            return {key: value for key, value in data.items()
                    if not str(key).casefold().startswith(_RETIRED_SETTING_PREFIXES)}
        return data

    @model_validator(mode="after")
    def load_secret_credentials(self):
        if not self.google_books_api_key and self.google_books_secret_id:
            from app.core.credentials import read_aws_secret

            self.google_books_api_key = read_aws_secret(
                self.google_books_secret_id,
                self.google_books_secret_region,
                "GOOGLE_BOOKS_API_KEY",
            )
        return self

    @property
    def llm_configured(self) -> bool:
        """Routed generation needs at least one direct provider credential."""
        if self.llm_provider == "routed":
            return bool(self.anthropic_api_key or self.openai_api_key)
        return True  # Dummy is always configured


settings = Settings()
