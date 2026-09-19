/// 生理性别 —— 只用于基础代谢公式。
enum Sex { male, female }

/// 日常活动水平（不含训练）。
enum ActivityLevel {
  sedentary('久坐', '办公室工作，几乎不走动', 1.2),
  light('轻度活动', '每天走动 30 分钟左右', 1.375),
  moderate('中度活动', '常走动或站立工作', 1.55),
  heavy('重体力', '体力劳动或长时间行走', 1.725);

  const ActivityLevel(this.label, this.description, this.factor);

  final String label;
  final String description;
  final double factor;
}

enum GoalType {
  cut('减脂', '在消耗基础上制造热量缺口'),
  bulk('增肌', '小幅热量盈余，配合高蛋白'),
  maintain('维持', '吃到消耗水平，保持现状');

  const GoalType(this.label, this.description);

  final String label;
  final String description;
}

enum TrainingType {
  strength('力量训练'),
  cardio('有氧为主'),
  mixed('力量 + 有氧');

  const TrainingType(this.label);

  final String label;
}

/// 每周训练计划。[days] 用 DateTime.monday..sunday（1..7）表示。
class TrainingPlan {
  const TrainingPlan({
    required this.days,
    this.type = TrainingType.strength,
    this.minutes = 60,
  });

  final Set<int> days;
  final TrainingType type;
  final int minutes;

  int get trainingDayCount => days.length;

  int get restDayCount => 7 - days.length;

  bool isTrainingDay(DateTime date) => days.contains(date.weekday);

  TrainingPlan copyWith({Set<int>? days, TrainingType? type, int? minutes}) {
    return TrainingPlan(
      days: days ?? this.days,
      type: type ?? this.type,
      minutes: minutes ?? this.minutes,
    );
  }
}

/// 用户档案。体脂率可空 —— 填了就换 Katch-McArdle 公式算 BMR。
class UserProfile {
  const UserProfile({
    required this.sex,
    required this.birthDate,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.plan,
    required this.goal,
    required this.targetWeightKg,
    required this.weeklyRateKg,
    this.bodyFatPercent,
    this.proteinPerKg = 1.8,
    this.fatPercentOfKcal = 25,
  });

  final Sex sex;
  final DateTime birthDate;
  final double heightCm;
  final double weightKg;
  final double? bodyFatPercent;
  final ActivityLevel activityLevel;
  final TrainingPlan plan;

  final GoalType goal;
  final double targetWeightKg;

  /// 每周期望体重变化，单位 kg，恒为正数；方向由 [goal] 决定。
  final double weeklyRateKg;

  /// 三大项分配策略：蛋白按体重给，脂肪按热量占比给，碳水填剩余。
  final double proteinPerKg;
  final double fatPercentOfKcal;

  int ageOn(DateTime date) {
    var age = date.year - birthDate.year;
    final hadBirthday = date.month > birthDate.month ||
        (date.month == birthDate.month && date.day >= birthDate.day);
    if (!hadBirthday) age -= 1;
    return age;
  }

  UserProfile copyWith({
    Sex? sex,
    DateTime? birthDate,
    double? heightCm,
    double? weightKg,
    Object? bodyFatPercent = _unset,
    ActivityLevel? activityLevel,
    TrainingPlan? plan,
    GoalType? goal,
    double? targetWeightKg,
    double? weeklyRateKg,
    double? proteinPerKg,
    double? fatPercentOfKcal,
  }) {
    return UserProfile(
      sex: sex ?? this.sex,
      birthDate: birthDate ?? this.birthDate,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      bodyFatPercent: bodyFatPercent == _unset
          ? this.bodyFatPercent
          : bodyFatPercent as double?,
      activityLevel: activityLevel ?? this.activityLevel,
      plan: plan ?? this.plan,
      goal: goal ?? this.goal,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      weeklyRateKg: weeklyRateKg ?? this.weeklyRateKg,
      proteinPerKg: proteinPerKg ?? this.proteinPerKg,
      fatPercentOfKcal: fatPercentOfKcal ?? this.fatPercentOfKcal,
    );
  }

  static const _unset = Object();
}
