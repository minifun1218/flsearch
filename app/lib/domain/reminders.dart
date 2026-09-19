import 'models/food.dart';
import 'nutrition_calculator.dart';

/// 提醒的排程逻辑（PRD R-033 ~ R-039）。
///
/// 纯计算，不碰通知插件也不碰 Flutter：什么时候提醒、提醒什么内容，全在这里
/// 算好，平台那层只负责把算出来的清单挂到系统上。PRD 的验收标准因此能逐条单测。

/// 一天里的一个时刻。不用 Flutter 的 TimeOfDay —— 这一层要保持纯 Dart。
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  DateTime onDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ClockTime plusMinutes(int minutes) {
    final total = (minutesOfDay + minutes) % (24 * 60);
    return ClockTime(total ~/ 60, total % 60);
  }

  @override
  int compareTo(ClockTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => minutesOfDay;

  Map<String, int> toJson() => {'h': hour, 'm': minute};

  static ClockTime fromJson(Object? json, ClockTime fallback) {
    if (json is! Map) return fallback;
    final h = (json['h'] as num?)?.toInt();
    final m = (json['m'] as num?)?.toInt();
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return fallback;
    }
    return ClockTime(h, m);
  }
}

enum ReminderKind {
  /// 每日进度检查：热量或蛋白不足就提醒（R-034）。
  dailyCheck('进度检查'),

  /// 当日热量超标（R-036）。不排程 —— 保存记录时立刻发。
  overLimit('超标提醒'),

  /// 某餐过点还没记（R-037）。
  missedMeal('漏记提醒'),

  /// 饮水（R-038）。
  water('饮水提醒'),

  /// 每周称重（R-033）。
  weighIn('称重提醒');

  const ReminderKind(this.label);

  final String label;
}

/// 免打扰时段。可以跨零点（22:00–07:00）。
class QuietHours {
  const QuietHours({
    this.enabled = true,
    this.start = const ClockTime(22, 0),
    this.end = const ClockTime(7, 0),
  });

  final bool enabled;
  final ClockTime start;
  final ClockTime end;

  bool covers(DateTime moment) {
    if (!enabled) return false;
    final minutes = moment.hour * 60 + moment.minute;
    final from = start.minutesOfDay;
    final to = end.minutesOfDay;
    // 跨零点时，落在 [start, 24:00) ∪ [00:00, end) 里都算。
    return from <= to
        ? minutes >= from && minutes < to
        : minutes >= from || minutes < to;
  }

  QuietHours copyWith({bool? enabled, ClockTime? start, ClockTime? end}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        start: start ?? this.start,
        end: end ?? this.end,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'start': start.toJson(),
        'end': end.toJson(),
      };

  static QuietHours fromJson(Object? json) {
    const fallback = QuietHours();
    if (json is! Map) return fallback;
    return QuietHours(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : fallback.enabled,
      start: ClockTime.fromJson(json['start'], fallback.start),
      end: ClockTime.fromJson(json['end'], fallback.end),
    );
  }
}

/// 一个餐次的时间窗，用来判断「过点没记」。
class MealWindow {
  const MealWindow({required this.start, required this.end});

  final ClockTime start;
  final ClockTime end;

  Map<String, dynamic> toJson() => {'start': start.toJson(), 'end': end.toJson()};

  static MealWindow fromJson(Object? json, MealWindow fallback) {
    if (json is! Map) return fallback;
    return MealWindow(
      start: ClockTime.fromJson(json['start'], fallback.start),
      end: ClockTime.fromJson(json['end'], fallback.end),
    );
  }
}

/// 提醒设置。每类可独立开关、可调时间（R-039）。
class ReminderSettings {
  const ReminderSettings({
    this.dailyCheckEnabled = true,
    this.dailyCheckAt = const ClockTime(20, 0),
    this.shortfallRatio = 0.8,
    this.overLimitEnabled = true,
    this.overLimitRatio = 1.1,
    this.missedMealEnabled = false,
    this.missedMealGraceMinutes = 60,
    this.mealWindows = defaultMealWindows,
    this.waterEnabled = false,
    this.waterIntervalHours = 2,
    this.waterStart = const ClockTime(8, 0),
    this.waterEnd = const ClockTime(22, 0),
    this.weighInEnabled = false,
    this.weighInWeekday = DateTime.sunday,
    this.weighInAt = const ClockTime(9, 0),
    this.quietHours = const QuietHours(),
  });

