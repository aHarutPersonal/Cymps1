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
    llm_provider: str = "dummy"  # "dummy", "openai", or "gemini"
    openai_api_key: str | None = None
    openai_model: str = "gpt-4.1-mini"  # Fast model for structured extraction
    openai_fast_model: str = "gpt-4o-mini"  # Lightweight model for thinking/discovery
    
    # Tavily (real-time web search for material URL resolution)
    tavily_api_key: str | None = None
    
    # Google Gemini (search grounding + LearnLM tutoring + structured extraction)
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-2.5-flash"  # Main model for structured extraction
    gemini_fast_model: str = "gemini-2.5-flash"  # Lightweight model for thinking/discovery
    
    # Plan generation
    plan_generator_mode: str = "deterministic"  # "deterministic" or "llm"
    
    @property
    def llm_configured(self) -> bool:
        """Check if LLM is properly configured."""
        if self.llm_provider == "openai":
            return bool(self.openai_api_key)
        if self.llm_provider == "gemini":
            return bool(self.gemini_api_key)
        return True  # Dummy is always configured


settings = Settings()
