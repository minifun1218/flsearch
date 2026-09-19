"""一次识别的完整链路（PRD R-018 ~ R-020、R-029、N-2、N-14）。

顺序是固定的：限额 → 存照片 → 调 Provider（硬超时）→ 查/写缓存 → 记账。
照片在调用之前就落盘，Provider 失败也不会丢图；营养值一律以缓存表为准。
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import date as Date
from datetime import datetime, time as Time, timezone

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models import RecognitionUsage, User
from ..schemas import RecognitionOut, RecognizedItemOut
from . import food_cache, photos
from .food_cache import NutritionValues
from .recognition import RecognitionError, get_recognizer

logger = logging.getLogger(__name__)


async def used_today(session: AsyncSession, *, user_id, day: Date | None = None) -> int:
    day = day or datetime.now(timezone.utc).date()
    start = datetime.combine(day, Time.min, tzinfo=timezone.utc)
    end = datetime.combine(day, Time.max, tzinfo=timezone.utc)
    return int(
        await session.scalar(
            select(func.count())
            .select_from(RecognitionUsage)
            .where(
                RecognitionUsage.user_id == user_id,
                RecognitionUsage.created_at >= start,
                RecognitionUsage.created_at <= end,
            )
        )
        or 0
    )


async def recognize_meal(
    session: AsyncSession, *, user: User, data: bytes, content_type: str
) -> RecognitionOut:
    settings = get_settings()
    recognizer = get_recognizer()

    limit = settings.daily_recognition_limit
    used = await used_today(session, user_id=user.id)
    if limit and used >= limit:
        # 达到上限不调用 AI，直接引导手动录入（PRD R-029）。
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"今日识别次数已用完（上限 {limit} 次），可以改用手动录入",
        )

    photo = await photos.save(
        session, user_id=user.id, data=data, content_type=content_type
    )

    started = time.perf_counter()
    try:
        result = await asyncio.wait_for(
            recognizer.recognize(data, content_type),
            timeout=settings.recognition_timeout_seconds,
        )
    except (TimeoutError, asyncio.TimeoutError):
        await _log(
            session,
            user=user,
            photo_id=photo.id,
            provider=recognizer.name,
            status_text="timeout",
            error="provider timeout",
            latency_ms=_elapsed(started),
        )
        # 失败也要留下账：下面的异常会触发回滚，先把这笔用量和照片提交掉。
        await session.commit()
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="识别超时了，照片已保留，可以重试或改用手动录入",
        ) from None
    except RecognitionError as exc:
        # 控制台给出失败阶段和上游状态，不输出照片、模型原文或鉴权信息。
        cause = exc.__cause__ or exc
        logger.warning(
            "Recognition failed: provider=%s error_type=%s upstream_status=%s",
            recognizer.name,
            type(cause).__name__,
            getattr(cause, "status_code", None),
        )
        await _log(
            session,
            user=user,
            photo_id=photo.id,
            provider=recognizer.name,
            status_text="failed",
            error=str(exc),
            latency_ms=_elapsed(started),
        )
        await session.commit()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="识别服务暂时不可用，照片已保留，可以重试或改用手动录入",
        ) from exc

    latency_ms = _elapsed(started)

    items: list[RecognizedItemOut] = []
    cache_hits = 0
    for raw in result.items:
        food, hit = await food_cache.resolve(
            session,
            name=raw.name,
            estimated=NutritionValues(
                kcal_per_100g=raw.kcal_per_100g,
                protein_per_100g=raw.protein_per_100g,
                carb_per_100g=raw.carb_per_100g,
                fat_per_100g=raw.fat_per_100g,
            ),
        )
        cache_hits += int(hit)
        items.append(
            RecognizedItemOut(
                food_name=food.name,
                estimated_grams=raw.estimated_grams,
                kcal_per_100g=food.kcal_per_100g,
                protein_per_100g=food.protein_per_100g,
                carb_per_100g=food.carb_per_100g,
                fat_per_100g=food.fat_per_100g,
                portion_uncertain=raw.portion_uncertain,
                nutrition_from_cache=hit,
            )
        )

    await _log(
        session,
        user=user,
        photo_id=photo.id,
        provider=recognizer.name,
        status_text="ok" if items else "empty",
        model=result.model,
        item_count=len(items),
        cache_hits=cache_hits,
        prompt_tokens=result.prompt_tokens,
        completion_tokens=result.completion_tokens,
        latency_ms=latency_ms,
    )

    return RecognitionOut(
        photo_id=photo.id,
        provider=recognizer.name,
        items=items,
        cache_hits=cache_hits,
        latency_ms=latency_ms,
        remaining_today=max(0, limit - used - 1) if limit else -1,
    )


def _elapsed(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)


async def _log(
    session: AsyncSession,
    *,
    user: User,
    photo_id,
    provider: str,
    status_text: str,
    model: str = "",
    error: str | None = None,
    item_count: int = 0,
    cache_hits: int = 0,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    latency_ms: int = 0,
) -> None:
    """每次调用都记一笔：按用户按日统计用量与缓存命中率（PRD N-14 / N-16）。"""
    session.add(
        RecognitionUsage(
            user_id=user.id,
            photo_id=photo_id,
            provider=provider,
            model=model,
            status=status_text,
            error=error,
            item_count=item_count,
            cache_hits=cache_hits,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            latency_ms=latency_ms,
        )
    )
    await session.flush()
