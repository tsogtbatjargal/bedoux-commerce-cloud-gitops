from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BEDOUX_")

    # Local-dev-only default. Never a production credential — real deployments
    # supply DATABASE_URL via Kubernetes Secrets (MVP) or Secrets Manager (P7).
    database_url: str = "postgresql+psycopg://bedoux:bedoux@localhost:5432/bedoux"


settings = Settings()
