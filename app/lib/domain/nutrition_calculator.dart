import 'dart:math' as math;

import 'models/profile.dart';

/// 三大项目标，单位克。
class MacroTargets {
  const MacroTargets({
    required this.proteinG,
    required this.carbG,
    required this.fatG,
  });

  final int proteinG;
  final int carbG;
  final int fatG;

  /// 三项折算回来的热量。与目标热量的差值应 ≤ 20 kcal（PRD R-011）。
  int get kcal => proteinG * 4 + carbG * 4 + fatG * 9;
}

/// 某一天的完整目标。
class DayTargets {
  const DayTargets({
    required this.kcal,
    required this.macros,
    required this.waterMl,
    required this.isTrainingDay,
  });

  final int kcal;
  final MacroTargets macros;
  final int waterMl;
  final bool isTrainingDay;
}

/// 计算链路的每一步，用于在「每日目标」页原样展示（PRD R-014）。
class TargetBreakdown {
  const TargetBreakdown({
    required this.bmr,
    required this.usedKatchMcArdle,
    required this.activityFactor,
    required this.tdee,
    required this.dailyDeltaKcal,
    required this.dailyKcal,
    required this.clampedToBmr,
    required this.trainingDayKcal,
    required this.restDayKcal,
  });

  final int bmr;

  /// true = 用了体脂率走 Katch-McArdle，false = Mifflin-St Jeor。
  final bool usedKatchMcArdle;
  final double activityFactor;
  final int tdee;

  /// 每日缺口（减脂为负）或盈余（增肌为正）。
  final int dailyDeltaKcal;

  /// 周日均目标热量。
  final int dailyKcal;

  /// 目标热量曾低于 BMR 被上调（PRD R-010 安全下限）。
  final bool clampedToBmr;

  final int trainingDayKcal;
  final int restDayKcal;
}

/// 营养目标计算。纯函数，不依赖任何框架 —— 便于单测覆盖 PRD 的验收标准。
abstract final class NutritionCalculator {
  /// 1 kg 体重对应的热量当量。
  static const kcalPerKg = 7700.0;

  /// 碳水周期化幅度。训练日上浮 [_cycleAmplitude] × 休息天数 / 7，
  /// 休息日下调 [_cycleAmplitude] × 训练天数 / 7，两者加权后周总量不变。
  /// 取 0.1867 时，4 训 3 休的训练日约比日均高 8%。
  static const _cycleAmplitude = 0.1867;

  /// 每公斤体重的日饮水量。
  static const _waterMlPerKg = 35.0;

  /// 训练日额外补水。
  static const _trainingWaterBonusMl = 500;

  /// 基础代谢。填了体脂率用 Katch-McArdle，否则用 Mifflin-St Jeor（PRD R-009）。
  static double bmr({
    required Sex sex,
    required double weightKg,
    required double heightCm,
    required int age,
    double? bodyFatPercent,
  }) {
    if (bodyFatPercent != null) {
      final leanMass = weightKg * (1 - bodyFatPercent / 100);
      return 370 + 21.6 * leanMass;
    }
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return sex == Sex.male ? base + 5 : base - 161;
  }

  /// 每日总消耗 = BMR × 活动系数（PRD R-010）。
  static double tdee(double bmr, ActivityLevel level) => bmr * level.factor;

  /// 三大项分配：蛋白按体重、脂肪按热量占比、碳水填剩余（PRD R-011）。
  ///
  /// [fatBasisKcal] 是脂肪占比所依据的热量，默认就是 [kcal]。做碳水周期化时
  /// 传日均热量，好让训练日和休息日的脂肪克数保持一致 —— 两天的差异应该
  /// 全部落在碳水上（PRD R-012），脂肪跟着当天热量浮动就不是周期化了。
  static MacroTargets macros({
    required int kcal,
    required double weightKg,
    required double proteinPerKg,
    required double fatPercentOfKcal,
    int? fatBasisKcal,
  }) {
    final protein = (weightKg * proteinPerKg).round();
    final fat = ((fatBasisKcal ?? kcal) * fatPercentOfKcal / 100 / 9).round();
    final carbKcal = kcal - protein * 4 - fat * 9;
    final carb = math.max(0, (carbKcal / 4).round());
    return MacroTargets(proteinG: protein, carbG: carb, fatG: fat);
  }

  /// 日饮水目标（PRD R-013）。
  static int waterMl({
    required double weightKg,
    required bool isTrainingDay,
  }) {
    final base = (weightKg * _waterMlPerKg).round();
    return isTrainingDay ? base + _trainingWaterBonusMl : base;
  }

  /// 走完整条链路，给出可展示的中间值（PRD R-009 ~ R-014）。
  static TargetBreakdown breakdown(UserProfile profile, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final basal = bmr(
      sex: profile.sex,
      weightKg: profile.weightKg,
      heightCm: profile.heightCm,
      age: profile.ageOn(today),
      bodyFatPercent: profile.bodyFatPercent,
    );
    final total = tdee(basal, profile.activityLevel);

    final perDayDelta = profile.weeklyRateKg * kcalPerKg / 7;
    final signed = switch (profile.goal) {
      GoalType.cut => -perDayDelta,
      GoalType.bulk => perDayDelta,
      GoalType.maintain => 0.0,
    };

    final raw = total + signed;
    // 安全下限：目标热量不得低于基础代谢。
    final clamped = raw < basal;
    final daily = (clamped ? basal : raw).round();

    final trainingDays = profile.plan.trainingDayCount;
    final restDays = profile.plan.restDayCount;

    // 碳水周期化：把热量往训练日挪，周总量守恒。
    final int trainKcal;
    final int restKcal;
    if (trainingDays == 0 || restDays == 0) {
      trainKcal = daily;
      restKcal = daily;
    } else {
      trainKcal = (daily * (1 + _cycleAmplitude * restDays / 7)).round();
      // 休息日由周总量反推，保证 (t×T + r×R) / 7 == daily。
      restKcal = ((daily * 7 - trainKcal * trainingDays) / restDays).round();
    }

    return TargetBreakdown(
      bmr: basal.round(),
      usedKatchMcArdle: profile.bodyFatPercent != null,
      activityFactor: profile.activityLevel.factor,
      tdee: total.round(),
      dailyDeltaKcal: signed.round(),
      dailyKcal: daily,
      clampedToBmr: clamped,
      trainingDayKcal: trainKcal,
      restDayKcal: restKcal,
    );
  }

  /// 指定日期的目标。训练日与休息日取不同热量，蛋白和脂肪不变，差异落在碳水上。
  static DayTargets targetsFor(
    UserProfile profile,
    DateTime date, {
    bool? overrideTrainingDay,
  }) {
    final isTraining =
        overrideTrainingDay ?? profile.plan.isTrainingDay(date);
    final parts = breakdown(profile, now: date);
    final kcal = isTraining ? parts.trainingDayKcal : parts.restDayKcal;

    return DayTargets(
      kcal: kcal,
      macros: macros(
        kcal: kcal,
        weightKg: profile.weightKg,
        proteinPerKg: profile.proteinPerKg,
        fatPercentOfKcal: profile.fatPercentOfKcal,
        // 脂肪按日均算，训练日和休息日一致。
        fatBasisKcal: parts.dailyKcal,
      ),
      waterMl: waterMl(weightKg: profile.weightKg, isTrainingDay: isTraining),
      isTrainingDay: isTraining,
    );
  }
}
