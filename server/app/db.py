"""数据库会话。

开发与测试默认跑 SQLite（零依赖、能直接跑起来），生产按 PRD 用 PostgreSQL：
把 DATABASE_URL 换成 postgresql+asyncpg://… 即可，模型层不需要改。
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from pathlib import Path

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from .config import Settings, get_settings


class Base(DeclarativeBase):
    pass


_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def _connect_args(settings: Settings) -> dict:
    # SQLite 的同一连接会被多个协程复用，关掉线程检查。
    return {"check_same_thread": False} if settings.is_sqlite else {}


def _ensure_sqlite_dir(settings: Settings) -> None:
    """SQLite 不会自己建目录，缺目录就是一句没头没脑的 unable to open database file。"""
    path = settings.database_url.split("///", 1)[-1]
    if path and path != ":memory:":
        Path(path).expanduser().parent.mkdir(parents=True, exist_ok=True)


def get_engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        settings = get_settings()
        if settings.is_sqlite:
            _ensure_sqlite_dir(settings)
        _engine = create_async_engine(
            settings.database_url,
            echo=settings.sql_echo,
            pool_pre_ping=True,
            connect_args=_connect_args(settings),
        )
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(
            get_engine(), expire_on_commit=False, autoflush=False
        )
    return _session_factory


async def session_scope() -> AsyncIterator[AsyncSession]:
    """请求级会话：正常返回就提交，抛异常就回滚。

    注意这次提交发生在**响应发出之后**。绝大多数写接口在返回前已经 flush 过，
    读请求会被 SQLite 的写锁挡住 / 在 PostgreSQL 上读到提交前的旧快照也无妨；
    但「这条写入必须在下一个请求到达前生效」的地方（令牌作废就是），要自己
    在返回前 `await session.commit()`，不能指望这里。
    """
    async with get_session_factory()() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def create_all() -> None:
    """建表。

    开发和测试用它把库拉起来；生产只走 Alembic（server/migrations/），
    create_all 不留版本记录也没有回退路径。
    """
    from . import models  # noqa: F401  确保模型都已注册到 Base.metadata

    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def dispose_engine() -> None:
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _session_factory = None
