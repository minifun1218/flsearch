import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_tokens.dart';

/// 本地存储。令牌、照片授权，以及最近一段时间的服务端响应快照。
///
/// 快照存的是**服务端原样返回的 JSON**：断网时按同一条解析路径喂给页面，
/// 不会出现「在线一套字段、离线另一套字段」的分叉。
///
/// 这里不是离线编辑队列（PRD R-003，尚未实现）—— 断网只能看，不能改。
class LocalStore {
  LocalStore(this._prefs);

  static const _kTokens = 'auth.tokens';
  static const _kEmail = 'auth.email';
  static const _kConsent = 'privacy.photo_consent';
  static const _kProfile = 'cache.profile';
  static const _kDays = 'cache.days';
  static const _kWeights = 'cache.weights';
  static const _kFavourites = 'prefs.favourites';
  static const _kReminders = 'prefs.reminders';
  static const _kNotifyDenied = 'prefs.notifications_denied';

  /// 快照最多留这么多天，免得本地无限长大。
  static const _maxCachedDays = 120;

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // ---------------------------------------------------------------- 令牌

  AuthTokens? readTokens() =>
      AuthTokens.fromStored(_readJson(_kTokens) as Map<String, dynamic>?);

  Future<void> writeTokens(AuthTokens? tokens) async {
    if (tokens == null) {
      await _prefs.remove(_kTokens);
      return;
    }
    await _prefs.setString(_kTokens, jsonEncode(tokens.toJson()));
  }

  String? readEmail() => _prefs.getString(_kEmail);

  Future<void> writeEmail(String? email) async {
    if (email == null) {
      await _prefs.remove(_kEmail);
      return;
    }
    await _prefs.setString(_kEmail, email);
  }

  // ---------------------------------------------------------------- 授权

  bool readPhotoConsent() => _prefs.getBool(_kConsent) ?? false;

  Future<void> writePhotoConsent(bool value) =>
      _prefs.setBool(_kConsent, value);

  // ---------------------------------------------------------------- 常吃

  Set<String>? readFavourites() => _prefs.getStringList(_kFavourites)?.toSet();

  Future<void> writeFavourites(Set<String> names) =>
      _prefs.setStringList(_kFavourites, names.toList());

  // ---------------------------------------------------------------- 提醒

  Map<String, dynamic>? readReminderSettings() =>
      _readJson(_kReminders) as Map<String, dynamic>?;

  Future<void> writeReminderSettings(Map<String, dynamic> json) =>
      _prefs.setString(_kReminders, jsonEncode(json));

  /// 通知权限被拒过。拒过就不再弹系统权限框（PRD R-035）。
  bool readNotificationsDenied() => _prefs.getBool(_kNotifyDenied) ?? false;

  Future<void> writeNotificationsDenied(bool denied) =>
      _prefs.setBool(_kNotifyDenied, denied);

  // ---------------------------------------------------------------- 快照

  Map<String, dynamic>? readProfile() =>
      _readJson(_kProfile) as Map<String, dynamic>?;

  Future<void> writeProfile(Map<String, dynamic>? json) async {
    if (json == null) {
      await _prefs.remove(_kProfile);
      return;
    }
    await _prefs.setString(_kProfile, jsonEncode(json));
  }

  /// 按日期键存的每日面板 JSON。
  Map<String, Map<String, dynamic>> readDays() {
    final raw = _readJson(_kDays);
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        entry.key as String: (entry.value as Map).cast<String, dynamic>(),
    };
  }

  Future<void> writeDays(Iterable<Map<String, dynamic>> days) async {
    final merged = readDays();
    for (final day in days) {
      final key = day['date'] as String?;
      if (key != null) merged[key] = day;
    }
    final keys = merged.keys.toList()..sort();
    final kept = keys.length <= _maxCachedDays
        ? keys
        : keys.sublist(keys.length - _maxCachedDays);
    await _prefs.setString(
      _kDays,
      jsonEncode({for (final key in kept) key: merged[key]}),
    );
  }

  Map<String, double> readWeights() {
    final raw = _readJson(_kWeights);
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        entry.key as String: (entry.value as num).toDouble(),
    };
  }

  Future<void> writeWeights(Map<String, double> weights) =>
      _prefs.setString(_kWeights, jsonEncode(weights));

  /// 退出登录 / 注销：账号相关的东西一个不留。
  Future<void> clearAccountData() async {
    await Future.wait([
      _prefs.remove(_kTokens),
      _prefs.remove(_kEmail),
      _prefs.remove(_kProfile),
      _prefs.remove(_kDays),
      _prefs.remove(_kWeights),
      _prefs.remove(_kFavourites),
    ]);
  }

  Object? _readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
