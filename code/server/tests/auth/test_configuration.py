import pytest
from pydantic import ValidationError

from app.core.config import Settings


def production(**changes):
    values = {
        "wanderville_env": "production",
        "database_url": "postgresql+psycopg2://localhost/wanderville",
        "jwt_secret_key": "z7Mr9Qt3uV1kL8Yh2F6bN4pS0wA5cD7e",
        "email_base_url": "https://example.com",
        "cors_origins": "https://example.com",
    }
    values.update(changes)
    return Settings(_env_file=None, **values)


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


def gmail(**changes):
    values = {
        "email_delivery": "gmail_api",
        "gmail_sender_email": "sender@gmail.com",
        "gmail_client_id": "client-id.apps.googleusercontent.com",
        "gmail_client_secret": "client-secret",
        "gmail_refresh_token": "refresh-token",
        "smtp_starttls": False,
    }
    values.update(changes)
    return production(**values)


def test_gmail_api_delivery_requires_complete_credentials():
    assert gmail().email_delivery == "gmail_api"
    # A missing refresh token would only fail at the first send, so refuse to boot.
    for missing in (
        {"gmail_sender_email": ""},
        {"gmail_client_id": ""},
        {"gmail_client_secret": ""},
        {"gmail_refresh_token": ""},
    ):
        with pytest.raises(ValidationError):
            gmail(**missing)
    with pytest.raises(ValidationError):
        gmail(gmail_sender_email="not-an-address")
    # A plain HTTP link would send verification tokens in the clear.
    with pytest.raises(ValidationError):
        gmail(email_base_url="http://wanderville.example")
