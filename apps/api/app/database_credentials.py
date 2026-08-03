"""Resolve the API database URL from the configured credential boundary.

Local and kind profiles use ``BEDOUX_DATABASE_URL`` (or its local default).
The P7.3 AWS profile supplies only a Secrets Manager name; the API, migration
Job, and seed Job fetch the same JSON ``DATABASE_URL`` value with their
ServiceAccount's temporary AWS identity. The secret value is never logged.
"""

import json
from typing import Any, Protocol

from app.config import settings


class SecretsManagerClient(Protocol):
    def get_secret_value(self, *, SecretId: str) -> dict[str, Any]: ...


def resolve_database_url(
    *,
    configured_settings=settings,
    secrets_client: SecretsManagerClient | None = None,
) -> str:
    """Return the database URL without copying it into Kubernetes configuration."""

    secret_name = configured_settings.database_secret_name
    if not secret_name:
        return configured_settings.database_url

    if secrets_client is None:
        import boto3

        secrets_client = boto3.client(
            "secretsmanager", region_name=configured_settings.database_secret_region
        )

    response = secrets_client.get_secret_value(SecretId=secret_name)
    secret_string = response.get("SecretString")
    if not isinstance(secret_string, str) or not secret_string:
        raise RuntimeError("database secret did not contain a SecretString")

    try:
        secret_document = json.loads(secret_string)
    except json.JSONDecodeError as exc:
        raise RuntimeError("database secret was not valid JSON") from exc

    database_url = secret_document.get("DATABASE_URL")
    if not isinstance(database_url, str) or not database_url:
        raise RuntimeError("database secret did not contain DATABASE_URL")
    return database_url
