"""识别 Provider 的统一接口（PRD R-019）。

业务层只认 `FoodRecognizer`：换 Provider 只改配置和这个包里的实现，
上层的缓存、落库、计费逻辑一行都不用动。Key 只在服务端（PRD N-7）。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from functools import lru_cache
from typing import Protocol

from ...config import get_settings


@dataclass(frozen=True)
class RawItem:
    """Provider 返回的一条食物。营养值是「本次估算」，是否采用由缓存层决定。"""

    name: str
    estimated_grams: int
    kcal_per_100g: float
    protein_per_100g: float
    carb_per_100g: float
    fat_per_100g: float
    portion_uncertain: bool = False


@dataclass(frozen=True)
class RecognitionResult:
    items: list[RawItem] = field(default_factory=list)
    model: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0


class RecognitionError(Exception):
    """Provider 调用失败或返回无法解析 —— 一律引导用户改手动录入（PRD R-019）。"""


class FoodRecognizer(Protocol):
    name: str

    async def recognize(self, image: bytes, content_type: str) -> RecognitionResult: ...


@lru_cache
def get_recognizer() -> FoodRecognizer:
    settings = get_settings()
    provider = settings.recognizer_provider.lower()
    if provider == "mock":
        from .mock import MockRecognizer

        return MockRecognizer()
    if provider in {"openai", "openai_compatible"}:
        from .openai_provider import OpenAIRecognizer

        return OpenAIRecognizer()
    raise RuntimeError(f"未知的识别 Provider：{settings.recognizer_provider}")
