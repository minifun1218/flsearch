import 'dart:typed_data';

import 'package:fitmeal/data/recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// PRD N-3：上传前压到长边 ≤1280px、≤500KB。
void main() {
  /// 造一张有细节的图 —— 纯色图怎么压都小，测不出东西。
  Uint8List photo(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, (x * 7 + y * 3) % 256, (x * y) % 256, x % 256);
      }
    }
    return img.encodeJpg(image, quality: 100);
  }

  test('大图被压到长边 1280 且不超过 500KB', () {
    final original = photo(2400, 1800);
    expect(original.length, greaterThan(500 * 1024));

    final compressed = compressForUpload(original);
    final decoded = img.decodeImage(compressed)!;

    expect(decoded.width, 1280);
    expect(decoded.height, 960); // 等比缩放
    expect(compressed.length, lessThanOrEqualTo(500 * 1024));
  });

  test('竖图按高度缩，宽高比不变', () {
    final decoded = img.decodeImage(compressForUpload(photo(1200, 2400)))!;
    expect(decoded.height, 1280);
    expect(decoded.width, 640);
  });

  test('本来就够小的图不会被放大', () {
    final decoded = img.decodeImage(compressForUpload(photo(640, 480)))!;
    expect(decoded.width, 640);
    expect(decoded.height, 480);
  });

  test('解不开的字节原样送上去，让服务端按它的规则拒绝', () {
    final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
    expect(compressForUpload(garbage), same(garbage));
  });
}
