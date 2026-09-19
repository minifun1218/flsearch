"""当日面板、饮食记录、饮水、体重（PRD R-016、R-021 ~ R-024、R-030 ~ R-032、R-040 ~ R-043）。"""

from __future__ import annotations

import uuid
from datetime import date as Date

from fastapi import APIRouter, HTTPException, Query, Response, status

from ..domain import nutrition
from ..domain.nutrition import ProfileInput
from ..deps import CurrentProfile, CurrentUser, SessionDep
from ..schemas import (
    DayOut,
    EntryBatchIn,
    EntryOut,
    EntryPatch,
    TrainingOverrideIn,
    WaterIn,
    WaterOut,
    WeightIn,
    WeightOut,
    WeightRecordedOut,
)
from ..services import diary as diary_service
from ..services import food_cache
from ..services.food_cache import NutritionValues

router = APIRouter(tags=["diary"])


@router.get("/days", response_model=list[DayOut])
async def get_days(
    session: SessionDep,
    profile: CurrentProfile,
    start: Date = Query(alias="from", description="起始日期，含"),
    end: Date = Query(alias="to", description="结束日期，含"),
) -> list[DayOut]:
    """一次取一段时间的每日面板：统计页要 7/30 天（PRD R-045、R-046）。"""
    if end < start:
        raise HTTPException(status_code=422, detail="结束日期不能早于开始日期")
    if (end - start).days > 365:
        raise HTTPException(status_code=422, detail="一次最多取 366 天")
    return await diary_service.range_view(session, profile=profile, start=start, end=end)


@router.get("/days/{day}", response_model=DayOut)
async def get_day(day: Date, session: SessionDep, profile: CurrentProfile) -> DayOut:
    return await diary_service.day_view(session, profile=profile, day=day)


@router.put("/days/{day}/training", response_model=DayOut)
async def set_training_day(
    day: Date,
    payload: TrainingOverrideIn,
    session: SessionDep,
    profile: CurrentProfile,
) -> DayOut:
    """把某天临时标成训练日/休息日；传 null 回到周计划（PRD R-016）。"""
    await diary_service.set_training_override(
        session, user_id=profile.user_id, day=day, value=payload.is_training_day
    )
    await session.flush()
    return await diary_service.day_view(session, profile=profile, day=day)


@router.post(
    "/entries", response_model=list[EntryOut], status_code=status.HTTP_201_CREATED
)
async def create_entries(
    payload: EntryBatchIn, session: SessionDep, user: CurrentUser
) -> list[EntryOut]:
    """保存一餐：识别结果确认后写入，或手动录入（PRD R-022 / R-023）。"""
    rows = await diary_service.add_entries(
        session, user_id=user.id, day=payload.date, items=payload.entries
    )
    return [diary_service.entry_out(row) for row in rows]


@router.patch("/entries/{entry_id}", response_model=EntryOut)
async def patch_entry(
    entry_id: uuid.UUID,
    payload: EntryPatch,
    session: SessionDep,
    user: CurrentUser,
) -> EntryOut:
    """改份量/餐次/日期，或修正营养值（PRD R-024、R-025）。"""
    entry = await diary_service.get_entry(session, user_id=user.id, entry_id=entry_id)

    if payload.grams is not None:
        entry.grams = payload.grams
    if payload.meal is not None:
        entry.meal = payload.meal
    if payload.date is not None:
        entry.entry_date = payload.date
    if payload.nutrition is not None:
        entry.kcal_per_100g = payload.nutrition.kcal_per_100g
        entry.protein_per_100g = payload.nutrition.protein_per_100g
        entry.carb_per_100g = payload.nutrition.carb_per_100g
        entry.fat_per_100g = payload.nutrition.fat_per_100g
        if payload.update_food_cache:
            # 修正写回缓存，只影响此后的识别与录入（PRD R-025）。
            await food_cache.upsert(
                session,
                name=entry.food_name,
                values=NutritionValues(**payload.nutrition.model_dump()),
            )

    await session.flush()
    return diary_service.entry_out(entry)


@router.delete("/entries/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_entry(
    entry_id: uuid.UUID, session: SessionDep, user: CurrentUser
) -> Response:
    entry = await diary_service.get_entry(session, user_id=user.id, entry_id=entry_id)
    await session.delete(entry)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/water", response_model=WaterOut, status_code=status.HTTP_201_CREATED)
async def add_water(
    payload: WaterIn, session: SessionDep, profile: CurrentProfile
) -> WaterOut:
    from ..models import WaterLog

    session.add(
        WaterLog(user_id=profile.user_id, entry_date=payload.date, ml=payload.ml)
    )
    await session.flush()
    return await _water_out(session, profile=profile, day=payload.date)


@router.delete("/water", response_model=WaterOut)
async def undo_water(
    session: SessionDep,
    profile: CurrentProfile,
    date: Date = Query(description="要撤销的那一天"),
) -> WaterOut:
    """撤销最近一次饮水（PRD R-030）。"""
    removed = await diary_service.undo_last_water(
        session, user_id=profile.user_id, day=date
    )
    if not removed:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="这一天还没有饮水记录"
        )
    await session.flush()
    return await _water_out(session, profile=profile, day=date)


@router.get("/weights", response_model=list[WeightOut])
async def list_weights(
    session: SessionDep,
    user: CurrentUser,
    limit: int = Query(default=90, ge=1, le=365),
) -> list[WeightOut]:
    from sqlalchemy import select

    from ..models import WeightLog

    rows = list(
        await session.scalars(
            select(WeightLog)
            .where(WeightLog.user_id == user.id)
            .order_by(WeightLog.entry_date.desc())
            .limit(limit)
        )
    )
    # 曲线按日期正序画（PRD R-031）。
    return [WeightOut.model_validate(row) for row in reversed(rows)]


@router.post(
    "/weights", response_model=WeightRecordedOut, status_code=status.HTTP_201_CREATED
)
async def record_weight(
    payload: WeightIn, session: SessionDep, profile: CurrentProfile
) -> WeightRecordedOut:
    """记体重并用新体重重算目标，返回前后差值（PRD R-031 / R-032）。"""
    before = nutrition.breakdown(
        ProfileInput.from_profile(profile), on=payload.date
    ).daily_kcal

    row = await diary_service.record_weight(
        session, user_id=profile.user_id, day=payload.date, kg=payload.kg
    )
    # 最新体重同时更新档案，之后的目标都按新体重算。
    profile.weight_kg = payload.kg
    await session.flush()

    after = nutrition.breakdown(
        ProfileInput.from_profile(profile), on=payload.date
    ).daily_kcal
    return WeightRecordedOut(
        weight=WeightOut.model_validate(row),
        daily_kcal_before=before,
        daily_kcal_after=after,
    )


async def _water_out(session, *, profile, day: Date) -> WaterOut:
    targets, _ = await diary_service.day_targets(session, profile=profile, day=day)
    total = await diary_service.water_total(session, user_id=profile.user_id, day=day)
    return WaterOut(date=day, total_ml=total, goal_ml=targets.water_ml)
