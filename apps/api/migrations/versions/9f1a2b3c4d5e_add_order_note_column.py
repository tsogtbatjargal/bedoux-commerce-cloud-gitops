"""add optional order note column (backward-compatible, GO-MVP-U1 demo migration)

Revision ID: 9f1a2b3c4d5e
Revises: 7c4e8af49b31
Create Date: 2026-09-10

Backward-compatible: nullable with no default read by existing app code, so a
previously-running release (which never selects or writes this column) keeps
working unmodified against the upgraded schema. Used as the GO-MVP-U1 real
migration-ordering demonstration (docs/PROGRESS.md GO-MVP-U1.3): this Job must
complete before the updated api/web workloads advance.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "9f1a2b3c4d5e"
down_revision: Union[str, None] = "7c4e8af49b31"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("orders", sa.Column("note", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("orders", "note")
