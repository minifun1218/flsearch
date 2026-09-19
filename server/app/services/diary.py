"""当日面板、饮食记录、饮水、体重、训练日覆盖。

对应 PRD R-016、R-021 ~ R-024、R-030 ~ R-032、R-040 ~ R-043。
所有查询都带 user_id，没有例外。
"""

from __future__ import annotations

import uuid
from datetime import date as Date
from datetime import timedelta

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..domain import nutrition
from ..domain.nutrition import ProfileInput
from ..models import (
    DayOverride,
    DiaryEntry,
    MealType,
    Profile,
    WaterLog,
    WeightLog,
)
from ..schemas import (
    DayOut,
    DayTargetsOut,
    EntryIn,
    EntryOut,
    MacroSumOut,
    MacroTargetsOut,
    MealGroupOut,
)


# ---------------------------------------------------------------- 目标


async def training_override(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date
) -> DayOverride | None:
    return await session.scalar(
        select(DayOverride).where(
            DayOverride.user_id == user_id, DayOverride.entry_date == day
        )
    )


async def set_training_override(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date, value: bool | None
) -> None:
    row = await training_override(session, user_id=user_id, day=day)
    if value is None:
        if row is not None:
            await session.delete(row)
        return
    if row is None:
        session.add(DayOverride(user_id=user_id, entry_date=day, is_training_day=value))
    else:
        row.is_training_day = value


async def day_targets(
    session: AsyncSession, *, profile: Profile, day: Date
) -> tuple[nutrition.DayTargets, bool]:
    """返回 (当日目标, 是否被手动覆盖)。"""
    override = await training_override(session, user_id=profile.user_id, day=day)
    targets = nutrition.targets_for(
        ProfileInput.from_profile(profile),
        day,
        override_training_day=None if override is None else override.is_training_day,
    )
    return targets, override is not None


def targets_out(targets: nutrition.DayTargets, day: Date, overridden: bool) -> DayTargetsOut:
    return DayTargetsOut(
        date=day,
        kcal=targets.kcal,
        macros=MacroTargetsOut(
            protein_g=targets.macros.protein_g,
            carb_g=targets.macros.carb_g,
            fat_g=targets.macros.fat_g,
            kcal=targets.macros.kcal,
        ),
        water_ml=targets.water_ml,
        is_training_day=targets.is_training_day,
        overridden=overridden,
    )


# ---------------------------------------------------------------- 记录


def entry_out(entry: DiaryEntry) -> EntryOut:
    ratio = entry.grams / 100
    return EntryOut(
        id=entry.id,
        entry_date=entry.entry_date,
        meal=entry.meal,
        food_name=entry.food_name,
        grams=entry.grams,
        kcal_per_100g=entry.kcal_per_100g,
        protein_per_100g=entry.protein_per_100g,
        carb_per_100g=entry.carb_per_100g,
        fat_per_100g=entry.fat_per_100g,
        from_photo=entry.from_photo,
        portion_uncertain=entry.portion_uncertain,
        kcal=round(entry.kcal_per_100g * ratio),
        protein=round(entry.protein_per_100g * ratio, 1),
        carb=round(entry.carb_per_100g * ratio, 1),
        fat=round(entry.fat_per_100g * ratio, 1),
        updated_at=entry.updated_at,
    )


def _sum(entries: list[DiaryEntry]) -> MacroSumOut:
    total = MacroSumOut()
    for e in entries:
        ratio = e.grams / 100
        total.kcal += round(e.kcal_per_100g * ratio)
        total.protein += e.protein_per_100g * ratio
        total.carb += e.carb_per_100g * ratio
        total.fat += e.fat_per_100g * ratio
    total.protein = round(total.protein, 1)
    total.carb = round(total.carb, 1)
    total.fat = round(total.fat, 1)
    return total


async def list_entries(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date
) -> list[DiaryEntry]:
    return list(
        await session.scalars(
            select(DiaryEntry)
            .where(DiaryEntry.user_id == user_id, DiaryEntry.entry_date == day)
            .order_by(DiaryEntry.created_at)
        )
    )


async def add_entries(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date, items: list[EntryIn]
) -> list[DiaryEntry]:
    rows = [
        DiaryEntry(
            user_id=user_id,
            entry_date=day,
            meal=item.meal,
            food_name=item.food_name.strip(),
            grams=item.grams,
            kcal_per_100g=item.kcal_per_100g,
            protein_per_100g=item.protein_per_100g,
            carb_per_100g=item.carb_per_100g,
            fat_per_100g=item.fat_per_100g,
            from_photo=item.from_photo,
            portion_uncertain=item.portion_uncertain,
        )
        for item in items
    ]
    session.add_all(rows)
    await session.flush()
    return rows


async def get_entry(
    session: AsyncSession, *, user_id: uuid.UUID, entry_id: uuid.UUID
) -> DiaryEntry:
    entry = await session.get(DiaryEntry, entry_id)
    # 归属校验：别人的记录一律当作不存在（PRD N-8）。
    if entry is None or entry.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="记录不存在")
    return entry


# ---------------------------------------------------------------- 饮水与体重