  /// 早中晚三餐的默认时间窗。加餐不提醒 —— 本来就不是非吃不可的一顿。
  static const defaultMealWindows = <MealType, MealWindow>{
    MealType.breakfast:
        MealWindow(start: ClockTime(6, 30), end: ClockTime(9, 30)),
    MealType.lunch: MealWindow(start: ClockTime(11, 0), end: ClockTime(13, 0)),
    MealType.dinner: MealWindow(start: ClockTime(17, 0), end: ClockTime(20, 0)),
  };

  // R-034
  final bool dailyCheckEnabled;
  final ClockTime dailyCheckAt;

  /// 低于目标的这个比例才提醒。0.8 = 目标的 80%。
  final double shortfallRatio;

  // R-036
  final bool overLimitEnabled;
  final double overLimitRatio;

  // R-037
  final bool missedMealEnabled;
  final int missedMealGraceMinutes;
  final Map<MealType, MealWindow> mealWindows;

  // R-038
  final bool waterEnabled;
  final int waterIntervalHours;
  final ClockTime waterStart;
  final ClockTime waterEnd;

  // R-033
  final bool weighInEnabled;
  final int weighInWeekday;
  final ClockTime weighInAt;

  // R-039
  final QuietHours quietHours;

  bool get anyEnabled =>
      dailyCheckEnabled ||
      overLimitEnabled ||
      missedMealEnabled ||
      waterEnabled ||
      weighInEnabled;

  ReminderSettings copyWith({
    bool? dailyCheckEnabled,
    ClockTime? dailyCheckAt,
    double? shortfallRatio,
    bool? overLimitEnabled,
    double? overLimitRatio,
    bool? missedMealEnabled,
    int? missedMealGraceMinutes,
    Map<MealType, MealWindow>? mealWindows,
    bool? waterEnabled,
    int? waterIntervalHours,
    ClockTime? waterStart,
    ClockTime? waterEnd,
    bool? weighInEnabled,
    int? weighInWeekday,
    ClockTime? weighInAt,
    QuietHours? quietHours,
  }) {
    return ReminderSettings(
      dailyCheckEnabled: dailyCheckEnabled ?? this.dailyCheckEnabled,
      dailyCheckAt: dailyCheckAt ?? this.dailyCheckAt,
      shortfallRatio: shortfallRatio ?? this.shortfallRatio,
      overLimitEnabled: overLimitEnabled ?? this.overLimitEnabled,
      overLimitRatio: overLimitRatio ?? this.overLimitRatio,
      missedMealEnabled: missedMealEnabled ?? this.missedMealEnabled,
      missedMealGraceMinutes:
          missedMealGraceMinutes ?? this.missedMealGraceMinutes,
      mealWindows: mealWindows ?? this.mealWindows,
      waterEnabled: waterEnabled ?? this.waterEnabled,
      waterIntervalHours: waterIntervalHours ?? this.waterIntervalHours,
      waterStart: waterStart ?? this.waterStart,
      waterEnd: waterEnd ?? this.waterEnd,
      weighInEnabled: weighInEnabled ?? this.weighInEnabled,
      weighInWeekday: weighInWeekday ?? this.weighInWeekday,
      weighInAt: weighInAt ?? this.weighInAt,
      quietHours: quietHours ?? this.quietHours,
    );
  }

  Map<String, dynamic> toJson() => {
        'daily_check_enabled': dailyCheckEnabled,
        'daily_check_at': dailyCheckAt.toJson(),
        'shortfall_ratio': shortfallRatio,
        'over_limit_enabled': overLimitEnabled,
        'over_limit_ratio': overLimitRatio,
        'missed_meal_enabled': missedMealEnabled,
        'missed_meal_grace_minutes': missedMealGraceMinutes,
        'meal_windows': {
          for (final entry in mealWindows.entries)
            entry.key.name: entry.value.toJson(),
        },
        'water_enabled': waterEnabled,
        'water_interval_hours': waterIntervalHours,
        'water_start': waterStart.toJson(),
        'water_end': waterEnd.toJson(),
        'weigh_in_enabled': weighInEnabled,
        'weigh_in_weekday': weighInWeekday,
        'weigh_in_at': weighInAt.toJson(),
        'quiet_hours': quietHours.toJson(),
      };

