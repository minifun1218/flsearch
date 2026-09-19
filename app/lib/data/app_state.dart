import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/food.dart';
import '../domain/models/profile.dart';
import '../domain/nutrition_calculator.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';
import 'api/api_exception.dart';
import 'api_repository.dart';
import 'demo_repository.dart';
import 'local/local_store.dart';
import 'repository.dart';

/// 应用状态。
///
/// 页面照旧读同步的 provider，写操作先本地生效再推给服务端（失败回滚并提示）：
/// 拍一下按钮就要有反应，而服务端才是最终真相 —— 两件事都要。
/// 真正说话的人是 [FitMealRepository]，这一层只负责状态和先后顺序。

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// 首页/统计页一次拉多少天。统计最长看近 30 天。
const kSyncWindowDays = 30;

// ---------------------------------------------------------------- 基础设施

/// 没有服务端也要能把每一屏点完：`--dart-define=FITMEAL_DEMO=true`。
const kDemoMode = bool.fromEnvironment('FITMEAL_DEMO');

/// 本地存储。`main()` 里打开后覆盖进来 —— 它的初始化是异步的，provider 不是。
final localStoreProvider = Provider<LocalStore>((ref) {
  throw StateError('localStoreProvider 必须在 main() 里 override');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final local = ref.watch(localStoreProvider);
  final client = ApiClient(
    baseUrl: ApiConfig.baseUrl,
    onTokensChanged: (tokens) => local.writeTokens(tokens),
    onSessionExpired: () => ref.read(sessionProvider.notifier).onSessionExpired(),
  );
  ref.onDispose(client.close);
  return client;
});

final repositoryProvider = Provider<FitMealRepository>((ref) {
  if (kDemoMode) return DemoRepository();
  return ApiRepository(
    client: ref.watch(apiClientProvider),
    local: ref.watch(localStoreProvider),
  );
});

// ---------------------------------------------------------------- 会话

enum AuthStage {
  /// 还在恢复登录态 / 拉首屏数据。
  loading,
  signedOut,

  /// 登录了但还没建档（服务端 `GET /profile` 返回 409）。
  needsProfile,
  ready,

  /// 连不上，本地也没有可用快照 —— 只能重试。
  failed,
}

class AppSession {
  const AppSession({
    required this.stage,
    this.offline = false,
    this.message,
  });

  final AuthStage stage;

  /// 数据来自本地快照，不是这次从服务端拿的。
  final bool offline;

  /// 失败原因，展示给用户看。
  final String? message;

  AppSession copyWith({AuthStage? stage, bool? offline, String? message}) =>
      AppSession(
        stage: stage ?? this.stage,
        offline: offline ?? this.offline,
        message: message,
      );
}

class SessionNotifier extends Notifier<AppSession> {
  @override
  AppSession build() {
    scheduleMicrotask(bootstrap);
    return const AppSession(stage: AuthStage.loading);
  }

  FitMealRepository get _repo => ref.read(repositoryProvider);

  /// 冷启动：有令牌就直接进去，没有就去登录。
  Future<void> bootstrap() async {
    state = const AppSession(stage: AuthStage.loading);
    try {
      if (!await _repo.restoreSession()) {
        state = const AppSession(stage: AuthStage.signedOut);
        return;
      }
    } on Object {
      state = const AppSession(stage: AuthStage.signedOut);
      return;
    }
    await loadEverything();
  }

  Future<void> signIn({required String email, required String password}) async {
    await _repo.login(email: email, password: password);
    await loadEverything();
  }

  Future<void> signUp({required String email, required String password}) async {
    await _repo.register(email: email, password: password);
    await loadEverything();
  }

  Future<void> signOut() async {
    await _repo.logout();
    _clearMemory();
    state = const AppSession(stage: AuthStage.signedOut);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    _clearMemory();
    state = const AppSession(stage: AuthStage.signedOut);
  }

  /// refresh 也救不回来 —— 退回登录页，但不清本地缓存（下次登录还能用）。
  void onSessionExpired() {
    _clearMemory();
    state = const AppSession(
      stage: AuthStage.signedOut,
      message: '登录状态已过期，请重新登录',
    );
  }

