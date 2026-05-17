from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    wanderville_env: str = "dev"
    wanderville_host: str = "127.0.0.1"
    wanderville_port: int = 8000

    # SQLAlchemy database URL, e.g. "sqlite:///./wanderville.db"
    database_url: str = "sqlite:///./wanderville.db"

    # JWT configuration
    jwt_secret_key: str = "change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7

    cors_origins: str = "*"

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_jwt_secret(cls, v: str, info) -> str:
        env = info.data.get("wanderville_env", "dev")
        if env != "dev" and v == "change-me":
            raise ValueError("JWT_SECRET_KEY must be changed from default in non-dev environments")
        return v


settings = Settings()
