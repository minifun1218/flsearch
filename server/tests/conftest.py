"""测试夹具。

每个测试跑在自己的临时 SQLite 库上，互不影响；识别 Provider 固定为 mock，
所以测试不联网、不花钱，也不依赖真实 Key。
"""

from __future__ import annotations

import sys
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

SERVER_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SERVER_ROOT))


@pytest.fixture(autouse=True)
def _settings(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{(tmp_path / 'test.db').as_posix()}"
    )
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "photos"))
    monkeypatch.setenv("RECOGNIZER_PROVIDER", "mock")
    monkeypatch.setenv("DAILY_RECOGNITION_LIMIT", "20")

    from app.config import get_settings
    from app.services.recognition import get_recognizer

    get_settings.cache_clear()
    get_recognizer.cache_clear()
    yield get_settings()
    get_settings.cache_clear()
    get_recognizer.cache_clear()


@pytest_asyncio.fixture
async def client(_settings) -> AsyncIterator[AsyncClient]:
    from app.db import dispose_engine
    from app.main import create_app

    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", timeout=30
    ) as http:
        # 触发 lifespan：建表、建目录。
        async with app.router.lifespan_context(app):
            yield http
    await dispose_engine()


@pytest.fixture
def default_profile() -> dict:
    """PRD 验收标准里那位用户的档案。测试用 fixture 取，别跨模块 import。"""
    return dict(DEFAULT_PROFILE)


@pytest_asyncio.fixture
async def auth_client(client: AsyncClient) -> AsyncClient:
    """已注册并建好档案的用户。大部分业务测试从这里开始。"""
    response = await client.post(
        "/api/v1/auth/register",
        json={"email": "lifter@example.com", "password": "fitmeal2026"},
    )
    assert response.status_code == 201, response.text
    client.headers["Authorization"] = f"Bearer {response.json()['access_token']}"

    profile = await client.put("/api/v1/profile", json=DEFAULT_PROFILE)
    assert profile.status_code == 200, profile.text
    return client


#: PRD 验收标准里反复用到的那位用户：男、1995-03-01、175cm、72.5kg、中度活动、减脂。
DEFAULT_PROFILE = {
    "sex": "male",
    "birth_date": "1995-03-01",
    "height_cm": 175,
    "weight_kg": 72.5,
    "body_fat_percent": None,
    "activity_level": "moderate",
    "training_days": [1, 3, 5],
    "training_type": "strength",
    "training_minutes": 60,
    "goal": "cut",
    "target_weight_kg": 68,
    "weekly_rate_kg": 0.5,
    "protein_per_kg": 1.8,
    "fat_percent_of_kcal": 25,
}
