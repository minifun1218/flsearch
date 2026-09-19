"""食物搜索与自定义食物（PRD R-023、R-025）。"""

from __future__ import annotations

from fastapi import APIRouter, Query, status

from ..deps import CurrentUser, SessionDep
from ..models import NutritionSource
from ..schemas import FoodIn, FoodOut
from ..services import food_cache
from ..services.food_cache import NutritionValues

router = APIRouter(prefix="/foods", tags=["foods"])


@router.get("", response_model=list[FoodOut])
async def search_foods(
    session: SessionDep,
    _: CurrentUser,
    q: str = Query(default="", description="食物名，支持部分匹配"),
    limit: int = Query(default=20, ge=1, le=50),
) -> list[FoodOut]:
    rows = await food_cache.search(session, query=q, limit=limit)
    return [FoodOut.model_validate(row) for row in rows]


@router.post("", response_model=FoodOut, status_code=status.HTTP_201_CREATED)
async def create_food(
    payload: FoodIn, session: SessionDep, _: CurrentUser
) -> FoodOut:
    """搜不到就自定义一条，之后所有人都能搜到（PRD R-023）。"""
    row = await food_cache.upsert(
        session,
        name=payload.name,
        values=NutritionValues(
            kcal_per_100g=payload.kcal_per_100g,
            protein_per_100g=payload.protein_per_100g,
            carb_per_100g=payload.carb_per_100g,
            fat_per_100g=payload.fat_per_100g,
        ),
        source=NutritionSource.user,
    )
    return FoodOut.model_validate(row)
