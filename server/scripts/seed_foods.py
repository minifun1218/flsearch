"""把客户端内置的那份食物表灌进缓存表，给搜索一个可用的起点（PRD R-023）。

    conda activate ai && python scripts/seed_foods.py

幂等：已存在的标准名不覆盖 —— 用户修正过的值（source=user）不应被种子数据盖回去。
数值与 app/lib/data/app_state.dart 里的 FoodLibrary 保持一致。
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select

from app.db import create_all, dispose_engine, get_session_factory
from app.domain.food_name import normalize
from app.models import FoodNutrition, NutritionSource

# (名称, 每 100g: 热量, 蛋白, 碳水, 脂肪)
SEEDS: list[tuple[str, float, float, float, float]] = [
    ("香煎鸡胸肉", 165, 31.0, 0.0, 3.6),
    ("水煮鸡胸肉", 133, 29.5, 0.0, 1.6),
    ("乳清蛋白粉", 400, 80.0, 8.0, 5.0),
    ("全麦吐司", 265, 10.3, 48.0, 3.6),
    ("水煮蛋", 143, 12.6, 1.1, 9.5),
    ("无糖希腊酸奶", 59, 10.0, 3.6, 0.4),
    ("香蕉", 88, 1.1, 22.5, 0.3),
    ("杂粮饭", 174, 4.2, 37.1, 1.0),
    ("糙米饭", 152, 3.5, 32.0, 1.1),
    ("米饭", 116, 2.6, 25.9, 0.3),
    ("蒜蓉西兰花", 78, 3.8, 6.4, 4.8),
    ("清蒸鲈鱼", 121, 18.6, 0.0, 5.0),
    ("无糖豆浆", 33, 3.0, 1.5, 1.6),
    ("混合坚果", 607, 20.0, 21.0, 54.0),
]


async def main() -> None:
    await create_all()
    added = skipped = 0
    async with get_session_factory()() as session:
        for name, kcal, protein, carb, fat in SEEDS:
            key = normalize(name)
            exists = await session.scalar(
                select(FoodNutrition).where(FoodNutrition.normalized_name == key)
            )
            if exists is not None:
                skipped += 1
                continue
            session.add(
                FoodNutrition(
                    name=name,
                    normalized_name=key,
                    kcal_per_100g=kcal,
                    protein_per_100g=protein,
                    carb_per_100g=carb,
                    fat_per_100g=fat,
                    source=NutritionSource.seed,
                )
            )
            added += 1
        await session.commit()
    await dispose_engine()
    print(f"种子食物：新增 {added} 条，已存在 {skipped} 条")


if __name__ == "__main__":
    asyncio.run(main())
