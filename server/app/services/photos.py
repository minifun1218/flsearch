"""照片存储与到期清理（PRD N-9、R-004）。

当前落本地磁盘，接对象存储时只需要换掉 save/remove 两个函数的实现。
每张照片都记了 expires_at，`purge_expired` 由定时任务或运维脚本调用。
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models import Photo, utcnow

_EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
}


def is_supported(content_type: str) -> bool:
    return content_type.lower() in _EXTENSIONS


async def save(
    session: AsyncSession, *, user_id: uuid.UUID, data: bytes, content_type: str
) -> Photo:
    settings = get_settings()
    root = Path(settings.storage_dir) / str(user_id)
    root.mkdir(parents=True, exist_ok=True)

    photo_id = uuid.uuid4()
    path = root / f"{photo_id}{_EXTENSIONS.get(content_type.lower(), '.bin')}"
    path.write_bytes(data)

    photo = Photo(
        id=photo_id,
        user_id=user_id,
        path=str(path),
        content_type=content_type,
        size_bytes=len(data),
        expires_at=datetime.now(timezone.utc)
        + timedelta(days=settings.photo_retention_days),
    )
    session.add(photo)
    await session.flush()
    return photo


def remove_files(paths: list[str]) -> int:
    removed = 0
    for raw in paths:
        try:
            Path(raw).unlink(missing_ok=True)
            removed += 1
        except OSError:
            # 文件删不掉不该影响业务，留给清理任务下次再试。
            continue
    return removed


async def purge_expired(session: AsyncSession) -> int:
    """删掉到期照片的文件并标记记录。返回清理条数。"""
    now = datetime.now(timezone.utc)
    rows = list(
        await session.scalars(
            select(Photo).where(Photo.expires_at <= now, Photo.deleted_at.is_(None))
        )
    )
    remove_files([row.path for row in rows])
    for row in rows:
        row.deleted_at = utcnow()
    return len(rows)
