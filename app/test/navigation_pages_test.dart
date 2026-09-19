import 'package:fitmeal/data/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, {double width = 390}) =>
      pumpApp(tester, width: width);

  testWidgets('统计入口显示趋势，支持周期与三大项切换', (tester) async {
    await pump(tester, width: 320);
    await tester.tap(find.text('统计').last);
    await tester.pumpAndSettle();
    expect(find.text('每日热量'), findsOneWidget);
    expect(find.textContaining('设计已完成'), findsNothing);
    await tester.tap(find.text('近 30 天'));
    await tester.pumpAndSettle();
    expect(find.text('5 天没有记录，未计入平均值'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '蛋白质'));
    await tester.pumpAndSettle();
    expect(find.text('每日蛋白质'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计可以翻看往期，各张卡片在窄屏下都能排开', (tester) async {
    final container = await pump(tester, width: 320);
    await tester.tap(find.text('统计').last);
    await tester.pumpAndSettle();

    String md(DateTime d) => '${d.month}/${d.day}';
    final today = dayOf(DateTime.now());
    String window(int weeksBack) {
      final end = today.subtract(Duration(days: 7 * weeksBack));
      return '${md(end.subtract(const Duration(days: 6)))} – ${md(end)}';
    }

    expect(find.text(window(0)), findsOneWidget);
    expect(find.byTooltip('下一期'), findsOneWidget);

    await tester.tap(find.byTooltip('上一期'));
    await tester.pumpAndSettle();
    expect(find.text(window(1)), findsOneWidget);
    expect(find.text('回到最近'), findsOneWidget);

    // 往右滑再退一期；往前翻会把那一段补进内存。
    await tester.fling(find.text(window(1)), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text(window(2)), findsOneWidget);
    final oldest = today.subtract(const Duration(days: 7 * 2 + 13));
    expect(
      container.read(logStoreProvider).containsKey(dayKey(oldest)),
      isTrue,
    );

    await tester.tap(find.text('回到最近'));
    await tester.pumpAndSettle();
    expect(find.text(window(0)), findsOneWidget);

    for (final title in [
      '体重与摄入对照',
      '达标率',
      '训练日 vs 休息日',
      '达标日历',
      '三大项日均 vs 目标',
      '饮水与餐次',
      '主要来源',
      '记录习惯',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, '按蛋白质'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的展示档案和两套目标，详情可返回', (tester) async {
    await pump(tester);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('我的档案'), findsOneWidget);
    expect(find.text('每日目标'), findsOneWidget);
    expect(find.text('体重记录'), findsOneWidget);
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('我的每日目标'), findsOneWidget);
    // App 现在跑在中文 locale 下，返回按钮的 tooltip 也是中文。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('我的档案'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记录体重覆盖今天并同步目标计算，越界值不能保存', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('记录体重'));
    await tester.tap(find.text('记录体重'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.text('保存并更新目标'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 20–300 kg 之间的体重'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '70.5');
    await tester.tap(find.text('保存并更新目标'));
    await tester.pumpAndSettle();
    expect(container.read(profileProvider).weightKg, 70.5);
    expect(container.read(weightStoreProvider)[dayKey(DateTime.now())], 70.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('档案拒绝反向减脂目标，训练日期可以修改', (tester) async {
    final container = await pump(tester, width: 320);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    final target = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '目标体重',
    );
    await tester.ensureVisible(target);
    await tester.enterText(target, '80');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('减脂目标体重需要低于当前体重'), findsOneWidget);
    expect(container.read(profileProvider).targetWeightKg, 68);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final tuesday = find.widgetWithText(FilterChip, '周二');
    await tester.scrollUntilVisible(
      tuesday,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(tuesday);
    await tester.pumpAndSettle();
    expect(container.read(profileProvider).plan.days, contains(2));
    expect(tester.takeException(), isNull);
  });
}
