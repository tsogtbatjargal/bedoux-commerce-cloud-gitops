"""store product image keys instead of static web paths

Revision ID: 7c4e8af49b31
Revises: 1e4c0248ef3e
Create Date: 2026-08-02
"""

from typing import Sequence, Union

from alembic import op


revision: str = "7c4e8af49b31"
down_revision: Union[str, None] = "1e4c0248ef3e"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column("products", "image_path", new_column_name="image_key")
    op.execute(
        "UPDATE products SET image_key = substring(image_key FROM 9) "
        "WHERE image_key LIKE '/static/%'"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE products SET image_key = '/static/' || image_key "
        "WHERE image_key NOT LIKE '/static/%'"
    )
    op.alter_column("products", "image_key", new_column_name="image_path")
