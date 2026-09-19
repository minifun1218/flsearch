import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../domain/models/food.dart';
import '../domain/models/recognition.dart';
import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/dto.dart';
import 'app_state.dart';

// 识别结果的模型放在 domain 里（纯 Dart，不碰 Flutter）：
// dto.dart 也要用它，而 dto 得能在不带 Flutter 的脚本里跑。
export '../domain/models/recognition.dart';

/// 识别一张餐食照片。
///
/// 一次服务端调用：图片上传 → 服务端按配置选一个 AI Provider 出结构化 JSON →
/// 用标准化食物名查营养缓存表，命中复用、未命中写回 → 返回结果。
/// Provider 换成谁，这个接口不变（PRD R-019）。
abstract interface class FoodRecognizer {
  Future<List<RecognizedItem>> recognize({required String imagePath});
}

/// 真实实现：压图 → `POST /recognitions`。
class ApiFoodRecognizer implements FoodRecognizer {
  ApiFoodRecognizer(this._client);

  final ApiClient _client;

  @override
  Future<List<RecognizedItem>> recognize({required String imagePath}) async {
    final bytes = await _read(imagePath);
    final compressed = await compute(compressForUpload, bytes);

    final Object? body;
    try {
      body = await _client.upload(
        '/recognitions',
        // The FastAPI endpoint names its UploadFile parameter `image`.
        // Keep this in lockstep with server/app/api/recognition.py; using
        // `photo` makes FastAPI reject the request with a missing-field 422.
        field: 'image',
        bytes: compressed,
        filename: 'meal.jpg',
        contentType: 'image/jpeg',
      );
    } on ApiException catch (e) {
      throw RecognitionFailure(_explain(e));
    } on NetworkException catch (e) {
      throw RecognitionFailure('网络不稳定：${e.message}');
    }

    final items = (body as Map<String, dynamic>)['items'] as List? ?? const [];
    if (items.isEmpty) {
      throw const RecognitionFailure('这张照片里没认出食物，换个角度再拍，或手动记录');
    }
    return [
      for (final item in items)
        Dto.recognizedItem(item as Map<String, dynamic>),
    ];
  }

  Future<Uint8List> _read(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      throw RecognitionFailure('读不到这张照片：${e.message}');
    }
  }

  /// 契约里那几个状态码，各自对应一句人话（PRD R-019 / R-029、N-2）。
  static String _explain(ApiException e) => switch (e.statusCode) {
        413 => '照片太大了，换一张再试',
        415 => '这个格式不支持，请用照片',
        429 => '今天的识别次数用完了，先手动记录吧',
        504 => '识别超时了，网络不稳时容易这样',
        502 => '识别服务暂时不可用，先手动记录吧',
        _ => e.message,
      };
}

/// 上传前压到长边 ≤1280px、≤500KB（PRD N-3）。
///
/// 顶层函数 —— 要丢进 isolate 跑（`compute`）：解码一张 4000×3000 的原图
/// 够卡掉几十帧，不能占着 UI 线程。
Uint8List compressForUpload(Uint8List original) {
  const maxEdge = 1280;
  const maxBytes = 500 * 1024;

  // 解不开就原样送上去，让服务端按它的规则拒绝，别在客户端自己判死刑。
  // decodeImage 对坏字节不一定返回 null，也可能直接抛，两种都要接住。
  img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } on Object {
    return original;
  }
  if (decoded == null) return original;

  final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longEdge <= maxEdge
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxEdge : null,
          height: decoded.height > decoded.width ? maxEdge : null,
          interpolation: img.Interpolation.average,
        );

  // 质量逐档下调，够小就停。餐食照片一般 80 就进得去。
  for (final quality in [80, 65, 50, 35]) {
    final encoded = img.encodeJpg(resized, quality: quality);
    if (encoded.length <= maxBytes) return encoded;
  }
  return img.encodeJpg(resized, quality: 25);
}

final recognizerProvider = Provider<FoodRecognizer>((ref) {
  if (kDemoMode) return DemoFoodRecognizer();
  return ApiFoodRecognizer(ref.watch(apiClientProvider));
});

/// 没有服务端时的替身，只给设计走查和测试用。
class DemoFoodRecognizer implements FoodRecognizer {
  var _round = 0;

  static const _plates = <List<(FoodNutrition, int, bool)>>[
    [
      (FoodLibrary.multigrainRice, 150, false),
      (FoodLibrary.panSearedChicken, 120, false),
      (FoodLibrary.garlicBroccoli, 180, true),
    ],
    [
      (FoodLibrary.brownRice, 180, false),
      (FoodLibrary.steamedFish, 150, true),
      (FoodLibrary.garlicBroccoli, 160, false),
    ],
    [
      (FoodLibrary.wholeWheatToast, 70, false),
      (FoodLibrary.boiledEgg, 105, false),
      (FoodLibrary.greekYogurt, 140, true),
    ],
  ];

  @override
  Future<List<RecognizedItem>> recognize({required String imagePath}) async {
    // 真机上这段时间花在上传和模型推理上，P95 约 8 秒（PRD N-2）。
    await Future<void>.delayed(const Duration(milliseconds: 2400));

    final plate = _plates[_round % _plates.length];
    _round++;

    return [
      for (final (food, grams, uncertain) in plate)
        RecognizedItem(
          food: food,
          estimatedGrams: grams,
          portionUncertain: uncertain,
        ),
    ];
  }
}
