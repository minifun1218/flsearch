/// 服务端返回了一个非 2xx 的响应。
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  /// 没建档 —— 客户端据此进入建档引导（GET /profile 返回 409）。
  bool get isProfileMissing => statusCode == 409;

  /// 登录态彻底失效，refresh 也救不回来，只能重新登录。
  bool get isUnauthorized => statusCode == 401;

  /// 当日识别次数用尽（PRD R-029）。
  bool get isQuotaExhausted => statusCode == 429;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 请求压根没送到服务端：断网、超时、地址不通。
///
/// 和 [ApiException] 分开，是因为处理方式完全不同：这一类要读本地缓存、
/// 提示「当前离线」，而不是把服务端的错误文案摆给用户看。
class NetworkException implements Exception {
  NetworkException(this.message);

  final String message;

  @override
  String toString() => 'NetworkException: $message';
}