  /// 建档完成后从这里接回主流程。
  Future<void> completeOnboarding(UserProfile profile) async {
    final saved = await _repo.saveProfile(profile);
    ref.read(profileProvider.notifier).hydrate(saved);
    await loadEverything();
  }

  /// 拉首屏要的全部东西：档案、最近 30 天、体重曲线。
  Future<void> loadEverything() async {
    state = const AppSession(stage: AuthStage.loading);
    try {
      final profile = await _repo.loadProfile();
      if (profile == null) {
        state = const AppSession(stage: AuthStage.needsProfile);
        return;
      }
      ref.read(profileProvider.notifier).hydrate(profile);

      final today = dayOf(DateTime.now());
      final days = await _repo.loadDays(
        today.subtract(const Duration(days: kSyncWindowDays - 1)),
        today,
      );
      ref.read(logStoreProvider.notifier).hydrate(days);
      ref
          .read(weightStoreProvider.notifier)
          .hydrate(await _repo.loadWeights());

      state = const AppSession(stage: AuthStage.ready);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        onSessionExpired();
        return;
      }
      state = AppSession(stage: AuthStage.failed, message: e.message);
    } on NetworkException catch (e) {
      // 有快照就先让用户看着，只是标成离线；一点都没有才算失败。
      final hasCache = ref.read(logStoreProvider).isNotEmpty;
      state = hasCache
          ? const AppSession(stage: AuthStage.ready, offline: true)
          : AppSession(
              stage: AuthStage.failed,
              message: '连不上服务端：${e.message}',
            );
    }
  }

  void _clearMemory() {
    ref.read(logStoreProvider.notifier).hydrate(const []);
    ref.read(weightStoreProvider.notifier).hydrate(const {});
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, AppSession>(SessionNotifier.new);

/// 当前登录的邮箱，给「我的」页展示。演示模式没有账号。
final accountEmailProvider = Provider<String?>((ref) {
  // 登录 / 退出都会改 session，跟着它重算。
  ref.watch(sessionProvider);
  if (kDemoMode) return null;
  return ref.watch(localStoreProvider).readEmail();
});

/// 一次性提示。写操作失败时由这里冒到界面上（HomeShell 监听并弹 SnackBar）。
class MessageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String text) => state = text;

  void clear() => state = null;
}

final appMessageProvider =
    NotifierProvider<MessageNotifier, String?>(MessageNotifier.new);

/// 把异常翻译成能摆给用户看的一句话。
String describeError(Object error) {
  if (error is ApiException) return error.message;
  if (error is NetworkException) return '连不上服务端：${error.message}';
  return '出了点问题，请稍后再试';
}

// ---------------------------------------------------------------- 档案

class ProfileNotifier extends Notifier<UserProfile> {
  /// 占位档案。只在 [AuthStage.ready] 之前存在 —— 那之前没有任何页面会读它。
  static final placeholder = UserProfile(
    sex: Sex.male,
    birthDate: DateTime(1995, 1, 1),
    heightCm: 175,
    weightKg: 70,
    activityLevel: ActivityLevel.moderate,
    plan: const TrainingPlan(days: {1, 3, 5}),
    goal: GoalType.maintain,
    targetWeightKg: 70,
    weeklyRateKg: 0.5,
  );

  Timer? _debounce;

  @override
  UserProfile build() {
    ref.onDispose(() => _debounce?.cancel());
    return placeholder;
  }

  void hydrate(UserProfile profile) => state = profile;

  /// 整份改档（档案编辑页）—— 立刻推给服务端，失败回滚。
  Future<void> update(UserProfile Function(UserProfile) change) async {
    final before = state;
    final next = change(before);
    state = next;
    await _push(next, before);
  }

  Future<void> setWeight(double kg) =>
      update((p) => p.copyWith(weightKg: kg));

  /// 记体重时服务端已经顺手把档案里的体重改了（`POST /weights`），
  /// 这里只把本地对齐，不要再 PUT 一次档案。
  void applyWeight(double kg) => state = state.copyWith(weightKg: kg);

  Future<void> setBodyFat(double? percent) =>
      update((p) => p.copyWith(bodyFatPercent: percent));

