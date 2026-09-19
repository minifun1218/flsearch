import 'dart:math' as math;

import '../domain/models/food.dart';
import 'app_state.dart';

/// 演示用的历史数据。接后端后整个文件删掉。
///
/// 数据是按天确定性生成的（用天数当种子），不是随机 —— 每次冷启动看到的
/// 曲线和统计都一样，方便对着设计稿核对。
abstract final class SeedData {
  /// 过去这些天没有记录，用来验证「未记录的日子不计入统计」。
  static const _skippedDaysAgo = {3, 9, 14, 21, 27};

  static const _breakfasts = <List<(FoodNutrition, int)>>[
    [
      (FoodLibrary.wholeWheatToast, 80),
      (FoodLibrary.boiledEgg, 110),
      (FoodLibrary.soyMilk, 250),
    ],
    [
      (FoodLibrary.greekYogurt, 150),
      (FoodLibrary.banana, 120),
      (FoodLibrary.mixedNuts, 20),
    ],
    [
      (FoodLibrary.wholeWheatToast, 60),
      (FoodLibrary.boiledEgg, 55),
      (FoodLibrary.greekYogurt, 120),
    ],
  ];

  static const _lunches = <List<(FoodNutrition, int)>>[
    [
      (FoodLibrary.multigrainRice, 200),
      (FoodLibrary.panSearedChicken, 120),
      (FoodLibrary.garlicBroccoli, 180),
    ],
    [
      (FoodLibrary.brownRice, 180),
      (FoodLibrary.steamedFish, 150),
      (FoodLibrary.garlicBroccoli, 150),
    ],
    [
      (FoodLibrary.multigrainRice, 160),
      (FoodLibrary.poachedChicken, 140),
      (FoodLibrary.garlicBroccoli, 200),
    ],
  ];

  static const _dinners = <List<(FoodNutrition, int)>>[
    [
      (FoodLibrary.brownRice, 150),
      (FoodLibrary.steamedFish, 160),
      (FoodLibrary.garlicBroccoli, 160),
    ],
    [
      (FoodLibrary.multigrainRice, 130),
      (FoodLibrary.panSearedChicken, 130),
      (FoodLibrary.garlicBroccoli, 140),
    ],
    [
      (FoodLibrary.poachedChicken, 150),
      (FoodLibrary.brownRice, 120),
      (FoodLibrary.garlicBroccoli, 180),
    ],
  ];

  static const _snacks = <List<(FoodNutrition, int)>>[
    [(FoodLibrary.wheyProtein, 30), (FoodLibrary.banana, 120)],
    [(FoodLibrary.greekYogurt, 150)],
    [(FoodLibrary.mixedNuts, 25), (FoodLibrary.banana, 100)],
  ];

  /// 今天：早、午、加餐已记，晚餐留空以展示空态。
  static DayLog today(DateTime date, String Function() nextId) {
    FoodEntry e(FoodNutrition f, int g, MealType m, {bool photo = false}) =>
        FoodEntry(id: nextId(), food: f, grams: g, meal: m, fromPhoto: photo);

    return DayLog(
      date: date,
      waterMl: 1200,
      entries: [
        e(FoodLibrary.wholeWheatToast, 80, MealType.breakfast),
        e(FoodLibrary.boiledEgg, 110, MealType.breakfast),
        e(FoodLibrary.soyMilk, 250, MealType.breakfast),
        e(FoodLibrary.multigrainRice, 200, MealType.lunch, photo: true),
        e(FoodLibrary.panSearedChicken, 120, MealType.lunch, photo: true),
        e(FoodLibrary.garlicBroccoli, 180, MealType.lunch, photo: true),
        e(FoodLibrary.wheyProtein, 30, MealType.snack),
        e(FoodLibrary.banana, 120, MealType.snack),
        e(FoodLibrary.mixedNuts, 25, MealType.snack),
      ],
    );
  }

  /// 过去 29 天。[daysAgo] 越大越久远。
  static Map<String, DayLog> history(DateTime today, String Function() nextId) {
    final out = <String, DayLog>{};

    for (var daysAgo = 29; daysAgo >= 1; daysAgo--) {
      if (_skippedDaysAgo.contains(daysAgo)) continue;

      final date = dayOf(today.subtract(Duration(days: daysAgo)));
      final pick = daysAgo % 3;
      final entries = <FoodEntry>[];

      void add(List<(FoodNutrition, int)> plan, MealType meal) {
        for (final (food, grams) in plan) {
          // 份量按天做一点浮动，让统计曲线不是一条直线。
          final jitter = 1 + ((daysAgo * 7) % 21 - 10) / 100;
          entries.add(
            FoodEntry(
              id: nextId(),
              food: food,
              grams: math.max(10, (grams * jitter).round()),
              meal: meal,
              fromPhoto: daysAgo % 4 != 0,
            ),
          );
        }
      }

      add(_breakfasts[pick], MealType.breakfast);
      add(_lunches[pick], MealType.lunch);
      add(_dinners[pick], MealType.dinner);
      if (daysAgo % 2 == 0) add(_snacks[pick], MealType.snack);

      out[dayKey(date)] = DayLog(
        date: date,
        entries: entries,
        waterMl: 1800 + (daysAgo * 137) % 1300,
      );
    }

    return out;
  }

  /// 过去 90 天的体重，每周一条，最新值与初始档案一致。
  static Map<String, double> weights(DateTime today) {
    final out = <String, double>{};
    const start = 76.5;
    const end = 72.5;

    for (var weeksAgo = 12; weeksAgo >= 0; weeksAgo--) {
      final date = dayOf(today.subtract(Duration(days: weeksAgo * 7)));
      final t = (12 - weeksAgo) / 12;
      // 主趋势 + 一点点回弹，真实体重不会单调下降
      final wobble = math.sin(weeksAgo * 1.7) * 0.18;
      out[dayKey(date)] = double.parse(
        (start + (end - start) * t + wobble).toStringAsFixed(1),
      );
    }

    out[dayKey(dayOf(today))] = end;
    return out;
  }
}
