// 对着真实服务端跑一遍主流程，验证客户端这层 DTO 和契约没有对不上。
//
// widget 测试里 HttpClient 被 flutter_test 挡掉了，发不出真请求，所以这件事
// 只能放在一个纯 Dart 脚本里做。
//
//   cd server && uvicorn app.main:app --port 8765
//   cd app && dart run tool/smoke.dart [http://127.0.0.1:8765/api/v1]
//
// 全绿才说明「客户端 ↔ 服务端」这条线是通的。

import 'dart:io';

import 'package:fitmeal/data/api/api_client.dart';
import 'package:fitmeal/data/api/auth_tokens.dart';
import 'package:fitmeal/data/api/dto.dart';
import 'package:fitmeal/domain/models/food.dart';
import 'package:fitmeal/domain/models/profile.dart';
import 'package:fitmeal/domain/nutrition_calculator.dart';

var _failures = 0;

void check(String what, bool ok, [String detail = '']) {
  stdout.writeln('${ok ? "  ok  " : " FAIL "} $what${detail.isEmpty ? "" : "  ($detail)"}');
  if (!ok) _failures++;
}

Future<void> main(List<String> args) async {
  final baseUrl =
      args.isNotEmpty ? args.first : 'http://127.0.0.1:8765/api/v1';
  final email = 'smoke+${DateTime.now().millisecondsSinceEpoch}@example.com';
  final client = ApiClient(baseUrl: baseUrl);

  stdout.writeln('服务端：$baseUrl');

  // ---- 注册 ----
  final tokens = AuthTokens.fromJson(
    await client.post(
      '/auth/register',
      body: {'email': email, 'password': 'fitmeal2026'},
      auth: false,
    ) as Map<String, dynamic>,
  );
  client.setTokens(tokens, notify: false);
  check('注册拿到 token 对', tokens.accessToken.isNotEmpty);

  // ---- 建档 ----
  final profile = UserProfile(
    sex: Sex.male,
    birthDate: DateTime(1995, 3, 1),
    heightCm: 175,
    weightKg: 72.5,
    activityLevel: ActivityLevel.moderate,
    plan: const TrainingPlan(days: {1, 3, 5}),
    goal: GoalType.cut,
    targetWeightKg: 68,
    weeklyRateKg: 0.5,
  );
  final savedProfile = Dto.profile(
    await client.put('/profile', body: Dto.profileJson(profile))
        as Map<String, dynamic>,
  );
  check('建档后读回来的字段一致',
      savedProfile.heightCm == 175 && savedProfile.plan.days.contains(3));

  // ---- 两边的目标必须算出同一个数（服务端 nutrition.py ↔ 客户端 calculator）----
  final monday = DateTime(2026, 9, 14);
  final targets = await client.get('/targets', query: {'date': Dto.date(monday)})
      as Map<String, dynamic>;
  final serverKcal = (targets['today'] as Map)['kcal'] as int;
  final localKcal =
      NutritionCalculator.targetsFor(savedProfile, monday).kcal;
  check('目标热量两端一致', serverKcal == localKcal, '服务端 $serverKcal / 客户端 $localKcal');

  final breakdown = targets['breakdown'] as Map<String, dynamic>;
  check('计算链路命中 PRD 验收数字',
      ((breakdown['bmr'] as int) - 1669).abs() <= 2 &&
          ((breakdown['tdee'] as int) - 2587).abs() <= 2 &&
          ((breakdown['daily_kcal'] as int) - 2037).abs() <= 2,
      'bmr=${breakdown['bmr']} tdee=${breakdown['tdee']} daily=${breakdown['daily_kcal']}');

  // ---- 记一餐 ----
  final entries = [
    FoodEntry(
      id: 'draft-0',
      food: const FoodNutrition(
        name: '杂粮饭',
        kcalPer100g: 174,
        proteinPer100g: 4.2,
        carbPer100g: 37.1,
        fatPer100g: 1.0,
      ),
      grams: 200,
      meal: MealType.lunch,
    ),
    FoodEntry(
      id: 'draft-1',
      food: const FoodNutrition(
        name: '香煎鸡胸肉',
        kcalPer100g: 165,
        proteinPer100g: 31,
        carbPer100g: 0,
        fatPer100g: 3.6,
      ),
      grams: 120,
      meal: MealType.lunch,
      fromPhoto: true,
    ),
  ];
  await client.post('/entries', body: {
    'date': Dto.date(monday),
    'entries': [for (final e in entries) Dto.entryJson(e)],
  });

  var day = Dto.dayLog(
      await client.get('/days/${Dto.date(monday)}') as Map<String, dynamic>);
  check('两条记录都进了午餐', day.entriesOf(MealType.lunch).length == 2);
  check('份量换算两端一致', day.totals.kcal == 348 + 198,
      '合计 ${day.totals.kcal} kcal');

  // ---- 改份量 ----
  final first = day.entriesOf(MealType.lunch).first;
  await client.patch('/entries/${first.id}', body: {
    'grams': 100,
    'meal': first.meal.name,
    'nutrition': Dto.nutritionJson(first.food),
    'update_food_cache': false,
  });
  day = Dto.dayLog(
      await client.get('/days/${Dto.date(monday)}') as Map<String, dynamic>);
  check('改份量后按比例重算',
      day.entriesOf(MealType.lunch).first.grams == 100);

  // ---- 饮水：加两次，撤销一次 ----
  await client.post('/water', body: {'date': Dto.date(monday), 'ml': 500});
  await client.post('/water', body: {'date': Dto.date(monday), 'ml': 200});
  await client.delete('/water', query: {'date': Dto.date(monday)});
  day = Dto.dayLog(
      await client.get('/days/${Dto.date(monday)}') as Map<String, dynamic>);
  check('撤销退的是最近那一次', day.waterMl == 500, '当前 ${day.waterMl} ml');

  // ---- 训练日覆盖 ----
  final overridden = Dto.dayLog(
    await client.put('/days/${Dto.date(monday)}/training',
        body: {'is_training_day': false}) as Map<String, dynamic>,
  );
  check('覆盖成休息日后带上 override 标记',
      overridden.trainingDayOverride == false);

  // ---- 区间接口：统计页那一屏 ----
  final days = (await client.get('/days', query: {
    'from': Dto.date(monday.subtract(const Duration(days: 6))),
    'to': Dto.date(monday),
  }) as List)
      .map((e) => Dto.dayLog(e as Map<String, dynamic>))
      .toList();
  check('区间返回 7 天，空白日也在', days.length == 7);
  check('只有记过的那天有内容',
      days.where((d) => d.entries.isNotEmpty).length == 1);

  // ---- 体重：同日覆盖并重算目标 ----
  final weight = await client.post('/weights',
      body: {'date': Dto.date(monday), 'kg': 71.0}) as Map<String, dynamic>;
  check('记体重返回目标热量前后差值',
      weight['daily_kcal_before'] != weight['daily_kcal_after'],
      '${weight['daily_kcal_before']} → ${weight['daily_kcal_after']}');

  final weights = await client.get('/weights', query: {'limit': '90'}) as List;
  check('体重曲线取得回来', weights.length == 1);

  // ---- 食物搜索 ----
  await client.post('/foods', body: {
    'name': '烤红薯',
    'kcal_per_100g': 90.0,
    'protein_per_100g': 1.6,
    'carb_per_100g': 20.7,
    'fat_per_100g': 0.2,
  });
  final found = (await client.get('/foods', query: {'q': '红薯'}) as List)
      .map((e) => Dto.food(e as Map<String, dynamic>))
      .toList();
  check('自定义食物随后搜得到',
      found.any((f) => f.name == '烤红薯' && f.kcalPer100g == 90));

  // ---- 刷新令牌是一次性的 ----
  final oldRefresh = client.tokens!.refreshToken;
  final rotated = AuthTokens.fromJson(await client.post('/auth/refresh',
      body: {'refresh_token': oldRefresh}, auth: false) as Map<String, dynamic>);
  client.setTokens(rotated, notify: false);
  var reuseRejected = false;
  try {
    await client.post('/auth/refresh',
        body: {'refresh_token': oldRefresh}, auth: false);
  } on Object {
    reuseRejected = true;
  }
  check('旧的 refresh_token 立刻作废', reuseRejected);

  // ---- 注销：数据跟着账号一起消失 ----
  await client.delete('/auth/me');
  var gone = false;
  try {
    await client.get('/profile');
  } on Object {
    gone = true;
  }
  check('注销后原 token 不再可用', gone);

  client.close();
  stdout.writeln(_failures == 0 ? '\n全部通过' : '\n$_failures 项失败');
  exit(_failures == 0 ? 0 : 1);
}