  /// 滑杆会连续触发，攒一下再发 —— 一次拖动不该打出几十个请求。
  void setProteinPerKg(double v) => _debounced((p) => p.copyWith(proteinPerKg: v));

  void setFatPercent(double v) =>
      _debounced((p) => p.copyWith(fatPercentOfKcal: v));

  void resetMacroSplit() =>
      _debounced((p) => p.copyWith(proteinPerKg: 1.8, fatPercentOfKcal: 25));

  void _debounced(UserProfile Function(UserProfile) change) {
    final before = state;
    state = change(before);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _push(state, before);
    });
  }

  Future<void> _push(UserProfile next, UserProfile rollback) async {
    try {
      state = await ref.read(repositoryProvider).saveProfile(next);
    } on Object catch (e) {
      state = rollback;
      ref.read(appMessageProvider.notifier).show(describeError(e));
    }
  }
}

final profileProvider =
    NotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

// ---------------------------------------------------------------- 选中日期

class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dayOf(DateTime.now());

  void shift(int days) => set(state.add(Duration(days: days)));

  void set(DateTime d) {
    state = dayOf(d);
    // 窗口之外的日子本地没有，翻到就现拉。
    ref.read(logStoreProvider.notifier).ensureLoaded(state);
  }

  bool get isToday => dayKey(state) == dayKey(DateTime.now());
}

final selectedDateProvider =
    NotifierProvider<SelectedDateNotifier, DateTime>(SelectedDateNotifier.new);

// ---------------------------------------------------------------- 记录

class LogStore extends Notifier<Map<String, DayLog>> {
  var _seq = 0;
  final _loading = <String>{};

  @override
  Map<String, DayLog> build() => const {};

  FitMealRepository get _repo => ref.read(repositoryProvider);

  void hydrate(Iterable<DayLog> days) {
    state = {for (final day in days) dayKey(day.date): day};
  }

  DayLog _logFor(DateTime date) =>
      state[dayKey(date)] ?? DayLog(date: dayOf(date));

  void _put(DayLog log) => state = {...state, dayKey(log.date): log};

  /// 翻到没缓存的日期时补一次。重复调用只发一个请求。
  Future<void> ensureLoaded(DateTime date) async {
    final key = dayKey(date);
    if (state.containsKey(key) || _loading.contains(key)) return;
    _loading.add(key);
    try {
      _put(await _repo.loadDay(date));
    } on Object {
      // 拉不到就先当空白日；提示留给写操作，翻日期不该弹窗打断。
      _put(DayLog(date: dayOf(date)));
    } finally {
      _loading.remove(key);
    }
  }

  /// 统计页往前翻时补一段。只取还没缓存的那几天，一次请求取完；
  /// 已在内存里的日子不覆盖 —— 那里可能有刚写、服务端还没回的改动。
  Future<void> ensureRangeLoaded(DateTime from, DateTime to) async {
    final missing = <String>[];
    DateTime? first;
    DateTime? last;
    for (
      var d = dayOf(from);
      !d.isAfter(dayOf(to));
      d = d.add(const Duration(days: 1))
    ) {
      final key = dayKey(d);
      if (state.containsKey(key) || _loading.contains(key)) continue;
      missing.add(key);
      first ??= d;
      last = d;
    }
    if (first == null || last == null) return;
    _loading.addAll(missing);
    try {
      final days = await _repo.loadDays(first, last);
      state = {
        ...state,
        for (final day in days)
          if (!state.containsKey(dayKey(day.date))) dayKey(day.date): day,
      };
    } on Object {
      // 拉不到就留空：统计里显示为未记录，下次翻到这段会再试。
    } finally {
      _loading.removeAll(missing);
    }
  }

  /// 本地先改、服务端后写，失败回滚并提示。
  Future<void> _mutate(
    DateTime date,
    DayLog optimistic,
    Future<DayLog> Function() call,
  ) async {
    final key = dayKey(date);
    final before = state[key];
    _put(optimistic);
    try {
      _put(await call());
    } on Object catch (e) {
      final rolled = {...state};
      if (before == null) {
        rolled.remove(key);
      } else {
        rolled[key] = before;
      }
      state = rolled;
      ref.read(appMessageProvider.notifier).show(describeError(e));
    }
  }

