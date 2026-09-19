import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/food.dart';
import '../domain/models/profile.dart';
import '../domain/nutrition_calculator.dart';
import '../domain/reminders.dart';
import 'app_state.dart';
import 'notifications/reminder_scheduler.dart';

/// 提醒的状态与调度（PRD R-033 ~ R-039）。
///
/// 排什么在 `domain/reminders.dart`，怎么挂在 `notifications/`，这里只管
/// 「什么时候重排」：设置改了、记录变了、体重变了、登录态变了，都要重排一次。

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  // 演示模式和桌面端没有通知，用空实现 —— 页面照样点得完。
  if (kDemoMode) return NoopReminderScheduler();

  final local = ref.watch(localStoreProvider);
  return LocalNotificationScheduler(
    wasDenied: local.readNotificationsDenied,
    rememberDenied: local.writeNotificationsDenied,
  );
});

// ---------------------------------------------------------------- 设置

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() {
    if (kDemoMode) return const ReminderSettings();
    return ReminderSettings.fromJson(
      ref.read(localStoreProvider).readReminderSettings(),
    );
  }

  void update(ReminderSettings Function(ReminderSettings) change) {
    state = change(state);
    if (!kDemoMode) {
      ref.read(localStoreProvider).writeReminderSettings(state.toJson());
    }
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);

// ---------------------------------------------------------------- 权限

class NotificationPermissionNotifier extends Notifier<NotificationPermission> {
  @override
  NotificationPermission build() {
    scheduleMicrotask(refresh);
    return NotificationPermission.notAsked;
  }

  Future<void> refresh() async {
    state = await ref.read(reminderSchedulerProvider).permission();
  }

  /// 需要发通知之前问一次。拒过就不再弹（R-035）。
  Future<NotificationPermission> request() async {
    state = await ref.read(reminderSchedulerProvider).requestPermission();
    return state;
  }
}

final notificationPermissionProvider =
    NotifierProvider<NotificationPermissionNotifier, NotificationPermission>(
        NotificationPermissionNotifier.new);

// ---------------------------------------------------------------- 应用内横幅

/// 没有通知权限时，到点就在应用内摆一条横幅（R-035 的降级路径）。
class ForegroundReminderNotifier extends Notifier<PlannedReminder?> {
  @override
  PlannedReminder? build() => null;

  void show(PlannedReminder reminder) => state = reminder;

  void dismiss() => state = null;
}

final foregroundReminderProvider =
    NotifierProvider<ForegroundReminderNotifier, PlannedReminder?>(
        ForegroundReminderNotifier.new);

// ---------------------------------------------------------------- 调度

/// 当前挂着的提醒计划。
///
/// 它 watch 了设置、记录、体重和档案 —— 任何一个变了就重算重挂，所以通知内容
/// 不会停留在旧数据上（「还差 800 kcal」那种数字是排程时算出来的）。
class ReminderCoordinator extends Notifier<List<PlannedReminder>> {
  Timer? _foregroundTimer;

  /// 上一轮每天的热量合计。超标提醒靠它判断「这一次保存把人推过线了」——
  /// 而不是每次重建都提醒一遍（PRD R-036）。
  final _lastKcal = <String, int>{};
  var _baselineReady = false;

  @override
  List<PlannedReminder> build() {
    ref.onDispose(() => _foregroundTimer?.cancel());

    final settings = ref.watch(reminderSettingsProvider);
    final ready = ref.watch(sessionProvider).stage == AuthStage.ready;
    final logs = ref.watch(logStoreProvider);
    final profile = ref.watch(profileProvider);
    final weights = ref.watch(weightStoreProvider);
    final permission = ref.watch(notificationPermissionProvider);

    if (!ready) {
      scheduleMicrotask(() => ref.read(reminderSchedulerProvider).cancelAll());
      return const [];
    }

    final now = DateTime.now();
    final plan = ReminderPlanner.plan(
      settings: settings,
      now: now,
      lastWeightAt: _latestWeightDate(weights),
      snapshotFor: (day) {
        final log = logs[dayKey(day)];
        return (
          log: log,
          targets: NutritionCalculator.targetsFor(
            profile,
            day,
            overrideTrainingDay: log?.trainingDayOverride,
          ),
        );
      },
    );

    scheduleMicrotask(() => _apply(plan, permission));
    scheduleMicrotask(() => _checkOverLimit(settings, logs, profile));
    return plan;
  }

