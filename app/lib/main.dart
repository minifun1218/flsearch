import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_state.dart';
import 'data/local/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // 演示模式整条仓储链都在内存里，不碰磁盘。
  if (kDemoMode) {
    runApp(const ProviderScope(child: FitMealApp()));
    return;
  }

  // 本地存储的打开是异步的，provider 的构造不是 —— 在这里打开，注入进去。
  final local = await LocalStore.open();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(local)],
      child: const FitMealApp(),
    ),
  );
}
