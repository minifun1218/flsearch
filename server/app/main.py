"""FitMeal 服务端入口。

启动：uvicorn app.main:app --reload（在 server/ 目录下）
文档：http://127.0.0.1:8000/docs
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import auth, diary, foods, profile, recognition
from .config import get_settings
from .db import create_all, dispose_engine

logger = logging.getLogger("fitmeal")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    Path(settings.storage_dir).mkdir(parents=True, exist_ok=True)
    # 开发/测试用 create_all 直接拉起表，省掉一步；生产只认 Alembic ——
    # 让进程去建表意味着没有版本记录也没有回退路径（见 README「迁移」）。
    if settings.app_env in {"dev", "test"}:
        await create_all()
    else:
        logger.info("env=%s 跳过 create_all，请确认已执行 alembic upgrade head", settings.app_env)
    logger.info("fitmeal server ready env=%s db=%s", settings.app_env, settings.database_url)
    yield
    await dispose_engine()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="FitMeal API",
        version="0.1.0",
        description="健身饮食记录服务端。接口契约见 docs/03-backend.md。",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    prefix = settings.api_prefix
    app.include_router(auth.router, prefix=prefix)
    app.include_router(profile.router, prefix=prefix)
    app.include_router(diary.router, prefix=prefix)
    app.include_router(foods.router, prefix=prefix)
    app.include_router(recognition.router, prefix=prefix)

    @app.get("/health", tags=["ops"])
    async def health() -> dict[str, str]:
        return {"status": "ok", "env": settings.app_env}

    return app


app = create_app()
