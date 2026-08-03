import json
from pathlib import Path
from unittest.mock import Mock

import pytest

from app.config import Settings
from app.database_credentials import resolve_database_url


def test_alembic_uses_the_shared_database_credential_boundary():
    migration_env = Path(__file__).parents[1] / "migrations" / "env.py"
    source = migration_env.read_text()

    assert "database_url = resolve_database_url()" in source
    assert "settings.database_url" not in source


def test_local_profile_keeps_database_url_without_an_aws_client():
    configured = Settings(database_url="postgresql+psycopg://local.example/bedoux")

    assert resolve_database_url(configured_settings=configured) == configured.database_url


def test_secrets_manager_profile_fetches_only_the_named_secret():
    client = Mock()
    client.get_secret_value.return_value = {
        "SecretString": json.dumps(
            {"DATABASE_URL": "postgresql+psycopg://private.example/bedoux"}
        )
    }
    configured = Settings(
        database_secret_name="bedoux-rds-credentials",
        database_secret_region="ca-central-1",
    )

    assert resolve_database_url(configured_settings=configured, secrets_client=client) == (
        "postgresql+psycopg://private.example/bedoux"
    )
    client.get_secret_value.assert_called_once_with(SecretId="bedoux-rds-credentials")


@pytest.mark.parametrize(
    "secret_string, message",
    [
        ("not-json", "not valid JSON"),
        (json.dumps({"OTHER": "value"}), "did not contain DATABASE_URL"),
    ],
)
def test_secrets_manager_profile_rejects_malformed_documents(secret_string, message):
    client = Mock()
    client.get_secret_value.return_value = {"SecretString": secret_string}
    configured = Settings(database_secret_name="bedoux-rds-credentials")

    with pytest.raises(RuntimeError, match=message):
        resolve_database_url(configured_settings=configured, secrets_client=client)
