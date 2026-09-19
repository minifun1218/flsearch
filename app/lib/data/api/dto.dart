import '../../domain/models/food.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/recognition.dart';

/// 服务端 JSON ↔ 领域模型。
///
/// 只有这一个文件知道字段叫什么名字：契约变了改这里，页面和仓储都不用动。
/// 枚举的线上取值见 `server/app/models.py`，两边必须一致。
abstract final class Dto {
  // ------------------------------------------------------------ 日期

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parseDate(String raw) {
    final parts = raw.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  // ------------------------------------------------------------ 枚举

  static const _sex = {'male': Sex.male, 'female': Sex.female};

  static const _activity = {
    'sedentary': ActivityLevel.sedentary,
    'light': ActivityLevel.light,
    'moderate': ActivityLevel.moderate,
    'heavy': ActivityLevel.heavy,
  };

  static const _goal = {
    'cut': GoalType.cut,
    'bulk': GoalType.bulk,
    'maintain': GoalType.maintain,
  };

  static const _training = {
    'strength': TrainingType.strength,
    'cardio': TrainingType.cardio,
    'mixed': TrainingType.mixed,
  };

  static const _meal = {
    'breakfast': MealType.breakfast,
    'lunch': MealType.lunch,
    'dinner': MealType.dinner,
    'snack': MealType.snack,
  };

  static String mealName(MealType meal) => meal.name;

  static MealType meal(String raw) => _meal[raw] ?? MealType.snack;

  // ------------------------------------------------------------ 档案

  static UserProfile profile(Map<String, dynamic> json) {
    return UserProfile(
      sex: _sex[json['sex']] ?? Sex.male,
      birthDate: parseDate(json['birth_date'] as String),
      heightCm: _double(json['height_cm']),
      weightKg: _double(json['weight_kg']),
      bodyFatPercent: json['body_fat_percent'] == null
          ? null
          : _double(json['body_fat_percent']),
      activityLevel: _activity[json['activity_level']] ?? ActivityLevel.moderate,
      plan: TrainingPlan(
        days: {
          for (final d in (json['training_days'] as List? ?? const []))
            (d as num).toInt(),
        },
        type: _training[json['training_type']] ?? TrainingType.strength,
        minutes: (json['training_minutes'] as num?)?.toInt() ?? 60,
      ),
      goal: _goal[json['goal']] ?? GoalType.maintain,
      targetWeightKg: _double(json['target_weight_kg']),
      weeklyRateKg: _double(json['weekly_rate_kg']),
      proteinPerKg: _double(json['protein_per_kg'] ?? 1.8),
      fatPercentOfKcal: _double(json['fat_percent_of_kcal'] ?? 25),
    );
  }

  static Map<String, dynamic> profileJson(UserProfile p) {
    return {
      'sex': p.sex.name,
      'birth_date': date(p.birthDate),
      'height_cm': p.heightCm,
      'weight_kg': p.weightKg,
      'body_fat_percent': p.bodyFatPercent,
      'activity_level': p.activityLevel.name,
      'training_days': p.plan.days.toList()..sort(),
      'training_type': p.plan.type.name,
      'training_minutes': p.plan.minutes,
      'goal': p.goal.name,
      'target_weight_kg': p.targetWeightKg,
      'weekly_rate_kg': p.weeklyRateKg,
      'protein_per_kg': p.proteinPerKg,
      'fat_percent_of_kcal': p.fatPercentOfKcal,
    };
  }

  // ------------------------------------------------------------ 食物与记录

  static FoodNutrition food(Map<String, dynamic> json) {
    return FoodNutrition(
      name: json['name'] as String? ?? json['food_name'] as String,
      kcalPer100g: _double(json['kcal_per_100g']),
      proteinPer100g: _double(json['protein_per_100g']),
      carbPer100g: _double(json['carb_per_100g']),
      fatPer100g: _double(json['fat_per_100g']),
    );
  }

  static Map<String, dynamic> nutritionJson(FoodNutrition f) => {
        'kcal_per_100g': f.kcalPer100g,
        'protein_per_100g': f.proteinPer100g,
        'carb_per_100g': f.carbPer100g,
        'fat_per_100g': f.fatPer100g,
      };

  static FoodEntry entry(Map<String, dynamic> json) {
    return FoodEntry(
      id: json['id'] as String,
      food: food(json),
      grams: (json['grams'] as num).toInt(),
      meal: meal(json['meal'] as String),
      fromPhoto: json['from_photo'] as bool? ?? false,
      portionUncertain: json['portion_uncertain'] as bool? ?? false,
    );
  }

  /// 新建记录的请求体。
  static Map<String, dynamic> entryJson(FoodEntry e) => {
        'food_name': e.food.name,
        'grams': e.grams,
        'meal': e.meal.name,
        'from_photo': e.fromPhoto,
        'portion_uncertain': e.portionUncertain,
        ...nutritionJson(e.food),
      };

  /// 一天的面板。
  ///
  /// 目标是客户端自己算的（同一套公式，离线也要能算，N-4），这里只取
  /// 服务端独有的部分：记录、饮水、训练日覆盖。
  static DayLog dayLog(Map<String, dynamic> json) {
    final targets = json['targets'] as Map<String, dynamic>? ?? const {};
    final entries = <FoodEntry>[
      for (final group in (json['meals'] as List? ?? const []))
        for (final row in ((group as Map)['entries'] as List? ?? const []))
          entry(row as Map<String, dynamic>),
    ];

    return DayLog(
      date: parseDate(json['date'] as String),
      entries: entries,
      waterMl: (json['water_ml'] as num?)?.toInt() ?? 0,
      trainingDayOverride: targets['overridden'] == true
          ? targets['is_training_day'] as bool?
          : null,
    );
  }

  // ------------------------------------------------------------ 识别

  static RecognizedItem recognizedItem(Map<String, dynamic> json) {
    return RecognizedItem(
      food: food(json),
      estimatedGrams: (json['estimated_grams'] as num).toInt(),
      portionUncertain: json['portion_uncertain'] as bool? ?? false,
      nutritionFromCache: json['nutrition_from_cache'] as bool? ?? false,
    );
  }

  static double _double(Object? value) => (value as num).toDouble();
}
