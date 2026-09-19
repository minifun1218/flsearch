import 'dart:math' as math;

import 'models/food.dart';
import 'models/profile.dart';
import 'nutrition_calculator.dart';

/// How a recorded day's calories compare with that day's target.
enum DayStatus { missing, under, hit, over }

/// A single day in the trend window. Empty days are kept so the chart can
/// show a gap instead of silently turning a missing record into zero.
class TrendDay {
  const TrendDay({
    required this.date,
    required this.log,
    required this.targets,
  });

  final DateTime date;
  final DayLog? log;
  final DayTargets targets;

  bool get hasRecord => log != null && log!.entries.isNotEmpty;
  MacroSum get totals => log?.totals ?? MacroSum.zero;
  int get waterMl => log?.waterMl ?? 0;

  /// On target means calories inside the target ±10% band (R-046).
  DayStatus get status {
    if (!hasRecord) return DayStatus.missing;
    final kcal = totals.kcal;
    if (kcal < targets.kcal * 0.9) return DayStatus.under;
    if (kcal > targets.kcal * 1.1) return DayStatus.over;
    return DayStatus.hit;
  }
}

/// Averages for a subset of days, e.g. training days only. Training and rest
/// days have different targets, so one combined average hides which of the
/// two is off.
class DayGroupStats {
  DayGroupStats(Iterable<TrendDay> days) : days = List.unmodifiable(days);

  final List<TrendDay> days;

  List<TrendDay> get recorded => days.where((day) => day.hasRecord).toList();

  int get totalDays => days.length;
  int get loggedDays => recorded.length;
  int get hitDays =>
      recorded.where((day) => day.status == DayStatus.hit).length;
  int get hitRate => loggedDays == 0 ? 0 : (hitDays * 100 / loggedDays).round();

  double _average(double Function(TrendDay) value) {
    final days = recorded;
    if (days.isEmpty) return 0;
    return days.fold<double>(0, (sum, day) => sum + value(day)) / days.length;
  }

  int get averageKcal => _average((day) => day.totals.kcal.toDouble()).round();
  int get averageTargetKcal =>
      _average((day) => day.targets.kcal.toDouble()).round();
  double get averageCarb => _average((day) => day.totals.carb);
  double get averageTargetCarb =>
      _average((day) => day.targets.macros.carbG.toDouble());
}

/// One food aggregated over the window, for the "where did it come from" list.
class FoodTally {
  const FoodTally({
    required this.name,
    required this.times,
    required this.grams,
    required this.kcal,
    required this.protein,
  });

  final String name;
  final int times;
  final int grams;
  final int kcal;
  final double protein;
}

/// Values used by the statistics page. Keeping this calculation outside the
/// widget makes the definition of "recorded day" and "hit rate" explicit and
/// easy to verify when the in-memory store is replaced by a repository.
class TrendSnapshot {
  const TrendSnapshot(this.days, {required this.currentStreak});

  final List<TrendDay> days;
  final int currentStreak;

  Iterable<TrendDay> get recordedDays => days.where((day) => day.hasRecord);

  int get totalDays => days.length;
  int get loggedDays => recordedDays.length;
  int get missingDays => totalDays - loggedDays;

  DateTime get startDate => days.first.date;
  DateTime get endDate => days.last.date;

  int get averageKcal {
    if (loggedDays == 0) return 0;
    return (recordedDays.fold<int>(0, (sum, day) => sum + day.totals.kcal) /
            loggedDays)
        .round();
  }

  int get averageTargetKcal {
    if (loggedDays == 0) return 0;
    return (recordedDays.fold<int>(0, (sum, day) => sum + day.targets.kcal) /
            loggedDays)
        .round();
  }

  double _average(double Function(MacroSum) value) {
    if (loggedDays == 0) return 0;
    return recordedDays.fold<double>(0, (sum, day) => sum + value(day.totals)) /
        loggedDays;
  }

  double get averageProtein => _average((sum) => sum.protein);
  double get averageCarb => _average((sum) => sum.carb);
  double get averageFat => _average((sum) => sum.fat);

