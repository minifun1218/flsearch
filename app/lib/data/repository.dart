import '../domain/models/food.dart';
import '../domain/models/profile.dart';

/// 记一次体重的结果：服务端会顺手重算目标热量，前后值都给回来（PRD R-032）。
typedef WeightRecorded = ({double kg, int dailyKcalBefore, int dailyKcalAfter});

/// 数据出口。页面和 [app_state] 只认这个接口，不关心背后是服务端还是本地假数据。
///
/// 两个实现：
/// - `ApiRepository` —— 真实实现，服务端 + 本地缓存；
/// - `DemoRepository` —— 内存假数据，给测试和没有服务端时的设计走查用。
abstract interface class FitMealRepository {
  /// 恢复登录态。返回 false 表示需要登录。
  Future<bool> restoreSession();

  Future<void> register({required String email, required String password});

  Future<void> login({required String email, required String password});

  Future<void> logout();

  /// 注销账号，服务端删除全部个人数据与照片（PRD R-004）。
  Future<void> deleteAccount();

  /// 读档案。null = 还没建档，客户端要走建档引导。
  Future<UserProfile?> loadProfile();

  Future<UserProfile> saveProfile(UserProfile profile);

  /// 一次取一段时间的每日面板。[from]、[to] 都含。
  Future<List<DayLog>> loadDays(DateTime from, DateTime to);

  Future<DayLog> loadDay(DateTime date);

  Future<DayLog> addEntries(DateTime date, List<FoodEntry> entries);

  /// 改一条记录。[newDate] 非空表示挪到别的日期；
  /// [updateFoodCache] 表示把营养值的修正写回缓存表（PRD R-025）。
  Future<DayLog> updateEntry(
    DateTime date,
    FoodEntry entry, {
    DateTime? newDate,
    bool updateFoodCache = false,
  });

  Future<DayLog> removeEntry(DateTime date, String entryId);

  Future<DayLog> pourWater(DateTime date, int ml);

  /// 撤销最近一次饮水（PRD R-030）。
  Future<DayLog> undoWater(DateTime date);

  Future<DayLog> setTrainingOverride(DateTime date, bool? isTrainingDay);

  Future<List<FoodNutrition>> searchFoods(String query);

  Future<FoodNutrition> createFood(FoodNutrition food);

  Future<Map<String, double>> loadWeights({int limit = 90});

  Future<WeightRecorded> recordWeight(DateTime date, double kg);
}
