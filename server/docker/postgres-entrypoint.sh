#!/usr/bin/env bash
# 单容器方案里 Postgres 那一半：数据目录为空就 initdb + 建库建用户，
# 不为空（挂了卷、重启过）就直接起服务——幂等，supervisor 重启这个程序不会重新建库。
set -euo pipefail

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | head -1)"
PG_USER="${POSTGRES_USER:-fitmeal}"
PG_PASSWORD="${POSTGRES_PASSWORD:-fitmeal}"
PG_DB="${POSTGRES_DB:-fitmeal}"

mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"
chmod 0700 "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[postgres] 数据目录为空，初始化 ..."
    su postgres -c "$PGBIN/initdb -D '$PGDATA' --auth=trust --encoding=UTF8 --locale=C.UTF-8"

    echo "[postgres] 临时起一次服务，建用户和库 ..."
    su postgres -c "$PGBIN/pg_ctl -D '$PGDATA' -w -o '-h 127.0.0.1 -p 5432' start"

    # 写成 SQL 文件再执行，不用在 su -c 的字符串里三层转义账号密码。
    INIT_SQL="/tmp/fitmeal-init.sql"
    cat > "$INIT_SQL" <<SQL
CREATE USER "$PG_USER" WITH SUPERUSER PASSWORD '$PG_PASSWORD';
CREATE DATABASE "$PG_DB" OWNER "$PG_USER";
SQL
    chown postgres:postgres "$INIT_SQL"
    su postgres -c "psql -h 127.0.0.1 -v ON_ERROR_STOP=1 -f '$INIT_SQL'"
    rm -f "$INIT_SQL"

    su postgres -c "$PGBIN/pg_ctl -D '$PGDATA' -w stop"
    echo "[postgres] 初始化完成。"
fi

echo "[postgres] 启动 ..."
exec su postgres -c "$PGBIN/postgres -D '$PGDATA' -h 0.0.0.0 -p 5432"
