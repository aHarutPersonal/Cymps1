from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


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

    # Extraction
    extractor_mode: str = "deterministic"  # "deterministic" or "llm"

    # LLM Configuration
    llm_provider: str = "dummy"  # dummy, openai, gemini, yunwu, openlux, openrouter
    zai_api_key: str | None = Field(default=None, repr=False, exclude=True)
    zai_secret_id: str | None = None
    zai_secret_region: str = "us-east-1"
    zai_base_url: str = "https://api.z.ai/api/paas/v4"
    zai_fast_model: str = "glm-5.3-flash"
    zai_model: str = "glm-5.3"
    zai_quality_model: str = "glm-5.3"
    # GLM's max_tokens includes hidden reasoning. Reserve it explicitly.
    zai_reasoning_token_reserve: int = Field(default=2048, ge=0, le=8192)
    # OpenLux is configured independently: old Yunwu credentials and pricing
    # assumptions must not be silently carried into a different account route.
    openlux_api_key: str | None = Field(default=None, repr=False, exclude=True)
    openlux_keychain_service: str | None = None
    openlux_secret_id: str | None = None
    openlux_secret_region: str = "us-east-1"
    openlux_base_url: str = "https://api.openlux.ai/v1"
    openlux_fast_model: str = "gpt-5.6-terra"
    openlux_model: str = "gpt-5.6-terra"
    openlux_quality_model: str = "gpt-5.6-sol"
    # Reserve for hidden reasoning separately from the requested visible text.
    openlux_reasoning_token_reserve: int = Field(default=2048, ge=0, le=8192)
    # Conservative budget estimates, NOT claimed account billing rates.
    # Override after reconciling this token's actual provider invoice.
    openlux_input_usd_per_million: float = Field(default=10.0, ge=0)
    openlux_output_usd_per_million: float = Field(default=50.0, ge=0)
    openai_api_key: str | None = None
    openai_model: str = "gpt-4.1-mini"  # Balanced model for user-visible generation
    openai_fast_model: str = "gpt-4o-mini"  # Lightweight model for thinking/discovery
    openai_quality_model: str = "gpt-4.1"  # Selective fallback for failed quality gates

    # Expressive in-reader narration. Recordings are content-addressed and
    # persisted; exact highlighting is exposed only when the provider supplies it.
    book_narration_enabled: bool = True
    book_narration_provider: str = "gemini"
    # Keep Gemini settings separate from legacy MiniMax environment overrides.
    book_narration_gemini_model: str = "gemini-3.8-flash-tts"
    book_narration_gemini_voice: str = "Sulafat"
    book_narration_gemini_mentor_voice: str = "Gacrux"
    book_narration_api_base_url: str = "https://api.yunwu.ai/minimax/v1"
    book_narration_tts_model: str = "speech-2.8-hd"
    book_narration_voice_id: str = "English_expressive_narrator"
    book_narration_mentor_voice_id: str = "English_Steadymentor"
    book_narration_media_dir: str = "media"
    book_narration_timeout_seconds: float = 60.0
    book_narration_subtitle_timeout_seconds: float = 10.0
    book_narration_max_audio_bytes: int = 20_000_000
    book_narration_max_subtitle_bytes: int = 1_000_000
    # Exact hostname observed from the provider's signed subtitle URLs. Keep
    # this an exact allowlist rather than trusting arbitrary upstream URLs.
    book_narration_subtitle_allowed_hosts: str = (
        "minimax-algeng-chat-tts.oss-cn-wulanchabu.aliyuncs.com"
    )

    # Yunwu's OpenAI-compatible gateway routes the current Gemini family.
    # Flash-Lite handles bounded work, Flash handles visible generation, and
    # Pro is reserved for deterministic quality-gate failures.
    yunwu_api_key: str | None = None
    yunwu_base_url: str = "https://yunwu.ai/v1"
    yunwu_fast_model: str = "gemini-3.5-flash-lite"
    yunwu_model: str = "gemini-3.6-flash"
    yunwu_quality_model: str = "gemini-3.1-pro-preview"
    yunwu_fallback_enabled: bool = True
    # Pricing depends on the API token's assigned Yunwu route. Six remains a
    # conservative default for a high-quality official transfer group.
    yunwu_group_ratio: float = 6.0
    yunwu_quota_price_cny: float = 0.5
    yunwu_usd_exchange_rate: float = 7.3

    # OpenRouter's OpenAI-compatible gateway. One model currently serves every
    # tier: the stealth route is a single model id, so fast/balanced/quality all
    # resolve to it until separate routes are worth configuring.
    openrouter_api_key: str | None = None
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    openrouter_fast_model: str = "stealth/ox-alpha"
    openrouter_model: str = "stealth/ox-alpha"
    openrouter_quality_model: str = "stealth/ox-alpha"
    openrouter_fallback_enabled: bool = True
    # The stealth route bills nothing today. Kept configurable so that if it ever
    # starts charging, spend re-enters the budget guard by config rather than by
    # someone remembering this file exists.
    openrouter_input_usd_per_million: float = 0.0
    openrouter_output_usd_per_million: float = 0.0

    # Tavily (real-time web search for material URL resolution)
    tavily_api_key: str | None = None

    # Google Gemini (search grounding + LearnLM tutoring + structured extraction)
    gemini_api_key: str | None = None
    # Current GA models. Flash handles user-visible planning/writing while
    # Flash-Lite handles bounded extraction, routing, and metadata work.
    gemini_model: str = "gemini-3.6-flash"
    gemini_fast_model: str = "gemini-3.5-flash-lite"
    gemini_quality_model: str = (
        "gemini-3.1-pro-preview"  # Selective quality fallback, never the default
    )

    # Plan generation
    plan_generator_mode: str = "deterministic"  # "deterministic" or "llm"
    # Safe runtime pilot. A catalog miss or failed personal composition falls
    # through to the existing bespoke lesson generator.
    lesson_catalog_first_enabled: bool = False

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

    @model_validator(mode="after")
    def load_openlux_credential(self):
        if self.llm_provider == "zai" and not self.zai_api_key and self.zai_secret_id:
            from app.core.credentials import read_aws_secret

            self.zai_api_key = read_aws_secret(
                self.zai_secret_id, self.zai_secret_region, "ZAI_API_KEY"
            )
        if not self.google_books_api_key and self.google_books_secret_id:
            from app.core.credentials import read_aws_secret

            self.google_books_api_key = read_aws_secret(
                self.google_books_secret_id,
                self.google_books_secret_region,
                "GOOGLE_BOOKS_API_KEY",
            )
        needs_openlux_credential = self.llm_provider == "openlux" or (
            self.book_narration_enabled
            and self.book_narration_provider.casefold() == "openlux"
        )
        if (
            needs_openlux_credential
            and not self.openlux_api_key
            and self.openlux_secret_id
        ):
            from app.core.credentials import read_aws_secret

            self.openlux_api_key = read_aws_secret(
                self.openlux_secret_id, self.openlux_secret_region
            )
        if (
            needs_openlux_credential
            and not self.openlux_api_key
            and self.openlux_keychain_service
        ):
            from app.core.credentials import read_keychain_secret

            self.openlux_api_key = read_keychain_secret(self.openlux_keychain_service)
        return self

    @property
    def llm_configured(self) -> bool:
        """Check if LLM is properly configured."""
        if self.llm_provider == "zai":
            return bool(self.zai_api_key)
        if self.llm_provider == "openai":
            return bool(self.openai_api_key)
        if self.llm_provider == "gemini":
            return bool(self.gemini_api_key)
        if self.llm_provider == "openlux":
            # Optional native search credentials must not disable ordinary
            # OpenLux generation. Search routes check their own prerequisites.
            return bool(self.openlux_api_key)
        if self.llm_provider == "openrouter":
            # Grounded source discovery is a native Gemini capability that no
            # OpenAI-compatible gateway can serve, so Gemini stays required here
            # exactly as it does for the Yunwu gateway below.
            return bool(self.openrouter_api_key and self.gemini_api_key)
        if self.llm_provider == "yunwu":
            # Several grounded and streaming product paths remain native
            # Gemini capabilities, and Gemini is also the gateway fallback.
            return bool(self.yunwu_api_key and self.gemini_api_key)
        return True  # Dummy is always configured


settings = Settings()
