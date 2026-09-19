#!/usr/bin/env bash
# 单容器方案里 API 那一半：等本地 Postgres 就绪 → 迁移 → 起 uvicorn。
# alembic upgrade head 是幂等的，supervisor 重启这个程序（比如 uvicorn 崩了）
# 重新跑一遍迁移不会有副作用。
set -euo pipefail

PG_USER="${POSTGRES_USER:-fitmeal}"
PG_PASSWORD="${POSTGRES_PASSWORD:-fitmeal}"
PG_DB="${POSTGRES_DB:-fitmeal}"

# 现算，不用 Dockerfile 里写死的默认值——不然 `docker run -e POSTGRES_PASSWORD=xxx`
# 改了密码，DATABASE_URL 不跟着变，postgres 那边建的是新密码，这边拿旧的去连会直接 401。
export DATABASE_URL="postgresql+asyncpg://${PG_USER}:${PG_PASSWORD}@127.0.0.1:5432/${PG_DB}"

echo "[api] 等待本地 Postgres 就绪 ..."
until pg_isready -h 127.0.0.1 -p 5432 -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; do
    sleep 1
done

echo "[api] alembic upgrade head ..."
alembic upgrade head

echo "[api] 启动 uvicorn ..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
