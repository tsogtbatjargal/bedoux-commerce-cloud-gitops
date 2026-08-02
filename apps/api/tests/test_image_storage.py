from unittest.mock import Mock

import pytest
from pydantic import ValidationError

from app.config import Settings
from app.image_storage import ImageUrlResolver


def test_static_adapter_returns_existing_web_asset_url():
    resolver = ImageUrlResolver(mode="static")

    assert resolver.url_for("products/mug-001.svg") == "/static/products/mug-001.svg"


def test_s3_adapter_generates_a_scoped_presigned_get_url():
    s3_client = Mock()
    s3_client.generate_presigned_url.return_value = "https://example.invalid/presigned-image"
    resolver = ImageUrlResolver(
        mode="s3",
        bucket="bedoux-learning-images",
        region="ca-central-1",
        presign_expires_seconds=900,
        s3_client=s3_client,
    )
    assert resolver.url_for("products/mug-001.svg") == "https://example.invalid/presigned-image"
    s3_client.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={"Bucket": "bedoux-learning-images", "Key": "products/mug-001.svg"},
        ExpiresIn=900,
    )


def test_s3_mode_requires_an_explicit_bucket():
    with pytest.raises(ValidationError, match="BEDOUX_S3_BUCKET"):
        Settings(image_storage_mode="s3")


@pytest.mark.parametrize("image_key", ["mug-001.svg", "other/mug-001.svg", "products/../secret"])
def test_adapter_refuses_to_escape_product_prefix(image_key):
    with pytest.raises(ValueError, match="products/ prefix"):
        ImageUrlResolver(mode="static").url_for(image_key)
