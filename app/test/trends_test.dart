import 'package:fitmeal/data/app_state.dart';
import 'package:fitmeal/domain/models/food.dart';
import 'package:fitmeal/domain/models/profile.dart';
import 'package:fitmeal/domain/nutrition_calculator.dart';
import 'package:fitmeal/domain/trends.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final end = DateTime(2026, 9, 16);
  final profile = UserProfile(
    sex: Sex.male,
    birthDate: DateTime(1995, 3, 1),
    heightCm: 175,
    weightKg: 72.5,
    activityLevel: ActivityLevel.moderate,
    plan: const TrainingPlan(days: {1, 3, 5, 6}),
    goal: GoalType.cut,
    targetWeightKg: 68,
    weeklyRateKg: 0.5,
  );

  FoodEntry entry(
    double kcal, {
    bool photo = false,
    String name = '测试食物',
    MealType meal = MealType.lunch,
    double protein = 20,
  }) => FoodEntry(
    id: 'test',
    food: FoodNutrition(
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: protein,
      carbPer100g: 30,
      fatPer100g: 10,
    ),
    grams: 100,
    meal: meal,
    fromPhoto: photo,
  );

  TrendSnapshot week(Map<String, DayLog> logs, {DateTime? endDate}) =>
      TrendCalculator.snapshot(
        logs: logs,
        profile: profile,
        endDate: endDate ?? end,
        range: 7,
      );

  int targetOn(DateTime date) =>
      NutritionCalculator.targetsFor(profile, date).kcal;

  test('R-045 空白日保留在时间轴，饮水不计为饮食记录', () {
    final logs = {
      dayKey(end): DayLog(date: end, entries: [entry(1200, photo: true)]),
      dayKey(end.subtract(const Duration(days: 1))): DayLog(
        date: end.subtract(const Duration(days: 1)),
        waterMl: 500,
      ),
    };
    final snapshot = TrendCalculator.snapshot(
      logs: logs,
      profile: profile,
      endDate: end,
      range: 7,
    );
    expect(snapshot.days.length, 7);
    expect(snapshot.days.first.date, DateTime(2026, 9, 10));
    expect(snapshot.days.last.date, end);
    expect(snapshot.loggedDays, 1);
    expect(snapshot.missingDays, 6);
    expect(snapshot.averageKcal, 1200);
    expect(snapshot.averageProtein, 20);
    expect(snapshot.photoEntryPercent, 100);
    expect(snapshot.currentStreak, 1);
  });

  test('R-046 达标率使用有记录天数：18/25 = 72%', () {
    final logs = <String, DayLog>{};
    for (var ago = 0; ago < 25; ago++) {
      final date = end.subtract(Duration(days: ago));
      final target = NutritionCalculator.targetsFor(profile, date).kcal;
      logs[dayKey(date)] = DayLog(
        date: date,
        entries: [entry(ago < 18 ? target.toDouble() : target * 0.5)],
      );
    }
    final snapshot = TrendCalculator.snapshot(
      logs: logs,
      profile: profile,
      endDate: end,
      range: 30,
    );
    expect(snapshot.loggedDays, 25);
    expect(snapshot.hitDays, 18);
    expect(snapshot.hitRate, 72);
    expect(snapshot.currentStreak, 25);
    final week = TrendCalculator.snapshot(
      logs: logs,
      profile: profile,
      endDate: end,
      range: 7,
    );
    expect(week.currentStreak, 25, reason: '连续记录天数不应被所选图表范围截断');
  });

  test('目标遵循当天训练覆盖，历史日期不漏算', () {
    final restTarget = NutritionCalculator.targetsFor(
      profile,
      end,
      overrideTrainingDay: false,
    );
    final snapshot = TrendCalculator.snapshot(
      logs: {
        dayKey(end): DayLog(
          date: end,
          trainingDayOverride: false,
          entries: [entry(restTarget.kcal.toDouble())],
        ),
      },
      profile: profile,
      endDate: end,
      range: 7,
    );
    expect(snapshot.days.last.targets.isTrainingDay, isFalse);
    expect(snapshot.hitRate, 100);
    expect(snapshot.averageTargetKcal, restTarget.kcal);
  });

  test('无记录时所有统计为 0，避免除零和虚假达标', () {
    final snapshot = TrendCalculator.snapshot(
      logs: {},
      profile: profile,
      endDate: end,
      range: 7,
    );
    expect(snapshot.loggedDays, 0);
    expect(snapshot.hitRate, 0);
    expect(snapshot.averageKcal, 0);
    expect(snapshot.averageProtein, 0);
    expect(snapshot.targetFat, 0);
    expect(snapshot.currentStreak, 0);
    expect(snapshot.photoEntryPercent, 0);
  });

  test('每天按 ±10% 归为达标 / 偏低 / 超出 / 未记录', () {
    DateTime ago(int days) => end.subtract(Duration(days: days));
    final snapshot = week({
      dayKey(ago(0)): DayLog(
        date: ago(0),
        entries: [entry(targetOn(ago(0)).toDouble())],
      ),
      dayKey(ago(1)): DayLog(
        date: ago(1),
        entries: [entry(targetOn(ago(1)) * 0.8)],
      ),
      dayKey(ago(2)): DayLog(
        date: ago(2),
        entries: [entry(targetOn(ago(2)) * 1.2)],
      ),
    });
    expect(snapshot.days.last.status, DayStatus.hit);
    expect(snapshot.countOf(DayStatus.hit), 1);
    expect(snapshot.countOf(DayStatus.under), 1);
    expect(snapshot.countOf(DayStatus.over), 1);
    expect(snapshot.countOf(DayStatus.missing), 4);
  });

  test('训练日与休息日分开统计，各用各的目标', () {
    // 9/14 是周一（训练日），9/15 是周二（休息日）。
    final monday = DateTime(2026, 9, 14);
    final tuesday = DateTime(2026, 9, 15);
    final snapshot = week({
      dayKey(monday): DayLog(
        date: monday,
        entries: [entry(targetOn(monday) * 0.7)],
      ),
      dayKey(tuesday): DayLog(
        date: tuesday,
        entries: [entry(targetOn(tuesday).toDouble())],
      ),
    });
    final training = snapshot.trainingDays;
    final rest = snapshot.restDays;
    expect(training.totalDays + rest.totalDays, 7);
    expect(training.totalDays, 4, reason: '9/10–9/16 里有周五、周六、周一、周三四个训练日');
    expect(training.loggedDays, 1);
    expect(training.hitDays, 0);
    expect(training.averageTargetKcal, targetOn(monday));
    expect(rest.loggedDays, 1);
    expect(rest.hitRate, 100);
    expect(rest.averageTargetKcal, targetOn(tuesday));
    expect(training.averageTargetKcal, greaterThan(rest.averageTargetKcal));
  });

  test('饮水单独统计：只记饮水的日子也算进饮水平均', () {
    final yesterday = end.subtract(const Duration(days: 1));
    final snapshot = week({
      dayKey(end): DayLog(date: end, entries: [entry(1000)], waterMl: 4000),
      dayKey(yesterday): DayLog(date: yesterday, waterMl: 1000),
    });
    expect(snapshot.loggedDays, 1);
    expect(snapshot.waterLoggedDays, 2);
    expect(snapshot.averageWaterMl, 2500);
    expect(snapshot.waterHitDays, 1);
    expect(snapshot.averageWaterTargetMl, greaterThan(0));
  });

  test('热量按餐次汇总，主要来源按热量或蛋白排序', () {
    final snapshot = week({
      dayKey(end): DayLog(
        date: end,
        entries: [
          entry(300, name: '燕麦', meal: MealType.breakfast, protein: 13),
          entry(600, name: '米饭', meal: MealType.lunch, protein: 3),
          entry(200, name: '鸡胸肉', meal: MealType.dinner, protein: 31),
          entry(200, name: '鸡胸肉', meal: MealType.snack, protein: 31),
        ],
      ),
    });
    expect(snapshot.mealKcal, {
      MealType.breakfast: 300,
      MealType.lunch: 600,
      MealType.dinner: 200,
      MealType.snack: 200,
    });
    final byKcal = snapshot.topFoods();
    expect(byKcal.map((food) => food.name), ['米饭', '鸡胸肉', '燕麦']);
    final byProtein = snapshot.topFoods(byProtein: true);
    expect(byProtein.first.name, '鸡胸肉');
    expect(byProtein.first.times, 2);
    expect(byProtein.first.grams, 200);
    expect(byProtein.first.protein, 62);
  });

  test('与上一周期对比：任一周期没有记录时不给差值', () {
    final lastWeek = end.subtract(const Duration(days: 7));
    final logs = {
      dayKey(end): DayLog(date: end, entries: [entry(1500)]),
      dayKey(lastWeek): DayLog(date: lastWeek, entries: [entry(1200)]),
    };
    final current = week(logs);
    final previous = week(logs, endDate: lastWeek);
    expect(current.deltaFrom(previous, (s) => s.averageKcal), 300);
    expect(
      current.deltaFrom(week({}, endDate: lastWeek), (s) => s.averageKcal),
      isNull,
    );
    expect(current.deltaFrom(null, (s) => s.averageKcal), isNull);
  });

  test('翻看往期时连续记录仍从今天算起', () {
    final logs = <String, DayLog>{};
    for (var ago = 0; ago < 10; ago++) {
      final date = end.subtract(Duration(days: ago));
      logs[dayKey(date)] = DayLog(date: date, entries: [entry(1000)]);
    }
    final older = TrendCalculator.snapshot(
      logs: logs,
      profile: profile,
      endDate: end.subtract(const Duration(days: 20)),
      range: 7,
      today: end,
    );
    expect(older.loggedDays, 0);
    expect(older.currentStreak, 10);
  });

  group('体重与摄入对照', () {
    Map<String, DayLog> everyDay(double kcal) => {
      for (var ago = 0; ago < 7; ago++)
        dayKey(end.subtract(Duration(days: ago))): DayLog(
          date: end.subtract(Duration(days: ago)),
          entries: [entry(kcal)],
        ),
    };

    test('没有记录时不推算', () {
      expect(
        TrendCalculator.energyBalance(
          snapshot: week({}),
          profile: profile,
          weights: const [],
        ),
        isNull,
      );
    });

    test('缺口按称重间隔换算成理论体重变化，并与实际对照', () {
      final balance = TrendCalculator.energyBalance(
        snapshot: week(everyDay(1500)),
        profile: profile,
        weights: [
          (date: DateTime(2026, 9, 1), kg: 80), // 太早，超出一周回看
          (date: DateTime(2026, 9, 7), kg: 73.0), // 起点：窗口前 3 天
          (date: DateTime(2026, 9, 12), kg: 72.8),
          (date: DateTime(2026, 9, 14), kg: 72.4), // 终点：窗口内最后一次
        ],
      )!;
      expect(balance.averageIntake, 1500);
      expect(balance.estimatedBurn, greaterThan(1500));
      expect(balance.dailyBalance, 1500 - balance.estimatedBurn);
      expect(balance.startWeight!.kg, 73.0);
      expect(balance.endWeight!.kg, 72.4);
      expect(balance.spanDays, 7);
      expect(
        balance.expectedChangeKg,
        closeTo(balance.dailyBalance * 7 / 7700, 1e-9),
      );
      expect(balance.actualChangeKg, closeTo(-0.6, 1e-9));
      expect(balance.weights.length, 3);
    });

    test('称重不足两次时只给推算，不给实际', () {
      final balance = TrendCalculator.energyBalance(
        snapshot: week(everyDay(2000)),
        profile: profile,
        weights: [(date: end, kg: 72.5)],
      )!;
      expect(balance.hasWeightChange, isFalse);
      expect(balance.actualChangeKg, isNull);
      expect(balance.spanDays, 7);
    });
  });
}
