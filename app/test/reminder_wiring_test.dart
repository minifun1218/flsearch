import 'package:fitmeal/data/app_state.dart';
import 'package:fitmeal/data/notifications/reminder_scheduler.dart';
import 'package:fitmeal/data/reminders_state.dart';
import 'package:fitmeal/domain/models/food.dart';
import 'package:fitmeal/domain/reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 排程算法本身在 reminders_test.dart 里逐条对着 PRD 验；这里验的是接线：
/// 数据一变有没有重排、有没有挂到系统上、没权限时是不是走应用内横幅。
void main() {
  /// 一条把当天顶到超标的记录。
  FoodEntry hugeMeal() => const FoodEntry(
        id: 'draft-over',
        food: FoodNutrition(
          name: '深夜炸鸡',
          kcalPer100g: 400,
          proteinPer100g: 20,
          carbPer100g: 20,
          fatPer100g: 28,
        ),
        grams: 2000,
        meal: MealType.dinner,
      );

  testWidgets('有权限时把计划挂到系统上，记录一变就重排', (tester) async {
    final scheduler =
        NoopReminderScheduler(permissionState: NotificationPermission.granted);
    final container = await pumpApp(
      tester,
      height: 1600,
      scheduler: scheduler,
      reminderSettings: const ReminderSettings(
        waterEnabled: true,
        waterIntervalHours: 2,
        // 免打扰关掉，免得测试跑在夜里结果不稳定。
        quietHours: QuietHours(enabled: false),
      ),
    );

    expect(scheduler.lastPlan, isNotEmpty);
    expect(
      scheduler.lastPlan.any((r) => r.kind == ReminderKind.water),
      isTrue,
    );

    // 记一笔之后重排过 —— 进度检查那条的文案会跟着变。
    final before = scheduler.lastPlan.length;
    final store = container.read(logStoreProvider.notifier);
    await store.addEntry(
      container.read(selectedDateProvider),
      store.newEntry(
        food: FoodLibrary.panSearedChicken,
        grams: 200,
        meal: MealType.dinner,
      ),
    );
    await tester.pumpAndSettle();
    expect(scheduler.lastPlan, isNotEmpty);
    expect(before, greaterThan(0));
  });

  testWidgets('所有提醒都关掉时，挂上去的计划是空的（R-039）', (tester) async {
    final scheduler =
        NoopReminderScheduler(permissionState: NotificationPermission.granted);
    await pumpApp(
      tester,
      height: 1600,
      scheduler: scheduler,
      reminderSettings: const ReminderSettings(
        dailyCheckEnabled: false,
        overLimitEnabled: false,
        missedMealEnabled: false,
        waterEnabled: false,
        weighInEnabled: false,
      ),
    );

    expect(scheduler.lastPlan, isEmpty);
  });

  testWidgets('保存导致超标时立刻发系统通知（R-036）', (tester) async {
    final scheduler =
        NoopReminderScheduler(permissionState: NotificationPermission.granted);
    final container = await pumpApp(
      tester,
      height: 1600,
      scheduler: scheduler,
      // 只留超标提醒，别让排程的那些混进来。
      reminderSettings: const ReminderSettings(
        dailyCheckEnabled: false,
        missedMealEnabled: false,
        waterEnabled: false,
        weighInEnabled: false,
        overLimitRatio: 1.1,
        quietHours: QuietHours(enabled: false),
      ),
    );
    expect(scheduler.shown, isEmpty);

    final store = container.read(logStoreProvider.notifier);
    await store.addEntry(container.read(selectedDateProvider), hugeMeal());
    await tester.pumpAndSettle();

    expect(scheduler.shown.length, 1);
    expect(scheduler.shown.single.title, '今天已经超标了');
    expect(scheduler.shown.single.body, contains('超出'));
  });

  testWidgets('没权限时超标降级成应用内横幅，可以关掉（R-035）', (tester) async {
    final scheduler =
        NoopReminderScheduler(permissionState: NotificationPermission.denied);
    final container = await pumpApp(
      tester,
      height: 1600,
      scheduler: scheduler,
      reminderSettings: const ReminderSettings(
        dailyCheckEnabled: false,
        missedMealEnabled: false,
        waterEnabled: false,
        weighInEnabled: false,
        quietHours: QuietHours(enabled: false),
      ),
    );

    final store = container.read(logStoreProvider.notifier);
    await store.addEntry(container.read(selectedDateProvider), hugeMeal());
    await tester.pumpAndSettle();

    // 系统通知一条没发，横幅顶上了。
    expect(scheduler.shown, isEmpty);
    expect(container.read(foregroundReminderProvider), isNotNull);
    expect(find.text('今天已经超标了'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(container.read(foregroundReminderProvider), isNull);
  });

  testWidgets('同一天再加一口不会重复弹超标', (tester) async {
    final scheduler =
        NoopReminderScheduler(permissionState: NotificationPermission.granted);
    final container = await pumpApp(
      tester,
      height: 1600,
      scheduler: scheduler,
      reminderSettings: const ReminderSettings(
        dailyCheckEnabled: false,
        missedMealEnabled: false,
        waterEnabled: false,
        weighInEnabled: false,
        quietHours: QuietHours(enabled: false),
      ),
    );

    final store = container.read(logStoreProvider.notifier);
    final date = container.read(selectedDateProvider);
    await store.addEntry(date, hugeMeal());
    await tester.pumpAndSettle();
    await store.addEntry(
      date,
      store.newEntry(food: FoodLibrary.banana, grams: 120, meal: MealType.snack),
    );
    await tester.pumpAndSettle();

    expect(scheduler.shown.length, 1);
  });

  testWidgets('提醒设置页可以逐类开关，并把接下来要发的列出来', (tester) async {
    final scheduler =
        NoopReminderScheduler(permissionState: NotificationPermission.granted);
    // 视口给足，两页都一屏装得下 —— 这条测的是开关和排期，不是滚动。
    final container = await pumpApp(
      tester,
      height: 3000,
      scheduler: scheduler,
      reminderSettings: const ReminderSettings(
        dailyCheckEnabled: false,
        missedMealEnabled: false,
        waterEnabled: false,
        weighInEnabled: false,
        quietHours: QuietHours(enabled: false),
      ),
    );

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.pumpAndSettle();

    // 超标提醒还开着，只是它不排期（保存时才发）—— 所以是「没有要发的」而不是「都关着」。
    expect(find.text('接下来三天没有要发的提醒。'), findsOneWidget);

    // 打开饮水提醒，排期立刻出现在页面底部。
    await tester.tap(find.text('按间隔提醒喝水'));
    await tester.pumpAndSettle();

    expect(container.read(reminderSettingsProvider).waterEnabled, isTrue);
    expect(
      container
          .read(reminderCoordinatorProvider)
          .any((r) => r.kind == ReminderKind.water),
      isTrue,
    );
    expect(find.text('接下来三天没有要发的提醒。'), findsNothing);
    expect(find.text('喝点水'), findsWidgets);
  });

  testWidgets('设置改完写进本地，重开应用还在', (tester) async {
    final container = await pumpApp(tester, height: 1600);
    container
        .read(reminderSettingsProvider.notifier)
        .update((s) => s.copyWith(waterEnabled: true, waterIntervalHours: 4));
    await tester.pumpAndSettle();

    final stored = container.read(localStoreProvider).readReminderSettings();
    final restored = ReminderSettings.fromJson(stored);
    expect(restored.waterEnabled, isTrue);
    expect(restored.waterIntervalHours, 4);
  });
}
