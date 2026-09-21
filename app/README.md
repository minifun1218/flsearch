# FitMeal

健身饮食记录 Flutter 客户端，设计稿位于 `../design`，需求文档位于 `../docs/01-prd.md`。

当前可用的流程：

- 今日热量、三大营养素、饮水和餐次记录；历史日期切换。
- 食物搜索、自定义录入、常吃与整餐复制、份量编辑和营养值修正。
- 照片识别的授权、上传前压缩、识别结果编辑与保存流程（服务端识别 Provider 默认仍是 mock）。
- 7/30 天热量与三大项趋势、按每日目标计算的达标率、记录习惯统计。
- 个人档案与目标编辑、训练安排、体重记录及曲线、更新体重前的目标变化预览。
- 训练日/休息日每日目标及完整计算依据。
- 注册 / 登录 / 建档引导 / 退出登录 / 注销账号，记录跟着账号走。
- 提醒：每日进度检查、超标、漏记、饮水、每周称重，逐类开关 + 全局免打扰；
  没有系统通知权限时降级为应用内横幅，且不再重复弹权限框。

## 跑起来

先把服务端拉起来（见 `../server/README.md`），再启动客户端：

```powershell
flutter pub get
flutter run --dart-define=FITMEAL_API_BASE_URL=
```

`FITMEAL_API_BASE_URL` 不传时按平台猜一个开发地址：Android 模拟器 `10.0.2.2:8000`，
桌面 `127.0.0.1:8000`。**真机调试必须显式传**，模拟器那个地址在真机上不存在。
正式包必须传 https 地址（PRD N-6）。

没有服务端也要点一遍界面（设计走查、截图）时走演示模式 —— 整条仓储链换成内存假数据：

```powershell
flutter run --dart-define=FITMEAL_DEMO=true
```

## 验证

```powershell
flutter analyze
flutter test
dart run tool/smoke.dart            # 对着真实服务端跑一遍主流程，需要先起服务端
flutter build apk --debug
flutter build apk --release --dart-define=FITMEAL_API_BASE_URL=
```

`flutter test` 里的 widget 测试用 `DemoRepository`，不联网；`tool/smoke.dart` 是唯一
真的发请求的那个 —— widget 测试里 HttpClient 被 flutter_test 挡住了，发不出去。

### Windows 跨盘打包

项目与 Pub 缓存位于不同盘符时（例如项目在 F 盘，Pub 缓存在 C 盘），Kotlin 增量编译
可能报 `this and base files have different roots`，并引发 `Daemon compilation failed`
或 `Could not close incremental caches`。`android/gradle.properties` 已通过
`kotlin.incremental=false` 关闭 Kotlin 增量编译，避开跨盘相对路径错误；代价是需要
重新编译 Kotlin 时耗时可能增加。

若修改配置后仍受旧缓存影响，在 `app` 目录清理并重新打包：

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

正式包请按上文追加 `--dart-define=FITMEAL_API_BASE_URL=...`，使用实际的 HTTPS 服务端地址。

## 分层

```
data/
  api/          ApiClient（带 401 静默刷新）、DTO、令牌模型
  local/        LocalStore：令牌、照片授权、最近若干天的服务端响应快照
  repository.dart      数据出口接口
  api_repository.dart  真实实现：服务端 + 本地快照
  demo_repository.dart 内存假数据，测试与演示模式用
  app_state.dart       provider 层：写操作本地先生效，再推服务端，失败回滚并提示
  notifications/  ReminderScheduler：把排好的提醒挂到系统上（可替换、可造假）
  reminders_state.dart 提醒设置与调度：数据一变就重排
domain/         纯计算：营养目标、统计、提醒排程、模型（不依赖 Flutter）
features/       页面
```

目标热量由客户端自己算（`domain/nutrition_calculator.dart`），和服务端
`server/app/domain/nutrition.py` 是同一套公式：离线也要看得到目标（PRD N-4），
`tool/smoke.dart` 会核对两边算出来的是同一个数。

提醒同理：什么时候提醒、提醒什么内容全在 `domain/reminders.dart` 里算，
PRD 的验收标准因此能逐条单测；`data/notifications/` 只负责挂到系统上。

当前仍未接：离线编辑队列（R-003）、真实 AI 识别 Provider。
详见 `../docs/02-development-status.md`。

如果 Windows JDK 17 构建时报 `Unable to establish loopback connection`，可为本次进程指定非缩写的 socket 临时目录：

```powershell
New-Item -ItemType Directory -Force -Path build/java-sockets | Out-Null
$socketDir = (Resolve-Path build/java-sockets).Path.Replace('\', '/')
$env:JAVA_TOOL_OPTIONS = "$env:JAVA_TOOL_OPTIONS -Djdk.net.unixdomain.tmpdir=$socketDir"
flutter build apk --debug
```
