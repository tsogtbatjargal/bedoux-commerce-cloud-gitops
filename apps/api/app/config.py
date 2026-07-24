from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BEDOUX_")

    # Local-dev-only default. Never a production credential — real deployments
    # supply DATABASE_URL via Kubernetes Secrets (MVP) or Secrets Manager (P7).
    database_url: str = "postgresql+psycopg://bedoux:bedoux@localhost:5432/bedoux"

    # Order-write kill switch (pending decision #4, docs/IMPLEMENTATION-PLAN.md).
    # Defaults on for local/kind so P2/P3 tests and demos keep working; the AWS
    # session chart values set this false by default and it's flipped on only for
    # the actual golden-path demo window.
    orders_enabled: bool = True

    # Request bounds alongside the kill switch — a public ALB DNS name with no
    # auth is one JSON body away from an unbounded write; cap it defensively even
    # though this is a learning deployment with no real traffic.
    max_request_body_bytes: int = 65_536


settings = Settings()
