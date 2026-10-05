from pathlib import Path
from typing import Literal
import os

from pydantic import Field, field_validator, model_validator
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
    google_client_secret: str = ""
    email_delivery: Literal["auto", "file", "smtp", "brevo", "gmail_api"] = "auto"
    brevo_api_key: str = ""
    # Sending through Google's HTTPS API with a stored refresh token avoids the
    # outbound SMTP block on free hosting and needs no purchased domain. These
    # are the sender mailbox's own credentials, deliberately separate from the
    # Google sign-in client below: players' sign-in grants no mail permission.
    gmail_sender_email: str = ""
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_refresh_token: str = ""
    world_worker_enabled: bool = False
    smtp_host: str = "localhost"
    smtp_port: int = Field(1025, ge=1, le=65535)
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_starttls: bool = True
    email_from: str = "noreply@wanderville.example"
    email_base_url: str = Field(default_factory=lambda: os.getenv("RENDER_EXTERNAL_URL", "http://localhost:8000"))
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
    max_move_speed: float = Field(3000, gt=0)
    chat_blocked_words: str = "damn,shit,fuck"
    # Base shared slot pool; each level adds its own increment on top.
    inventory_partition_slots: int = Field(30, ge=1, le=1000)
    # Balancing choice: no planting XP existed before, so it defaults to a
    # small flat rate and stays separate from each crop's harvest reward.
    farm_plant_xp: int = Field(1, ge=0, le=1000)

    @field_validator("database_url", mode="before")
    @classmethod
    def normalize_postgres_url(cls, value):
        if isinstance(value, str) and value.startswith("postgres://"):
            return value.replace("postgres://", "postgresql+psycopg2://", 1)
        return value

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
            if self.email_delivery == "file":
                raise ValueError("File email delivery is development-only")
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
            https_delivery = self.email_delivery in {"brevo", "gmail_api"}
            if not self.email_base_url.startswith("https://") or (
                not https_delivery and not self.smtp_starttls
            ):
                raise ValueError(
                    "Production email requires HTTPS links and SMTP STARTTLS"
                )
            if self.email_delivery == "brevo" and not self.brevo_api_key:
                raise ValueError("Set BREVO_API_KEY for Brevo delivery")
            if self.email_delivery == "gmail_api":
                missing = [
                    name
                    for name, value in (
                        ("GMAIL_SENDER_EMAIL", self.gmail_sender_email),
                        ("GMAIL_CLIENT_ID", self.gmail_client_id),
                        ("GMAIL_CLIENT_SECRET", self.gmail_client_secret),
                        ("GMAIL_REFRESH_TOKEN", self.gmail_refresh_token),
                    )
                    if not value
                ]
                if missing:
                    raise ValueError(
                        "Gmail API delivery requires " + ", ".join(missing)
                    )
                if "@" not in self.gmail_sender_email:
                    raise ValueError(
                        "GMAIL_SENDER_EMAIL must be the verified sender mailbox"
                    )
        return self


settings = Settings()
