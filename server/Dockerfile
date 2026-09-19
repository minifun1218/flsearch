# FitMeal 服务端镜像。
#
# 只装运行时需要的东西：依赖单独一层缓存，代码变了不用重装依赖。
# 同一份镜像给两个角色共用——具体跑迁移还是跑服务，由 docker-compose.yml
# 按服务覆盖启动命令决定，镜像本身不写死该干哪件事（见仓库根目录 docker-compose.yml）。
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN mkdir -p /data/photos

# 照片落在挂卷目录，容器重建不丢；SQLite 只在没配 DATABASE_URL 时才会用到这里。
ENV STORAGE_DIR=/data/photos

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
