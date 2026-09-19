"""档案与营养目标（PRD R-005 ~ R-017、R-044）。"""

from __future__ import annotations

from datetime import date as Date

from fastapi import APIRouter, HTTPException, Query, status

from ..domain import nutrition
from ..domain.nutrition import ProfileInput
from ..deps import CurrentProfile, CurrentUser, SessionDep
from ..models import GoalType, Profile
from ..schemas import (
    BreakdownOut,
    ProfileIn,
    ProfileOut,
    TargetsOut,
)
from ..services import diary

router = APIRouter(tags=["profile"])


def _check_goal(payload: ProfileIn) -> None:
    """减脂目标体重必须低于当前体重，增肌反之（PRD R-008）。"""
    if payload.goal == GoalType.cut and payload.target_weight_kg >= payload.weight_kg:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="减脂目标体重需要低于当前体重",
        )
    if payload.goal == GoalType.bulk and payload.target_weight_kg <= payload.weight_kg:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="增肌目标体重需要高于当前体重",
        )


@router.get("/profile", response_model=ProfileOut)
async def get_profile(profile: CurrentProfile) -> ProfileOut:
    return ProfileOut.model_validate(profile)


@router.put("/profile", response_model=ProfileOut)
async def put_profile(
    payload: ProfileIn, session: SessionDep, user: CurrentUser
) -> ProfileOut:
    """建档与改档共用一个入口：整份覆盖，语义清楚，客户端也好实现。"""
    _check_goal(payload)

    profile = await session.get(Profile, user.id)
    if profile is None:
        profile = Profile(user_id=user.id, **payload.model_dump())
        session.add(profile)
    else:
        for field, value in payload.model_dump().items():
            setattr(profile, field, value)
    await session.flush()
    return ProfileOut.model_validate(profile)


@router.get("/targets", response_model=TargetsOut)
async def get_targets(
    session: SessionDep,
    profile: CurrentProfile,
    date: Date | None = Query(default=None, description="默认今天"),
) -> TargetsOut:
    """当日目标 + 训练日/休息日两套 + 完整计算链路（PRD R-012、R-014、R-044）。"""
    day = date or Date.today()
    snapshot = ProfileInput.from_profile(profile)
    parts = nutrition.breakdown(snapshot, on=day)

    today, overridden = await diary.day_targets(session, profile=profile, day=day)
    training = nutrition.targets_for(snapshot, day, override_training_day=True)
    rest = nutrition.targets_for(snapshot, day, override_training_day=False)

    return TargetsOut(
        today=diary.targets_out(today, day, overridden),
        training_day=diary.targets_out(training, day, False),
        rest_day=diary.targets_out(rest, day, False),
        breakdown=BreakdownOut(**parts.__dict__),
        meal_kcal=nutrition.meal_targets(today.kcal),
    )
