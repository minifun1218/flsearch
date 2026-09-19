"""营养目标计算（PRD R-009 ~ R-014、R-017）。

纯函数，不碰数据库和框架。这里的每一步都与客户端 `app/lib/domain/nutrition_calculator.dart`
一一对应 —— 两端算出的数字必须完全一致，否则用户会看到服务端和本地对不上的目标。
改这里就要同步改那边。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date as Date

from ..models import ActivityLevel, GoalType, MealType, Sex

#: 1 kg 体重对应的热量当量。
KCAL_PER_KG = 7700.0

#: 碳水周期化幅度。训练日上浮 amplitude × 休息天数 / 7，休息日由周总量反推，
#: 保证一周总热量守恒（PRD R-012：两天差异全部落在碳水上）。
CYCLE_AMPLITUDE = 0.1867

#: 每公斤体重的日饮水量与训练日补水（PRD R-013）。
WATER_ML_PER_KG = 35.0
TRAINING_WATER_BONUS_ML = 500

#: 餐次热量比例（PRD R-017）。
MEAL_SPLIT: dict[MealType, float] = {
    MealType.breakfast: 0.25,
    MealType.lunch: 0.35,
    MealType.dinner: 0.30,
    MealType.snack: 0.10,
}


@dataclass(frozen=True)
class ProfileInput:
    """计算所需的档案快照。从 ORM 行构造，避免算法依赖数据库对象。"""

    sex: Sex
    birth_date: Date
    height_cm: float
    weight_kg: float
    activity_level: ActivityLevel
    goal: GoalType
    target_weight_kg: float
    weekly_rate_kg: float
    training_days: frozenset[int]
    body_fat_percent: float | None = None
    protein_per_kg: float = 1.8
    fat_percent_of_kcal: float = 25.0

    @classmethod
    def from_profile(cls, profile) -> "ProfileInput":
        return cls(
            sex=profile.sex,
            birth_date=profile.birth_date,
            height_cm=profile.height_cm,
            weight_kg=profile.weight_kg,
            activity_level=profile.activity_level,
            goal=profile.goal,
            target_weight_kg=profile.target_weight_kg,
            weekly_rate_kg=profile.weekly_rate_kg,
            training_days=frozenset(profile.training_days or []),
            body_fat_percent=profile.body_fat_percent,
            protein_per_kg=profile.protein_per_kg,
            fat_percent_of_kcal=profile.fat_percent_of_kcal,
        )

    def age_on(self, day: Date) -> int:
        had_birthday = (day.month, day.day) >= (self.birth_date.month, self.birth_date.day)
        return day.year - self.birth_date.year - (0 if had_birthday else 1)

    def is_training_day(self, day: Date) -> bool:
        return day.isoweekday() in self.training_days

    @property
    def training_day_count(self) -> int:
        return len(self.training_days)

    @property
    def rest_day_count(self) -> int:
        return 7 - len(self.training_days)


@dataclass(frozen=True)
class MacroTargets:
    protein_g: int
    carb_g: int
    fat_g: int

    @property
    def kcal(self) -> int:
        """三项折算回来的热量，与目标热量差值应 ≤ 20 kcal（PRD R-011）。"""
        return self.protein_g * 4 + self.carb_g * 4 + self.fat_g * 9


@dataclass(frozen=True)
class DayTargets:
    kcal: int
    macros: MacroTargets
    water_ml: int
    is_training_day: bool


@dataclass(frozen=True)
class TargetBreakdown:
    """计算链路的每一步，「每日目标」页原样展示（PRD R-014）。"""

    bmr: int
    used_katch_mcardle: bool
    activity_factor: float
    tdee: int
    daily_delta_kcal: int
    daily_kcal: int
    clamped_to_bmr: bool
    training_day_kcal: int
    rest_day_kcal: int


def bmr(
    *,
    sex: Sex,
    weight_kg: float,
    height_cm: float,
    age: int,
    body_fat_percent: float | None = None,
) -> float:
    """基础代谢：填了体脂率用 Katch-McArdle，否则 Mifflin-St Jeor（PRD R-009）。"""
    if body_fat_percent is not None:
        lean_mass = weight_kg * (1 - body_fat_percent / 100)
        return 370 + 21.6 * lean_mass
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return base + 5 if sex == Sex.male else base - 161


def tdee(basal: float, level: ActivityLevel) -> float:
    """每日总消耗 = BMR × 活动系数（PRD R-010）。"""
    return basal * level.factor


def macros(
    *,
    kcal: int,
    weight_kg: float,
    protein_per_kg: float,
    fat_percent_of_kcal: float,
    fat_basis_kcal: int | None = None,
) -> MacroTargets:
    """蛋白按体重、脂肪按热量占比、碳水填剩余（PRD R-011）。

    `fat_basis_kcal` 传日均热量时，训练日和休息日的脂肪克数保持一致 ——
    周期化的差异应该全部落在碳水上（PRD R-012）。
    """
    protein = round(weight_kg * protein_per_kg)
    fat = round((fat_basis_kcal if fat_basis_kcal is not None else kcal) * fat_percent_of_kcal / 100 / 9)
    carb_kcal = kcal - protein * 4 - fat * 9
    carb = max(0, round(carb_kcal / 4))
    return MacroTargets(protein_g=protein, carb_g=carb, fat_g=fat)


def water_ml(*, weight_kg: float, is_training_day: bool) -> int:
    """日饮水目标（PRD R-013）。"""
    base = round(weight_kg * WATER_ML_PER_KG)
    return base + TRAINING_WATER_BONUS_ML if is_training_day else base


def breakdown(profile: ProfileInput, *, on: Date) -> TargetBreakdown:
    """走完整条链路，给出可展示的中间值（PRD R-009 ~ R-014）。"""
    basal = bmr(
        sex=profile.sex,
        weight_kg=profile.weight_kg,
        height_cm=profile.height_cm,
        age=profile.age_on(on),
        body_fat_percent=profile.body_fat_percent,
    )
    total = tdee(basal, profile.activity_level)

    per_day_delta = profile.weekly_rate_kg * KCAL_PER_KG / 7
    signed = {
        GoalType.cut: -per_day_delta,
        GoalType.bulk: per_day_delta,
        GoalType.maintain: 0.0,
    }[profile.goal]

    raw = total + signed
    # 安全下限：目标热量不得低于基础代谢（PRD R-010）。
    clamped = raw < basal
    daily = round(basal if clamped else raw)

    training_days = profile.training_day_count
    rest_days = profile.rest_day_count

    if training_days == 0 or rest_days == 0:
        train_kcal = rest_kcal = daily
    else:
        train_kcal = round(daily * (1 + CYCLE_AMPLITUDE * rest_days / 7))
        # 休息日由周总量反推，保证 (t×T + r×R) / 7 == daily。
        rest_kcal = round((daily * 7 - train_kcal * training_days) / rest_days)

    return TargetBreakdown(
        bmr=round(basal),
        used_katch_mcardle=profile.body_fat_percent is not None,
        activity_factor=profile.activity_level.factor,
        tdee=round(total),
        daily_delta_kcal=round(signed),
        daily_kcal=daily,
        clamped_to_bmr=clamped,
        training_day_kcal=train_kcal,
        rest_day_kcal=rest_kcal,
    )


def targets_for(
    profile: ProfileInput,
    day: Date,
    *,
    override_training_day: bool | None = None,
) -> DayTargets:
    """指定日期的目标。训练日与休息日热量不同，蛋白和脂肪不变（PRD R-012、R-016）。"""
    is_training = (
        override_training_day
        if override_training_day is not None
        else profile.is_training_day(day)
    )
    parts = breakdown(profile, on=day)
    kcal = parts.training_day_kcal if is_training else parts.rest_day_kcal

    return DayTargets(
        kcal=kcal,
        macros=macros(
            kcal=kcal,
            weight_kg=profile.weight_kg,
            protein_per_kg=profile.protein_per_kg,
            fat_percent_of_kcal=profile.fat_percent_of_kcal,
            fat_basis_kcal=parts.daily_kcal,
        ),
        water_ml=water_ml(weight_kg=profile.weight_kg, is_training_day=is_training),
        is_training_day=is_training,
    )


def meal_targets(day_kcal: int) -> dict[MealType, int]:
    """把当日热量按餐次比例分配（PRD R-017）。"""
    return {meal: round(day_kcal * share) for meal, share in MEAL_SPLIT.items()}
