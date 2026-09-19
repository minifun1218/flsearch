import '../nutrition_calculator.dart';

enum MealType {
  breakfast('早餐'),
  lunch('午餐'),
  dinner('晚餐'),
  snack('加餐');

  const MealType(this.label);

  final String label;
}

/// 食物的每 100g 营养值。
///
/// 服务端按标准化食物名缓存这张表：识别出食物先查缓存，命中就复用，
/// 未命中才采用本次 AI 估算值并写回。这是同一食物长期数据一致的唯一保障
/// （PRD R-020 / R-025）。
class FoodNutrition {
  const FoodNutrition({
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbPer100g,
    required this.fatPer100g,
  });

  final String name;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbPer100g;
  final double fatPer100g;

  String get summary => '${kcalPer100g.toStringAsFixed(0)} kcal / 100g · '
      '蛋白 ${_trim(proteinPer100g)} · '
      '碳水 ${_trim(carbPer100g)} · '
      '脂肪 ${_trim(fatPer100g)}';

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  FoodNutrition copyWith({
    String? name,
    double? kcalPer100g,
    double? proteinPer100g,
    double? carbPer100g,
    double? fatPer100g,
  }) {
    return FoodNutrition(
      name: name ?? this.name,
      kcalPer100g: kcalPer100g ?? this.kcalPer100g,
      proteinPer100g: proteinPer100g ?? this.proteinPer100g,
      carbPer100g: carbPer100g ?? this.carbPer100g,
      fatPer100g: fatPer100g ?? this.fatPer100g,
    );
  }
}

/// 一条饮食记录 = 食物 + 份量。营养值由份量换算得出，不单独存储。
class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.food,
    required this.grams,
    required this.meal,
    this.fromPhoto = false,
    this.portionUncertain = false,
  });

  final String id;
  final FoodNutrition food;
  final int grams;
  final MealType meal;

  /// 由拍照识别添加。
  final bool fromPhoto;

  /// AI 对份量把握不大，提示用户确认（识别结果页的「份量待确认」）。
  final bool portionUncertain;

  double get _ratio => grams / 100;

  int get kcal => (food.kcalPer100g * _ratio).round();

  double get protein => food.proteinPer100g * _ratio;

  double get carb => food.carbPer100g * _ratio;

  double get fat => food.fatPer100g * _ratio;

  FoodEntry copyWith({
    FoodNutrition? food,
    int? grams,
    MealType? meal,
    bool? portionUncertain,
  }) {
    return FoodEntry(
      id: id,
      food: food ?? this.food,
      grams: grams ?? this.grams,
      meal: meal ?? this.meal,
      fromPhoto: fromPhoto,
      portionUncertain: portionUncertain ?? this.portionUncertain,
    );
  }
}

/// 一组营养素合计。
class MacroSum {
  const MacroSum({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
  });

  static const zero = MacroSum(kcal: 0, protein: 0, carb: 0, fat: 0);

  final int kcal;
  final double protein;
  final double carb;
  final double fat;

  MacroSum operator +(FoodEntry e) => MacroSum(
        kcal: kcal + e.kcal,
        protein: protein + e.protein,
        carb: carb + e.carb,
        fat: fat + e.fat,
      );
}

/// 某一天的全部记录。
class DayLog {
  const DayLog({
    required this.date,
    this.entries = const [],
    this.waterMl = 0,
    this.trainingDayOverride,
  });

  final DateTime date;
  final List<FoodEntry> entries;
  final int waterMl;

  /// 用户把这天临时标成训练日或休息日，覆盖周计划（PRD R-016）。
  final bool? trainingDayOverride;

  List<FoodEntry> entriesOf(MealType meal) =>
      entries.where((e) => e.meal == meal).toList();

  MacroSum get totals => entries.fold(MacroSum.zero, (sum, e) => sum + e);

  MacroSum totalsOf(MealType meal) =>
      entriesOf(meal).fold(MacroSum.zero, (sum, e) => sum + e);

  /// 相对目标还剩多少 —— 首页最大的那个数字（可为负，表示已超出）。
  int remainingKcal(DayTargets targets) => targets.kcal - totals.kcal;

  DayLog copyWith({
    List<FoodEntry>? entries,
    int? waterMl,
    Object? trainingDayOverride = _unset,
  }) {
    return DayLog(
      date: date,
      entries: entries ?? this.entries,
      waterMl: waterMl ?? this.waterMl,
      trainingDayOverride: trainingDayOverride == _unset
          ? this.trainingDayOverride
          : trainingDayOverride as bool?,
    );
  }

  static const _unset = Object();
}
