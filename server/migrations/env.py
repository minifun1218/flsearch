"""Alembic 运行环境。

地址与模型都从应用里拿：`app.config` 提供 DATABASE_URL，`app.models` 提供
`Base.metadata`。这样迁移永远跟着代码走，不会出现「迁移建的表和模型对不上」。

用法（server/ 目录下）：

    alembic upgrade head            # 建表 / 升级到最新
    alembic revision --autogenerate -m "说明"
    alembic downgrade -1            # 回退一版
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from app import models  # noqa: F401  让所有表注册到 Base.metadata
from app.config import get_settings
from app.db import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

settings = get_settings()
config.set_main_option("sqlalchemy.url", settings.database_url)

target_metadata = Base.metadata


def _configure(connection: Connection | None = None, url: str | None = None) -> None:
    context.configure(
        connection=connection,
        url=url,
        target_metadata=target_metadata,
        compare_type=True,
        compare_server_default=True,
        # SQLite 不支持 ALTER，改列要靠「建新表 + 拷数据」，batch 模式替我们做这件事。
        render_as_batch=settings.is_sqlite,
    )


def run_migrations_offline() -> None:
    """只生成 SQL，不连库（alembic upgrade head --sql）。"""
    _configure(url=settings.database_url, connection=None)
    with context.begin_transaction():
        context.run_migrations()


def _run(connection: Connection) -> None:
    _configure(connection=connection)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(_run)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
