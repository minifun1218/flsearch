"""拍照识别（PRD R-018 ~ R-020、R-029、N-3）。"""

from __future__ import annotations

from fastapi import APIRouter, File, HTTPException, UploadFile, status

from ..config import get_settings
from ..deps import CurrentUser, SessionDep
from ..schemas import RecognitionOut
from ..services import photos, recognition_service

router = APIRouter(prefix="/recognitions", tags=["recognition"])


@router.post("", response_model=RecognitionOut, status_code=status.HTTP_201_CREATED)
async def recognize(
    session: SessionDep,
    user: CurrentUser,
    image: UploadFile = File(description="餐食照片，客户端应先压缩到长边 ≤1280px"),
) -> RecognitionOut:
    settings = get_settings()
    content_type = (image.content_type or "").lower()
    if not photos.is_supported(content_type):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="只接受 JPEG / PNG / WebP / HEIC 图片",
        )

    data = await image.read()
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="图片内容为空"
        )
    if len(data) > settings.max_upload_bytes:
        # 客户端本应压到 500KB 以内（PRD N-3），这里是兜底。
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"图片超过 {settings.max_upload_bytes // 1024} KB，请压缩后重试",
        )

    return await recognition_service.recognize_meal(
        session, user=user, data=data, content_type=content_type
    )
