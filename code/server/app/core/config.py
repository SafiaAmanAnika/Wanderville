from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVER_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=SERVER_ROOT / ".env", extra="ignore")

    wanderville_env: Literal["dev", "test", "staging", "production"] = "dev"
    wanderville_host: str = "127.0.0.1"
    wanderville_port: int = Field(8000, ge=1, le=65535)
    database_url: str = "postgresql+psycopg2://localhost/wanderville_dev"
    jwt_secret_key: str = "development-only-change-this-secret"
    jwt_algorithm: Literal["HS256", "HS384", "HS512"] = "HS256"
    access_token_expire_minutes: int = Field(15, gt=0)
    refresh_token_expire_days: int = Field(30, gt=0)
    google_client_id: str = ""
    smtp_host: str = "localhost"
    smtp_port: int = Field(1025, ge=1, le=65535)
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_starttls: bool = True
    email_from: str = "noreply@wanderville.example"
    email_base_url: str = "http://localhost:8000"
    email_verification_expire_minutes: int = Field(60, gt=0)
    password_reset_expire_minutes: int = Field(30, gt=0)
    max_login_attempts: int = Field(5, gt=0)
    lockout_minutes: int = Field(15, gt=0)
    cors_origins: str = "http://localhost:8000"
    starting_aura: int = Field(0, ge=0, le=1_000_000)
    farm_consume_inventory: bool = True
    # SRS defines ordering; these tunable rates are explicit balancing choices.
    farm_spring_growth_rate: float = Field(1.0, gt=0, le=10)
    farm_summer_growth_rate: float = Field(1.25, gt=0, le=10)
    farm_autumn_growth_rate: float = Field(0.9, gt=0, le=10)
    farm_winter_growth_rate: float = Field(0.75, gt=0, le=10)
    dev_allow_world_mutation: bool = False

    @property
    def is_development(self) -> bool:
        return self.wanderville_env in {"dev", "test"}

    @property
    def allowed_origins(self) -> list[str]:
        return [
            value.strip() for value in self.cors_origins.split(",") if value.strip()
        ]

    @model_validator(mode="after")
    def production_policy(self):
        if not self.is_development:
            secret = self.jwt_secret_key.lower()
            if len(secret) < 32 or any(
                word in secret
                for word in (
                    "change",
                    "example",
                    "development",
                    "placeholder",
                    "replace",
                    "your_",
                )
            ):
                raise ValueError(
                    "Set a random JWT_SECRET_KEY of at least 32 characters"
                )
            if not self.database_url.startswith(
                ("postgresql://", "postgresql+psycopg2://")
            ):
                raise ValueError("Non-development environments require PostgreSQL")
            if "*" in self.allowed_origins:
                raise ValueError("Configure explicit CORS origins outside development")
            if not self.farm_consume_inventory:
                raise ValueError("Production planting must consume inventory")
            if self.dev_allow_world_mutation:
                raise ValueError(
                    "World mutation compatibility switch is development-only"
                )
            if not self.email_base_url.startswith("https://") or not self.smtp_starttls:
                raise ValueError(
                    "Production email requires HTTPS links and SMTP STARTTLS"
                )
        return self


settings = Settings()
