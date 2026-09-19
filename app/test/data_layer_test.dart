import 'dart:convert';
import 'dart:io';

import 'package:fitmeal/data/api/api_client.dart';
import 'package:fitmeal/data/api/api_exception.dart';
import 'package:fitmeal/data/api/dto.dart';
import 'package:fitmeal/data/api_repository.dart';
import 'package:fitmeal/data/local/local_store.dart';
import 'package:fitmeal/domain/models/food.dart';
import 'package:fitmeal/domain/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务端的 JSON 长什么样，就照 `docs/03-backend.md` 里的样子写。
Map<String, dynamic> dayJson({
  String date = '2026-09-16',
  bool overridden = false,
  bool isTrainingDay = true,
  int waterMl = 1200,
}) {
  return {
    'date': date,
    'targets': {
      'date': date,
      'kcal': 2254,
      'macros': {'protein_g': 131, 'carb_g': 250, 'fat_g': 57, 'kcal': 2037},
      'water_ml': 3038,
      'is_training_day': isTrainingDay,
      'overridden': overridden,
    },
    'totals': {'kcal': 232, 'protein': 3.9, 'carb': 38.9, 'fat': 0.5},
    'remaining_kcal': 2022,
    'meals': [
      {
        'meal': 'lunch',
        'target_kcal': 676,
        'totals': {'kcal': 232, 'protein': 3.9, 'carb': 38.9, 'fat': 0.5},
        'entries': [
          {
            'id': 'e-1',
            'date': date,
            'meal': 'lunch',
            'food_name': '杂粮饭',
            'grams': 200,
            'kcal_per_100g': 116.0,
            'protein_per_100g': 2.6,
            'carb_per_100g': 25.9,
            'fat_per_100g': 0.3,
            'from_photo': true,
            'portion_uncertain': false,
            'kcal': 232,
            'protein': 5.2,
            'carb': 51.8,
            'fat': 0.6,
            'updated_at': '2026-09-16T10:00:00Z',
          },
        ],
      },
      {'meal': 'breakfast', 'target_kcal': 550, 'totals': {}, 'entries': []},
      {'meal': 'dinner', 'target_kcal': 676, 'totals': {}, 'entries': []},
      {'meal': 'snack', 'target_kcal': 352, 'totals': {}, 'entries': []},
    ],
    'water_ml': waterMl,
    'weight_kg': 72.5,
  };
}

const profileJson = {
  'sex': 'male',
  'birth_date': '1995-03-01',
  'height_cm': 175.0,
  'weight_kg': 72.5,
  'body_fat_percent': null,
  'activity_level': 'moderate',
  'training_days': [1, 3, 5],
  'training_type': 'strength',
  'training_minutes': 60,
  'goal': 'cut',
  'target_weight_kg': 68.0,
  'weekly_rate_kg': 0.5,
  'protein_per_kg': 1.8,
  'fat_percent_of_kcal': 25.0,
  'updated_at': '2026-09-16T10:00:00Z',
};

