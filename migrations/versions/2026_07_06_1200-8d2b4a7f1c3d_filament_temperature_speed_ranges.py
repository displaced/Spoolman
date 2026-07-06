"""filament_temperature_speed_ranges.

Revision ID: 8d2b4a7f1c3d
Revises: 415a8f855e14
Create Date: 2026-07-06 12:00:00.000000
"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "8d2b4a7f1c3d"
down_revision = "415a8f855e14"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Perform the upgrade."""
    op.create_table(
        "filament_temperature_speed_range",
        sa.Column("filament_id", sa.Integer(), nullable=False),
        sa.Column("idx", sa.Integer(), nullable=False),
        sa.Column("temperature_min", sa.Integer(), nullable=True, comment="Minimum extruder temperature in \u00b0C."),
        sa.Column("temperature_max", sa.Integer(), nullable=True, comment="Maximum extruder temperature in \u00b0C."),
        sa.Column("print_speed_min", sa.Integer(), nullable=True, comment="Minimum print speed in mm/s."),
        sa.Column("print_speed_max", sa.Integer(), nullable=True, comment="Maximum print speed in mm/s."),
        sa.ForeignKeyConstraint(["filament_id"], ["filament.id"]),
        sa.PrimaryKeyConstraint("filament_id", "idx"),
    )
    op.create_index(
        op.f("ix_filament_temperature_speed_range_filament_id"),
        "filament_temperature_speed_range",
        ["filament_id"],
        unique=False,
    )

    conn = op.get_bind()
    rows = conn.execute(
        sa.text("SELECT id, settings_extruder_temp FROM filament WHERE settings_extruder_temp IS NOT NULL")
    )
    values = [{"filament_id": row.id, "temperature": row.settings_extruder_temp} for row in rows]
    if values:
        conn.execute(
            sa.text(
                """
                INSERT INTO filament_temperature_speed_range (
                    filament_id, idx, temperature_min, temperature_max, print_speed_min, print_speed_max
                )
                VALUES (:filament_id, 0, :temperature, :temperature, NULL, NULL)
                """
            ),
            values,
        )

    op.drop_column("filament", "settings_extruder_temp")


def downgrade() -> None:
    """Perform the downgrade."""
    op.add_column(
        "filament",
        sa.Column("settings_extruder_temp", sa.Integer(), nullable=True, comment="Overridden extruder temperature."),
    )

    conn = op.get_bind()
    rows = conn.execute(
        sa.text(
            """
            SELECT filament_id, idx, temperature_min, temperature_max
            FROM filament_temperature_speed_range
            ORDER BY filament_id ASC, idx ASC
            """
        )
    )

    first_values: dict[int, int] = {}
    for row in rows:
        if row.filament_id in first_values:
            continue
        if row.temperature_min is not None:
            first_values[row.filament_id] = row.temperature_min
        elif row.temperature_max is not None:
            first_values[row.filament_id] = row.temperature_max

    updates = [{"filament_id": filament_id, "value": value} for filament_id, value in first_values.items()]
    if updates:
        conn.execute(
            sa.text("UPDATE filament SET settings_extruder_temp = :value WHERE id = :filament_id"),
            updates,
        )

    op.drop_index(
        op.f("ix_filament_temperature_speed_range_filament_id"),
        table_name="filament_temperature_speed_range",
    )
    op.drop_table("filament_temperature_speed_range")
