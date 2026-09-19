import 'package:fitmeal/data/notifications/reminder_scheduler.dart';
import 'package:fitmeal/data/reminders_state.dart';
import 'package:fitmeal/domain/reminders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  late bool denied;
  late bool enabled;
  late bool requestGranted;
  late List<MethodCall> calls;
  late LocalNotificationScheduler scheduler;

  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    denied = false;
    enabled = false;
    requestGranted = false;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          timezoneChannel,
          (_) async => 'Asia/Singapore',
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'areNotificationsEnabled':
              return enabled;
            case 'checkPermissions':
              return {'isEnabled': enabled};
            case 'requestNotificationsPermission':
              enabled = requestGranted;
              return requestGranted;
            case 'cancelAll':
            case 'zonedSchedule':
              return null;
            default:
              throw StateError('Unexpected notification call: ${call.method}');
          }
        });
    scheduler = LocalNotificationScheduler(
      wasDenied: () => denied,
      rememberDenied: (value) async => denied = value,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Android settings grant overrides and clears an earlier denial',
    () async {
      denied = true;
      enabled = true;

      expect(await scheduler.permission(), NotificationPermission.granted);
      expect(denied, isFalse);
      expect(calls.map((c) => c.method), [
        'initialize',
        'areNotificationsEnabled',
      ]);
    },
  );

  test('request recognizes a settings grant without prompting again', () async {
    denied = true;
    enabled = true;

    expect(await scheduler.requestPermission(), NotificationPermission.granted);
    expect(denied, isFalse);
    expect(
      calls.any((c) => c.method == 'requestNotificationsPermission'),
      isFalse,
    );
  });

  test(
    'an existing denial never repeats the system permission prompt',
    () async {
      denied = true;

      expect(await scheduler.permission(), NotificationPermission.denied);
      expect(
        await scheduler.requestPermission(),
        NotificationPermission.denied,
      );
      expect(denied, isTrue);
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isFalse,
      );
    },
  );

  test(
    'first denial is remembered and subsequent requests do not prompt',
    () async {
      expect(await scheduler.permission(), NotificationPermission.notAsked);
      expect(
        await scheduler.requestPermission(),
        NotificationPermission.denied,
      );
      expect(
        await scheduler.requestPermission(),
        NotificationPermission.denied,
      );
      expect(denied, isTrue);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
    },
  );

  test('a first-time grant is returned successfully', () async {
    requestGranted = true;

    expect(await scheduler.requestPermission(), NotificationPermission.granted);
    expect(denied, isFalse);
  });

  test('iOS settings grant also overrides a saved denial', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    denied = true;
    enabled = true;

    expect(await scheduler.requestPermission(), NotificationPermission.granted);
    expect(denied, isFalse);
    expect(calls.map((c) => c.method), ['initialize', 'checkPermissions']);
  });

  test('unsupported platforms do not call the notification plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    expect(
      await scheduler.requestPermission(),
      NotificationPermission.unsupported,
    );
    expect(calls, isEmpty);
  });

  testWidgets('returning from Android settings schedules water reminders', (
    tester,
  ) async {
    denied = true;
    final container = await pumpApp(
      tester,
      scheduler: scheduler,
      reminderSettings: const ReminderSettings(
        dailyCheckEnabled: false,
        missedMealEnabled: false,
        weighInEnabled: false,
        waterEnabled: true,
        quietHours: QuietHours(enabled: false),
      ),
    );
    expect(
      container.read(notificationPermissionProvider),
      NotificationPermission.denied,
    );
    expect(calls.any((c) => c.method == 'zonedSchedule'), isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      container.read(notificationPermissionProvider),
      NotificationPermission.granted,
    );
    expect(denied, isFalse);
    expect(
      calls
          .where((c) => c.method == 'zonedSchedule')
          .any((c) => (c.arguments as Map)['payload'] == 'water'),
      isTrue,
    );
    expect(
      calls.any((c) => c.method == 'requestNotificationsPermission'),
      isFalse,
    );
  });
}