  Future<void> addEntry(DateTime date, FoodEntry entry) =>
      addAll(date, [entry]);

  Future<void> addAll(DateTime date, List<FoodEntry> entries) {
    final log = _logFor(date);
    return _mutate(
      date,
      log.copyWith(entries: [...log.entries, ...entries]),
      () => _repo.addEntries(date, entries),
    );
  }

  Future<void> removeEntry(DateTime date, String id) {
    final log = _logFor(date);
    return _mutate(
      date,
      log.copyWith(entries: log.entries.where((e) => e.id != id).toList()),
      () => _repo.removeEntry(date, id),
    );
  }

  /// 改一条记录。[updateFoodCache] 为真时把营养值写回缓存表（PRD R-025）。
  Future<void> updateEntry(
    DateTime date,
    FoodEntry updated, {
    bool updateFoodCache = false,
  }) {
    final log = _logFor(date);
    return _mutate(
      date,
      log.copyWith(entries: [
        for (final e in log.entries) e.id == updated.id ? updated : e,
      ]),
      () => _repo.updateEntry(date, updated, updateFoodCache: updateFoodCache),
    );
  }

  Future<void> pourWater(DateTime date, int ml) {
    final log = _logFor(date);
    return _mutate(
      date,
      log.copyWith(waterMl: (log.waterMl + ml).clamp(0, 10000)),
      () => _repo.pourWater(date, ml),
    );
  }

  /// 撤销最近一次饮水（PRD R-030）。退多少由服务端说了算。
  Future<void> undoWater(DateTime date) {
    final log = _logFor(date);
    return _mutate(
      date,
      log.copyWith(waterMl: (log.waterMl - 200).clamp(0, 10000)),
      () => _repo.undoWater(date),
    );
  }

  Future<void> setTrainingDayOverride(DateTime date, bool? value) {
    return _mutate(
      date,
      _logFor(date).copyWith(trainingDayOverride: value),
      () => _repo.setTrainingOverride(date, value),
    );
  }

  /// 还没落库的记录。id 只在本地有意义，保存后会被服务端的 id 换掉。
  FoodEntry newEntry({
    required FoodNutrition food,
    required int grams,
    required MealType meal,
    bool fromPhoto = false,
    bool portionUncertain = false,
  }) {
    return FoodEntry(
      id: 'draft-${_seq++}',
      food: food,
      grams: grams,
      meal: meal,
      fromPhoto: fromPhoto,
      portionUncertain: portionUncertain,
    );
  }
}

final logStoreProvider =
    NotifierProvider<LogStore, Map<String, DayLog>>(LogStore.new);

/// 当前选中日期的记录。
final dayLogProvider = Provider<DayLog>((ref) {
  final date = ref.watch(selectedDateProvider);
  final logs = ref.watch(logStoreProvider);
  return logs[dayKey(date)] ?? DayLog(date: date);
});

/// 当前选中日期的目标。会尊重「临时改成训练日」的覆盖。
///
/// 目标在客户端算，不等服务端 —— 同一套公式两边各一份，断网也要看得到目标（N-4）。
final dayTargetsProvider = Provider<DayTargets>((ref) {
  final profile = ref.watch(profileProvider);
  final date = ref.watch(selectedDateProvider);
  final log = ref.watch(dayLogProvider);
  return NutritionCalculator.targetsFor(
    profile,
    date,
    overrideTrainingDay: log.trainingDayOverride,
  );
});

/// 计算链路，给「每日目标」页展示。
final breakdownProvider = Provider<TargetBreakdown>((ref) {
  return NutritionCalculator.breakdown(ref.watch(profileProvider));
});

// ---------------------------------------------------------------- 照片同意

/// 是否已同意把照片上传给第三方 AI 识别（PRD R-048）。同意过就不再弹窗。
class PhotoConsentNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (kDemoMode) return false;
    return ref.read(localStoreProvider).readPhotoConsent();
  }

  void accept() => _set(true);

  void revoke() => _set(false);

  void _set(bool value) {
    state = value;
    if (!kDemoMode) ref.read(localStoreProvider).writePhotoConsent(value);
  }
}

