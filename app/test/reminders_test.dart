import 'package:fitmeal/domain/models/food.dart';
import 'package:fitmeal/domain/models/profile.dart';
import 'package:fitmeal/domain/nutrition_calculator.dart';
import 'package:fitmeal/domain/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

/// 逐条对着 PRD R-033 ~ R-039 的验收标准写。
void main() {
  // 2026-09-16 是周三。
  final wednesday = DateTime(2026, 9, 16);

  final profile = UserProfile(
    sex: Sex.male,
    birthDate: DateTime(1995, 3, 1),
    heightCm: 175,
    weightKg: 72.5,
    activityLevel: ActivityLevel.moderate,
    plan: const TrainingPlan(days: {1, 3, 5}),
    goal: GoalType.cut,
    targetWeightKg: 68,
    weeklyRateKg: 0.5,
  );

  DayTargets targetsOn(DateTime day) =>
      NutritionCalculator.targetsFor(profile, day);

  FoodEntry entry(int kcalPer100g, int grams, MealType meal,
          {double protein = 0}) =>
      FoodEntry(
        id: 'e-${meal.name}-$grams',
        food: FoodNutrition(
          name: '测试食物',
          kcalPer100g: kcalPer100g.toDouble(),
          proteinPer100g: protein,
          carbPer100g: 0,
          fatPer100g: 0,
        ),
        grams: grams,
        meal: meal,
      );

  /// 按目标的百分比造一天的记录。
  DayLog logAt(DateTime day, double ratioOfTarget, {List<MealType> meals = const [MealType.lunch]}) {
    final targets = targetsOn(day);
    final kcal = (targets.kcal * ratioOfTarget).round();
    final protein = targets.macros.proteinG * ratioOfTarget;
    return DayLog(
      date: day,
      entries: [
        for (final meal in meals)
          FoodEntry(
            id: 'e-${meal.name}',
            food: FoodNutrition(
              name: '测试餐',
              kcalPer100g: (kcal / meals.length).toDouble(),
              proteinPer100g: protein / meals.length,
              carbPer100g: 0,
              fatPer100g: 0,
            ),
            grams: 100,
            meal: meal,
          ),
      ],
    );
  }

  List<PlannedReminder> plan({
    required ReminderSettings settings,
    required DateTime now,
    DayLog? today,
    DateTime? lastWeightAt,
    int horizon = 1,
  }) {
    return ReminderPlanner.plan(
      settings: settings,
      now: now,
      horizon: horizon,
      lastWeightAt: lastWeightAt,
      snapshotFor: (day) => (
        log: day == DateTime(now.year, now.month, now.day) ? today : null,
        targets: targetsOn(day),
      ),
    );
  }

  group('R-034 每日进度检查', () {
    const settings = ReminderSettings(
      dailyCheckAt: ClockTime(20, 0),
      shortfallRatio: 0.8,
    );

    test('摄入 55% 时在 20:00 提醒，文案带上还差多少热量和蛋白质', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 18, 0),
        today: logAt(wednesday, 0.55),
      );

      final check = reminders.singleWhere((r) => r.kind == ReminderKind.dailyCheck);
      expect(check.at, DateTime(2026, 9, 16, 20, 0));

      final targets = targetsOn(wednesday);
      final kcalLeft = targets.kcal - (targets.kcal * 0.55).round();
      expect(check.body, contains('$kcalLeft kcal'));
      expect(check.body, contains('蛋白质'));
    });

    test('摄入 92% 时不提醒', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 18, 0),
        today: logAt(wednesday, 0.92),
      );
      expect(reminders.where((r) => r.kind == ReminderKind.dailyCheck), isEmpty);
    });

    test('热量够了但蛋白差得远，照样提醒', () {
      final targets = targetsOn(wednesday);
      final log = DayLog(
        date: wednesday,
        // 全靠碳水吃满热量，蛋白接近 0。
        entries: [entry(targets.kcal, 100, MealType.lunch)],
      );
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 18, 0),
        today: log,
      );
      final check = reminders.singleWhere((r) => r.kind == ReminderKind.dailyCheck);
      expect(check.body, contains('g 蛋白质'));
    });

    test('已经过了 20:00 就不再排今天的', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 21, 0),
        today: logAt(wednesday, 0.3),
      );
      expect(reminders.where((r) => r.kind == ReminderKind.dailyCheck), isEmpty);
    });

    test('关掉就不排', () {
      final reminders = plan(
        settings: settings.copyWith(dailyCheckEnabled: false),
        now: DateTime(2026, 9, 16, 18, 0),
        today: logAt(wednesday, 0.2),
      );
      expect(reminders, isEmpty);
    });
  });

  group('R-036 超标提醒', () {
    const settings = ReminderSettings(overLimitRatio: 1.1);
    final targets = targetsOn(wednesday);

    test('达到 115% 时给出文案', () {
      final message = ReminderPlanner.overLimitMessage(
        settings: settings,
        targets: targets,
        totals: MacroSum(
          kcal: (targets.kcal * 1.15).round(),
          protein: 100,
          carb: 200,
          fat: 60,
        ),
        now: DateTime(2026, 9, 16, 19, 0),
      );
      expect(message, isNotNull);
      expect(message, contains('115%'));
      expect(message, contains('超出'));
    });

    test('105% 还在阈值内，不提醒', () {
      final message = ReminderPlanner.overLimitMessage(
        settings: settings,
        targets: targets,
        totals: MacroSum(
          kcal: (targets.kcal * 1.05).round(),
          protein: 100,
          carb: 200,
          fat: 60,
        ),
        now: DateTime(2026, 9, 16, 19, 0),
      );
      expect(message, isNull);
    });

    test('免打扰时段里超标也不打扰', () {
      final message = ReminderPlanner.overLimitMessage(
        settings: settings,
        targets: targets,
        totals: MacroSum(kcal: targets.kcal * 2, protein: 100, carb: 200, fat: 60),
        now: DateTime(2026, 9, 16, 23, 30),
      );
      expect(message, isNull);
    });
  });

  group('R-037 漏记提醒', () {
    const settings = ReminderSettings(
      missedMealEnabled: true,
      missedMealGraceMinutes: 60,
      dailyCheckEnabled: false,
    );

    test('午餐窗 11:00–13:00 + 宽限 60 分钟 → 14:00 提醒', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 10, 0),
      );
      final lunch = reminders.firstWhere(
        (r) => r.kind == ReminderKind.missedMeal && r.title.contains('午餐'),
      );
      expect(lunch.at, DateTime(2026, 9, 16, 14, 0));
    });

    test('已经记过午餐就不提醒午餐，早餐照旧', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 8, 0),
        today: DayLog(
          date: wednesday,
          entries: [entry(200, 150, MealType.lunch)],
        ),
      );
      final missed = reminders.where((r) => r.kind == ReminderKind.missedMeal);
      expect(missed.any((r) => r.title.contains('午餐')), isFalse);
      expect(missed.any((r) => r.title.contains('早餐')), isTrue);
    });

    test('加餐不提醒 —— 本来就不是非吃不可的一顿', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 5, 0),
      );
      expect(
        reminders.any((r) => r.title.contains('加餐')),
        isFalse,
      );
    });
  });

  group('R-038 饮水提醒', () {
    const settings = ReminderSettings(
      waterEnabled: true,
      waterIntervalHours: 2,
      waterStart: ClockTime(8, 0),
      waterEnd: ClockTime(22, 0),
      dailyCheckEnabled: false,
      quietHours: QuietHours(enabled: false),
    );

    test('活动时段内每 2 小时一次，22:00 之后没有', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 0, 1),
      ).where((r) => r.kind == ReminderKind.water).toList();

      expect(
        reminders.map((r) => r.at.hour).toList(),
        [8, 10, 12, 14, 16, 18, 20],
      );
    });

    test('间隔改成 3 小时就按 3 小时排', () {
      final hours = plan(
        settings: settings.copyWith(waterIntervalHours: 3),
        now: DateTime(2026, 9, 16, 0, 1),
      ).where((r) => r.kind == ReminderKind.water).map((r) => r.at.hour).toList();
      expect(hours, [8, 11, 14, 17, 20]);
    });

    test('关掉饮水提醒后一条都不排（R-039）', () {
      final reminders = plan(
        settings: settings.copyWith(waterEnabled: false),
        now: DateTime(2026, 9, 16, 0, 1),
      );
      expect(reminders.where((r) => r.kind == ReminderKind.water), isEmpty);
    });
  });

  group('R-033 称重提醒', () {
    const settings = ReminderSettings(
      weighInEnabled: true,
      weighInWeekday: DateTime.sunday,
      weighInAt: ClockTime(9, 0),
      dailyCheckEnabled: false,
    );

    test('周日 09:00 提醒，本周没称过', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 12, 0),
        horizon: 7,
      ).where((r) => r.kind == ReminderKind.weighIn).toList();

      expect(reminders.length, 1);
      expect(reminders.single.at, DateTime(2026, 9, 20, 9, 0)); // 周日
    });

    test('本周已经称过就不提醒', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 12, 0),
        horizon: 7,
        lastWeightAt: DateTime(2026, 9, 15), // 同一周的周二
      );
      expect(reminders.where((r) => r.kind == ReminderKind.weighIn), isEmpty);
    });

    test('上周称的不算本周', () {
      final reminders = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 12, 0),
        horizon: 7,
        lastWeightAt: DateTime(2026, 9, 10), // 上一周的周四
      );
      expect(reminders.where((r) => r.kind == ReminderKind.weighIn).length, 1);
    });
  });

  group('R-039 免打扰', () {
    test('22:00–07:00 之间的提醒全部丢掉，时段结束也不补发', () {
      const settings = ReminderSettings(
        waterEnabled: true,
        waterIntervalHours: 1,
        waterStart: ClockTime(6, 0),
        waterEnd: ClockTime(23, 59),
        dailyCheckEnabled: false,
        quietHours: QuietHours(start: ClockTime(22, 0), end: ClockTime(7, 0)),
      );

      final hours = plan(
        settings: settings,
        now: DateTime(2026, 9, 16, 0, 1),
      ).map((r) => r.at.hour).toList();

      expect(hours.contains(6), isFalse); // 免打扰里
      expect(hours.contains(22), isFalse);
      expect(hours.contains(23), isFalse);
      expect(hours.first, 7); // 时段一结束就是第一条，没有补发 6 点那条
    });

    test('跨零点的时段判断正确', () {
      const quiet = QuietHours(start: ClockTime(22, 0), end: ClockTime(7, 0));
      expect(quiet.covers(DateTime(2026, 9, 16, 23, 0)), isTrue);
      expect(quiet.covers(DateTime(2026, 9, 16, 3, 0)), isTrue);
      expect(quiet.covers(DateTime(2026, 9, 16, 7, 0)), isFalse);
      expect(quiet.covers(DateTime(2026, 9, 16, 21, 59)), isFalse);
    });

    test('不跨零点的时段也对', () {
      const quiet = QuietHours(start: ClockTime(13, 0), end: ClockTime(14, 0));
      expect(quiet.covers(DateTime(2026, 9, 16, 13, 30)), isTrue);
      expect(quiet.covers(DateTime(2026, 9, 16, 14, 0)), isFalse);
      expect(quiet.covers(DateTime(2026, 9, 16, 12, 59)), isFalse);
    });
  });

  group('排程本身', () {
    test('同一份输入排两次，id 完全一致 —— 重排不会留下孤儿通知', () {
      const settings = ReminderSettings(
        waterEnabled: true,
        missedMealEnabled: true,
        weighInEnabled: true,
      );
      final now = DateTime(2026, 9, 16, 5, 0);
      final first = plan(settings: settings, now: now, horizon: 3);
      final second = plan(settings: settings, now: now, horizon: 3);

      expect(first.map((r) => r.id).toList(), second.map((r) => r.id).toList());
      expect(first.map((r) => r.id).toSet().length, first.length); // 不重复
    });

    test('结果按时间正序，且全在未来', () {
      const settings = ReminderSettings(
        waterEnabled: true,
        missedMealEnabled: true,
      );
      final now = DateTime(2026, 9, 16, 12, 30);
      final reminders = plan(settings: settings, now: now, horizon: 3);

      expect(reminders, isNotEmpty);
      for (final r in reminders) {
        expect(r.at.isAfter(now), isTrue, reason: '$r 不该排在过去');
      }
      final times = reminders.map((r) => r.at).toList();
      expect(times, orderedEquals([...times]..sort()));
    });

    test('设置能存能读，往返不丢字段', () {
      const settings = ReminderSettings(
        dailyCheckAt: ClockTime(21, 15),
        shortfallRatio: 0.7,
        missedMealEnabled: true,
        missedMealGraceMinutes: 45,
        waterEnabled: true,
        waterIntervalHours: 3,
        weighInEnabled: true,
        weighInWeekday: DateTime.monday,
        quietHours: QuietHours(start: ClockTime(23, 0), end: ClockTime(6, 30)),
      );

      final restored = ReminderSettings.fromJson(settings.toJson());
      expect(restored.dailyCheckAt, const ClockTime(21, 15));
      expect(restored.shortfallRatio, 0.7);
      expect(restored.missedMealGraceMinutes, 45);
      expect(restored.waterIntervalHours, 3);
      expect(restored.weighInWeekday, DateTime.monday);
      expect(restored.quietHours.end, const ClockTime(6, 30));
      expect(restored.mealWindows[MealType.lunch]!.end, const ClockTime(13, 0));
    });

    test('存坏了的 JSON 退回默认值，不炸', () {
      final restored = ReminderSettings.fromJson({
        'daily_check_at': {'h': 99, 'm': 99},
        'water_interval_hours': 'nonsense',
        'meal_windows': 'broken',
      });
      expect(restored.dailyCheckAt, const ClockTime(20, 0));
      expect(restored.waterIntervalHours, 2);
      expect(restored.mealWindows[MealType.dinner]!.start, const ClockTime(17, 0));
    });
  });
}
