# FitMeal 服务端

FastAPI + SQLAlchemy(async)。开发跑 SQLite，生产按 PRD 用 PostgreSQL。
接口契约与数据模型见 `../docs/03-backend.md`，需求编号一律引用 `../docs/01-prd.md`。

## 跑起来

```bash
conda activate ai                 # 本机约定：AI 相关项目用 ai 环境
pip install -r requirements.txt
cp .env.example .env              # 按需改 SECRET_KEY / DATABASE_URL / Provider
python scripts/seed_foods.py      # 可选：灌入客户端那份食物表，搜索一开始就有内容
uvicorn app.main:app --reload
```

- 文档：http://127.0.0.1:8000/docs
- 健康检查：http://127.0.0.1:8000/health

## 迁移

表结构由 Alembic 管（`migrations/`），地址从 `app.config` 的 `DATABASE_URL` 读，
迁移和应用永远指向同一个库。

```bash
alembic upgrade head                        # 建表 / 升到最新
alembic revision --autogenerate -m "说明"   # 改完 models.py 后生成一版
alembic downgrade -1                        # 回退一版
alembic upgrade head --sql                  # 只出 SQL，交给 DBA 审
```

`APP_ENV=dev|test` 时进程启动会顺手 `create_all()` 把表拉起来，方便本地直接跑；
其它环境（含生产）不建表，**部署前必须先 `alembic upgrade head`**。改了
`models.py` 就要生成迁移：跑一次 `--autogenerate`，输出为空才说明两边一致。

测试（不联网、不花钱，识别走 mock Provider）：

```bash
pytest -q
```

## 目录

```
app/
  config.py        环境配置（Key 只在这一层，绝不下发客户端）
  db.py            引擎与会话；请求级事务
  models.py        全部数据表
  schemas.py       请求/响应模型，字段与客户端 Dart 模型一一对应
  security.py      bcrypt 密码 + JWT access + 一次性 refresh
  deps.py          依赖注入：会话、当前用户、当前档案
  domain/
    nutrition.py   营养目标计算，与客户端 nutrition_calculator.dart 同一套公式
    food_name.py   食物名标准化 —— 缓存表的键
  services/        业务逻辑（auth / diary / food_cache / photos / recognition_service）
    recognition/   Provider 接口与实现（mock、openai 兼容）
  api/             路由
tests/             pytest，逐条对着 PRD 验收标准写
migrations/        Alembic 迁移，versions/ 下一版一个文件
scripts/           运维脚本（灌种子食物、Provider 横评）
```

## Provider 横评

默认 Provider 选谁，用 `scripts/eval_providers.py` 出的那张表决定，不靠感觉
（PRD R-019 / R-020，以及 PRD「风险」里那条建议）：

```bash
# 先确认脚本本身是通的（不联网、不花钱）
python scripts/eval_providers.py --make-sample var/eval-sample
python scripts/eval_providers.py --dataset var/eval-sample --provider mock

# 真正的横评：20~30 张真实中餐照片 + 人工标注（只标食物名和克数）
python scripts/eval_providers.py --dataset eval/zh-meals     --provider openai:gpt-4o-mini     --provider openai:qwen-vl-max@https://dashscope.aliyuncs.com/compatible-mode/v1     --repeat 3 --out eval/report.md
```

出的表有六列要看：识别率、准确率、份量平均偏差、返回可用率、重复一致性、延迟。
其中**返回可用率低于 95% 基本不能用**（R-019 要求失败要能明确引导手动录入），
**重复一致性低**意味着同一食物会以各种别名进缓存表，把 R-020 的一致性保障冲掉。

算分逻辑有单测守着（`tests/test_eval_harness.py`）；真实照片和标注不进仓库。

## MiniMax 识别返回 502

前端的「识别服务暂时不可用」对应 `POST /api/v1/recognitions` 返回 502。
它可能是上游调用失败，也可能是响应解析失败，HTTP 访问日志本身无法区分。

