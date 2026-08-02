"""Storage-neutral product-image URL generation (ADR 0011).

The database keeps a stable object key such as ``products/mug-001.svg``. This
module is the only place that decides whether that key becomes a local static
URL or a short-lived S3 URL. It deliberately does not fetch or proxy image
bytes through the API.
"""

from functools import lru_cache
from typing import Literal, Protocol
from urllib.parse import quote

from app.config import settings


class S3PresigningClient(Protocol):
    def generate_presigned_url(
        self,
        ClientMethod: str,
        Params: dict[str, str],
        ExpiresIn: int,
    ) -> str: ...


class ImageUrlResolver:
    """Translate a stable product-image key to the API's `image_url` value."""

    def __init__(
        self,
        *,
        mode: Literal["static", "s3"],
        bucket: str | None = None,
        region: str | None = None,
        presign_expires_seconds: int = 900,
        s3_client: S3PresigningClient | None = None,
    ) -> None:
        self.mode = mode
        self.bucket = bucket
        self.presign_expires_seconds = presign_expires_seconds

        if mode == "s3":
            if not bucket:
                raise ValueError("an S3 bucket is required in s3 image-storage mode")
            if s3_client is None:
                import boto3

                s3_client = boto3.client("s3", region_name=region)
        self.s3_client = s3_client

    def url_for(self, image_key: str) -> str:
        if not image_key.startswith("products/") or ".." in image_key.split("/"):
            raise ValueError("product image key must stay within the products/ prefix")

        if self.mode == "static":
            return f"/static/{quote(image_key, safe='/')}"

        if self.s3_client is None or self.bucket is None:  # defensive; constructor validates it
            raise RuntimeError("S3 image-storage mode is not configured")
        return self.s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": image_key},
            ExpiresIn=self.presign_expires_seconds,
        )


@lru_cache
def get_image_url_resolver() -> ImageUrlResolver:
    """Create one SDK client per API process; boto3 resolves IRSA automatically."""
    return ImageUrlResolver(
        mode=settings.image_storage_mode,
        bucket=settings.s3_bucket,
        region=settings.s3_region,
        presign_expires_seconds=settings.s3_presign_expires_seconds,
    )
