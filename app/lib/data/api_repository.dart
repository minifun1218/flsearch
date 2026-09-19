import '../domain/models/food.dart';
import '../domain/models/profile.dart';
import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/auth_tokens.dart';
import 'api/dto.dart';
import 'local/local_store.dart';
import 'repository.dart';

/// 真实实现：服务端是唯一真相，本地快照只用来在断网时把最后看到的内容摆出来。
///
/// 写操作一律直连服务端，失败就抛出去 —— 离线编辑队列是 PRD R-003，还没做，
/// 与其假装写成功，不如老实报错。
class ApiRepository implements FitMealRepository {
  ApiRepository({required this.client, required this.local});

  final ApiClient client;
  final LocalStore local;

  // ---------------------------------------------------------------- 账号

  @override
  Future<bool> restoreSession() async {
    final tokens = local.readTokens();
    if (tokens == null) return false;
    client.setTokens(tokens, notify: false);
    return true;
  }

  @override
  Future<void> register({required String email, required String password}) =>
      _authenticate('/auth/register', email, password);

  @override
  Future<void> login({required String email, required String password}) =>
      _authenticate('/auth/login', email, password);

  Future<void> _authenticate(String path, String email, String password) async {
    final body = await client.post(
      path,
      body: {'email': email.trim(), 'password': password},
      auth: false,
    );
    client.setTokens(AuthTokens.fromJson(body as Map<String, dynamic>));
    await local.writeEmail(email.trim());
  }

  @override
  Future<void> logout() async {
    final refresh = client.tokens?.refreshToken;
    try {
      if (refresh != null) {
        await client.post('/auth/logout', body: {'refresh_token': refresh});
      }
    } on ApiException {
      // 服务端说这个令牌已经不算数了 —— 那正是我们想要的结果。
    } on NetworkException {
      // 断网也要能退出：本地清干净，服务端那半边等它自己过期。
    }
    client.setTokens(null, notify: false);
    await local.clearAccountData();
  }

  @override
  Future<void> deleteAccount() async {
    await client.delete('/auth/me');
    client.setTokens(null, notify: false);
    await local.clearAccountData();
  }

  // ---------------------------------------------------------------- 档案

  @override
  Future<UserProfile?> loadProfile() async {
    try {
      final json = await client.get('/profile') as Map<String, dynamic>;
      await local.writeProfile(json);
      return Dto.profile(json);
    } on ApiException catch (e) {
      // 409 = 还没建档，不是错误。
      if (e.isProfileMissing) return null;
      rethrow;
    } on NetworkException {
      final cached = local.readProfile();
      if (cached == null) rethrow;
      return Dto.profile(cached);
    }
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    final json = await client.put(
      '/profile',
      body: Dto.profileJson(profile),
    ) as Map<String, dynamic>;
    await local.writeProfile(json);
    return Dto.profile(json);
  }

  // ---------------------------------------------------------------- 每日

  @override
  Future<List<DayLog>> loadDays(DateTime from, DateTime to) async {
    try {
      final rows = await client.get(
        '/days',
        query: {'from': Dto.date(from), 'to': Dto.date(to)},
      ) as List;
      final days = rows.cast<Map<String, dynamic>>();
      await local.writeDays(days);
      return days.map(Dto.dayLog).toList();
    } on NetworkException {
      final cached = local.readDays();
      if (cached.isEmpty) rethrow;
      final out = <DayLog>[];
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
        final json = cached[Dto.date(d)];
        out.add(json == null ? DayLog(date: d) : Dto.dayLog(json));
      }
      return out;
    }
  }

  @override
  Future<DayLog> loadDay(DateTime date) async {
    try {
      return await _day(await client.get('/days/${Dto.date(date)}'));
    } on NetworkException {
      final cached = local.readDays()[Dto.date(date)];
      if (cached == null) rethrow;
      return Dto.dayLog(cached);
    }
  }

  @override
  Future<DayLog> addEntries(DateTime date, List<FoodEntry> entries) async {
    await client.post('/entries', body: {
      'date': Dto.date(date),
      'entries': [for (final e in entries) Dto.entryJson(e)],
    });
    return loadDay(date);
  }

  @override
  Future<DayLog> updateEntry(
    DateTime date,
    FoodEntry entry, {
    DateTime? newDate,
    bool updateFoodCache = false,
  }) async {
    await client.patch('/entries/${entry.id}', body: {
      'grams': entry.grams,
      'meal': entry.meal.name,
      if (newDate != null) 'date': Dto.date(newDate),
      'nutrition': Dto.nutritionJson(entry.food),
      'update_food_cache': updateFoodCache,
    });
    // 挪了日期就刷新目标那天；原来那天由调用方按需再拉一次。
    return loadDay(newDate ?? date);
  }

  @override
  Future<DayLog> removeEntry(DateTime date, String entryId) async {
    await client.delete('/entries/$entryId');
    return loadDay(date);
  }

  @override
  Future<DayLog> pourWater(DateTime date, int ml) async {
    await client.post('/water', body: {'date': Dto.date(date), 'ml': ml});
    return loadDay(date);
  }

  @override
  Future<DayLog> undoWater(DateTime date) async {
    await client.delete('/water', query: {'date': Dto.date(date)});
    return loadDay(date);
  }

  @override
  Future<DayLog> setTrainingOverride(DateTime date, bool? isTrainingDay) async {
    return _day(
      await client.put(
        '/days/${Dto.date(date)}/training',
        body: {'is_training_day': isTrainingDay},
      ),
    );
  }

  Future<DayLog> _day(Object? body) async {
    final json = body as Map<String, dynamic>;
    await local.writeDays([json]);
    return Dto.dayLog(json);
  }

  // ---------------------------------------------------------------- 食物

  @override
  Future<List<FoodNutrition>> searchFoods(String query) async {
    final rows = await client.get(
      '/foods',
      query: {'q': query.trim(), 'limit': '30'},
    ) as List;
    return [for (final row in rows) Dto.food(row as Map<String, dynamic>)];
  }

  @override
  Future<FoodNutrition> createFood(FoodNutrition food) async {
    final json = await client.post('/foods', body: {
      'name': food.name,
      ...Dto.nutritionJson(food),
    }) as Map<String, dynamic>;
    return Dto.food(json);
  }

  // ---------------------------------------------------------------- 体重

  @override
  Future<Map<String, double>> loadWeights({int limit = 90}) async {
    try {
      final rows = await client.get(
        '/weights',
        query: {'limit': '$limit'},
      ) as List;
      final weights = {
        for (final row in rows.cast<Map<String, dynamic>>())
          row['date'] as String: (row['kg'] as num).toDouble(),
      };
      await local.writeWeights(weights);
      return weights;
    } on NetworkException {
      final cached = local.readWeights();
      if (cached.isEmpty) rethrow;
      return cached;
    }
  }

  @override
  Future<WeightRecorded> recordWeight(DateTime date, double kg) async {
    final json = await client.post('/weights', body: {
      'date': Dto.date(date),
      'kg': kg,
    }) as Map<String, dynamic>;
    return (
      kg: ((json['weight'] as Map)['kg'] as num).toDouble(),
      dailyKcalBefore: (json['daily_kcal_before'] as num).toInt(),
      dailyKcalAfter: (json['daily_kcal_after'] as num).toInt(),
    );
  }
}
