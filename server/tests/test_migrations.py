"""迁移守卫。

只保证一件事：`alembic upgrade head` 建出来的库和 `models.py` 完全一致。
改了模型忘记生成迁移，这条会红 —— 那正是上线时最难查的一类事故。
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import create_engine

SERVER_ROOT = Path(__file__).resolve().parent.parent


def _alembic(args: list[str], db_url: str) -> subprocess.CompletedProcess:
    # env.py 里有 asyncio.run()，不能在 pytest 的事件循环里直接调，起子进程跑。
    env = {**os.environ, "DATABASE_URL": db_url}
    return subprocess.run(
        [sys.executable, "-m", "alembic", *args],
        cwd=SERVER_ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def test_upgrade_head_matches_models(tmp_path: Path) -> None:
    db_file = tmp_path / "migrated.db"
    result = _alembic(["upgrade", "head"], f"sqlite+aiosqlite:///{db_file.as_posix()}")
    assert result.returncode == 0, result.stderr
    assert db_file.exists()

    from app.db import Base
    from app import models  # noqa: F401  注册全部表

    engine = create_engine(f"sqlite:///{db_file.as_posix()}")
    try:
        with engine.connect() as conn:
            context = MigrationContext.configure(
                conn, opts={"compare_type": True, "target_metadata": Base.metadata}
            )
            diff = compare_metadata(context, Base.metadata)
    finally:
        engine.dispose()

    # alembic_version 是迁移自己的表，模型里当然没有。
    drift = [d for d in diff if "alembic_version" not in str(d)]
    assert drift == [], f"模型与迁移不一致，请跑 alembic revision --autogenerate：{drift}"


def test_renders_postgres_ddl() -> None:
    """离线出一份 PostgreSQL DDL —— 迁移里不能混进 SQLite 专属写法。"""
    result = _alembic(
        ["upgrade", "head", "--sql"],
        "postgresql+asyncpg://user:pass@localhost:5432/fitmeal",
    )
    assert result.returncode == 0, result.stderr
    sql = result.stdout
    assert "CREATE TABLE users" in sql
    assert "TIMESTAMP WITH TIME ZONE" in sql
    # batch 模式是 SQLite 的补丁，PostgreSQL 上不该出现临时表搬运。
    assert "_alembic_tmp" not in sql


@pytest.mark.parametrize("table", ["users", "profiles", "diary_entries", "food_nutrition"])
def test_core_tables_created(tmp_path: Path, table: str) -> None:
    db_file = tmp_path / "tables.db"
    result = _alembic(["upgrade", "head"], f"sqlite+aiosqlite:///{db_file.as_posix()}")
    assert result.returncode == 0, result.stderr

    import sqlite3

    with sqlite3.connect(db_file) as conn:
        names = {row[0] for row in conn.execute("select name from sqlite_master where type='table'")}
    assert table in names
