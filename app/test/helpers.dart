import 'package:fitmeal/app.dart';
import 'package:fitmeal/data/app_state.dart';
import 'package:fitmeal/data/demo_repository.dart';
import 'package:fitmeal/data/local/local_store.dart';
import 'package:fitmeal/data/notifications/reminder_scheduler.dart';
import 'package:fitmeal/data/reminders_state.dart';
import 'package:fitmeal/data/repository.dart';
import 'package:fitmeal/domain/reminders.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// widget 测试的统一入口。
///
/// 仓储层换成 [DemoRepository]：不联网、不读磁盘，数据是那份确定性假数据，
/// 断言因此稳定。真实实现（`ApiRepository`）由服务端的 pytest 那套覆盖。
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  FitMealRepository? repository,
  ReminderScheduler? scheduler,
  ReminderSettings? reminderSettings,
}) async {
  // 测试环境不联网取字体，回落到 system-ui。
  GoogleFonts.config.allowRuntimeFetching = false;

  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  // 本地存储走 shared_preferences 的内存替身：每个测试一张白纸，
  // 但走的仍是真实那条读写路径。
  SharedPreferences.setMockInitialValues({});
  final local = await LocalStore.open();
  if (reminderSettings != null) {
    await local.writeReminderSettings(reminderSettings.toJson());
  }

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(local),
      repositoryProvider.overrideWithValue(repository ?? DemoRepository()),
      // 默认「这个平台没有通知」：测试里不该有真的排程，也不该留下定时器。
      reminderSchedulerProvider
          .overrideWithValue(scheduler ?? NoopReminderScheduler()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const FitMealApp(),
    ),
  );
  // 冷启动要恢复登录态、拉档案和最近 30 天，settle 一次才到主界面。
  await tester.pumpAndSettle();
  return container;
}
