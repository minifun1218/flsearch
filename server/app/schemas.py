"""请求 / 响应模型。

命名对齐客户端的 Dart 模型：字段一律 snake_case，客户端解析时一一对应。
校验范围与 PRD 验收标准一致（身高 100–230、体重 20–300、体脂率 3–60…）。
"""

from __future__ import annotations

import uuid
from datetime import date as Date
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from .models import ActivityLevel, GoalType, MealType, NutritionSource, Sex, TrainingType

# ---------------------------------------------------------------- 账号


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)

    @field_validator("password")
    @classmethod
    def strong_enough(cls, value: str) -> str:
        # PRD R-001：≥8 位且含字母和数字。
        if not any(c.isalpha() for c in value) or not any(c.isdigit() for c in value):
            raise ValueError("密码需同时包含字母和数字")
        return value


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    created_at: datetime


# ---------------------------------------------------------------- 档案


class ProfileIn(BaseModel):
    sex: Sex
    birth_date: Date
    height_cm: float = Field(ge=100, le=230)
    weight_kg: float = Field(ge=20, le=300)
    body_fat_percent: float | None = Field(default=None, ge=3, le=60)
    activity_level: ActivityLevel
    training_days: list[int] = Field(default_factory=list)
    training_type: TrainingType = TrainingType.strength
    training_minutes: int = Field(default=60, ge=0, le=600)
    goal: GoalType
    target_weight_kg: float = Field(ge=20, le=300)
    weekly_rate_kg: float = Field(default=0.5, ge=0, le=1.5)
    protein_per_kg: float = Field(default=1.8, ge=0.8, le=3.5)
    fat_percent_of_kcal: float = Field(default=25.0, ge=10, le=60)

    @field_validator("training_days")
    @classmethod
    def valid_weekdays(cls, value: list[int]) -> list[int]:
        days = sorted(set(value))
        if any(d < 1 or d > 7 for d in days):
            raise ValueError("训练日取值为 1–7（周一到周日）")
        return days

    @field_validator("birth_date")
    @classmethod
    def not_in_future(cls, value: Date) -> Date:
        if value > Date.today():
            raise ValueError("出生日期不能晚于今天")
        return value


class ProfileOut(ProfileIn):
    model_config = ConfigDict(from_attributes=True)

    updated_at: datetime


# ---------------------------------------------------------------- 目标


class MacroTargetsOut(BaseModel):
    protein_g: int
    carb_g: int
    fat_g: int
    kcal: int


class DayTargetsOut(BaseModel):
    date: Date
    kcal: int
    macros: MacroTargetsOut
    water_ml: int
    is_training_day: bool
    # 该日是否被手动覆盖过训练/休息（PRD R-016）。
    overridden: bool = False


class BreakdownOut(BaseModel):
    """计算链路，「每日目标」页逐行展示（PRD R-014）。"""

    bmr: int
    used_katch_mcardle: bool
    activity_factor: float
    tdee: int
    daily_delta_kcal: int
    daily_kcal: int
    clamped_to_bmr: bool
    training_day_kcal: int
    rest_day_kcal: int


class TargetsOut(BaseModel):
    today: DayTargetsOut
    training_day: DayTargetsOut
    rest_day: DayTargetsOut
    breakdown: BreakdownOut
    meal_kcal: dict[MealType, int]


class TrainingOverrideIn(BaseModel):
    # null = 清除覆盖，回到周计划。
    is_training_day: bool | None = None


# ---------------------------------------------------------------- 食物与记录


class NutritionIn(BaseModel):
    kcal_per_100g: float = Field(ge=0, le=900)
    protein_per_100g: float = Field(ge=0, le=100)
    carb_per_100g: float = Field(ge=0, le=100)
    fat_per_100g: float = Field(ge=0, le=100)


class FoodOut(NutritionIn):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    normalized_name: str
    source: NutritionSource


class FoodIn(NutritionIn):
    name: str = Field(min_length=1, max_length=64)


class EntryIn(NutritionIn):
    food_name: str = Field(min_length=1, max_length=64)
    grams: int = Field(ge=1, le=5000)
    meal: MealType
    from_photo: bool = False
    portion_uncertain: bool = False


class EntryBatchIn(BaseModel):
    """保存一餐（识别结果或手动录入都走这里，PRD R-022 / R-023）。"""

    date: Date
    entries: list[EntryIn] = Field(min_length=1, max_length=50)


class EntryPatch(BaseModel):
    grams: int | None = Field(default=None, ge=1, le=5000)
    meal: MealType | None = None
    date: Date | None = None
    nutrition: NutritionIn | None = None
    # 同时把修正写回缓存表，影响此后的识别（PRD R-025）。
    update_food_cache: bool = False


class EntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    date: Date = Field(validation_alias="entry_date")
    meal: MealType
    food_name: str
    grams: int
    kcal_per_100g: float
    protein_per_100g: float
    carb_per_100g: float
    fat_per_100g: float
    from_photo: bool
    portion_uncertain: bool
    kcal: int
    protein: float
    carb: float
    fat: float
    updated_at: datetime


class MacroSumOut(BaseModel):
    kcal: int = 0
    protein: float = 0
    carb: float = 0
    fat: float = 0


class MealGroupOut(BaseModel):
    meal: MealType
    entries: list[EntryOut]
    totals: MacroSumOut
    target_kcal: int


class DayOut(BaseModel):
    """首页一次取完：记录、合计、目标、饮水、体重（PRD R-040 ~ R-043）。"""

    date: Date
    targets: DayTargetsOut
    totals: MacroSumOut
    remaining_kcal: int
    meals: list[MealGroupOut]
    water_ml: int
    weight_kg: float | None = None


# ---------------------------------------------------------------- 饮水与体重


class WaterIn(BaseModel):
    date: Date
    ml: int = Field(ge=1, le=3000)


class WaterOut(BaseModel):
    date: Date
    total_ml: int
    goal_ml: int


class WeightIn(BaseModel):
    date: Date
    kg: float = Field(ge=20, le=300)


class WeightOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    date: Date = Field(validation_alias="entry_date")
    kg: float


class WeightRecordedOut(BaseModel):
    """记体重会重算目标，前后差值一并返回（PRD R-032）。"""

    weight: WeightOut
    daily_kcal_before: int
    daily_kcal_after: int


# ---------------------------------------------------------------- 识别


class RecognizedItemOut(NutritionIn):
    food_name: str
    estimated_grams: int
    portion_uncertain: bool = False
    # 营养值取自缓存表而不是本次 AI 估算（PRD R-020）。
    nutrition_from_cache: bool = False


class RecognitionOut(BaseModel):
    photo_id: uuid.UUID | None
    provider: str
    items: list[RecognizedItemOut]
    cache_hits: int
    latency_ms: int
    # 当日剩余识别次数（PRD R-029）。
    remaining_today: int


class ErrorOut(BaseModel):
    detail: str
    code: str | None = None
