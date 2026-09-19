"""注册、登录、刷新、登出、注销（PRD R-001、R-004）。"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import security
from ..models import (
    DayOverride,
    DiaryEntry,
    Photo,
    Profile,
    RecognitionUsage,
    RefreshToken,
    User,
    WaterLog,
    WeightLog,
    utcnow,
)
from ..schemas import TokenPair


def _normalize_email(email: str) -> str:
    return email.strip().lower()


async def register(session: AsyncSession, *, email: str, password: str) -> tuple[User, TokenPair]:
    email = _normalize_email(email)
    existing = await session.scalar(select(User).where(User.email == email))
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该邮箱已注册")

    user = User(email=email, password_hash=security.hash_password(password))
    session.add(user)
    await session.flush()
    return user, await issue_tokens(session, user)


async def login(session: AsyncSession, *, email: str, password: str) -> tuple[User, TokenPair]:
    email = _normalize_email(email)
    user = await session.scalar(select(User).where(User.email == email))
    # 邮箱不存在和密码错误给同一句话，不泄露某个邮箱是否注册过。
    if user is None or user.deleted_at is not None or not security.verify_password(
        password, user.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="邮箱或密码不正确"
        )
    return user, await issue_tokens(session, user)


async def issue_tokens(session: AsyncSession, user: User) -> TokenPair:
    access, expires_in = security.create_access_token(user.id)
    raw, hashed, expires_at = security.new_refresh_token()
    session.add(
        RefreshToken(user_id=user.id, token_hash=hashed, expires_at=expires_at)
    )
    return TokenPair(access_token=access, refresh_token=raw, expires_in=expires_in)


async def refresh(session: AsyncSession, *, refresh_token: str) -> TokenPair:
    """用 refresh token 换一对新的，并把旧的作废（一次性使用）。"""
    hashed = security.hash_refresh_token(refresh_token)
    row = await session.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hashed)
    )
    now = datetime.now(timezone.utc)
    if row is None or row.revoked_at is not None or _aware(row.expires_at) <= now:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="刷新令牌无效或已过期"
        )

    user = await session.get(User, row.user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="账号不存在")

    row.revoked_at = now
    pair = await issue_tokens(session, user)
    # 就地提交，不等请求收尾。收尾提交发生在响应发出之后，那之间旧令牌仍然有效 ——
    # 实测客户端拿到新令牌立刻重放旧的，约 15% 能换到第二对（PRD R-001 要求一次性）。
    await session.commit()
    return pair


async def logout(session: AsyncSession, *, refresh_token: str | None, user: User) -> None:
    """登出：作废这台设备的 refresh token；没带就把该用户的全部作废。"""
    if refresh_token:
        hashed = security.hash_refresh_token(refresh_token)
        row = await session.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == hashed, RefreshToken.user_id == user.id
            )
        )
        if row is not None and row.revoked_at is None:
            row.revoked_at = utcnow()
        # 和 refresh 同理：作废必须在响应发出之前落库。
        await session.commit()
        return

    rows = await session.scalars(
        select(RefreshToken).where(
            RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None)
        )
    )
    for row in rows:
        row.revoked_at = utcnow()
    await session.commit()


async def delete_account(session: AsyncSession, *, user: User) -> list[str]:
    """注销：删掉该用户的全部业务数据，返回需要从磁盘清理的照片路径（PRD R-004）。"""
    paths = list(
        await session.scalars(select(Photo.path).where(Photo.user_id == user.id))
    )
    for model in (
        DiaryEntry,
        WaterLog,
        WeightLog,
        DayOverride,
        Photo,
        RecognitionUsage,
        RefreshToken,
        Profile,
    ):
        await session.execute(delete(model).where(model.user_id == user.id))
    await session.execute(delete(User).where(User.id == user.id))
    return paths


def _aware(value: datetime) -> datetime:
    """SQLite 取回来的 datetime 没有时区，补上 UTC 再比较。"""
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
