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
    llm_provider: str = "dummy"  # "dummy" or "openai"
    openai_api_key: str | None = None
    openai_model: str = "gpt-4o"  # Main model for complex tasks
    openai_fast_model: str = "gpt-4o-mini"  # Faster model for simple tasks (discovery, etc.)
    
    # Plan generation
    plan_generator_mode: str = "deterministic"  # "deterministic" or "llm"
    
    @property
    def llm_configured(self) -> bool:
        """Check if LLM is properly configured."""
        if self.llm_provider == "openai":
            return bool(self.openai_api_key)
        return True  # Dummy is always configured


settings = Settings()
