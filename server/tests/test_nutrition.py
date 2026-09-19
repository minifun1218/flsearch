"""营养计算：逐条对着 PRD 的验收数字验（R-009 ~ R-013、R-017）。

这些数字同时是客户端 Dart 实现的验收标准 —— 两端算出来必须一致。
"""

from __future__ import annotations

from datetime import date

from app.domain import nutrition
from app.domain.nutrition import ProfileInput
from app.models import ActivityLevel, GoalType, MealType, Sex

TODAY = date(2026, 9, 16)


def profile(**overrides) -> ProfileInput:
    base = dict(
        sex=Sex.male,
        birth_date=date(1995, 3, 1),
        height_cm=175,
        weight_kg=72.5,
        activity_level=ActivityLevel.moderate,
        goal=GoalType.cut,
        target_weight_kg=68,
        weekly_rate_kg=0.5,
        training_days=frozenset({1, 3, 5}),
    )
    base.update(overrides)
    return ProfileInput(**base)


def test_bmr_mifflin_st_jeor():
    """R-009：男、31 岁、175cm、72.5kg、未填体脂率 → 1669 kcal（±1）。"""
    p = profile()
    assert p.age_on(TODAY) == 31
    value = nutrition.bmr(
        sex=p.sex, weight_kg=p.weight_kg, height_cm=p.height_cm, age=p.age_on(TODAY)
    )
    assert abs(round(value) - 1669) <= 1


def test_bmr_katch_mcardle():
    """R-009：补填体脂率 18% → 改用 Katch-McArdle，1654 kcal（±1）。"""
    value = nutrition.bmr(
        sex=Sex.male, weight_kg=72.5, height_cm=175, age=31, body_fat_percent=18
    )
    assert abs(round(value) - 1654) <= 1
    assert nutrition.breakdown(profile(body_fat_percent=18), on=TODAY).used_katch_mcardle


def test_tdee_and_daily_target():
    """R-010：TDEE = 1669×1.55 = 2587；减脂 0.5kg/周 → 2037 kcal。"""
    parts = nutrition.breakdown(profile(), on=TODAY)
    assert abs(parts.tdee - 2587) <= 1
    assert abs(parts.daily_delta_kcal + 550) <= 1
    assert abs(parts.daily_kcal - 2037) <= 2
    assert parts.clamped_to_bmr is False


def test_daily_target_never_below_bmr():
    """R-010 安全下限：激进速率下目标热量被抬回 BMR。"""
    parts = nutrition.breakdown(
        profile(activity_level=ActivityLevel.sedentary, weekly_rate_kg=1.5), on=TODAY
    )
    assert parts.clamped_to_bmr is True
    assert parts.daily_kcal == parts.bmr


def test_macro_split():
    """R-011：2037 kcal、72.5kg、1.8g/kg、25% → 蛋白 131 / 脂肪 57 / 碳水 250（±2）。"""
    macros = nutrition.macros(
        kcal=2037, weight_kg=72.5, protein_per_kg=1.8, fat_percent_of_kcal=25
    )
    assert abs(macros.protein_g - 131) <= 2
    assert abs(macros.fat_g - 57) <= 2
    assert abs(macros.carb_g - 250) <= 2
    assert abs(macros.kcal - 2037) <= 20


def test_training_day_is_higher_and_difference_is_carbs():
    """R-012：训练日热量更高，差异落在碳水上，蛋白和脂肪不变。"""
    p = profile()
    monday = date(2026, 9, 14)  # 周一，训练日
    tuesday = date(2026, 9, 15)  # 周二，休息日

    train = nutrition.targets_for(p, monday)
    rest = nutrition.targets_for(p, tuesday)

    assert train.is_training_day and not rest.is_training_day
    assert train.kcal > rest.kcal
    assert train.macros.protein_g == rest.macros.protein_g
    assert train.macros.fat_g == rest.macros.fat_g
    assert train.macros.carb_g > rest.macros.carb_g


def test_weekly_energy_is_conserved():
    """周期化不能偷偷改变周总量：t×训练天 + r×休息天 == 日均×7。"""
    p = profile()
    parts = nutrition.breakdown(p, on=TODAY)
    weekly = parts.training_day_kcal * 3 + parts.rest_day_kcal * 4
    assert abs(weekly - parts.daily_kcal * 7) <= 4


def test_water_targets():
    """R-013：72.5kg → 休息日 2538ml、训练日 3038ml（±50）。"""
    assert abs(nutrition.water_ml(weight_kg=72.5, is_training_day=False) - 2538) <= 50
    assert abs(nutrition.water_ml(weight_kg=72.5, is_training_day=True) - 3038) <= 50


def test_meal_split_sums_to_day_target():
    """R-017：早 25% / 午 35% / 晚 30% / 加餐 10%，四项之和等于目标（±5）。"""
    split = nutrition.meal_targets(2037)
    assert abs(split[MealType.breakfast] - 509) <= 5
    assert abs(split[MealType.lunch] - 713) <= 5
    assert abs(split[MealType.dinner] - 611) <= 5
    assert abs(split[MealType.snack] - 204) <= 5
    assert abs(sum(split.values()) - 2037) <= 5


def test_no_training_day_means_flat_targets():
    """R-007：一天训练日都没勾，全周按同一套目标。"""
    parts = nutrition.breakdown(profile(training_days=frozenset()), on=TODAY)
    assert parts.training_day_kcal == parts.rest_day_kcal == parts.daily_kcal