MiniMax 的 OpenAI 兼容接口默认可能把 `<think>...</think>` 放在 `content`
的最终 JSON 之前。直接 `json.loads(content)` 会把成功响应判为失败。
当前 Provider 为 MiniMax 模型启用 `reasoning_split=true`，并兼容完整的思考段
与 JSON 代码块包装；最终食物字段仍经过严格校验，未完成的思考或截断响应仍报错。
接口行为见 [MiniMax 官方文档](https://platform.minimax.cn/docs/api-reference/text-openai-api)。

此修复在服务端生效。把更新后的 `app/services/recognition/openai_provider.py`
与 `app/services/recognition_service.py` 同步到服务器。使用本项目 Compose 的部署，
在服务器的 `server/` 目录执行：

```bash
docker compose --env-file .env.docker up -d --build --no-deps api
docker compose --env-file .env.docker logs --tail=100 api
```

镜像通过 `COPY . .` 包含源码，因此更新源文件后需要重新构建并重建 API 容器；
单独 `docker compose restart api` 仍会运行旧镜像中的代码。
单容器部署则需要用 `Dockerfile.allinone` 重建镜像，并沿用原来的环境变量和卷配置更新容器。

失败时日志会输出 `Recognition failed` 及 `error_type`、`upstream_status`。
例如 `JSONDecodeError` 表示返回内容不是 JSON，`ValidationError` 表示字段不符合约定，
`AuthenticationError` / `upstream_status=401` 表示上游鉴权失败。
更具体的历史错误保存在 `recognition_usage.error`。

## 几个关键决定

**营养计算两端各算一份，公式必须同源。** `domain/nutrition.py` 是
`app/lib/domain/nutrition_calculator.dart` 的逐行移植：客户端离线也要能算目标（N-4），
服务端要保证换设备后数字一致（R-002）。改动任一边都要同步另一边，测试里那些
PRD 验收数字（1669 / 2587 / 2037 / 131g…）就是两边的共同锚点。

**营养值以缓存表为准，不是以本次 AI 输出为准。** 识别结果先按标准名查
`food_nutrition`，命中就用缓存值——哪怕这次 AI 给了别的数（R-020）。这是
「同一食物两周内 5 次识别数值完全一致」的唯一保障。已保存的记录持有自己的营养快照，
所以后来的修正（R-025）只影响之后的记录，不会追溯改写历史。

**食物名标准化保守优先。** 见 `domain/food_name.py` 顶部的策略说明：
做法和部位一律保留（清蒸鱼 ≠ 红烧鱼），只归一份量词、标点和显式别名。
宁可漏合并（命中率低一点）也不错合并（数据脏掉）。

**识别失败也要留下账。** Provider 超时或返回非法 JSON 时，照片已经落盘、用量已经记账，
然后才抛错——客户端拿到的是明确失败 + 引导手动录入（R-019、N-2、N-14）。

## 下一步

1. **接真实 Provider**：`RECOGNIZER_PROVIDER=openai` + `OPENAI_API_KEY` / `OPENAI_BASE_URL`
   即可切换。上线前先按上面那节跑一遍横评再定默认 Provider —— 脚本和算分都已就绪，
   缺的是凭据和 20~30 张标注过的真实中餐照片。
2. **离线同步（R-003）**：`diary_entries.updated_at` 已经就位，还差批量 push/pull 接口
   与 updatedAt 冲突裁决。
3. **收藏同步（R-027）**：常吃目前只存在客户端本地，换设备不跟着走。
4. **照片清理**：`services/photos.purge_expired()` 已实现，还需要挂到定时任务上。
5. **PostgreSQL 实测**：迁移能渲染出干净的 PG DDL，但还没在真实实例上跑过。

提醒（R-033 ~ R-039）已经由客户端的本地通知实现，服务端不需要推送通道。
