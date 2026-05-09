from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    wanderville_env: str = "dev"
    wanderville_host: str = "127.0.0.1"
    wanderville_port: int = 8000


settings = Settings()