  static ReminderSettings fromJson(Object? json) {
    const fallback = ReminderSettings();
    if (json is! Map) return fallback;

    final windows = <MealType, MealWindow>{};
    final rawWindows = json['meal_windows'];
    for (final entry in defaultMealWindows.entries) {
      windows[entry.key] = MealWindow.fromJson(
        rawWindows is Map ? rawWindows[entry.key.name] : null,
        entry.value,
      );
    }

    return ReminderSettings(
      dailyCheckEnabled:
          _bool(json['daily_check_enabled'], fallback.dailyCheckEnabled),
      dailyCheckAt:
          ClockTime.fromJson(json['daily_check_at'], fallback.dailyCheckAt),
      shortfallRatio:
          _double(json['shortfall_ratio'], fallback.shortfallRatio),
      overLimitEnabled:
          _bool(json['over_limit_enabled'], fallback.overLimitEnabled),
      overLimitRatio: _double(json['over_limit_ratio'], fallback.overLimitRatio),
      missedMealEnabled:
          _bool(json['missed_meal_enabled'], fallback.missedMealEnabled),
      missedMealGraceMinutes: _int(
          json['missed_meal_grace_minutes'], fallback.missedMealGraceMinutes),
      mealWindows: windows,
      waterEnabled: _bool(json['water_enabled'], fallback.waterEnabled),
      waterIntervalHours:
          _int(json['water_interval_hours'], fallback.waterIntervalHours),
      waterStart: ClockTime.fromJson(json['water_start'], fallback.waterStart),
      waterEnd: ClockTime.fromJson(json['water_end'], fallback.waterEnd),
      weighInEnabled: _bool(json['weigh_in_enabled'], fallback.weighInEnabled),
      weighInWeekday: _int(json['weigh_in_weekday'], fallback.weighInWeekday),
      weighInAt: ClockTime.fromJson(json['weigh_in_at'], fallback.weighInAt),
      quietHours: QuietHours.fromJson(json['quiet_hours']),
    );
  }

  // 存档可能是旧版本写的，也可能被人手改坏了 —— 读不出来就退回默认值，不抛。
  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static int _int(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;

  static double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;
}

/// 排好的一条提醒。
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
  });

  /// 系统通知 id。同一类同一时刻算出来的 id 固定，重排不会留下孤儿。
  final int id;
  final ReminderKind kind;
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => '${kind.name}@${at.toIso8601String()} $title';
}

/// 排程要用到的当天数据。
typedef DaySnapshot = ({DayLog? log, DayTargets targets});

abstract final class ReminderPlanner {
  /// 往后排几天。
  ///
  /// 没有后台任务，排程只能在应用还活着的时候做一次 —— 多排几天，用户几天不开
  /// 应用也还有提醒。每次数据变化或应用回到前台都会重排，内容因此不会太旧。
  static const horizonDays = 3;

  /// 算出接下来要挂的全部提醒。
  ///
  /// [snapshotFor] 给出某一天的记录与目标；未来的日子自然没有记录，
  /// 那正是「没开应用就没记东西」的真实状态。
  /// [lastWeightAt] 是最近一次称重的日期，用来判断本周是否已经称过。
  static List<PlannedReminder> plan({
    required ReminderSettings settings,
    required DateTime now,
    required DaySnapshot Function(DateTime day) snapshotFor,
    DateTime? lastWeightAt,
    int horizon = horizonDays,
  }) {
    final out = <PlannedReminder>[];

    for (var offset = 0; offset < horizon; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      final snapshot = snapshotFor(day);

      if (settings.dailyCheckEnabled) {
        final reminder = _dailyCheck(settings, day, snapshot);
        if (reminder != null) out.add(reminder);
      }
      if (settings.missedMealEnabled) {
        out.addAll(_missedMeals(settings, day, snapshot));
      }
      if (settings.waterEnabled) {
        out.addAll(_water(settings, day, snapshot));
      }
      if (settings.weighInEnabled) {
        final reminder = _weighIn(settings, day, lastWeightAt);
        if (reminder != null) out.add(reminder);
      }
    }

    // 已经过去的不排；免打扰时段内的直接丢掉，时段结束也不补发（R-039）。
    final kept = out
        .where((r) => r.at.isAfter(now) && !settings.quietHours.covers(r.at))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return kept;
  }

  /// 保存记录后立刻判断要不要发超标提醒（R-036）。超了返回文案，没超返回 null。
  static String? overLimitMessage({
    required ReminderSettings settings,
    required DayTargets targets,
    required MacroSum totals,
    required DateTime now,
  }) {
    if (!settings.overLimitEnabled || targets.kcal <= 0) return null;
    if (settings.quietHours.covers(now)) return null;

    final limit = (targets.kcal * settings.overLimitRatio).round();
    if (totals.kcal <= limit) return null;

    final over = totals.kcal - targets.kcal;
    final percent = (totals.kcal / targets.kcal * 100).round();
    return '今天已摄入 ${totals.kcal} kcal，是目标的 $percent%，超出 $over kcal。'
        '晚点的餐次可以少一些，或者加一次训练。';
  }

  // ---------------------------------------------------------------- 各类

