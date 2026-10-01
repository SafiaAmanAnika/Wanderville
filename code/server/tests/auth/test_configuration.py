import pytest
from pydantic import ValidationError

from app.core.config import Settings


def production(**changes):
    return Settings(
        _env_file=None,
        wanderville_env="production",
        database_url="postgresql+psycopg2://localhost/wanderville",
        jwt_secret_key="z7Mr9Qt3uV1kL8Yh2F6bN4pS0wA5cD7e",
        email_base_url="https://example.com",
        cors_origins="https://example.com",
        **changes,
    )


def test_production_settings_reject_insecure_secrets_and_options():
    for secret in ("change-me", "short", "development-only-change-this-secret"):
        with pytest.raises(ValidationError):
            Settings(
                _env_file=None, wanderville_env="production", jwt_secret_key=secret
            )
    for values in (
        {"farm_consume_inventory": False},
        {"dev_allow_world_mutation": True},
        {"smtp_starttls": False},
    ):
        with pytest.raises(ValidationError):
            production(**values)
    assert not production().is_development