  Future<void> _apply(
    List<PlannedReminder> plan,
    NotificationPermission permission,
  ) async {
    final scheduler = ref.read(reminderSchedulerProvider);

    // 有要发的东西才问权限，而且只问这一次（R-035）。
    if (plan.isNotEmpty && permission == NotificationPermission.notAsked) {
      final granted =
          await ref.read(notificationPermissionProvider.notifier).request();
      permission = granted;
    }

    if (permission == NotificationPermission.granted) {
      await scheduler.apply(plan);
      _foregroundTimer?.cancel();
      _foregroundTimer = null;
      return;
    }

    await scheduler.cancelAll();
    // 权限被拒：系统通知发不出去，改由应用内横幅顶上（R-035）。
    // unsupported（桌面端 / 测试）不是降级场景，那里本来就没有提醒。
    if (permission == NotificationPermission.denied) _armForeground(plan);
  }

  /// 应用还在前台时，到点自己弹横幅。
  void _armForeground(List<PlannedReminder> plan) {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    if (plan.isEmpty) return;

    final now = DateTime.now();
    final next = plan.firstWhere(
      (r) => r.at.isAfter(now),
      orElse: () => plan.last,
    );
    final wait = next.at.difference(now);
    if (wait.isNegative) return;

    _foregroundTimer = Timer(wait, () {
      ref.read(foregroundReminderProvider.notifier).show(next);
      _armForeground(plan.where((r) => r.at.isAfter(next.at)).toList());
    });
  }

  /// 哪一天的热量刚被这次保存推过阈值，就为那天发一条超标提醒（R-036）。
  ///
  /// 首次建立基线时不发 —— 冷启动拉回一堆历史数据，不该一次性弹一串提醒。
  Future<void> _checkOverLimit(
    ReminderSettings settings,
    Map<String, DayLog> logs,
    UserProfile profile,
  ) async {
    final crossed = <DayLog>[];

    for (final entry in logs.entries) {
      final log = entry.value;
      final before = _lastKcal[entry.key];
      final now = log.totals.kcal;
      _lastKcal[entry.key] = now;
      if (!_baselineReady || before == null || now <= before) continue;

      final targets = NutritionCalculator.targetsFor(
        profile,
        log.date,
        overrideTrainingDay: log.trainingDayOverride,
      );
      final limit = (targets.kcal * settings.overLimitRatio).round();
      // 刚跨过去的那一次才提醒，之后再加一口不会重复弹。
      if (before <= limit && now > limit) crossed.add(log);
    }
    _baselineReady = true;
    if (crossed.isEmpty) return;

    final log = crossed.first;
    final message = ReminderPlanner.overLimitMessage(
      settings: settings,
      targets: NutritionCalculator.targetsFor(
        profile,
        log.date,
        overrideTrainingDay: log.trainingDayOverride,
      ),
      totals: log.totals,
      now: DateTime.now(),
    );
    if (message == null) return;

    const title = '今天已经超标了';
    if (ref.read(notificationPermissionProvider) ==
        NotificationPermission.granted) {
      await ref
          .read(reminderSchedulerProvider)
          .showNow(title: title, body: message);
      return;
    }
    // 降级：应用内横幅（R-035）。
    ref.read(foregroundReminderProvider.notifier).show(
          PlannedReminder(
            id: ReminderKind.overLimit.index,
            kind: ReminderKind.overLimit,
            at: DateTime.now(),
            title: title,
            body: message,
          ),
        );
  }

  static DateTime? _latestWeightDate(Map<String, double> weights) {
    DateTime? latest;
    for (final key in weights.keys) {
      final parts = key.split('-').map(int.tryParse).toList();
      if (parts.length != 3 || parts.any((p) => p == null)) continue;
      final date = DateTime(parts[0]!, parts[1]!, parts[2]!);
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }
}

final reminderCoordinatorProvider =
    NotifierProvider<ReminderCoordinator, List<PlannedReminder>>(
        ReminderCoordinator.new);

/// 接下来最近的那条提醒，「我的」页上摆一行给用户看。
final nextReminderProvider = Provider<PlannedReminder?>((ref) {
  final plan = ref.watch(reminderCoordinatorProvider);
  return plan.isEmpty ? null : plan.first;
});

/// 提醒里用到的餐次顺序，设置页按这个排。
const reminderMeals = [MealType.breakfast, MealType.lunch, MealType.dinner];