  double _target(double Function(MacroTargets) value) {
    if (loggedDays == 0) return 0;
    return recordedDays.fold<double>(
          0,
          (sum, day) => sum + value(day.targets.macros),
        ) /
        loggedDays;
  }

  double get targetProtein => _target((macros) => macros.proteinG.toDouble());
  double get targetCarb => _target((macros) => macros.carbG.toDouble());
  double get targetFat => _target((macros) => macros.fatG.toDouble());

  /// The denominator intentionally contains recorded days only (R-046).
  int get hitDays =>
      recordedDays.where((day) => day.status == DayStatus.hit).length;

  int get hitRate => loggedDays == 0 ? 0 : (hitDays * 100 / loggedDays).round();

  int countOf(DayStatus status) =>
      days.where((day) => day.status == status).length;

  DayGroupStats get trainingDays =>
      DayGroupStats(days.where((day) => day.targets.isTrainingDay));

  DayGroupStats get restDays =>
      DayGroupStats(days.where((day) => !day.targets.isTrainingDay));

  int get photoEntryPercent {
    final entries = recordedDays.expand((day) => day.log!.entries).toList();
    if (entries.isEmpty) return 0;
    final photoCount = entries.where((entry) => entry.fromPhoto).length;
    return (photoCount * 100 / entries.length).round();
  }

  /// Water is tracked on its own: a day with water but no food is still a
  /// missing food record, but its water counts here.
  Iterable<TrendDay> get waterDays => days.where((day) => day.waterMl > 0);

  int get waterLoggedDays => waterDays.length;

  int get averageWaterMl => waterLoggedDays == 0
      ? 0
      : (waterDays.fold<int>(0, (sum, day) => sum + day.waterMl) /
                waterLoggedDays)
            .round();

  int get averageWaterTargetMl => waterLoggedDays == 0
      ? 0
      : (waterDays.fold<int>(0, (sum, day) => sum + day.targets.waterMl) /
                waterLoggedDays)
            .round();

  int get waterHitDays =>
      waterDays.where((day) => day.waterMl >= day.targets.waterMl).length;

  /// Calories per meal summed over the window.
  Map<MealType, int> get mealKcal => {
    for (final meal in MealType.values)
      meal: recordedDays.fold<int>(
        0,
        (sum, day) => sum + day.log!.totalsOf(meal).kcal,
      ),
  };

  /// Foods ranked by total calories, or by total protein when [byProtein].
  List<FoodTally> topFoods({bool byProtein = false, int limit = 5}) {
    final tallies = <String, FoodTally>{};
    for (final entry in recordedDays.expand((day) => day.log!.entries)) {
      final previous = tallies[entry.food.name];
      tallies[entry.food.name] = FoodTally(
        name: entry.food.name,
        times: (previous?.times ?? 0) + 1,
        grams: (previous?.grams ?? 0) + entry.grams,
        kcal: (previous?.kcal ?? 0) + entry.kcal,
        protein: (previous?.protein ?? 0) + entry.protein,
      );
    }
    final ranked = tallies.values.toList()
      ..sort(
        (a, b) => byProtein
            ? b.protein.compareTo(a.protein)
            : b.kcal.compareTo(a.kcal),
      );
    return ranked.take(limit).toList();
  }

  /// Change of [value] against [previous]. Null when either window has no
  /// records — comparing with an empty week would only produce noise.
  double? deltaFrom(
    TrendSnapshot? previous,
    num Function(TrendSnapshot) value,
  ) {
    if (previous == null || loggedDays == 0 || previous.loggedDays == 0) {
      return null;
    }
    return (value(this) - value(previous)).toDouble();
  }
}

/// Intake against estimated burn, and the weight change it should have
/// produced next to the weight change that was actually measured.
class EnergyBalance {
  const EnergyBalance({
    required this.averageIntake,
    required this.estimatedBurn,
    required this.periodDays,
    required this.weights,
    this.startWeight,
    this.endWeight,
  });

