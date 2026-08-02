from typing import Literal

from pydantic import Field, model_validator
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

    # P7.2 image-storage adapter (ADR 0011). Static remains the local/default
    # mode. In S3 mode boto3 obtains temporary credentials from the API pod's
    # IRSA identity; no AWS credentials are configured in the frontend.
    image_storage_mode: Literal["static", "s3"] = "static"
    s3_bucket: str | None = None
    s3_region: str | None = None
    s3_presign_expires_seconds: int = Field(default=900, ge=60, le=3600)

    @model_validator(mode="after")
    def require_s3_bucket_for_s3_mode(self) -> "Settings":
        if self.image_storage_mode == "s3" and not self.s3_bucket:
            raise ValueError("BEDOUX_S3_BUCKET is required when BEDOUX_IMAGE_STORAGE_MODE=s3")
        return self


settings = Settings()
