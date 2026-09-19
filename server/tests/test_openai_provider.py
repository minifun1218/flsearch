"""兼容服务输出包装：思考内容不是最终答案，食物字段仍须严格校验。"""

from __future__ import annotations

import base64
import json

import httpx
import pytest
from openai import AsyncOpenAI

from app.services.recognition import RecognitionError
from app.services.recognition.openai_provider import OpenAIRecognizer

PAYLOAD = {
    "items": [
        {
            "name": "清蒸鱼",
            "grams": 150,
            "kcal_per_100g": 120,
            "protein_per_100g": 20,
            "carb_per_100g": 0,
            "fat_per_100g": 4,
            "portion_uncertain": True,
        }
    ]
}
ANSWER = json.dumps(PAYLOAD, ensure_ascii=False)
IMAGE = b"test-image-bytes"


@pytest.fixture
def provider(monkeypatch):
    """使用真实 SDK 的 HTTP 序列化/响应解析，但不联网。"""
    clients = []

    def make(content, *, model="MiniMax-M3", choices=True, finish_reason="stop"):
        requests = []

        def handle(request):
            requests.append(json.loads(request.content))
            return httpx.Response(
                200,
                json={
                    "id": "test-completion",
                    "object": "chat.completion",
                    "created": 0,
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "finish_reason": finish_reason,
                            "message": {"role": "assistant", "content": content},
                        }
                    ] if choices else [],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
                },
            )

        def client_factory(**kwargs):
            client = AsyncOpenAI(
                **kwargs,
                max_retries=0,
                http_client=httpx.AsyncClient(transport=httpx.MockTransport(handle)),
            )
            clients.append(client)
            return client

        monkeypatch.setattr("openai.AsyncOpenAI", client_factory)
        recognizer = OpenAIRecognizer(
            api_key="test-key", base_url="https://provider.test/v1", model=model
        )
        return recognizer, requests

    return make, clients


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "content",
    [
        ANSWER,
        f"<think>这里只是推理中的示例：{{\"items\": []}}</think>\n{ANSWER}",
        f"```json\n{ANSWER}\n```",
        f" <think>只解析最终答案。</think>\n```json\n{ANSWER}\n``` ",
    ],
)
async def test_recognizes_final_answer_with_supported_wrappers(provider, content):
    make, clients = provider
    recognizer, requests = make(content)
    try:
        result = await recognizer.recognize(IMAGE, "image/jpeg")
    finally:
        for client in clients:
            await client.close()

    assert len(result.items) == 1
    assert result.items[0].name == "清蒸鱼"
    assert result.items[0].estimated_grams == 150
    assert result.items[0].portion_uncertain is True
    assert result.model == "MiniMax-M3"
    assert (result.prompt_tokens, result.completion_tokens) == (100, 50)
    assert requests[0]["reasoning_split"] is True
    image_url = requests[0]["messages"][1]["content"][1]["image_url"]["url"]
    assert image_url == "data:image/jpeg;base64," + base64.b64encode(IMAGE).decode()


@pytest.mark.asyncio
async def test_other_models_keep_standard_request_and_empty_food_result(provider):
    make, clients = provider
    recognizer, requests = make('{"items": []}', model="gpt-4o-mini")
    try:
        result = await recognizer.recognize(IMAGE, "image/png")
    finally:
        for client in clients:
            await client.close()
    assert result.items == []
    assert "reasoning_split" not in requests[0]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "content, kwargs",
    [
        (None, {}),
        ("", {}),
        ('<think>{"items": []}', {}),
        ('<think>{"items": []}</think>最终答案无法确定', {}),
        (f"这是识别结果：{ANSWER}", {}),
        ("{}", {}),
        ('{"items": [{"name": "清蒸鱼", "grams": -1}]}', {}),
        (ANSWER, {"choices": False}),
        (ANSWER, {"finish_reason": "length"}),
    ],
)
async def test_invalid_or_incomplete_results_still_fail(provider, content, kwargs):
    make, clients = provider
    recognizer, _ = make(content, **kwargs)
    try:
        with pytest.raises(RecognitionError):
            await recognizer.recognize(IMAGE, "image/jpeg")
    finally:
        for client in clients:
            await client.close()
