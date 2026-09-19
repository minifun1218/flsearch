"""密码与令牌。

密码用 bcrypt 加盐哈希存储，任何接口都不回传密码字段（PRD N-5）。
access token 是短期 JWT；refresh token 是随机串，库里只存 sha256（PRD R-001）。
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import get_settings

ALGORITHM = "HS256"
#: bcrypt 的输入上限是 72 字节，超出部分会被静默截断 —— 先自己拦住。
MAX_PASSWORD_BYTES = 72


class TokenError(Exception):
    """令牌无效、过期或类型不符。"""


def hash_password(raw: str) -> str:
    return bcrypt.hashpw(raw.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(raw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(raw.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        return False


def create_access_token(user_id: uuid.UUID) -> tuple[str, int]:
    """返回 (token, 有效期秒数)。"""
    settings = get_settings()
    expires_in = settings.access_token_ttl_minutes * 60
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=expires_in)).timestamp()),
    }
    return jwt.encode(payload, settings.secret_key, algorithm=ALGORITHM), expires_in


def decode_access_token(token: str) -> uuid.UUID:
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[ALGORITHM])
    except jwt.PyJWTError as exc:
        raise TokenError(str(exc)) from exc
    if payload.get("type") != "access":
        raise TokenError("not an access token")
    try:
        return uuid.UUID(payload["sub"])
    except (KeyError, ValueError) as exc:
        raise TokenError("bad subject") from exc


def new_refresh_token() -> tuple[str, str, datetime]:
    """返回 (明文, 哈希, 过期时间)。明文只在这一次响应里出现。"""
    settings = get_settings()
    raw = secrets.token_urlsafe(48)
    expires_at = datetime.now(timezone.utc) + timedelta(
        days=settings.refresh_token_ttl_days
    )
    return raw, hash_refresh_token(raw), expires_at


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
