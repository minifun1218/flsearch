import '../domain/models/food.dart';
import '../domain/models/profile.dart';
import 'app_state.dart';
import 'repository.dart';
import 'seed_data.dart';

/// 内存实现，不连服务端。
///
/// 两处在用：widget 测试，以及 `--dart-define=FITMEAL_DEMO=true` 启动的
/// 设计走查包 —— 没有服务端也能把每一屏点完。数据是 [SeedData] 那份确定性
/// 假数据，所以截图和测试断言都稳定。
class DemoRepository implements FitMealRepository {
  DemoRepository({DateTime? today, UserProfile? profile})
      : _today = dayOf(today ?? DateTime.now()) {
    _profile = profile ?? demoProfile;
    _days = {
      ...SeedData.history(_today, _nextId),
      dayKey(_today): SeedData.today(_today, _nextId),
    };
    _weights = {...SeedData.weights(_today)};
  }

  /// 设计稿里那位用户，也是 PRD 验收标准反复引用的那份档案。
  static final demoProfile = UserProfile(
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

  final DateTime _today;
  late UserProfile _profile;
  late Map<String, DayLog> _days;
  late Map<String, double> _weights;
  final _foods = <String, FoodNutrition>{
    for (final f in FoodLibrary.all) f.name: f,
  };

  var _seq = 0;

  String _nextId() => 'e${_seq++}';

  DayLog _logFor(DateTime date) => _days[dayKey(date)] ?? DayLog(date: dayOf(date));

  DayLog _put(DayLog log) => _days[dayKey(log.date)] = log;

  @override
  Future<bool> restoreSession() async => true;

  @override
  Future<void> register({required String email, required String password}) async {}

  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<UserProfile?> loadProfile() async => _profile;

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async =>
      _profile = profile;

  @override
  Future<List<DayLog>> loadDays(DateTime from, DateTime to) async {
    final out = <DayLog>[];
    for (var d = dayOf(from); !d.isAfter(dayOf(to)); d = d.add(const Duration(days: 1))) {
      out.add(_logFor(d));
    }
    return out;
  }

  @override
  Future<DayLog> loadDay(DateTime date) async => _logFor(date);

  @override
  Future<DayLog> addEntries(DateTime date, List<FoodEntry> entries) async {
    final log = _logFor(date);
    return _put(log.copyWith(entries: [
      ...log.entries,
      for (final e in entries)
        FoodEntry(
          id: _nextId(),
          food: e.food,
          grams: e.grams,
          meal: e.meal,
          fromPhoto: e.fromPhoto,
          portionUncertain: e.portionUncertain,
        ),
    ]));
  }

  @override
  Future<DayLog> updateEntry(
    DateTime date,
    FoodEntry entry, {
    DateTime? newDate,
    bool updateFoodCache = false,
  }) async {
    if (updateFoodCache) _foods[entry.food.name] = entry.food;

    final log = _logFor(date);
    if (newDate != null && dayKey(newDate) != dayKey(date)) {
      _put(log.copyWith(
        entries: log.entries.where((e) => e.id != entry.id).toList(),
      ));
      final target = _logFor(newDate);
      return _put(target.copyWith(entries: [...target.entries, entry]));
    }
    return _put(log.copyWith(
      entries: [
        for (final e in log.entries) e.id == entry.id ? entry : e,
      ],
    ));
  }

  @override
  Future<DayLog> removeEntry(DateTime date, String entryId) async {
    final log = _logFor(date);
    return _put(log.copyWith(
      entries: log.entries.where((e) => e.id != entryId).toList(),
    ));
  }

  @override
  Future<DayLog> pourWater(DateTime date, int ml) async {
    final log = _logFor(date);
    _pours.putIfAbsent(dayKey(date), () => []).add(ml);
    return _put(log.copyWith(waterMl: (log.waterMl + ml).clamp(0, 10000)));
  }

  final _pours = <String, List<int>>{};

  @override
  Future<DayLog> undoWater(DateTime date) async {
    final log = _logFor(date);
    final pours = _pours[dayKey(date)];
    // 没有本次会话记的那几次，就按一杯 200 ml 退 —— 假数据里的存量没有明细。
    final last = (pours == null || pours.isEmpty) ? 200 : pours.removeLast();
    return _put(log.copyWith(waterMl: (log.waterMl - last).clamp(0, 10000)));
  }

  @override
  Future<DayLog> setTrainingOverride(DateTime date, bool? isTrainingDay) async =>
      _put(_logFor(date).copyWith(trainingDayOverride: isTrainingDay));

  @override
  Future<List<FoodNutrition>> searchFoods(String query) async {
    final q = query.trim();
    final all = _foods.values.toList();
    return q.isEmpty ? all : all.where((f) => f.name.contains(q)).toList();
  }

  @override
  Future<FoodNutrition> createFood(FoodNutrition food) async =>
      _foods[food.name] = food;

  @override
  Future<Map<String, double>> loadWeights({int limit = 90}) async =>
      Map.of(_weights);

  @override
  Future<WeightRecorded> recordWeight(DateTime date, double kg) async {
    _weights[dayKey(date)] = kg;
    return (kg: kg, dailyKcalBefore: 0, dailyKcalAfter: 0);
  }
}
