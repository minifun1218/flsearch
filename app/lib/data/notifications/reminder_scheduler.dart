import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/reminders.dart';

/// 通知权限的三种状态。
enum NotificationPermission {
  granted,

  /// 用户拒绝过。**不再重复弹窗**，改用应用内横幅（PRD R-035）。
  denied,

  /// 还没问过。
  notAsked,

  /// 这个平台压根没有本地通知（桌面端 / 测试）。
  unsupported,
}

/// 把排好的提醒挂到系统上。
///
/// 排什么由 [ReminderPlanner] 决定，这一层只管挂和取消 —— 换插件、换平台都不影响
/// 那边的逻辑，也让测试能塞一个假的进来。
abstract interface class ReminderScheduler {
  Future<void> init();

  /// 当前权限状态，不弹窗。
  Future<NotificationPermission> permission();

  /// 先检查系统权限；仍被拒绝时不重复弹窗（R-035）。
  Future<NotificationPermission> requestPermission();

  /// 用新计划整体替换旧的 —— 先全撤再挂，不会留下已经不成立的提醒。
  Future<void> apply(List<PlannedReminder> plan);

  /// 立刻发一条（超标提醒走这条路，R-036）。
  Future<void> showNow({required String title, required String body});

  Future<void> cancelAll();
}

/// 什么也不做。桌面端、测试和演示模式用。
class NoopReminderScheduler implements ReminderScheduler {
  NoopReminderScheduler({
    this.permissionState = NotificationPermission.unsupported,
  });

  final NotificationPermission permissionState;

  /// 最近一次挂上去的计划，测试断言用。
  List<PlannedReminder> lastPlan = const [];

  final shown = <({String title, String body})>[];

  @override
  Future<void> init() async {}

  @override
  Future<NotificationPermission> permission() async => permissionState;

  @override
  Future<NotificationPermission> requestPermission() async => permissionState;

  @override
  Future<void> apply(List<PlannedReminder> plan) async => lastPlan = plan;

  @override
  Future<void> showNow({required String title, required String body}) async =>
      shown.add((title: title, body: body));

  @override
  Future<void> cancelAll() async => lastPlan = const [];
}

/// flutter_local_notifications 的实现。
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler({
    required this.wasDenied,
    required this.rememberDenied,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// 之前是否已经被拒过 —— 拒过就不再弹系统权限框（R-035）。
  final bool Function() wasDenied;
  final Future<void> Function(bool denied) rememberDenied;

  final FlutterLocalNotificationsPlugin _plugin;
  var _ready = false;

  static const _channelId = 'fitmeal_reminders';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '饮食提醒',
      channelDescription: '进度检查、漏记、饮水、称重与超标提醒',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> init() async {
    if (_ready || !_supported) return;

    tzdata.initializeTimeZones();
    // 排程按本地时区算：跨时区旅行时提醒还应该在「当地的 20:00」。
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // 拿不到就用 UTC 兜底，宁可偏一点也不要整个功能起不来。
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // 权限单独申请，初始化时不弹窗 —— 弹窗时机由业务决定（R-035）。
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<NotificationPermission> permission() async {
    if (!_supported) return NotificationPermission.unsupported;
    await init();

    // 系统设置中的授权优先于本地的历史拒绝记录；查询本身不会弹权限框。
    bool? enabled;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      enabled = await android.areNotificationsEnabled();
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      enabled = (await ios.checkPermissions())?.isEnabled;
    }

    if (enabled == true) {
      if (wasDenied()) await rememberDenied(false);
      return NotificationPermission.granted;
    }
    return wasDenied()
        ? NotificationPermission.denied
        : NotificationPermission.notAsked;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    final current = await permission();
    // 允许从系统设置恢复授权，但仍被拒绝时不再弹窗（R-035）。
    if (current != NotificationPermission.notAsked) return current;

    bool? granted;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      // Android 13 以下没有这个权限，插件返回 true。
      granted = await android.requestNotificationsPermission();
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    if (granted == true) {
      await rememberDenied(false);
      return NotificationPermission.granted;
    }
    await rememberDenied(true);
    return NotificationPermission.denied;
  }

  @override
  Future<void> apply(List<PlannedReminder> plan) async {
    if (!_supported) return;
    await init();
    await _plugin.cancelAll();

    for (final reminder in plan) {
      final at = tz.TZDateTime.from(reminder.at, tz.local);
      if (!at.isAfter(tz.TZDateTime.now(tz.local))) continue;
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: at,
        notificationDetails: _details,
        // 提醒不是闹钟：用非精确模式，省电，也不用去要 SCHEDULE_EXACT_ALARM。
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.kind.name,
      );
    }
  }

  @override
  Future<void> showNow({required String title, required String body}) async {
    if (!_supported) return;
    await init();
    await _plugin.show(
      // 即时提醒复用同一个 id：连续超标只留最新那条，不刷屏。
      id: ReminderKind.overLimit.index,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
  }
}
