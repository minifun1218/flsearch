"""服务端配置。

所有可调项都从环境变量读（见 .env.example），代码里不写死密钥、地址和阈值。
AI Provider 的 Key 只存在这一层，绝不下发客户端（PRD N-7）。
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVER_ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=SERVER_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "dev"
    api_prefix: str = "/api/v1"

    # ---- 安全 ----
    # 生产必须覆盖：换掉这个值等于让所有已签发的 token 立即失效。
    secret_key: str = "dev-only-change-me"
    access_token_ttl_minutes: int = 30
    refresh_token_ttl_days: int = 30
    password_min_length: int = 8

    # ---- 存储 ----
    database_url: str = f"sqlite+aiosqlite:///{(SERVER_ROOT / 'var' / 'fitmeal.db').as_posix()}"
    sql_echo: bool = False
    storage_dir: Path = SERVER_ROOT / "var" / "photos"
    # 上传照片的保留期限，到期清理（PRD N-9 / R-049）。
    photo_retention_days: int = 30

    # ---- 识别 ----
    # mock = 本地假识别，接真实 Provider 前的替身；openai = 任意 OpenAI 兼容的多模态接口。
    recognizer_provider: str = "mock"
    recognition_timeout_seconds: float = 15.0
    daily_recognition_limit: int = 20
    max_upload_bytes: int = 5 * 1024 * 1024

    openai_api_key: str | None = None
    openai_base_url: str | None = None
    openai_model: str = "gpt-4o-mini"

    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


@lru_cache
def get_settings() -> Settings:
    return Settings()
