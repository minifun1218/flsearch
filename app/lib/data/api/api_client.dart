import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_exception.dart';
import 'auth_tokens.dart';

/// 和服务端说话的唯一出口。
///
/// 三件事在这一层解决，上面的仓储层不用重复写：
/// 1. 带上 `Authorization: Bearer <access_token>`；
/// 2. 撞到 401 就静默 refresh 一次再重放原请求（契约里 401 的语义就是这个）；
/// 3. 把「网络不通」和「服务端说不行」分成两种异常抛出去。
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
    this.onTokensChanged,
    this.onSessionExpired,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;

  /// 令牌被刷新或清空时回调，交给上层落盘。
  final void Function(AuthTokens? tokens)? onTokensChanged;

  /// refresh 也失败 —— 登录态没救了，上层要退回登录页。
  final void Function()? onSessionExpired;

  AuthTokens? _tokens;
  Future<AuthTokens?>? _refreshing;

  AuthTokens? get tokens => _tokens;

  bool get isAuthenticated => _tokens != null;

  void setTokens(AuthTokens? tokens, {bool notify = true}) {
    _tokens = tokens;
    if (notify) onTokensChanged?.call(tokens);
  }

  void close() => _http.close();

  // ------------------------------------------------------------ 动词

  Future<dynamic> get(String path, {Map<String, String?>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> delete(String path,
          {Map<String, String?>? query, Object? body, bool auth = true}) =>
      _send('DELETE', path, query: query, body: body, auth: auth);

  /// multipart 上传（只有识别接口用）。
  Future<dynamic> upload(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    Future<http.Response> attempt() async {
      final request = http.MultipartRequest('POST', _uri(path, null))
        ..headers.addAll(await _headers(auth: true, json: false))
        ..files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType: _mediaType(contentType),
          ),
        );
      final streamed = await _http.send(request).timeout(timeout);
      return http.Response.fromStream(streamed);
    }

    return _guard(() async {
      var response = await attempt();
      if (response.statusCode == 401 && await _refresh() != null) {
        response = await attempt();
      }
      return _decode(response);
    });
  }

  // ------------------------------------------------------------ 内部

  Uri _uri(String path, Map<String, String?>? query) {
    final cleaned = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && value.isNotEmpty) cleaned[key] = value;
    });
    final uri = Uri.parse('$baseUrl$path');
    return cleaned.isEmpty ? uri : uri.replace(queryParameters: cleaned);
  }

  Future<Map<String, String>> _headers({
    required bool auth,
    bool json = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json; charset=utf-8';
    if (auth) {
      // access 已经过期就先换一对，省掉一个必然 401 的来回。
      if (_tokens != null && _tokens!.isExpired) await _refresh();
      final token = _tokens?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    bool auth = true,
  }) {
    Future<http.Response> attempt() async {
      final request = http.Request(method, _uri(path, query))
        ..headers.addAll(await _headers(auth: auth));
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _http.send(request).timeout(timeout);
      return http.Response.fromStream(streamed);
    }

    return _guard(() async {
      var response = await attempt();
      if (auth && response.statusCode == 401 && await _refresh() != null) {
        response = await attempt();
      }
      return _decode(response);
    });
  }

  /// 刷新令牌。并发请求同时撞 401 时只发一次刷新，其余等这一个。
  Future<AuthTokens?> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<AuthTokens?> _doRefresh() async {
    final refreshToken = _tokens?.refreshToken;
    if (refreshToken == null) return null;
    try {
      final response = await _http
          .post(
            _uri('/auth/refresh', null),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(timeout);
      if (response.statusCode >= 400) {
        // refresh 也被拒了：令牌作废或过期，只能重新登录。
        setTokens(null);
        onSessionExpired?.call();
        return null;
      }
      final pair = AuthTokens.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      setTokens(pair);
      return pair;
    } on Object {
      // 网络问题不等于登录失效，别把用户踢出去。
      return null;
    }
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SocketException catch (e) {
      throw NetworkException(e.message.isEmpty ? '网络不可用' : e.message);
    } on TimeoutException {
      throw NetworkException('请求超时');
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    } on HandshakeException catch (e) {
      throw NetworkException(e.message);
    }
  }

  dynamic _decode(http.Response response) {
    final text = response.bodyBytes.isEmpty
        ? ''
        : utf8.decode(response.bodyBytes, allowMalformed: true);
    final body = text.isEmpty ? null : _tryJson(text);

    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    throw ApiException(
      response.statusCode,
      _messageOf(body) ?? 'HTTP ${response.statusCode}',
      code: body is Map ? body['code'] as String? : null,
    );
  }

  static dynamic _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// FastAPI 的错误体有两种：`{"detail": "文案"}` 和校验失败时的 detail 数组。
  static String? _messageOf(dynamic body) {
    if (body is String && body.isNotEmpty) return body;
    if (body is! Map) return null;
    final detail = body['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        final raw = first['msg'].toString();
        return raw.replaceFirst(RegExp(r'^Value error, '), '');
      }
    }
    return null;
  }

  static MediaType _mediaType(String contentType) {
    final parts = contentType.split('/');
    return parts.length == 2
        ? MediaType(parts[0], parts[1])
        : MediaType('image', 'jpeg');
  }
}