async def water_total(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date
) -> int:
    rows = await session.scalars(
        select(WaterLog.ml).where(
            WaterLog.user_id == user_id, WaterLog.entry_date == day
        )
    )
    return sum(rows)


async def undo_last_water(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date
) -> bool:
    row = await session.scalar(
        select(WaterLog)
        .where(WaterLog.user_id == user_id, WaterLog.entry_date == day)
        .order_by(WaterLog.created_at.desc(), WaterLog.id.desc())
        .limit(1)
    )
    if row is None:
        return False
    await session.delete(row)
    return True


async def record_weight(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date, kg: float
) -> WeightLog:
    """同一天覆盖而不是新增（PRD R-031）。"""
    row = await session.scalar(
        select(WeightLog).where(
            WeightLog.user_id == user_id, WeightLog.entry_date == day
        )
    )
    if row is None:
        row = WeightLog(user_id=user_id, entry_date=day, kg=kg)
        session.add(row)
    else:
        row.kg = kg
    await session.flush()
    return row


async def weight_on(
    session: AsyncSession, *, user_id: uuid.UUID, day: Date
) -> float | None:
    return await session.scalar(
        select(WeightLog.kg).where(
            WeightLog.user_id == user_id, WeightLog.entry_date == day
        )
    )


# ---------------------------------------------------------------- 首页


def _assemble_day(
    *,
    day: Date,
    targets: nutrition.DayTargets,
    overridden: bool,
    entries: list[DiaryEntry],
    water_ml: int,
    weight_kg: float | None,
) -> DayOut:
    meal_kcal = nutrition.meal_targets(targets.kcal)
    groups = []
    for meal in MealType:
        in_meal = [e for e in entries if e.meal == meal]
        groups.append(
            MealGroupOut(
                meal=meal,
                entries=[entry_out(e) for e in in_meal],
                totals=_sum(in_meal),
                target_kcal=meal_kcal[meal],
            )
        )

    totals = _sum(entries)
    return DayOut(
        date=day,
        targets=targets_out(targets, day, overridden),
        totals=totals,
        remaining_kcal=targets.kcal - totals.kcal,
        meals=groups,
        water_ml=water_ml,
        weight_kg=weight_kg,
    )


async def day_view(session: AsyncSession, *, profile: Profile, day: Date) -> DayOut:
    """首页一次取完当天的全部内容（PRD R-040 ~ R-043）。"""
    targets, overridden = await day_targets(session, profile=profile, day=day)
    return _assemble_day(
        day=day,
        targets=targets,
        overridden=overridden,
        entries=await list_entries(session, user_id=profile.user_id, day=day),
        water_ml=await water_total(session, user_id=profile.user_id, day=day),
        weight_kg=await weight_on(session, user_id=profile.user_id, day=day),
    )


async def range_view(
    session: AsyncSession, *, profile: Profile, start: Date, end: Date
) -> list[DayOut]:
    """一次取一段时间的每日面板（统计页要 7/30 天，逐天请求太蠢）。

    四张表各查一次然后在内存里按天归位 —— 天数再多也还是常数次查询。
    没有任何记录的那天也会出现在结果里，且 entries 为空：统计页要靠这个
    区分「没吃」和「没记」（PRD R-046）。
    """
    user_id = profile.user_id

    entries = list(
        await session.scalars(
            select(DiaryEntry)
            .where(
                DiaryEntry.user_id == user_id,
                DiaryEntry.entry_date >= start,
                DiaryEntry.entry_date <= end,
            )
            .order_by(DiaryEntry.created_at)
        )
    )
    by_day: dict[Date, list[DiaryEntry]] = {}
    for entry in entries:
        by_day.setdefault(entry.entry_date, []).append(entry)

    water: dict[Date, int] = {}
    for row_date, ml in await session.execute(
        select(WaterLog.entry_date, WaterLog.ml).where(
            WaterLog.user_id == user_id,
            WaterLog.entry_date >= start,
            WaterLog.entry_date <= end,
        )
    ):
        water[row_date] = water.get(row_date, 0) + ml

    weights = {
        row_date: kg
        for row_date, kg in await session.execute(
            select(WeightLog.entry_date, WeightLog.kg).where(
                WeightLog.user_id == user_id,
                WeightLog.entry_date >= start,
                WeightLog.entry_date <= end,
            )
        )
    }

    overrides = {
        row_date: value
        for row_date, value in await session.execute(
            select(DayOverride.entry_date, DayOverride.is_training_day).where(
                DayOverride.user_id == user_id,
                DayOverride.entry_date >= start,
                DayOverride.entry_date <= end,
            )
        )
    }

    profile_input = ProfileInput.from_profile(profile)
    out: list[DayOut] = []
    day = start
    while day <= end:
        override = overrides.get(day)
        targets = nutrition.targets_for(
            profile_input, day, override_training_day=override
        )
        out.append(
            _assemble_day(
                day=day,
                targets=targets,
                overridden=day in overrides,
                entries=by_day.get(day, []),
                water_ml=water.get(day, 0),
                weight_kg=weights.get(day),
            )
        )
        day += timedelta(days=1)
    return out
