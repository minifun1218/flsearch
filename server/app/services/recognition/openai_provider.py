"""OpenAI 兼容的多模态 Provider。

任何提供 /chat/completions 且支持图片输入的服务都能用：改 base_url 和 model 即可
（PRD R-019 要求换 Provider 不动业务代码）。返回必须是严格 JSON，解析失败就当失败，
宁可让用户改手动录入，也不猜一个数字写进记录。
"""

from __future__ import annotations

import base64
import json
import re

from pydantic import BaseModel, Field, ValidationError

from ...config import get_settings
from . import RawItem, RecognitionError, RecognitionResult

SYSTEM_PROMPT = """你是营养师，负责从餐食照片里识别食物并估算份量。
只返回 JSON，不要任何解释文字，格式：
{"items":[{"name":"食物名","grams":150,"kcal_per_100g":152,"protein_per_100g":3.4,
"carb_per_100g":32,"fat_per_100g":0.6,"portion_uncertain":false}]}
要求：
1. name 用简体中文常用叫法，带上做法（清蒸/红烧/油炸），不要加「一份」「新鲜」这类修饰词。
2. grams 是这张照片里该食物的可食部分重量，整数。
3. 营养值是每 100g 的数值，不是整份的。
4. 份量把握不大时把 portion_uncertain 设为 true。
5. 照片里没有食物时返回 {"items":[]}。"""


class _Item(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    grams: int = Field(ge=1, le=5000)
    kcal_per_100g: float = Field(ge=0, le=900)
    protein_per_100g: float = Field(ge=0, le=100)
    carb_per_100g: float = Field(ge=0, le=100)
    fat_per_100g: float = Field(ge=0, le=100)
    portion_uncertain: bool = False


class _Payload(BaseModel):
    items: list[_Item]


def _parse_payload(content: str) -> _Payload:
    """只去掉明确的输出包装；最终答案仍须是完整、符合约定的 JSON。"""
    content = content.strip()
    # MiniMax 的兼容接口默认把思考过程放在 content 的 <think> 中。
    # 即使中转服务忽略 reasoning_split，也不能把思考里的示例当成识别结果。
    while content.startswith("<think>"):
        _, closed, content = content.partition("</think>")
        if not closed:
            raise RecognitionError("识别结果包含未结束的思考内容")
        content = content.strip()

    fenced = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", content, re.DOTALL | re.IGNORECASE)
    if fenced:
        content = fenced.group(1)

    try:
        return _Payload.model_validate(json.loads(content))
    except json.JSONDecodeError as exc:
        raise RecognitionError(f"识别结果不是合法 JSON：{exc}") from exc
    except ValidationError as exc:
        # 保留字段位置和错误类型，避免把模型原文写进诊断信息。
        errors = ", ".join(
            f"{'.'.join(map(str, error['loc']))}: {error['type']}"
            for error in exc.errors(include_input=False, include_url=False)
        )
        raise RecognitionError(f"识别结果字段不符合约定：{errors}") from exc


class OpenAIRecognizer:
    name = "openai"

    def __init__(
        self,
        *,
        model: str | None = None,
        base_url: str | None = None,
        api_key: str | None = None,
    ) -> None:
        """默认全部读配置；横评脚本要在一次进程里比几个模型，所以留了覆盖口。"""
        settings = get_settings()
        key = api_key or settings.openai_api_key
        if not key:
            raise RuntimeError("未配置 OPENAI_API_KEY，无法启用 openai 识别 Provider")
        from openai import AsyncOpenAI

        self._model = model or settings.openai_model
        self._client = AsyncOpenAI(
            api_key=key,
            base_url=base_url or settings.openai_base_url,
            timeout=settings.recognition_timeout_seconds,
        )

    async def recognize(self, image: bytes, content_type: str) -> RecognitionResult:
        data_url = f"data:{content_type};base64,{base64.b64encode(image).decode()}"
        options = {}
        if self._model.lower().startswith("minimax-"):
            # MiniMax 专属参数；其他 OpenAI 兼容服务不接收这个扩展。
            options["extra_body"] = {"reasoning_split": True}
        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                response_format={"type": "json_object"},
                temperature=0,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": "识别这张餐食照片。"},
                            {"type": "image_url", "image_url": {"url": data_url}},
                        ],
                    },
                ],
                **options,
            )
        except Exception as exc:  # 网络、鉴权、限流都归为一类失败
            raise RecognitionError(f"识别服务调用失败：{exc}") from exc

        if not response.choices:
            raise RecognitionError("识别服务未返回候选结果")
        choice = response.choices[0]
        if choice.finish_reason == "length":
            raise RecognitionError("识别结果被截断，请调整模型输出长度限制")
        payload = _parse_payload(choice.message.content or "")

        usage = getattr(response, "usage", None)
        return RecognitionResult(
            items=[
                RawItem(
                    name=item.name,
                    estimated_grams=item.grams,
                    kcal_per_100g=item.kcal_per_100g,
                    protein_per_100g=item.protein_per_100g,
                    carb_per_100g=item.carb_per_100g,
                    fat_per_100g=item.fat_per_100g,
                    portion_uncertain=item.portion_uncertain,
                )
                for item in payload.items
            ],
            model=self._model,
            prompt_tokens=getattr(usage, "prompt_tokens", 0) or 0,
            completion_tokens=getattr(usage, "completion_tokens", 0) or 0,
        )
