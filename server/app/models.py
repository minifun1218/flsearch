"""数据模型。

一张表对应一件事，跨表一律用 user_id 隔离 —— 每个查询都必须带上它（PRD N-8）。
枚举统一存字符串（native_enum=False），SQLite 和 PostgreSQL 行为一致。
"""

from __future__ import annotations

import enum
import uuid
from datetime import date as Date
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Date as SADate,
    DateTime,
    Enum as SAEnum,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def new_id() -> uuid.UUID:
    return uuid.uuid4()


class Sex(str, enum.Enum):
    male = "male"
    female = "female"


class ActivityLevel(str, enum.Enum):
    sedentary = "sedentary"
    light = "light"
    moderate = "moderate"
    heavy = "heavy"

    @property
    def factor(self) -> float:
        return {
            ActivityLevel.sedentary: 1.2,
            ActivityLevel.light: 1.375,
            ActivityLevel.moderate: 1.55,
            ActivityLevel.heavy: 1.725,
        }[self]


class GoalType(str, enum.Enum):
    cut = "cut"
    bulk = "bulk"
    maintain = "maintain"


class TrainingType(str, enum.Enum):
    strength = "strength"
    cardio = "cardio"
    mixed = "mixed"


class MealType(str, enum.Enum):
    breakfast = "breakfast"
    lunch = "lunch"
    dinner = "dinner"
    snack = "snack"


class NutritionSource(str, enum.Enum):
    """每 100g 营养值的来源，用来解释「这个数字是怎么来的」。"""

    ai = "ai"  # AI 本次估算，已写回缓存
    user = "user"  # 用户修正或自建（PRD R-025）
    seed = "seed"  # 预置种子数据


def _enum(py_enum: type[enum.Enum], length: int = 16) -> SAEnum:
    return SAEnum(py_enum, native_enum=False, length=length, validate_strings=True)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    # 注销后置位，账号不可再登录，数据随后被清理（PRD R-004）。
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    profile: Mapped["Profile"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )


class RefreshToken(Base):
    """刷新令牌。

    只存哈希：库被读走也换不出 access token。每次刷新旋转一次（PRD R-001）。
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Profile(Base):
    """个人档案 + 训练计划 + 目标（PRD R-005 ~ R-008、R-015）。"""

    __tablename__ = "profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )

    sex: Mapped[Sex] = mapped_column(_enum(Sex), default=Sex.male)
    birth_date: Mapped[Date] = mapped_column(SADate)
    height_cm: Mapped[float] = mapped_column(Float)
    weight_kg: Mapped[float] = mapped_column(Float)
    body_fat_percent: Mapped[float | None] = mapped_column(Float, default=None)
    activity_level: Mapped[ActivityLevel] = mapped_column(
        _enum(ActivityLevel), default=ActivityLevel.moderate
    )

    # 周计划里的训练日，1=周一 … 7=周日。
    training_days: Mapped[list[int]] = mapped_column(JSON, default=list)
    training_type: Mapped[TrainingType] = mapped_column(
        _enum(TrainingType), default=TrainingType.strength
    )
    training_minutes: Mapped[int] = mapped_column(Integer, default=60)

    goal: Mapped[GoalType] = mapped_column(_enum(GoalType), default=GoalType.maintain)
    target_weight_kg: Mapped[float] = mapped_column(Float)
    weekly_rate_kg: Mapped[float] = mapped_column(Float, default=0.5)

    # 三大项分配策略，用户可调（PRD R-015）。
    protein_per_kg: Mapped[float] = mapped_column(Float, default=1.8)
    fat_percent_of_kcal: Mapped[float] = mapped_column(Float, default=25.0)

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    user: Mapped[User] = relationship(back_populates="profile")


class FoodNutrition(Base):
    """食物营养缓存表（PRD R-020 / R-025）。

    按标准化食物名唯一。识别结果先查这里，命中就复用，未命中才采用 AI 估值并写回 ——
    这是同一食物长期数值一致的唯一保障，所以是全局表，不按用户分。
    """

    __tablename__ = "food_nutrition"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(128))
    normalized_name: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    kcal_per_100g: Mapped[float] = mapped_column(Float)
    protein_per_100g: Mapped[float] = mapped_column(Float)
    carb_per_100g: Mapped[float] = mapped_column(Float)
    fat_per_100g: Mapped[float] = mapped_column(Float)
    source: Mapped[NutritionSource] = mapped_column(
        _enum(NutritionSource), default=NutritionSource.ai
    )
    hit_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class DiaryEntry(Base):
    """一条饮食记录。

    营养值在保存时快照进这一行：之后缓存表被修正，历史记录不被追溯改写
    （PRD R-025 只影响之后的记录）。
    """

    __tablename__ = "diary_entries"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    entry_date: Mapped[Date] = mapped_column(SADate, index=True)
    meal: Mapped[MealType] = mapped_column(_enum(MealType))

    food_name: Mapped[str] = mapped_column(String(128))
    grams: Mapped[int] = mapped_column(Integer)
    kcal_per_100g: Mapped[float] = mapped_column(Float)
    protein_per_100g: Mapped[float] = mapped_column(Float)
    carb_per_100g: Mapped[float] = mapped_column(Float)
    fat_per_100g: Mapped[float] = mapped_column(Float)

    from_photo: Mapped[bool] = mapped_column(Boolean, default=False)
    portion_uncertain: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    # 离线同步按 updated_at 取较新者（PRD R-003）。
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    @property
    def ratio(self) -> float:
        return self.grams / 100

    @property
    def kcal(self) -> int:
        return round(self.kcal_per_100g * self.ratio)


class WaterLog(Base):
    """饮水记录。一次一条，撤销就是删掉最近一条（PRD R-030）。"""

    __tablename__ = "water_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    entry_date: Mapped[Date] = mapped_column(SADate, index=True)
    ml: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class WeightLog(Base):
    """体重记录。同一天再记就覆盖（PRD R-031）。"""

    __tablename__ = "weight_logs"
    __table_args__ = (UniqueConstraint("user_id", "entry_date", name="uq_weight_day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    entry_date: Mapped[Date] = mapped_column(SADate, index=True)
    kg: Mapped[float] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class DayOverride(Base):
    """把某一天临时标成训练日 / 休息日，覆盖周计划（PRD R-016）。"""

    __tablename__ = "day_overrides"
    __table_args__ = (UniqueConstraint("user_id", "entry_date", name="uq_override_day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    entry_date: Mapped[Date] = mapped_column(SADate, index=True)
    is_training_day: Mapped[bool] = mapped_column(Boolean)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class Photo(Base):
    """上传的餐食照片。到期由清理任务删除（PRD N-9）。"""

    __tablename__ = "photos"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    path: Mapped[str] = mapped_column(String(512))
    content_type: Mapped[str] = mapped_column(String(64))
    size_bytes: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )


class RecognitionUsage(Base):
    """每次识别的调用记录：成本统计与缓存命中率都看这张表（PRD N-14 / N-16）。"""

    __tablename__ = "recognition_usage"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    photo_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    provider: Mapped[str] = mapped_column(String(32))
    model: Mapped[str] = mapped_column(String(64), default="")
    status: Mapped[str] = mapped_column(String(16))  # ok / empty / failed / timeout
    error: Mapped[str | None] = mapped_column(Text, default=None)
    item_count: Mapped[int] = mapped_column(Integer, default=0)
    cache_hits: Mapped[int] = mapped_column(Integer, default=0)
    prompt_tokens: Mapped[int] = mapped_column(Integer, default=0)
    completion_tokens: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, index=True
    )
