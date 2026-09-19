"""识别链路与营养缓存表（PRD R-018 ~ R-020、R-023、R-025、R-029、N-14）。"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.domain.food_name import normalize

pytestmark = pytest.mark.asyncio

# 一张「图片」。mock Provider 按内容哈希挑固定的一组结果，所以同样的字节永远同样的返回。
IMAGE = b"\xff\xd8\xff\xe0fitmeal-test-plate"


def upload(data: bytes = IMAGE) -> dict:
    return {"image": ("plate.jpg", data, "image/jpeg")}


async def test_recognition_returns_structured_items(auth_client: AsyncClient):
    """R-019：每个条目都有名称、估计克数和每 100g 的四项营养值。"""
    response = await auth_client.post("/api/v1/recognitions", files=upload())
    assert response.status_code == 201, response.text
    body = response.json()

    assert body["provider"] == "mock"
    assert body["items"], "mock 应该至少认出一样东西"
    for item in body["items"]:
        assert item["food_name"]
        assert 1 <= item["estimated_grams"] <= 5000
        assert 0 <= item["kcal_per_100g"] <= 900
        assert item["protein_per_100g"] >= 0
    assert body["remaining_today"] == 19  # 上限 20，用掉 1 次


async def test_second_recognition_hits_cache(auth_client: AsyncClient):
    """R-020：第一次写回缓存，第二次一律取缓存值，数值完全一致。"""
    first = (await auth_client.post("/api/v1/recognitions", files=upload())).json()
    assert first["cache_hits"] == 0
    assert all(not item["nutrition_from_cache"] for item in first["items"])

    second = (await auth_client.post("/api/v1/recognitions", files=upload())).json()
    assert second["cache_hits"] == len(second["items"])
    assert all(item["nutrition_from_cache"] for item in second["items"])

    by_name = {item["food_name"]: item for item in first["items"]}
    for item in second["items"]:
        assert item["kcal_per_100g"] == by_name[item["food_name"]]["kcal_per_100g"]
        assert item["protein_per_100g"] == by_name[item["food_name"]]["protein_per_100g"]


async def test_recognized_food_is_searchable(auth_client: AsyncClient):
    """R-023：识别写回缓存后，手动录入能搜到同一个食物。"""
    recognized = (await auth_client.post("/api/v1/recognitions", files=upload())).json()
    name = recognized["items"][0]["food_name"]

    found = (await auth_client.get(f"/api/v1/foods?q={name}")).json()
    assert any(row["name"] == name for row in found)


async def test_custom_food_and_correction_update_cache(auth_client: AsyncClient):
    """R-023 / R-025：自定义食物可录入；修正营养值写回缓存，影响此后的记录。"""
    created = await auth_client.post(
        "/api/v1/foods",
        json={
            "name": "番茄炒蛋",
            "kcal_per_100g": 120,
            "protein_per_100g": 7.5,
            "carb_per_100g": 4.2,
            "fat_per_100g": 8.1,
        },
    )
    assert created.status_code == 201
    assert created.json()["normalized_name"] == normalize("番茄炒蛋")

    entry = (
        await auth_client.post(
            "/api/v1/entries",
            json={
                "date": "2026-09-16",
                "entries": [
                    {
                        "food_name": "番茄炒蛋",
                        "grams": 200,
                        "meal": "dinner",
                        "kcal_per_100g": 120,
                        "protein_per_100g": 7.5,
                        "carb_per_100g": 4.2,
                        "fat_per_100g": 8.1,
                    }
                ],
            },
        )
    ).json()[0]

    corrected = await auth_client.patch(
        f"/api/v1/entries/{entry['id']}",
        json={
            "nutrition": {
                "kcal_per_100g": 145,
                "protein_per_100g": 7.5,
                "carb_per_100g": 4.2,
                "fat_per_100g": 10.5,
            },
            "update_food_cache": True,
        },
    )
    assert corrected.status_code == 200
    assert corrected.json()["kcal_per_100g"] == 145

    found = (await auth_client.get("/api/v1/foods?q=番茄炒蛋")).json()
    assert found[0]["kcal_per_100g"] == 145
    assert found[0]["source"] == "user"


async def test_rejects_non_image_and_oversize(auth_client: AsyncClient, monkeypatch):
    bad_type = await auth_client.post(
        "/api/v1/recognitions",
        files={"image": ("notes.txt", b"hello", "text/plain")},
    )
    assert bad_type.status_code == 415

    from app.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "max_upload_bytes", 10)
    too_big = await auth_client.post("/api/v1/recognitions", files=upload(b"x" * 64))
    assert too_big.status_code == 413


async def test_daily_limit_blocks_further_calls(auth_client: AsyncClient, monkeypatch):
    """R-029：到达当日上限后不再调用 AI。"""
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "daily_recognition_limit", 1)

    first = await auth_client.post("/api/v1/recognitions", files=upload())
    assert first.status_code == 201
    assert first.json()["remaining_today"] == 0

    blocked = await auth_client.post("/api/v1/recognitions", files=upload())
    assert blocked.status_code == 429
    assert "手动录入" in blocked.json()["detail"]


async def test_usage_is_logged(auth_client: AsyncClient):
    """N-14：每次识别都要能按用户按日统计。"""
    await auth_client.post("/api/v1/recognitions", files=upload())

    from sqlalchemy import select

    from app.db import get_session_factory
    from app.models import RecognitionUsage

    async with get_session_factory()() as session:
        rows = list(await session.scalars(select(RecognitionUsage)))
    assert len(rows) == 1
    assert rows[0].status == "ok"
    assert rows[0].provider == "mock"
    assert rows[0].item_count >= 1
    assert rows[0].latency_ms >= 0


async def test_failed_provider_keeps_photo_and_logs_cause(
    auth_client: AsyncClient, monkeypatch, caplog
):
    """失败仍须记账；Docker 日志能区分解析错误，且不会泄露模型原文。"""
    import json
    import logging

    from sqlalchemy import select

    from app.db import get_session_factory
    from app.models import RecognitionUsage
    from app.services import recognition_service
    from app.services.recognition import RecognitionError

    class BrokenRecognizer:
        name = "openai"

        async def recognize(self, image, content_type):
            try:
                json.loads("private-model-response")
            except json.JSONDecodeError as exc:
                raise RecognitionError("识别结果不是合法 JSON") from exc

    monkeypatch.setattr(recognition_service, "get_recognizer", BrokenRecognizer)
    with caplog.at_level(logging.WARNING, logger=recognition_service.__name__):
        response = await auth_client.post("/api/v1/recognitions", files=upload())

    assert response.status_code == 502
    assert "手动录入" in response.json()["detail"]
    assert "error_type=JSONDecodeError" in caplog.text
    assert "private-model-response" not in caplog.text

    async with get_session_factory()() as session:
        rows = list(await session.scalars(select(RecognitionUsage)))
    assert len(rows) == 1
    assert rows[0].status == "failed"
    assert rows[0].photo_id is not None
    assert rows[0].error == "识别结果不是合法 JSON"
