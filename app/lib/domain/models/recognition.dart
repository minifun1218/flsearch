import 'food.dart';

/// 一条识别结果。
class RecognizedItem {
  const RecognizedItem({
    required this.food,
    required this.estimatedGrams,
    this.portionUncertain = false,
    this.nutritionFromCache = false,
  });

  final FoodNutrition food;
  final int estimatedGrams;

  /// AI 对份量把握不大，前端标「份量待确认」并把这条聚焦（PRD R-021）。
  final bool portionUncertain;

  /// 营养值来自服务端缓存表而不是本次 AI 估算（PRD R-020）。
  final bool nutritionFromCache;
}

class RecognitionFailure implements Exception {
  const RecognitionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