final photoConsentProvider =
    NotifierProvider<PhotoConsentNotifier, bool>(PhotoConsentNotifier.new);

// ---------------------------------------------------------------- 食物搜索

/// 搜索营养缓存表。断网时退回本地那份内置食物表，手动录入这条路不能断。
final foodSearchProvider =
    FutureProvider.family<List<FoodNutrition>, String>((ref, query) async {
  try {
    return await ref.watch(repositoryProvider).searchFoods(query);
  } on Object {
    return FoodLibrary.search(query);
  }
});

// ---------------------------------------------------------------- 常吃

/// 常吃列表。服务端还没有收藏接口（PRD R-027），先只存在这台设备上。
class FavouritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    if (kDemoMode) return _seed;
    return ref.read(localStoreProvider).readFavourites() ?? _seed;
  }

  static const _seed = <String>{
    '香煎鸡胸肉',
    '乳清蛋白粉',
    '全麦吐司',
    '水煮蛋',
    '无糖希腊酸奶',
    '香蕉',
  };

  bool contains(String name) => state.contains(name);

  void toggle(String name) {
    state = state.contains(name)
        ? (Set.of(state)..remove(name))
        : (Set.of(state)..add(name));
    if (!kDemoMode) ref.read(localStoreProvider).writeFavourites(state);
  }
}

final favouritesProvider =
    NotifierProvider<FavouritesNotifier, Set<String>>(FavouritesNotifier.new);

/// 常吃列表的营养值：优先用记录里出现过的那份，其次本地食物表。
final favouriteFoodsProvider = Provider<List<FoodNutrition>>((ref) {
  final names = ref.watch(favouritesProvider);
  final known = <String, FoodNutrition>{
    for (final food in FoodLibrary.all) food.name: food,
    for (final log in ref.watch(logStoreProvider).values)
      for (final entry in log.entries) entry.food.name: entry.food,
  };
  return [
    for (final name in names)
      if (known[name] != null) known[name]!,
  ];
});

// ---------------------------------------------------------------- 最近几餐

/// 一顿完整的历史餐次，用于「整餐复制」。
class PastMeal {
  const PastMeal({
    required this.date,
    required this.meal,
    required this.entries,
  });

  final DateTime date;
  final MealType meal;
  final List<FoodEntry> entries;

  int get kcal => entries.fold(0, (sum, e) => sum + e.kcal);

  String get names => entries.map((e) => e.food.name).join(' · ');
}

/// 最近 7 天里除今天之外的餐次，新的在前。
final recentMealsProvider = Provider<List<PastMeal>>((ref) {
  final logs = ref.watch(logStoreProvider);
  final today = dayOf(DateTime.now());
  final out = <PastMeal>[];

  for (var daysAgo = 1; daysAgo <= 7; daysAgo++) {
    final date = dayOf(today.subtract(Duration(days: daysAgo)));
    final log = logs[dayKey(date)];
    if (log == null) continue;
    for (final meal in MealType.values) {
      final entries = log.entriesOf(meal);
      if (entries.isEmpty) continue;
      out.add(PastMeal(date: date, meal: meal, entries: entries));
    }
  }
  return out;
});

// ---------------------------------------------------------------- 体重

class WeightStore extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  void hydrate(Map<String, double> weights) => state = Map.of(weights);

  /// 同一天重复录入会覆盖，不新增一条（PRD R-031）。
  /// 服务端会顺手重算目标热量，前后值一并返回（PRD R-032）。
  Future<WeightRecorded?> record(DateTime date, double kg) async {
    final before = state;
    state = {...state, dayKey(date): kg};
    try {
      return await ref.read(repositoryProvider).recordWeight(date, kg);
    } on Object catch (e) {
      state = before;
      ref.read(appMessageProvider.notifier).show(describeError(e));
      return null;
    }
  }
}

final weightStoreProvider =
    NotifierProvider<WeightStore, Map<String, double>>(WeightStore.new);

/// 一条体重记录。
typedef WeightPoint = ({DateTime date, double kg});

