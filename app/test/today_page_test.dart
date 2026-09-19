import 'package:fitmeal/data/app_state.dart';
import 'package:fitmeal/domain/models/food.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  // 整页比手机屏高，给足视口高度，免得 ListView 把下半页懒掉。
  Future<ProviderContainer> pump(WidgetTester tester) =>
      pumpApp(tester, height: 1600);

  testWidgets('首页渲染出目标、三大项和餐次分组', (tester) async {
    final container = await pump(tester);

    expect(find.text('今日记录'), findsOneWidget);
    expect(find.text('蛋白质'), findsWidgets);
    expect(find.text('碳水'), findsWidgets);
    expect(find.text('脂肪'), findsWidgets);

    // 晚餐没有 seed 数据，应该显示空态
    final targets = container.read(dayTargetsProvider);
    final suggested = (targets.kcal * 0.30).round();
    expect(find.text('还没有记录 · 建议 $suggested kcal'), findsOneWidget);
  });

  testWidgets('点饮水按钮会累加，撤销退回最近一次', (tester) async {
    final container = await pump(tester);
    final date = container.read(selectedDateProvider);

    expect(container.read(dayLogProvider).waterMl, 1200);

    await tester.tap(find.text('500 ml'));
    await tester.pumpAndSettle();
    expect(container.read(dayLogProvider).waterMl, 1700);

    await tester.tap(find.text('200 ml'));
    await tester.pumpAndSettle();
    expect(container.read(dayLogProvider).waterMl, 1900);

    // 撤销退的是最近那一次（200），不是固定值（PRD R-030）。
    await container.read(logStoreProvider.notifier).undoWater(date);
    await tester.pumpAndSettle();
    expect(container.read(dayLogProvider).waterMl, 1700);
  });

  testWidgets('剩余热量随记录变化，超标时切到超标文案', (tester) async {
    final container = await pump(tester);
    final date = container.read(selectedDateProvider);
    final targets = container.read(dayTargetsProvider);
    final before = container.read(dayLogProvider).totals.kcal;

    expect(find.text('还可摄入'), findsOneWidget);

    // 灌一条大份量的记录把当天顶到超标
    final store = container.read(logStoreProvider.notifier);
    await store.addEntry(
      date,
      store.newEntry(
        food: FoodLibrary.mixedNuts,
        grams: 500,
        meal: MealType.dinner,
      ),
    );
    await tester.pumpAndSettle();

    final after = container.read(dayLogProvider).totals.kcal;
    expect(after, greaterThan(before));
    expect(after, greaterThan(targets.kcal));
    expect(find.text('已超出'), findsOneWidget);
  });

  testWidgets('切到训练日 / 休息日，目标热量跟着换', (tester) async {
    final container = await pump(tester);
    final date = container.read(selectedDateProvider);
    final store = container.read(logStoreProvider.notifier);

    final first = container.read(dayTargetsProvider);
    await store.setTrainingDayOverride(date, !first.isTrainingDay);
    await tester.pumpAndSettle();

    final second = container.read(dayTargetsProvider);
    expect(second.isTrainingDay, isNot(first.isTrainingDay));
    expect(second.kcal, isNot(first.kcal));
    // 蛋白按体重给，两天一样；差异落在碳水上
    expect(second.macros.proteinG, first.macros.proteinG);
    expect(second.macros.carbG, isNot(first.macros.carbG));
  });
  testWidgets('点首页日期唤出日期选择器，选完切到那一天', (tester) async {
    final container = await pump(tester);
    final today = container.read(selectedDateProvider);
    // 选本月早几天的日子 —— 未来的日子选择器不开放，跨月也不在这一屏里。
    final wanted = DateTime(
      today.year,
      today.month,
      today.day > 3 ? today.day - 3 : 1,
    );

    await tester.tap(find.text('${today.month}月${today.day}日'));
    await tester.pumpAndSettle();
    expect(find.text('选择日期'), findsOneWidget);

    await tester.tap(find.text('${wanted.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();

    expect(dayKey(container.read(selectedDateProvider)), dayKey(wanted));
    expect(find.text('${wanted.month}月${wanted.day}日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
