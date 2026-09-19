/// 一对令牌。access 短命（默认 30 分钟），refresh 一次性、用一次换一对新的。
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final seconds = (json['expires_in'] as num?)?.toInt() ?? 1800;
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: seconds)),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// 提前 60 秒当作过期，免得请求正好卡在失效瞬间。
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  static AuthTokens? fromStored(Map<String, dynamic>? json) {
    if (json == null) return null;
    final access = json['access_token'] as String?;
    final refresh = json['refresh_token'] as String?;
    final expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
    if (access == null || refresh == null || expiresAt == null) return null;
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
    );
  }
}
