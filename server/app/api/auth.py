"""账号接口（PRD R-001、R-004）。"""

from __future__ import annotations

from fastapi import APIRouter, Body, Response, status

from ..deps import CurrentUser, SessionDep
from ..schemas import (
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
    UserOut,
)
from ..services import auth as auth_service
from ..services import photos

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, session: SessionDep) -> TokenPair:
    _, tokens = await auth_service.register(
        session, email=payload.email, password=payload.password
    )
    return tokens


@router.post("/login", response_model=TokenPair)
async def login(payload: LoginRequest, session: SessionDep) -> TokenPair:
    _, tokens = await auth_service.login(
        session, email=payload.email, password=payload.password
    )
    return tokens


@router.post("/refresh", response_model=TokenPair)
async def refresh(payload: RefreshRequest, session: SessionDep) -> TokenPair:
    return await auth_service.refresh(session, refresh_token=payload.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    session: SessionDep,
    user: CurrentUser,
    refresh_token: str | None = Body(default=None, embed=True),
) -> Response:
    await auth_service.logout(session, refresh_token=refresh_token, user=user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserOut)
async def me(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(session: SessionDep, user: CurrentUser) -> Response:
    """注销账号，个人数据与照片一并删除（PRD R-004）。"""
    paths = await auth_service.delete_account(session, user=user)
    photos.remove_files(paths)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
