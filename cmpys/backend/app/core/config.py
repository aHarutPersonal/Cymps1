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

    # JWT
    jwt_secret_key: str = "change-me-in-production-use-openssl-rand-hex-32"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7

    # Extraction
    extractor_mode: str = "deterministic"  # "deterministic" or "llm"
    
    # LLM Configuration
    llm_provider: str = "dummy"  # "dummy", "openai", "gemini", or "yunwu"
    openai_api_key: str | None = None
    openai_model: str = "gpt-4.1-mini"  # Balanced model for user-visible generation
    openai_fast_model: str = "gpt-4o-mini"  # Lightweight model for thinking/discovery
    openai_quality_model: str = "gpt-4.1"  # Selective fallback for failed quality gates

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
    
    # Tavily (real-time web search for material URL resolution)
    tavily_api_key: str | None = None
    
    # Google Gemini (search grounding + LearnLM tutoring + structured extraction)
    gemini_api_key: str | None = None
    # Current GA models. Flash handles user-visible planning/writing while
    # Flash-Lite handles bounded extraction, routing, and metadata work.
    gemini_model: str = "gemini-3.6-flash"
    gemini_fast_model: str = "gemini-3.5-flash-lite"
    gemini_quality_model: str = "gemini-3.1-pro-preview"  # Selective quality fallback, never the default
    
    # Plan generation
    plan_generator_mode: str = "deterministic"  # "deterministic" or "llm"

    # Local LLM (Spec 2 — inert until then)
    local_llm_base_url: str | None = None   # e.g. http://gpu-box:8000/v1 (Spec 2)
    local_llm_model: str | None = None       # e.g. qwen2.5-32b-instruct (Spec 2)
    embedding_model: str = "bge-m3"           # used by Spec 2 ingestion

    # 24/7 catalog scheduler. Conservative defaults keep a small deployment
    # within a predictable LLM budget while still draining demand continuously.
    catalog_scheduler_enabled: bool = True
    catalog_tick_seconds: int = 60
    catalog_dispatch_per_tick: int = 1
    catalog_daily_job_limit: int = 50
    catalog_seed_per_tick: int = 25
    catalog_max_attempts: int = 3
    catalog_stale_job_minutes: int = 20
    catalog_quotes_per_idol_limit: int = 30
    catalog_quote_min_confidence: float = 0.84
    catalog_quote_verification_enabled: bool = True
    catalog_quote_verification_batch_size: int = 4
    catalog_quote_verification_daily_limit: int = 2

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
    
    @property
    def llm_configured(self) -> bool:
        """Check if LLM is properly configured."""
        if self.llm_provider == "openai":
            return bool(self.openai_api_key)
        if self.llm_provider == "gemini":
            return bool(self.gemini_api_key)
        if self.llm_provider == "yunwu":
            # Several grounded and streaming product paths remain native
            # Gemini capabilities, and Gemini is also the gateway fallback.
            return bool(self.yunwu_api_key and self.gemini_api_key)
        return True  # Dummy is always configured


settings = Settings()