/// 按日期正序排好的体重序列。
final weightSeriesProvider = Provider<List<WeightPoint>>((ref) {
  final raw = ref.watch(weightStoreProvider);
  final points = <WeightPoint>[];
  raw.forEach((key, kg) {
    final parts = key.split('-').map(int.parse).toList();
    points.add((date: DateTime(parts[0], parts[1], parts[2]), kg: kg));
  });
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
});

// ---------------------------------------------------------------- 食物库

/// 内置的常见食物每 100g 营养值。
///
/// 权威版本在服务端的营养缓存表（PRD R-020）；这份是断网时的兜底，
/// 也是 [DemoRepository] 那套假数据的素材。
abstract final class FoodLibrary {
  static const wholeWheatToast = FoodNutrition(
    name: '全麦吐司',
    kcalPer100g: 265,
    proteinPer100g: 10.3,
    carbPer100g: 48.0,
    fatPer100g: 3.6,
  );

  static const boiledEgg = FoodNutrition(
    name: '水煮蛋',
    kcalPer100g: 143,
    proteinPer100g: 12.6,
    carbPer100g: 1.1,
    fatPer100g: 9.5,
  );

  static const soyMilk = FoodNutrition(
    name: '无糖豆浆',
    kcalPer100g: 33,
    proteinPer100g: 3.0,
    carbPer100g: 1.5,
    fatPer100g: 1.6,
  );

  static const multigrainRice = FoodNutrition(
    name: '杂粮饭',
    kcalPer100g: 174,
    proteinPer100g: 4.2,
    carbPer100g: 37.1,
    fatPer100g: 1.0,
  );

  static const panSearedChicken = FoodNutrition(
    name: '香煎鸡胸肉',
    kcalPer100g: 165,
    proteinPer100g: 31.0,
    carbPer100g: 0,
    fatPer100g: 3.6,
  );

  static const garlicBroccoli = FoodNutrition(
    name: '蒜蓉西兰花',
    kcalPer100g: 78,
    proteinPer100g: 3.8,
    carbPer100g: 6.4,
    fatPer100g: 4.8,
  );

  static const wheyProtein = FoodNutrition(
    name: '乳清蛋白粉',
    kcalPer100g: 400,
    proteinPer100g: 80.0,
    carbPer100g: 8.0,
    fatPer100g: 5.0,
  );

  static const banana = FoodNutrition(
    name: '香蕉',
    kcalPer100g: 88,
    proteinPer100g: 1.1,
    carbPer100g: 22.5,
    fatPer100g: 0.3,
  );

  static const mixedNuts = FoodNutrition(
    name: '混合坚果',
    kcalPer100g: 607,
    proteinPer100g: 20.0,
    carbPer100g: 21.0,
    fatPer100g: 54.0,
  );

  static const poachedChicken = FoodNutrition(
    name: '水煮鸡胸肉',
    kcalPer100g: 133,
    proteinPer100g: 29.5,
    carbPer100g: 0,
    fatPer100g: 1.6,
  );

  static const greekYogurt = FoodNutrition(
    name: '无糖希腊酸奶',
    kcalPer100g: 59,
    proteinPer100g: 10.0,
    carbPer100g: 3.6,
    fatPer100g: 0.4,
  );

  static const brownRice = FoodNutrition(
    name: '糙米饭',
    kcalPer100g: 152,
    proteinPer100g: 3.5,
    carbPer100g: 32.0,
    fatPer100g: 1.1,
  );

  static const steamedFish = FoodNutrition(
    name: '清蒸鲈鱼',
    kcalPer100g: 121,
    proteinPer100g: 18.6,
    carbPer100g: 0,
    fatPer100g: 5.0,
  );

  /// 常吃 / 搜索用的全量列表。
  static const all = <FoodNutrition>[
    panSearedChicken,
    poachedChicken,
    wheyProtein,
    wholeWheatToast,
    boiledEgg,
    greekYogurt,
    banana,
    multigrainRice,
    brownRice,
    garlicBroccoli,
    steamedFish,
    soyMilk,
    mixedNuts,
  ];

  static List<FoodNutrition> search(String query) {
    if (query.trim().isEmpty) return all;
    return all.where((f) => f.name.contains(query.trim())).toList();
  }
}
