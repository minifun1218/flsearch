import 'dart:convert';
import 'dart:io';

import 'package:fitmeal/data/api/api_client.dart';
import 'package:fitmeal/data/api/api_exception.dart';
import 'package:fitmeal/data/api/auth_tokens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 契约里 401 的语义是固定的：access 过期，客户端应静默 refresh 后重试原请求。
/// 这一组就是盯着那件事，外加错误体的翻译。
void main() {
  AuthTokens tokens({String access = 'a1', String refresh = 'r1', int ttl = 1800}) {
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.now().add(Duration(seconds: ttl)),
    );
  }

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  test('401 会静默刷新并重放原请求', () async {
    final calls = <String>[];
    var accessToken = 'stale';

    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/auth/refresh')) {
          accessToken = 'fresh';
          return json({
            'access_token': 'fresh',
            'refresh_token': 'r2',
            'expires_in': 1800,
          });
        }
        if (request.headers['Authorization'] != 'Bearer $accessToken' ||
            accessToken == 'stale') {
          return json({'detail': 'token 无效'}, status: 401);
        }
        return json({'ok': true});
      }),
    )..setTokens(tokens(access: 'stale'), notify: false);

    final body = await client.get('/profile');

    expect(body, {'ok': true});
    expect(calls, [
      'GET /api/v1/profile',
      'POST /api/v1/auth/refresh',
      'GET /api/v1/profile',
    ]);
    expect(client.tokens!.accessToken, 'fresh');
  });

  test('refresh 也被拒 —— 令牌清空并通知上层重新登录', () async {
    var expiredCalls = 0;

    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return json({'detail': 'refresh 已作废'}, status: 401);
        }
        return json({'detail': 'token 无效'}, status: 401);
      }),
      onSessionExpired: () => expiredCalls++,
    )..setTokens(tokens(), notify: false);

    await expectLater(
      client.get('/profile'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(client.tokens, isNull);
    expect(expiredCalls, 1);
  });

  test('access 已过期就先换一对，不白跑一个必然 401 的来回', () async {
    final calls = <String>[];
    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      httpClient: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/auth/refresh')) {
          return json({
            'access_token': 'fresh',
            'refresh_token': 'r2',
            'expires_in': 1800,
          });
        }
        return json({'ok': true});
      }),
      // 已经过期的一对（TTL 为负）。
    )..setTokens(tokens(ttl: -10), notify: false);

    await client.get('/days/2026-09-16');
    expect(calls.first, endsWith('/auth/refresh'));
    expect(calls.length, 2);
  });

  test('FastAPI 的两种错误体都翻译成一句人话', () async {
    ApiClient clientReturning(Object body, int status) => ApiClient(
          baseUrl: 'https://api.test/api/v1',
          httpClient: MockClient((_) async => json(body, status: status)),
        );

    await expectLater(
      clientReturning({'detail': '减脂目标体重需要低于当前体重'}, 422).put('/profile'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', '减脂目标体重需要低于当前体重')),
    );

    // 校验失败时 detail 是数组，且 msg 带着 pydantic 的前缀。
    await expectLater(
      clientReturning({
        'detail': [
          {'loc': ['body', 'height_cm'], 'msg': 'Value error, 身高超出范围'},
        ],
      }, 422)
          .put('/profile'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', '身高超出范围')),
    );
  });

  test('连不上是 NetworkException，不是 ApiException', () async {
    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      httpClient: MockClient((_) async => throw const SocketException('连接被拒绝')),
    );

    await expectLater(client.get('/days', auth: false), throwsA(isA<NetworkException>()));
  });

  test('未登录的请求不带 Authorization', () async {
    String? header;
    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      httpClient: MockClient((request) async {
        header = request.headers['Authorization'];
        return json({
          'access_token': 'a',
          'refresh_token': 'r',
          'expires_in': 1800,
        });
      }),
    );

    await client.post('/auth/login', body: {'email': 'a@b.c'}, auth: false);
    expect(header, isNull);
  });

  test('查询参数里的空值会被丢掉，不会发出 ?q=', () async {
    Uri? seen;
    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      httpClient: MockClient((request) async {
        seen = request.url;
        return json(const []);
      }),
    )..setTokens(tokens(), notify: false);

    await client.get('/foods', query: {'q': '', 'limit': '30'});
    expect(seen!.queryParameters, {'limit': '30'});
  });
}
