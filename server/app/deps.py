"""FastAPI 依赖：会话与当前用户。

每个业务接口都必须经过 `CurrentUser`，拿到的 user_id 是后续所有查询的过滤条件 ——
用户 A 不可能读到用户 B 的数据（PRD N-8）。
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .db import session_scope
from .models import Profile, User
from .security import TokenError, decode_access_token

SessionDep = Annotated[AsyncSession, Depends(session_scope)]

_bearer = HTTPBearer(auto_error=False, description="Bearer <access_token>")


async def get_current_user(
    session: SessionDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="缺少访问令牌",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        user_id = decode_access_token(credentials.credentials)
    except TokenError:
        # 客户端收到 401 就用 refresh_token 静默换新并重试（PRD R-001）。
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="访问令牌无效或已过期",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None

    user = await session.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="账号不存在")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


async def get_current_profile(session: SessionDep, user: CurrentUser) -> Profile:
    profile = await session.get(Profile, user.id)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="尚未创建个人档案，请先提交档案",
        )
    return profile


CurrentProfile = Annotated[Profile, Depends(get_current_profile)]
