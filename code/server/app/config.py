from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


SERVER_ROOT = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=SERVER_ROOT / ".env", extra="ignore")

    wanderville_env: str = "dev"
    wanderville_host: str = "127.0.0.1"
    wanderville_port: int = 8000

    database_url: str = "postgresql://wanderville_admin:wanderville123@localhost:5432/wanderville"

    jwt_secret_key: str = "change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    google_client_id: str = ""

    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    email_from: str = "noreply@wanderville.game"
    email_base_url: str = "http://localhost:8000"
    email_verification_expire_minutes: int = 60
    password_reset_expire_minutes: int = 30

    max_login_attempts: int = 5
    lockout_minutes: int = 15

    cors_origins: str = "*"

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_jwt_secret(cls, v: str, info) -> str:
        env = info.data.get("wanderville_env", "dev")
        if env != "dev" and v == "change-me":
            raise ValueError("JWT_SECRET_KEY must be changed from default in non-dev environments")
        return v


settings = Settings()