  /// Average over recorded days; unrecorded days are assumed to look alike.
  final int averageIntake;

  /// TDEE from the current profile — an estimate, not a measurement.
  final int estimatedBurn;
  final int periodDays;

  /// Weigh-ins used for the comparison, oldest first.
  final List<({DateTime date, double kg})> weights;
  final ({DateTime date, double kg})? startWeight;
  final ({DateTime date, double kg})? endWeight;

  int get dailyBalance => averageIntake - estimatedBurn;

  bool get hasWeightChange =>
      startWeight != null &&
      endWeight != null &&
      endWeight!.date.isAfter(startWeight!.date);

  /// Days between the two weigh-ins, or the whole window when there are
  /// fewer than two. Expected change is scaled to the same span as the
  /// measured one so the two numbers are comparable.
  int get spanDays => hasWeightChange
      ? endWeight!.date.difference(startWeight!.date).inDays
      : periodDays;

  double get expectedChangeKg =>
      dailyBalance * spanDays / NutritionCalculator.kcalPerKg;

  double? get actualChangeKg =>
      hasWeightChange ? endWeight!.kg - startWeight!.kg : null;
}

abstract final class TrendCalculator {
  /// [today] anchors the current streak so browsing an older window still
  /// shows today's streak; it defaults to [endDate].
  static TrendSnapshot snapshot({
    required Map<String, DayLog> logs,
    required UserProfile profile,
    required DateTime endDate,
    required int range,
    DateTime? today,
  }) {
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final days = <TrendDay>[];
    for (var offset = range - 1; offset >= 0; offset--) {
      final date = end.subtract(Duration(days: offset));
      final log = logs[_dayKey(date)];
      days.add(
        TrendDay(
          date: date,
          log: log,
          targets: NutritionCalculator.targetsFor(
            profile,
            date,
            overrideTrainingDay: log?.trainingDayOverride,
          ),
        ),
      );
    }
    final anchor = today ?? endDate;
    var streak = 0;
    var streakDate = DateTime(anchor.year, anchor.month, anchor.day);
    while (logs[_dayKey(streakDate)]?.entries.isNotEmpty ?? false) {
      streak++;
      streakDate = streakDate.subtract(const Duration(days: 1));
    }
    return TrendSnapshot(List.unmodifiable(days), currentStreak: streak);
  }

  /// Null when nothing was recorded in the window.
  ///
  /// The starting weight may come from up to a week before the window, since
  /// people rarely weigh in exactly on its first day.
  static EnergyBalance? energyBalance({
    required TrendSnapshot snapshot,
    required UserProfile profile,
    required List<({DateTime date, double kg})> weights,
  }) {
    if (snapshot.loggedDays == 0) return null;
    final start = snapshot.startDate;
    final end = snapshot.endDate;
    final sorted = [...weights]..sort((a, b) => a.date.compareTo(b.date));
    final inside = sorted
        .where(
          (point) => !point.date.isBefore(start) && !point.date.isAfter(end),
        )
        .toList();
    final lookback = start.subtract(const Duration(days: 7));
    final before = sorted
        .where(
          (point) =>
              point.date.isBefore(start) && !point.date.isBefore(lookback),
        )
        .toList();
    final startWeight = before.isNotEmpty
        ? before.last
        : (inside.isNotEmpty ? inside.first : null);
    final endWeight = inside.isNotEmpty ? inside.last : null;
    final burn = NutritionCalculator.tdee(
      NutritionCalculator.bmr(
        sex: profile.sex,
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.ageOn(end),
        bodyFatPercent: profile.bodyFatPercent,
      ),
      profile.activityLevel,
    ).round();
    return EnergyBalance(
      averageIntake: snapshot.averageKcal,
      estimatedBurn: burn,
      periodDays: math.max(1, snapshot.totalDays),
      weights: [if (before.isNotEmpty) before.last, ...inside],
      startWeight: startWeight,
      endWeight: endWeight,
    );
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
