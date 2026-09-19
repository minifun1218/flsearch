"""initial schema —— 与 app/models.py 一一对应的建表迁移。

在此之前建表靠 create_all()；接 PostgreSQL 必须走迁移，这是第一版基线。

Revision ID: 8f46bae4b7e9
Revises: 
Create Date: 2026-09-16 20:07:35.384553
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = '8f46bae4b7e9'
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('food_nutrition',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('name', sa.String(length=128), nullable=False),
    sa.Column('normalized_name', sa.String(length=128), nullable=False),
    sa.Column('kcal_per_100g', sa.Float(), nullable=False),
    sa.Column('protein_per_100g', sa.Float(), nullable=False),
    sa.Column('carb_per_100g', sa.Float(), nullable=False),
    sa.Column('fat_per_100g', sa.Float(), nullable=False),
    sa.Column('source', sa.Enum('ai', 'user', 'seed', name='nutritionsource', native_enum=False, length=16), nullable=False),
    sa.Column('hit_count', sa.Integer(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('food_nutrition', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_food_nutrition_normalized_name'), ['normalized_name'], unique=True)

    op.create_table('users',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('email', sa.String(length=320), nullable=False),
    sa.Column('password_hash', sa.String(length=128), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_users_email'), ['email'], unique=True)

    op.create_table('day_overrides',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('entry_date', sa.Date(), nullable=False),
    sa.Column('is_training_day', sa.Boolean(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'entry_date', name='uq_override_day')
    )
    with op.batch_alter_table('day_overrides', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_day_overrides_entry_date'), ['entry_date'], unique=False)
        batch_op.create_index(batch_op.f('ix_day_overrides_user_id'), ['user_id'], unique=False)

    op.create_table('diary_entries',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('entry_date', sa.Date(), nullable=False),
    sa.Column('meal', sa.Enum('breakfast', 'lunch', 'dinner', 'snack', name='mealtype', native_enum=False, length=16), nullable=False),
    sa.Column('food_name', sa.String(length=128), nullable=False),
    sa.Column('grams', sa.Integer(), nullable=False),
    sa.Column('kcal_per_100g', sa.Float(), nullable=False),
    sa.Column('protein_per_100g', sa.Float(), nullable=False),
    sa.Column('carb_per_100g', sa.Float(), nullable=False),
    sa.Column('fat_per_100g', sa.Float(), nullable=False),
    sa.Column('from_photo', sa.Boolean(), nullable=False),
    sa.Column('portion_uncertain', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('diary_entries', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_diary_entries_entry_date'), ['entry_date'], unique=False)
        batch_op.create_index(batch_op.f('ix_diary_entries_user_id'), ['user_id'], unique=False)

    op.create_table('photos',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('path', sa.String(length=512), nullable=False),
    sa.Column('content_type', sa.String(length=64), nullable=False),
    sa.Column('size_bytes', sa.Integer(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('photos', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_photos_expires_at'), ['expires_at'], unique=False)
        batch_op.create_index(batch_op.f('ix_photos_user_id'), ['user_id'], unique=False)

    op.create_table('profiles',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('sex', sa.Enum('male', 'female', name='sex', native_enum=False, length=16), nullable=False),
    sa.Column('birth_date', sa.Date(), nullable=False),
    sa.Column('height_cm', sa.Float(), nullable=False),
    sa.Column('weight_kg', sa.Float(), nullable=False),
    sa.Column('body_fat_percent', sa.Float(), nullable=True),
    sa.Column('activity_level', sa.Enum('sedentary', 'light', 'moderate', 'heavy', name='activitylevel', native_enum=False, length=16), nullable=False),
    sa.Column('training_days', sa.JSON(), nullable=False),
    sa.Column('training_type', sa.Enum('strength', 'cardio', 'mixed', name='trainingtype', native_enum=False, length=16), nullable=False),
    sa.Column('training_minutes', sa.Integer(), nullable=False),
    sa.Column('goal', sa.Enum('cut', 'bulk', 'maintain', name='goaltype', native_enum=False, length=16), nullable=False),
    sa.Column('target_weight_kg', sa.Float(), nullable=False),
    sa.Column('weekly_rate_kg', sa.Float(), nullable=False),
    sa.Column('protein_per_kg', sa.Float(), nullable=False),
    sa.Column('fat_percent_of_kcal', sa.Float(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('user_id')
    )
    op.create_table('recognition_usage',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('photo_id', sa.Uuid(), nullable=True),
    sa.Column('provider', sa.String(length=32), nullable=False),
    sa.Column('model', sa.String(length=64), nullable=False),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('error', sa.Text(), nullable=True),
    sa.Column('item_count', sa.Integer(), nullable=False),
    sa.Column('cache_hits', sa.Integer(), nullable=False),
    sa.Column('prompt_tokens', sa.Integer(), nullable=False),
    sa.Column('completion_tokens', sa.Integer(), nullable=False),
    sa.Column('latency_ms', sa.Integer(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('recognition_usage', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_recognition_usage_created_at'), ['created_at'], unique=False)
        batch_op.create_index(batch_op.f('ix_recognition_usage_user_id'), ['user_id'], unique=False)

    op.create_table('refresh_tokens',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('token_hash', sa.String(length=64), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('refresh_tokens', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_refresh_tokens_token_hash'), ['token_hash'], unique=True)
        batch_op.create_index(batch_op.f('ix_refresh_tokens_user_id'), ['user_id'], unique=False)

    op.create_table('water_logs',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('entry_date', sa.Date(), nullable=False),
    sa.Column('ml', sa.Integer(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('water_logs', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_water_logs_entry_date'), ['entry_date'], unique=False)
        batch_op.create_index(batch_op.f('ix_water_logs_user_id'), ['user_id'], unique=False)

    op.create_table('weight_logs',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('entry_date', sa.Date(), nullable=False),
    sa.Column('kg', sa.Float(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'entry_date', name='uq_weight_day')
    )
    with op.batch_alter_table('weight_logs', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_weight_logs_entry_date'), ['entry_date'], unique=False)
        batch_op.create_index(batch_op.f('ix_weight_logs_user_id'), ['user_id'], unique=False)



def downgrade() -> None:
    with op.batch_alter_table('weight_logs', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_weight_logs_user_id'))
        batch_op.drop_index(batch_op.f('ix_weight_logs_entry_date'))

    op.drop_table('weight_logs')
    with op.batch_alter_table('water_logs', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_water_logs_user_id'))
        batch_op.drop_index(batch_op.f('ix_water_logs_entry_date'))

    op.drop_table('water_logs')
    with op.batch_alter_table('refresh_tokens', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_refresh_tokens_user_id'))
        batch_op.drop_index(batch_op.f('ix_refresh_tokens_token_hash'))

    op.drop_table('refresh_tokens')
    with op.batch_alter_table('recognition_usage', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_recognition_usage_user_id'))
        batch_op.drop_index(batch_op.f('ix_recognition_usage_created_at'))

    op.drop_table('recognition_usage')
    op.drop_table('profiles')
    with op.batch_alter_table('photos', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_photos_user_id'))
        batch_op.drop_index(batch_op.f('ix_photos_expires_at'))

    op.drop_table('photos')
    with op.batch_alter_table('diary_entries', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_diary_entries_user_id'))
        batch_op.drop_index(batch_op.f('ix_diary_entries_entry_date'))

    op.drop_table('diary_entries')
    with op.batch_alter_table('day_overrides', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_day_overrides_user_id'))
        batch_op.drop_index(batch_op.f('ix_day_overrides_entry_date'))

    op.drop_table('day_overrides')
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_users_email'))

    op.drop_table('users')
    with op.batch_alter_table('food_nutrition', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_food_nutrition_normalized_name'))

    op.drop_table('food_nutrition')
