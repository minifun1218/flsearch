# FitMeal

面向健身人群的饮食记录 App：拍照 + AI 识别把单餐录入压缩到十几秒，按身体数据与训练计划自动算出训练日 / 休息日两套营养目标，在摄入偏离时主动提醒。

- 客户端：Flutter（首期交付 Android，iOS 保持可构建）
- 服务端：FastAPI + SQLAlchemy(async)，开发用 SQLite，生产用 PostgreSQL
- 识别：可插拔的云端多模态大模型（当前默认仍是 mock Provider）

## 仓库结构

```
app/       Flutter 客户端
server/    FastAPI 服务端（Docker 部署文件也在里面）
design/    设计稿（HTML 原型）
docs/      文档：PRD、后端契约、开发状态、部署命令
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/01-prd.md](docs/01-prd.md) | PRD：需求列表（R-001 ~ R-049）、验收标准、非功能需求 |
| [docs/02-development-status.md](docs/02-development-status.md) | 开发状态：已实现 / 未完成清单 |
| [docs/03-backend.md](docs/03-backend.md) | 后端接口契约与数据模型 |
| [docs/04-deployment.md](docs/04-deployment.md) | 后端部署命令（compose 与单容器两种） |

## 跑起来

服务端（详见 [server/README.md](server/README.md)）：

```bash
cd server
conda activate ai
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

客户端（详见 [app/README.md](app/README.md)）：

```powershell
cd app
flutter pub get
flutter run --dart-define=FITMEAL_API_BASE_URL=https://easycodetech.top/api/v1
```

没有服务端只想点一遍界面时，用演示模式（仓储链换成内存假数据）：

```powershell
flutter run --dart-define=FITMEAL_DEMO=true
```

## 验证

```bash
# 服务端
cd server && pytest -q

# 客户端
cd app
flutter analyze
flutter test
dart run tool/smoke.dart   # 对着真实服务端跑主流程，需先起服务端
```

## 当前状态

主循环已跑通：注册 → 建档算目标 → 拍照识别记录 → 面板看进度 → 提醒。服务端与客户端两侧的验收测试、冒烟测试均通过；提醒、统计、体重、常吃复制等 P1 功能已实现。

仍未完成的主要交付项：

- **R-019 / R-020**：默认识别 Provider 仍是 mock。横评脚本（`server/scripts/eval_providers.py`）与算分已就绪，缺 API Key 与 20~30 张标注过的真实中餐照片。
- **R-003 / R-026**：离线只读，没有编辑队列、冲突裁决与待识别照片队列。
- **R-027**：常吃只存在本机，服务端没有收藏接口。
- **R-047**：CSV 导出未实现。
- 部署侧：HTTPS 反向代理、照片到期清理定时任务、PostgreSQL 实测、Android 真机通知验收。

详见 [docs/02-development-status.md](docs/02-development-status.md)。
