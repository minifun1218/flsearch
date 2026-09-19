"""食物营养缓存表（PRD R-020、R-023、R-025）。

规则只有一条，但必须守住：**同一个标准名，每 100g 的营养值只有一个版本**。
识别先查这里，命中就复用缓存值（哪怕本次 AI 给了别的数），未命中才写回。
用户修正则直接改写缓存，影响此后的识别；已保存的历史记录持有自己的快照，不被追溯修改。
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..domain.food_name import clean_display_name, normalize
from ..models import FoodNutrition, NutritionSource


@dataclass(frozen=True)
class NutritionValues:
    kcal_per_100g: float
    protein_per_100g: float
    carb_per_100g: float
    fat_per_100g: float


async def get_by_name(session: AsyncSession, name: str) -> FoodNutrition | None:
    key = normalize(name)
    if not key:
        return None
    return await session.scalar(
        select(FoodNutrition).where(FoodNutrition.normalized_name == key)
    )


async def resolve(
    session: AsyncSession, *, name: str, estimated: NutritionValues
) -> tuple[FoodNutrition, bool]:
    """按名字取营养值。返回 (记录, 是否命中缓存)。"""
    key = normalize(name)
    if not key:
        raise ValueError("食物名为空")

    row = await session.scalar(
        select(FoodNutrition).where(FoodNutrition.normalized_name == key)
    )
    if row is not None:
        row.hit_count += 1
        return row, True

    row = FoodNutrition(
        name=clean_display_name(name),
        normalized_name=key,
        kcal_per_100g=estimated.kcal_per_100g,
        protein_per_100g=estimated.protein_per_100g,
        carb_per_100g=estimated.carb_per_100g,
        fat_per_100g=estimated.fat_per_100g,
        source=NutritionSource.ai,
    )
    session.add(row)
    await session.flush()
    return row, False


async def upsert(
    session: AsyncSession,
    *,
    name: str,
    values: NutritionValues,
    source: NutritionSource = NutritionSource.user,
) -> FoodNutrition:
    """用户自建食物或修正营养值：覆盖缓存中的这一条（PRD R-023 / R-025）。"""
    key = normalize(name)
    if not key:
        raise ValueError("食物名为空")

    row = await session.scalar(
        select(FoodNutrition).where(FoodNutrition.normalized_name == key)
    )
    if row is None:
        row = FoodNutrition(name=clean_display_name(name), normalized_name=key)
        session.add(row)

    row.kcal_per_100g = values.kcal_per_100g
    row.protein_per_100g = values.protein_per_100g
    row.carb_per_100g = values.carb_per_100g
    row.fat_per_100g = values.fat_per_100g
    row.source = source
    await session.flush()
    return row


async def search(
    session: AsyncSession, *, query: str, limit: int = 20
) -> list[FoodNutrition]:
    """按名字搜索（PRD R-023）。空词给最常命中的几条，当作「热门」。"""
    key = normalize(query)
    stmt = select(FoodNutrition)
    if key:
        stmt = stmt.where(FoodNutrition.normalized_name.contains(key))
    stmt = stmt.order_by(FoodNutrition.hit_count.desc(), FoodNutrition.name).limit(limit)
    return list(await session.scalars(stmt))