void main() {
  group('Dto', () {
    test('档案能原样转回去', () {
      final profile = Dto.profile(Map.of(profileJson));
      expect(profile.sex, Sex.male);
      expect(profile.birthDate, DateTime(1995, 3, 1));
      expect(profile.plan.days, {1, 3, 5});
      expect(profile.goal, GoalType.cut);
      expect(profile.bodyFatPercent, isNull);

      final json = Dto.profileJson(profile);
      expect(json['sex'], 'male');
      expect(json['birth_date'], '1995-03-01');
      expect(json['training_days'], [1, 3, 5]);
      expect(json['body_fat_percent'], isNull);
    });

    test('每日面板：四个餐次的记录合成一天', () {
      final log = Dto.dayLog(dayJson());
      expect(log.date, DateTime(2026, 9, 16));
      expect(log.waterMl, 1200);
      expect(log.entries.length, 1);

      final entry = log.entries.single;
      expect(entry.id, 'e-1');
      expect(entry.meal, MealType.lunch);
      expect(entry.food.name, '杂粮饭');
      expect(entry.grams, 200);
      expect(entry.fromPhoto, isTrue);
      // 客户端自己按份量换算，和服务端给的 kcal 对得上。
      expect(entry.kcal, 232);
    });

    test('只有被手动覆盖过的那天才带 trainingDayOverride（R-016）', () {
      expect(Dto.dayLog(dayJson()).trainingDayOverride, isNull);
      expect(
        Dto.dayLog(dayJson(overridden: true, isTrainingDay: false))
            .trainingDayOverride,
        isFalse,
      );
    });

    test('日期一律 YYYY-MM-DD，月和日补零', () {
      expect(Dto.date(DateTime(2026, 9, 6)), '2026-09-06');
      expect(Dto.parseDate('2026-09-06'), DateTime(2026, 9, 6));
    });
  });

  group('ApiRepository', () {
    late LocalStore local;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      local = await LocalStore.open();
    });

    ApiRepository repo(http.Client client) => ApiRepository(
          client: ApiClient(
            baseUrl: 'https://api.test/api/v1',
            httpClient: client,
          ),
          local: local,
        );

    http.Response ok(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    test('拉到的每一天都写进快照，断网时照样摆得出来', () async {
      final online = repo(MockClient((_) async => ok([dayJson()])));
      final days = await online.loadDays(
        DateTime(2026, 9, 16),
        DateTime(2026, 9, 16),
      );
      expect(days.single.entries.single.food.name, '杂粮饭');

      // 换一个连不上的客户端，同一段时间应该走本地快照。
      final offline = repo(
        MockClient((_) async => throw const SocketException('断网')),
      );
      final cached = await offline.loadDays(
        DateTime(2026, 9, 16),
        DateTime(2026, 9, 16),
      );
      expect(cached.single.entries.single.food.name, '杂粮饭');
      expect(cached.single.waterMl, 1200);
    });

    test('快照里没有的那天按空白日给，不是报错', () async {
      await repo(MockClient((_) async => ok([dayJson()]))).loadDays(
        DateTime(2026, 9, 16),
        DateTime(2026, 9, 16),
      );

      final offline = repo(
        MockClient((_) async => throw const SocketException('断网')),
      );
      final days = await offline.loadDays(
        DateTime(2026, 9, 15),
        DateTime(2026, 9, 16),
      );
      expect(days.length, 2);
      expect(days.first.entries, isEmpty);
      expect(days.last.entries.length, 1);
    });

    test('一点快照都没有时，断网是实打实的失败', () async {
      final offline = repo(
        MockClient((_) async => throw const SocketException('断网')),
      );
      await expectLater(
        offline.loadDays(DateTime(2026, 9, 16), DateTime(2026, 9, 16)),
        throwsA(isA<NetworkException>()),
      );
    });

    test('没建档的 409 不是错误，是 null', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': '还没有档案'}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(await repo(client).loadProfile(), isNull);
    });

    test('断网时档案走本地快照', () async {
      await repo(MockClient((_) async => ok(profileJson))).loadProfile();

      final offline = repo(
        MockClient((_) async => throw const SocketException('断网')),
      );
      final profile = await offline.loadProfile();
      expect(profile!.heightCm, 175);
      expect(profile.plan.days, {1, 3, 5});
    });

    test('写操作不假装成功：断网就抛出去（R-003 的离线队列还没做）', () async {
      final offline = repo(
        MockClient((_) async => throw const SocketException('断网')),
      );
      await expectLater(
        offline.pourWater(DateTime(2026, 9, 16), 200),
        throwsA(isA<NetworkException>()),
      );
    });

    test('登出会把账号相关的本地数据清干净', () async {
      await repo(MockClient((_) async => ok(profileJson))).loadProfile();
      expect(local.readProfile(), isNotNull);

      await repo(MockClient((_) async => http.Response('', 204))).logout();
      expect(local.readProfile(), isNull);
      expect(local.readTokens(), isNull);
      expect(local.readDays(), isEmpty);
    });

    test('改记录时把营养修正一并写回缓存表（R-025）', () async {
      Map<String, dynamic>? sent;
      final client = MockClient((request) async {
        if (request.method == 'PATCH') {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return ok(<String, dynamic>{});
        }
        return ok(dayJson());
      });

      await repo(client).updateEntry(
        DateTime(2026, 9, 16),
        const FoodEntry(
          id: 'e-1',
          food: FoodNutrition(
            name: '杂粮饭',
            kcalPer100g: 120,
            proteinPer100g: 3,
            carbPer100g: 26,
            fatPer100g: 0.4,
          ),
          grams: 180,
          meal: MealType.dinner,
        ),
        updateFoodCache: true,
      );

      expect(sent!['grams'], 180);
      expect(sent!['meal'], 'dinner');
      expect(sent!['update_food_cache'], isTrue);
      expect((sent!['nutrition'] as Map)['kcal_per_100g'], 120);
    });
  });
}
