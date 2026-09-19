import 'package:fitmeal/domain/models/profile.dart';
import 'package:fitmeal/domain/nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用例直接取自 docs/01-prd.md 的验收标准（R-009 ~ R-013）。
/// 基准人物：男，1995-03-01 生（2026-09-16 为 31 岁），175cm，72.5kg，
/// 中度活动，减脂，目标 68kg，每周 0.5kg，周一三五六训练。
void main() {
  final on = DateTime(2026, 9, 16); // 周三
  final birth = DateTime(1995, 3, 1);

  UserProfile profileWith({
    double? bodyFat,
    GoalType goal = GoalType.cut,
    double rate = 0.5,
    Set<int> days = const {1, 3, 5, 6},
    double proteinPerKg = 1.8,
    double fatPct = 25,
  }) {
    return UserProfile(
      sex: Sex.male,
      birthDate: birth,
      heightCm: 175,
      weightKg: 72.5,
      bodyFatPercent: bodyFat,
      activityLevel: ActivityLevel.moderate,
      plan: TrainingPlan(days: days),
      goal: goal,
      targetWeightKg: 68,
      weeklyRateKg: rate,
      proteinPerKg: proteinPerKg,
      fatPercentOfKcal: fatPct,
    );
  }

  group('R-009 基础代谢', () {
    test('未填体脂率走 Mifflin-St Jeor，得 1669 kcal', () {
      final bmr = NutritionCalculator.bmr(
        sex: Sex.male,
        weightKg: 72.5,
        heightCm: 175,
        age: 31,
      );
      expect(bmr, closeTo(1669, 1));
    });

    test('填了体脂率改走 Katch-McArdle，得 1654 kcal', () {
      final bmr = NutritionCalculator.bmr(
        sex: Sex.male,
        weightKg: 72.5,
        heightCm: 175,
        age: 31,
        bodyFatPercent: 18,
      );
      expect(bmr, closeTo(1654, 1));
    });

    test('女性用 −161 分支', () {
      final male = NutritionCalculator.bmr(
        sex: Sex.male,
        weightKg: 72.5,
        heightCm: 175,
        age: 31,
      );
      final female = NutritionCalculator.bmr(
        sex: Sex.female,
        weightKg: 72.5,
        heightCm: 175,
        age: 31,
      );
      expect(male - female, closeTo(166, 0.001));
    });

    test('体脂率一填，链路即标注换了公式', () {
      expect(
        NutritionCalculator.breakdown(profileWith(), now: on).usedKatchMcArdle,
        isFalse,
      );
      expect(
        NutritionCalculator.breakdown(profileWith(bodyFat: 18), now: on)
            .usedKatchMcArdle,
        isTrue,
      );
    });
  });

  group('R-010 TDEE 与目标热量', () {
    test('TDEE = BMR × 1.55 = 2587', () {
      final parts = NutritionCalculator.breakdown(profileWith(), now: on);
      expect(parts.bmr, closeTo(1669, 1));
      expect(parts.tdee, closeTo(2587, 2));
    });

    test('每周 0.5kg 对应每日 550 kcal 缺口，日均目标 2037', () {
      final parts = NutritionCalculator.breakdown(profileWith(), now: on);
      expect(parts.dailyDeltaKcal, closeTo(-550, 1));
      expect(parts.dailyKcal, closeTo(2037, 2));
      expect(parts.clampedToBmr, isFalse);
    });

    test('增肌方向为盈余', () {
      final parts = NutritionCalculator.breakdown(
        profileWith(goal: GoalType.bulk, rate: 0.25),
        now: on,
      );
      expect(parts.dailyDeltaKcal, greaterThan(0));
      expect(parts.dailyKcal, greaterThan(parts.tdee));
    });

    test('维持不加不减', () {
      final parts = NutritionCalculator.breakdown(
        profileWith(goal: GoalType.maintain),
        now: on,
      );
      expect(parts.dailyDeltaKcal, 0);
      expect(parts.dailyKcal, parts.tdee);
    });

    test('速率过于激进时锁到 BMR，并标记已兜底', () {
      // 每周 1.0kg → 每日 1100 kcal 缺口 → 2587 − 1100 = 1487 < BMR 1669
      final parts = NutritionCalculator.breakdown(
        profileWith(rate: 1.0),
        now: on,
      );
      expect(parts.clampedToBmr, isTrue);
      expect(parts.dailyKcal, parts.bmr);
    });
  });

  group('R-011 三大项分配', () {
    test('2037 kcal / 72.5kg / 1.8 g·kg / 25% → 131 · 250 · 57', () {
      final m = NutritionCalculator.macros(
        kcal: 2037,
        weightKg: 72.5,
        proteinPerKg: 1.8,
        fatPercentOfKcal: 25,
      );
      expect(m.proteinG, closeTo(131, 2));
      expect(m.carbG, closeTo(250, 2));
      expect(m.fatG, closeTo(57, 2));
    });

    test('三项折算热量与目标差值 ≤ 20 kcal', () {
      for (final kcal in [1600, 1820, 2037, 2200, 2800]) {
        for (final perKg in [1.2, 1.8, 2.2, 2.4]) {
          for (final fatPct in [15.0, 25.0, 35.0]) {
            final m = NutritionCalculator.macros(
              kcal: kcal,
              weightKg: 72.5,
              proteinPerKg: perKg,
              fatPercentOfKcal: fatPct,
            );
            expect(
              (m.kcal - kcal).abs(),
              lessThanOrEqualTo(20),
              reason: 'kcal=$kcal perKg=$perKg fat=$fatPct → ${m.kcal}',
            );
          }
        }
      }
    });

    test('蛋白系数调到 2.2 得 160g，碳水相应减少', () {
      final base = NutritionCalculator.macros(
        kcal: 2037,
        weightKg: 72.5,
        proteinPerKg: 1.8,
        fatPercentOfKcal: 25,
      );
      final high = NutritionCalculator.macros(
        kcal: 2037,
        weightKg: 72.5,
        proteinPerKg: 2.2,
        fatPercentOfKcal: 25,
      );
      expect(high.proteinG, closeTo(160, 2));
      expect(high.carbG, lessThan(base.carbG));
    });

    test('碳水不会被算成负数', () {
      final m = NutritionCalculator.macros(
        kcal: 1200,
        weightKg: 120,
        proteinPerKg: 2.4,
        fatPercentOfKcal: 40,
      );
      expect(m.carbG, greaterThanOrEqualTo(0));
    });
  });

  group('R-012 碳水周期化', () {
    test('训练日高于休息日，且周加权平均回到日均', () {
      final profile = profileWith();
      final parts = NutritionCalculator.breakdown(profile, now: on);

      expect(parts.trainingDayKcal, greaterThan(parts.restDayKcal));
      expect(parts.trainingDayKcal, closeTo(2200, 15));
      expect(parts.restDayKcal, closeTo(1820, 15));

      final weekTotal = parts.trainingDayKcal * profile.plan.trainingDayCount +
          parts.restDayKcal * profile.plan.restDayCount;
      expect(weekTotal / 7, closeTo(parts.dailyKcal, 2));
    });

    test('任意训练天数下周总量都守恒', () {
      for (var n = 1; n <= 6; n++) {
        final days = {for (var d = 1; d <= n; d++) d};
        final profile = profileWith(days: days);
        final parts = NutritionCalculator.breakdown(profile, now: on);
        final weekTotal =
            parts.trainingDayKcal * n + parts.restDayKcal * (7 - n);
        expect(
          weekTotal / 7,
          closeTo(parts.dailyKcal, 2),
          reason: '训练 $n 天时不守恒',
        );
      }
    });

    test('一天都不练时两套目标相同', () {
      final parts = NutritionCalculator.breakdown(
        profileWith(days: const {}),
        now: on,
      );
      expect(parts.trainingDayKcal, parts.restDayKcal);
    });

    test('差异全部落在碳水上，蛋白与脂肪两天完全一致', () {
      final profile = profileWith();
      final train = NutritionCalculator.targetsFor(
        profile,
        DateTime(2026, 9, 16), // 周三，训练日
      );
      final rest = NutritionCalculator.targetsFor(
        profile,
        DateTime(2026, 9, 17), // 周四，休息日
      );

      expect(train.isTrainingDay, isTrue);
      expect(rest.isTrainingDay, isFalse);
      expect(train.macros.proteinG, rest.macros.proteinG);
      expect(train.macros.fatG, rest.macros.fatG);
      expect(train.macros.carbG, greaterThan(rest.macros.carbG));
    });

    test('基准人物的两套目标与设计稿一致：2200/131/291/57 与 1820/131/196/57',
        () {
      final profile = profileWith();
      final train =
          NutritionCalculator.targetsFor(profile, DateTime(2026, 9, 16));
      final rest =
          NutritionCalculator.targetsFor(profile, DateTime(2026, 9, 17));

      expect(train.kcal, 2200);
      expect(train.macros.proteinG, 131);
      expect(train.macros.carbG, 291);
      expect(train.macros.fatG, 57);
      expect(train.waterMl, 3038);

      expect(rest.kcal, 1820);
      expect(rest.macros.proteinG, 131);
      expect(rest.macros.carbG, 196);
      expect(rest.macros.fatG, 57);
      expect(rest.waterMl, 2538);
    });

    test('可以临时把某天覆盖成训练日', () {
      final profile = profileWith();
      final thursday = DateTime(2026, 9, 17);
      final normal = NutritionCalculator.targetsFor(profile, thursday);
      final overridden = NutritionCalculator.targetsFor(
        profile,
        thursday,
        overrideTrainingDay: true,
      );
      expect(normal.isTrainingDay, isFalse);
      expect(overridden.isTrainingDay, isTrue);
      expect(overridden.kcal, greaterThan(normal.kcal));
    });
  });

  group('R-013 饮水目标', () {
    test('休息日 2538ml，训练日 3038ml', () {
      expect(
        NutritionCalculator.waterMl(weightKg: 72.5, isTrainingDay: false),
        closeTo(2538, 50),
      );
      expect(
        NutritionCalculator.waterMl(weightKg: 72.5, isTrainingDay: true),
        closeTo(3038, 50),
      );
    });
  });

  group('年龄计算', () {
    test('生日未过按上一岁算', () {
      final p = profileWith();
      expect(p.ageOn(DateTime(2026, 9, 16)), 31);
      expect(p.ageOn(DateTime(2026, 2, 28)), 30);
      expect(p.ageOn(DateTime(2026, 3, 1)), 31);
    });
  });
}
