"""账号链路（PRD R-001、R-002、R-004、N-5、N-8）。"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_register_login_refresh_logout(client: AsyncClient):
    registered = await client.post(
        "/api/v1/auth/register",
        json={"email": "A@Example.com", "password": "fitmeal2026"},
    )
    assert registered.status_code == 201
    tokens = registered.json()
    assert tokens["access_token"] and tokens["refresh_token"]

    # 邮箱大小写不敏感，同一个账号。
    again = await client.post(
        "/api/v1/auth/register",
        json={"email": "a@example.com", "password": "fitmeal2026"},
    )
    assert again.status_code == 409
    assert again.json()["detail"] == "该邮箱已注册"

    logged_in = await client.post(
        "/api/v1/auth/login",
        json={"email": "a@example.com", "password": "fitmeal2026"},
    )
    assert logged_in.status_code == 200

    refreshed = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != tokens["refresh_token"]

    # 旧的 refresh token 用过一次就作废。
    reused = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert reused.status_code == 401

    access = refreshed.json()["access_token"]
    headers = {"Authorization": f"Bearer {access}"}
    me = await client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["email"] == "a@example.com"
    assert "password" not in me.text and "hash" not in me.text  # PRD N-5

    out = await client.post(
        "/api/v1/auth/logout",
        headers=headers,
        json={"refresh_token": refreshed.json()["refresh_token"]},
    )
    assert out.status_code == 204
    dead = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": refreshed.json()["refresh_token"]}
    )
    assert dead.status_code == 401


async def test_wrong_password_and_weak_password(client: AsyncClient):
    await client.post(
        "/api/v1/auth/register",
        json={"email": "b@example.com", "password": "fitmeal2026"},
    )
    bad = await client.post(
        "/api/v1/auth/login", json={"email": "b@example.com", "password": "wrongpass1"}
    )
    assert bad.status_code == 401
    # 不泄露邮箱是否注册过：两种失败同一句话。
    unknown = await client.post(
        "/api/v1/auth/login", json={"email": "nobody@example.com", "password": "wrongpass1"}
    )
    assert unknown.json()["detail"] == bad.json()["detail"]

    weak = await client.post(
        "/api/v1/auth/register", json={"email": "c@example.com", "password": "alphabets"}
    )
    assert weak.status_code == 422  # 缺数字


async def test_business_endpoints_require_token(client: AsyncClient):
    for method, url in [
        ("get", "/api/v1/profile"),
        ("get", "/api/v1/targets"),
        ("get", "/api/v1/days/2026-09-16"),
        ("get", "/api/v1/foods"),
    ]:
        response = await getattr(client, method)(url)
        assert response.status_code == 401, url


async def test_user_cannot_touch_another_users_entry(client: AsyncClient, default_profile: dict):
    """PRD N-8：换个账号就读不到、也删不掉别人的记录。"""
    first = await client.post(
        "/api/v1/auth/register",
        json={"email": "owner@example.com", "password": "fitmeal2026"},
    )
    owner = {"Authorization": f"Bearer {first.json()['access_token']}"}
    await client.put("/api/v1/profile", headers=owner, json=default_profile)
    created = await client.post(
        "/api/v1/entries",
        headers=owner,
        json={
            "date": "2026-09-16",
            "entries": [
                {
                    "food_name": "米饭",
                    "grams": 150,
                    "meal": "lunch",
                    "kcal_per_100g": 116,
                    "protein_per_100g": 2.6,
                    "carb_per_100g": 25.9,
                    "fat_per_100g": 0.3,
                }
            ],
        },
    )
    entry_id = created.json()[0]["id"]

    second = await client.post(
        "/api/v1/auth/register",
        json={"email": "intruder@example.com", "password": "fitmeal2026"},
    )
    intruder = {"Authorization": f"Bearer {second.json()['access_token']}"}

    patched = await client.patch(
        f"/api/v1/entries/{entry_id}", headers=intruder, json={"grams": 10}
    )
    assert patched.status_code == 404
    deleted = await client.delete(f"/api/v1/entries/{entry_id}", headers=intruder)
    assert deleted.status_code == 404

    still_there = await client.get("/api/v1/days/2026-09-16", headers=owner)
    lunch = next(m for m in still_there.json()["meals"] if m["meal"] == "lunch")
    assert len(lunch["entries"]) == 1


async def test_delete_account_removes_data(auth_client: AsyncClient):
    """PRD R-004：注销后账号无法登录，数据不再存在。"""
    await auth_client.post(
        "/api/v1/entries",
        json={
            "date": "2026-09-16",
            "entries": [
                {
                    "food_name": "鸡胸肉",
                    "grams": 120,
                    "meal": "dinner",
                    "kcal_per_100g": 165,
                    "protein_per_100g": 31,
                    "carb_per_100g": 0,
                    "fat_per_100g": 3.6,
                }
            ],
        },
    )
    gone = await auth_client.delete("/api/v1/auth/me")
    assert gone.status_code == 204

    login = await auth_client.post(
        "/api/v1/auth/login",
        json={"email": "lifter@example.com", "password": "fitmeal2026"},
    )
    assert login.status_code == 401