  static PlannedReminder? _dailyCheck(
    ReminderSettings settings,
    DateTime day,
    DaySnapshot snapshot,
  ) {
    final totals = snapshot.log?.totals ?? MacroSum.zero;
    final targets = snapshot.targets;
    if (targets.kcal <= 0) return null;

    final kcalRatio = totals.kcal / targets.kcal;
    final proteinTarget = targets.macros.proteinG;
    final proteinRatio =
        proteinTarget <= 0 ? 1.0 : totals.protein / proteinTarget;

    // 热量和蛋白，任意一项不足就提醒（R-034）。
    if (kcalRatio >= settings.shortfallRatio &&
        proteinRatio >= settings.shortfallRatio) {
      return null;
    }

    final kcalLeft = targets.kcal - totals.kcal;
    final proteinLeft = proteinTarget - totals.protein;
    final parts = <String>[
      if (kcalLeft > 0) '$kcalLeft kcal',
      if (proteinLeft > 0) '${proteinLeft.round()} g 蛋白质',
    ];

    return PlannedReminder(
      id: _id(ReminderKind.dailyCheck, day, 0),
      kind: ReminderKind.dailyCheck,
      at: settings.dailyCheckAt.onDay(day),
      title: '今天还差一点',
      body: parts.isEmpty
          ? '今天的记录还不完整，点开看看。'
          : '距离今天的目标还差 ${parts.join(' 和 ')}。',
    );
  }

  static List<PlannedReminder> _missedMeals(
    ReminderSettings settings,
    DateTime day,
    DaySnapshot snapshot,
  ) {
    final out = <PlannedReminder>[];
    for (final entry in settings.mealWindows.entries) {
      final meal = entry.key;
      // 这一餐已经记过就不提醒。
      if (snapshot.log?.entriesOf(meal).isNotEmpty ?? false) continue;

      final fireAt = entry.value.end
          .plusMinutes(settings.missedMealGraceMinutes)
          .onDay(day);
      out.add(PlannedReminder(
        id: _id(ReminderKind.missedMeal, day, meal.index),
        kind: ReminderKind.missedMeal,
        at: fireAt,
        title: '${meal.label}还没记',
        body: '补记一下${meal.label}吧，隔太久就想不起来吃了什么了。',
      ));
    }
    return out;
  }

  static List<PlannedReminder> _water(
    ReminderSettings settings,
    DateTime day,
    DaySnapshot snapshot,
  ) {
    final interval = settings.waterIntervalHours.clamp(1, 12);
    final start = settings.waterStart.minutesOfDay;
    final end = settings.waterEnd.minutesOfDay;
    if (end <= start) return const [];

    final out = <PlannedReminder>[];
    var slot = 0;
    // 活动时段内每隔 interval 小时一次；时段结束之后不再发（R-038）。
    for (var minutes = start; minutes < end; minutes += interval * 60) {
      final at = DateTime(day.year, day.month, day.day, 0, minutes);
      out.add(PlannedReminder(
        id: _id(ReminderKind.water, day, slot),
        kind: ReminderKind.water,
        at: at,
        title: '喝点水',
        body: snapshot.log == null
            ? '今天的饮水目标 ${snapshot.targets.waterMl} ml。'
            : '今天喝了 ${snapshot.log!.waterMl} / ${snapshot.targets.waterMl} ml。',
      ));
      slot++;
    }
    return out;
  }

  static PlannedReminder? _weighIn(
    ReminderSettings settings,
    DateTime day,
    DateTime? lastWeightAt,
  ) {
    if (day.weekday != settings.weighInWeekday) return null;
    // 这一周已经称过就不提醒（R-033）。
    if (lastWeightAt != null && _sameWeek(lastWeightAt, day)) return null;

    return PlannedReminder(
      id: _id(ReminderKind.weighIn, day, 0),
      kind: ReminderKind.weighIn,
      at: settings.weighInAt.onDay(day),
      title: '该称体重了',
      body: '早上空腹称一次，趋势比单点数字更有用。',
    );
  }

  /// 周一为一周之始。
  static bool _sameWeek(DateTime a, DateTime b) {
    DateTime mondayOf(DateTime d) =>
        DateTime(d.year, d.month, d.day - (d.weekday - 1));
    return mondayOf(a) == mondayOf(b);
  }

  /// 通知 id：类别 + 日期 + 槽位，稳定且不串。
  static int _id(ReminderKind kind, DateTime day, int slot) {
    final dayKey = day.year % 100 * 10000 + day.month * 100 + day.day;
    return kind.index * 100000000 + dayKey * 100 + slot;
  }
}
