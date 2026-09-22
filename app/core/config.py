from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "app-manb-ms"
    app_version: str = "0.1.0"
    environment: str = "local"

    aws_region: str = "us-east-1"
    crm_api_key_secret_name: str = "dev/crm/API_key"
    # Set in-cluster by the External Secrets Operator sync (k8s/external-secrets/).
    # Left unset for local dev, where the SDK fetches the secret directly instead.
    crm_api_key: str | None = None

    model_config = SettingsConfigDict(env_file=".env", env_prefix="APP_", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
