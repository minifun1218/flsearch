"""档案、目标、记录、饮水、体重（PRD R-005 ~ R-008、R-016、R-022 ~ R-024、R-030 ~ R-032、R-040 ~ R-043）。"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio

MONDAY = "2026-09-14"  # 训练日
TUESDAY = "2026-09-15"  # 休息日


def rice(grams: int = 150, meal: str = "lunch") -> dict:
    return {
        "food_name": "米饭",
        "grams": grams,
        "meal": meal,
        "kcal_per_100g": 116,
        "protein_per_100g": 2.6,
        "carb_per_100g": 25.9,
        "fat_per_100g": 0.3,
    }


async def test_profile_roundtrip_and_validation(auth_client: AsyncClient, default_profile: dict):
    saved = await auth_client.get("/api/v1/profile")
    assert saved.status_code == 200
    assert saved.json()["height_cm"] == 175
    assert saved.json()["body_fat_percent"] is None  # 留空就是留空（R-005）

    too_tall = await auth_client.put(
        "/api/v1/profile", json={**default_profile, "height_cm": 0}
    )
    assert too_tall.status_code == 422

    # R-008：减脂目标体重必须低于当前体重。
    wrong_goal = await auth_client.put(
        "/api/v1/profile", json={**default_profile, "target_weight_kg": 80}
    )
    assert wrong_goal.status_code == 422
    assert wrong_goal.json()["detail"] == "减脂目标体重需要低于当前体重"


async def test_targets_expose_full_chain(auth_client: AsyncClient):
    """R-014：计算链路每一步都是具体数值。"""
    response = await auth_client.get(f"/api/v1/targets?date={MONDAY}")
    assert response.status_code == 200
    body = response.json()

    parts = body["breakdown"]
    assert abs(parts["bmr"] - 1669) <= 2
    assert parts["activity_factor"] == 1.55
    assert abs(parts["tdee"] - 2587) <= 2
    assert abs(parts["daily_kcal"] - 2037) <= 2
    assert parts["used_katch_mcardle"] is False

    assert body["today"]["is_training_day"] is True
    assert body["training_day"]["kcal"] > body["rest_day"]["kcal"]
    assert sum(body["meal_kcal"].values()) == pytest.approx(body["today"]["kcal"], abs=5)


async def test_day_view_totals_and_remaining(auth_client: AsyncClient):
    """R-040 ~ R-041：分组、小计、剩余热量。"""
    await auth_client.post(
        "/api/v1/entries",
        json={"date": MONDAY, "entries": [rice(150), rice(80, "breakfast")]},
    )

    day = (await auth_client.get(f"/api/v1/days/{MONDAY}")).json()
    lunch = next(m for m in day["meals"] if m["meal"] == "lunch")
    breakfast = next(m for m in day["meals"] if m["meal"] == "breakfast")
    dinner = next(m for m in day["meals"] if m["meal"] == "dinner")

    assert lunch["totals"]["kcal"] == 174  # 116 × 1.5
    assert breakfast["totals"]["kcal"] == 93
    assert dinner["entries"] == []
    assert day["totals"]["kcal"] == 267
    assert day["remaining_kcal"] == day["targets"]["kcal"] - 267


async def test_entry_edit_and_delete(auth_client: AsyncClient):
    """R-021 / R-024：改份量按比例走，删掉就从汇总里消失。"""
    created = await auth_client.post(
        "/api/v1/entries", json={"date": MONDAY, "entries": [rice(150)]}
    )
    entry = created.json()[0]
    assert entry["kcal"] == 174

    patched = await auth_client.patch(
        f"/api/v1/entries/{entry['id']}", json={"grams": 80}
    )
    assert patched.status_code == 200
    assert patched.json()["kcal"] == 93  # 174 × 8/15

    day = (await auth_client.get(f"/api/v1/days/{MONDAY}")).json()
    assert day["totals"]["kcal"] == 93

    removed = await auth_client.delete(f"/api/v1/entries/{entry['id']}")
    assert removed.status_code == 204
    day = (await auth_client.get(f"/api/v1/days/{MONDAY}")).json()
    assert day["totals"]["kcal"] == 0


async def test_entry_saved_to_chosen_date(auth_client: AsyncClient):
    """R-022：存到昨天就不该影响今天。"""
    await auth_client.post(
        "/api/v1/entries", json={"date": TUESDAY, "entries": [rice(150)]}
    )
    monday = (await auth_client.get(f"/api/v1/days/{MONDAY}")).json()
    tuesday = (await auth_client.get(f"/api/v1/days/{TUESDAY}")).json()
    assert monday["totals"]["kcal"] == 0
    assert tuesday["totals"]["kcal"] == 174


async def test_training_day_override(auth_client: AsyncClient):
    """R-016：把休息日临时标成训练日，分母跟着换；清除后回到周计划。"""
    before = (await auth_client.get(f"/api/v1/days/{TUESDAY}")).json()
    assert before["targets"]["is_training_day"] is False

    overridden = await auth_client.put(
        f"/api/v1/days/{TUESDAY}/training", json={"is_training_day": True}
    )
    assert overridden.status_code == 200
    assert overridden.json()["targets"]["is_training_day"] is True
    assert overridden.json()["targets"]["overridden"] is True
    assert overridden.json()["targets"]["kcal"] > before["targets"]["kcal"]

    cleared = await auth_client.put(
        f"/api/v1/days/{TUESDAY}/training", json={"is_training_day": None}
    )
    assert cleared.json()["targets"]["is_training_day"] is False
    assert cleared.json()["targets"]["overridden"] is False


async def test_water_add_and_undo(auth_client: AsyncClient):
    """R-030：200 + 200 + 500 = 900，撤销回到 400。"""
    for ml in (200, 200, 500):
        response = await auth_client.post("/api/v1/water", json={"date": MONDAY, "ml": ml})
        assert response.status_code == 201
    assert response.json()["total_ml"] == 900
    assert response.json()["goal_ml"] > 0

    undone = await auth_client.request(
        "DELETE", f"/api/v1/water?date={MONDAY}"
    )
    assert undone.status_code == 200
    assert undone.json()["total_ml"] == 400


async def test_weight_overwrites_same_day_and_recalculates(auth_client: AsyncClient):
    """R-031 / R-032：同日覆盖，且目标按新体重重算并给出差值。"""
    first = await auth_client.post("/api/v1/weights", json={"date": MONDAY, "kg": 72.5})
    assert first.status_code == 201

    second = await auth_client.post("/api/v1/weights", json={"date": MONDAY, "kg": 71.2})
    body = second.json()
    assert body["weight"]["kg"] == 71.2
    assert body["daily_kcal_after"] < body["daily_kcal_before"]

    history = (await auth_client.get("/api/v1/weights")).json()
    assert len(history) == 1  # 覆盖而不是新增
    assert history[0]["kg"] == 71.2

    profile = (await auth_client.get("/api/v1/profile")).json()
    assert profile["weight_kg"] == 71.2


async def test_day_requires_profile(client: AsyncClient):
    """没建档就问目标，给的是「先建档」而不是 500。"""
    registered = await client.post(
        "/api/v1/auth/register",
        json={"email": "fresh@example.com", "password": "fitmeal2026"},
    )
    headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
    response = await client.get(f"/api/v1/days/{MONDAY}", headers=headers)
    assert response.status_code == 409
    assert "档案" in response.json()["detail"]


async def test_day_range_returns_every_day_including_empty(auth_client: AsyncClient):
    """统计页要一次取一段（PRD R-045、R-046）：没记录的那天也要在，且为空。"""
    await auth_client.post(
        "/api/v1/entries", json={"date": MONDAY, "entries": [rice(200)]}
    )
    await auth_client.post("/api/v1/water", json={"date": MONDAY, "ml": 500})
    await auth_client.post("/api/v1/weights", json={"date": TUESDAY, "kg": 72.0})

    response = await auth_client.get(f"/api/v1/days?from={MONDAY}&to=2026-09-16")
    assert response.status_code == 200
    days = response.json()
    assert [d["date"] for d in days] == [MONDAY, TUESDAY, "2026-09-16"]

    monday = days[0]
    assert monday["totals"]["kcal"] == 232
    assert monday["water_ml"] == 500
    assert monday["targets"]["is_training_day"] is True

    # 空白日：有目标、没有记录 —— 统计的分母据此排除这一天。
    empty = days[2]
    assert empty["totals"]["kcal"] == 0
    assert all(group["entries"] == [] for group in empty["meals"])
    assert empty["targets"]["kcal"] > 0
    assert days[1]["weight_kg"] == 72.0


async def test_day_range_rejects_backwards_and_overlong_windows(auth_client: AsyncClient):
    backwards = await auth_client.get(f"/api/v1/days?from={TUESDAY}&to={MONDAY}")
    assert backwards.status_code == 422

    too_long = await auth_client.get("/api/v1/days?from=2020-01-01&to=2026-09-16")
    assert too_long.status_code == 422


async def test_day_range_honours_training_override(auth_client: AsyncClient):
    """R-016：临时覆盖过的那天，区间接口给的也是覆盖后的目标。"""
    await auth_client.put(
        f"/api/v1/days/{TUESDAY}/training", json={"is_training_day": True}
    )
    days = (await auth_client.get(f"/api/v1/days?from={TUESDAY}&to={TUESDAY}")).json()
    assert days[0]["targets"]["is_training_day"] is True
    assert days[0]["targets"]["overridden"] is True


async def test_day_range_is_scoped_to_the_owner(client: AsyncClient, default_profile: dict):
    """N-8：区间接口同样只看自己的数据。"""
    first = await client.post(
        "/api/v1/auth/register",
        json={"email": "a@example.com", "password": "fitmeal2026"},
    )
    client.headers["Authorization"] = f"Bearer {first.json()['access_token']}"
    await client.put("/api/v1/profile", json=default_profile)
    await client.post("/api/v1/entries", json={"date": MONDAY, "entries": [rice(300)]})

    second = await client.post(
        "/api/v1/auth/register",
        json={"email": "b@example.com", "password": "fitmeal2026"},
    )
    client.headers["Authorization"] = f"Bearer {second.json()['access_token']}"
    await client.put("/api/v1/profile", json=default_profile)

    days = (await client.get(f"/api/v1/days?from={MONDAY}&to={MONDAY}")).json()
    assert days[0]["totals"]["kcal"] == 0
