import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 服务端地址。
///
/// 打包时用 `--dart-define=FITMEAL_API_BASE_URL=https://…/api/v1` 覆盖。
/// 没给就按平台猜一个开发地址：Android 模拟器访问宿主机要走 10.0.2.2，
/// 桌面/Web 直接 127.0.0.1（真机调试必须显式传，模拟器那个地址在真机上不存在）。
abstract final class ApiConfig {
  static const _override = String.fromEnvironment('FITMEAL_API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _stripTrailingSlash(_override);
    return _stripTrailingSlash('${_devHost()}/api/v1');
  }

  /// 明文 HTTP 只在开发地址上允许；正式环境必须是 https（PRD N-6）。
  static bool get isInsecure => !baseUrl.startsWith('https://');

  static String _devHost() {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    return Platform.isAndroid
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
