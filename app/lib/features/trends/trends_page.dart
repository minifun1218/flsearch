import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/ring_progress.dart';
import '../../core/widgets/weight_chart.dart';
import '../../data/app_state.dart';
import '../../domain/models/food.dart';
import '../../domain/trends.dart';

/// Statistics for the selected time window. Missing days remain visible in
/// the chart as gaps, which keeps the logging habit honest.
class TrendsPage extends ConsumerStatefulWidget {
  const TrendsPage({super.key});

  @override
  ConsumerState<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends ConsumerState<TrendsPage> {
  var _range = 7;

  /// How many windows back from the current one; 0 = the window ending today.
  var _offset = 0;

  /// Requests in flight; paging quickly can start several.
  var _pending = 0;

  /// Browsing goes back one year at most — the server's range limit.
  int get _maxOffset => 365 ~/ _range;

  DateTime get _today => dayOf(DateTime.now());

  DateTime get _endDate => _today.subtract(Duration(days: _offset * _range));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureLoaded();
    });
  }

  /// Loads the shown window and the one before it, which the comparison
  /// needs. Only the most recent 30 days arrive with the first sync.
  Future<void> _ensureLoaded() async {
    final end = _endDate;
    final from = end.subtract(Duration(days: _range * 2 - 1));
    setState(() => _pending++);
    try {
      await ref.read(logStoreProvider.notifier).ensureRangeLoaded(from, end);
    } finally {
      if (mounted) setState(() => _pending--);
    }
  }

  void _setRange(int range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _offset = 0;
    });
    _ensureLoaded();
  }

  void _shift(int delta) {
    final next = (_offset + delta).clamp(0, _maxOffset);
    if (next == _offset) return;
    setState(() => _offset = next);
    _ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logStoreProvider);
    final profile = ref.watch(profileProvider);
    final weights = ref.watch(weightSeriesProvider);
    final end = _endDate;
    final snapshot = TrendCalculator.snapshot(
      logs: logs,
      profile: profile,
      endDate: end,
      range: _range,
      today: _today,
    );
    final previous = TrendCalculator.snapshot(
      logs: logs,
      profile: profile,
      endDate: end.subtract(Duration(days: _range)),
      range: _range,
    );
    final balance = TrendCalculator.energyBalance(
      snapshot: snapshot,
      profile: profile,
      weights: weights,
    );

    Widget padded(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: child,
    );
    const gap = SizedBox(height: AppSpacing.cardGap);

    // Swiping sideways pages through windows; the list itself only scrolls
    // vertically, so the two gestures never compete.
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 300) _shift(1);
        if (velocity < -300) _shift(-1);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.topSafe, bottom: 36),
        children: [
          const LargeTitle('统计'),
          padded(
            SegmentedTabs(
              labels: const ['近 7 天', '近 30 天'],
              selected: _range == 7 ? 0 : 1,
              onChanged: (index) => _setRange(index == 0 ? 7 : 30),
            ),
          ),
          const SizedBox(height: 6),
          padded(
            _PeriodBar(
              start: snapshot.startDate,
              end: snapshot.endDate,
              offset: _offset,
              loading: _pending > 0,
              canGoBack: _offset < _maxOffset,
              onShift: _shift,
              onReset: () => _shift(-_offset),
            ),
          ),
          const SizedBox(height: 6),
          padded(_DailyCaloriesCard(snapshot: snapshot, previous: previous)),
          gap,
          padded(
            _EnergyBalanceCard(
              balance: balance,
              targetWeightKg: profile.targetWeightKg,
            ),
          ),
          gap,
          padded(_HitRateCard(snapshot: snapshot, previous: previous)),
          gap,
          padded(_DayTypeCard(snapshot: snapshot)),
          gap,
          padded(_CalendarCard(snapshot: snapshot, today: _today)),
          gap,
          padded(_MacroAverageCard(snapshot: snapshot, previous: previous)),
          gap,
          padded(_WaterMealCard(snapshot: snapshot)),
          gap,
          padded(_TopFoodsCard(snapshot: snapshot)),
          gap,
          padded(_HabitCard(snapshot: snapshot, previous: previous)),
        ],
      ),
    );
  }
}

String _md(DateTime date) => '${date.month}/${date.day}';

String _signed(num value, {int decimals = 0}) {
  final text = value.abs().toStringAsFixed(decimals);
  if (double.parse(text) == 0) return text;
  return value > 0 ? '+$text' : '-$text';
}

/// Window navigation: ‹ 9/12 – 9/18 ›. Swiping does the same thing.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.start,
    required this.end,
    required this.offset,
    required this.loading,
    required this.canGoBack,
    required this.onShift,
    required this.onReset,
  });

  final DateTime start;
  final DateTime end;
  final int offset;
  final bool loading;
  final bool canGoBack;
  final ValueChanged<int> onShift;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '上一期',
          onPressed: canGoBack ? () => onShift(1) : null,
          icon: const Icon(Icons.chevron_left, size: 22),
          color: AppColors.ink2,
          disabledColor: AppColors.line,
        ),
        Expanded(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_md(start)} – ${_md(end)}',
                    style: AppFonts.number(size: 14, weight: FontWeight.w500),
                  ),
                  if (loading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.ink4,
                      ),
                    ),
                  ],
                ],
              ),
              if (offset == 0)
                Text(
                  '含今天 · 左右滑动翻看往期',
                  style: AppFonts.text(size: 11, color: AppColors.ink4),
                )
              else
                GestureDetector(
                  onTap: onReset,
                  child: Text(
                    '回到最近',
                    style: AppFonts.text(
                      size: 11,
                      color: AppColors.ink2,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: '下一期',
          onPressed: offset > 0 ? () => onShift(-1) : null,
          icon: const Icon(Icons.chevron_right, size: 22),
          color: AppColors.ink2,
          disabledColor: AppColors.line,
        ),
      ],
    );
  }
}

/// "较上期 +12 kcal". Neutral by default: more protein is good when cutting
/// and bulking alike, but more carbs depends on the goal, so only metrics
/// with an unambiguous direction get a colour.
class _Delta extends StatelessWidget {
  const _Delta(this.value, {this.unit = '', this.upIsGood});

  final double? value;
  final String unit;
  final bool? upIsGood;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null) return const SizedBox.shrink();
    final rounded = value.roundToDouble();
    final flat = rounded == 0;
    final color = flat || upIsGood == null
        ? AppColors.ink3
        : (rounded > 0) == upIsGood
        ? AppColors.positive
        : AppColors.danger;
    final arrow = flat ? '' : (rounded > 0 ? '↑' : '↓');
    return Text(
      flat ? '较上期持平' : '较上期 $arrow${rounded.abs().toStringAsFixed(0)}$unit',
      style: AppFonts.text(size: 11, color: color),
    );
  }
}

enum _TrendMetric {
  calories('热量', 'kcal', AppColors.ink),
  protein('蛋白质', 'g', AppColors.protein),
  carb('碳水', 'g', AppColors.carb),
  fat('脂肪', 'g', AppColors.fat);

  const _TrendMetric(this.label, this.unit, this.color);
  final String label;
  final String unit;
  final Color color;

  double value(TrendDay day) => switch (this) {
    calories => day.totals.kcal.toDouble(),
    protein => day.totals.protein,
    carb => day.totals.carb,
    fat => day.totals.fat,
  };

  double target(TrendDay day) => switch (this) {
    calories => day.targets.kcal.toDouble(),
    protein => day.targets.macros.proteinG.toDouble(),
    carb => day.targets.macros.carbG.toDouble(),
    fat => day.targets.macros.fatG.toDouble(),
  };

  double average(TrendSnapshot snapshot) => switch (this) {
    calories => snapshot.averageKcal.toDouble(),
    protein => snapshot.averageProtein,
    carb => snapshot.averageCarb,
    fat => snapshot.averageFat,
  };
}

class _DailyCaloriesCard extends StatefulWidget {
  const _DailyCaloriesCard({required this.snapshot, required this.previous});

  final TrendSnapshot snapshot;
  final TrendSnapshot previous;

  @override
  State<_DailyCaloriesCard> createState() => _DailyCaloriesCardState();
}

class _DailyCaloriesCardState extends State<_DailyCaloriesCard> {
  var _metric = _TrendMetric.calories;
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant _DailyCaloriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.totalDays != widget.snapshot.totalDays ||
        oldWidget.snapshot.startDate != widget.snapshot.startDate) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final selected = snapshot.days[_selectedIndex ?? snapshot.totalDays - 1];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '每日${_metric.label}',
                style: AppFonts.text(size: 14, weight: FontWeight.w500),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  NumText('${_metric.average(snapshot).round()}', size: 20),
                  const SizedBox(width: 5),
                  Text(
                    '日均 ${_metric.unit}',
                    style: AppFonts.text(size: 11, color: AppColors.ink3),
                  ),
                ],
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _Delta(
              snapshot.deltaFrom(widget.previous, _metric.average),
              unit: ' ${_metric.unit}',
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final metric in _TrendMetric.values)
                ChoiceChip(
                  label: Text(metric.label),
                  selected: _metric == metric,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _metric = metric),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 158,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => setState(() {
                  _selectedIndex =
                      (details.localPosition.dx /
                              constraints.maxWidth *
                              snapshot.totalDays)
                          .floor()
                          .clamp(0, snapshot.totalDays - 1);
                }),
                // Bars grow in whenever the window or the metric changes; a
                // new key restarts the tween from zero.
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(
                    '${snapshot.startDate}-${snapshot.totalDays}-$_metric',
                  ),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 560),
                  builder: (context, progress, _) => CustomPaint(
                    painter: _CaloriesChartPainter(
                      snapshot,
                      _metric,
                      _selectedIndex,
                      progress,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.missingDays == 0
                ? '每天都有记录'
                : '${snapshot.missingDays} 天没有记录，未计入平均值',
            style: AppFonts.text(size: 11, color: AppColors.ink4),
          ),
          const SizedBox(height: 4),
          Text(
            '虚线为每日目标 · 点击柱状图查看当天',
            style: AppFonts.text(size: 11, color: AppColors.ink4),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.lineSoft),
          const SizedBox(height: 12),
          Text(
            '${selected.date.month}/${selected.date.day} · ${selected.targets.isTrainingDay ? '训练日' : '休息日'}',
            style: AppFonts.text(size: 12, weight: FontWeight.w500),
          ),
          const SizedBox(height: 5),
          Text(
            selected.hasRecord
                ? '${selected.totals.kcal} kcal · 蛋白 ${selected.totals.protein.round()}g · 碳水 ${selected.totals.carb.round()}g · 脂肪 ${selected.totals.fat.round()}g'
                : '这一天还没有饮食记录',
            style: AppFonts.text(size: 11, color: AppColors.ink3, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _CaloriesChartPainter extends CustomPainter {
  _CaloriesChartPainter(
    this.snapshot,
    this.metric,
    this.selectedIndex,
    this.progress,
  );

  final TrendSnapshot snapshot;
  final _TrendMetric metric;
  final int? selectedIndex;

  /// 0 → 1 over the entry animation.
  final double progress;
  static const _chartHeight = 125.0;

  /// Bars start one after another, left to right, across this share of the
  /// animation; each then takes the rest to grow.
  static const _stagger = 0.4;

  double _barProgress(int index, int count) {
    final start = count <= 1 ? 0.0 : _stagger * index / (count - 1);
    final local = ((progress - start) / (1 - _stagger)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(local);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshot.days.isEmpty) return;

    final maxKcal = snapshot.days.fold<double>(
      1,
      (max, day) => math.max(
        max,
        math.max(metric.target(day), day.hasRecord ? metric.value(day) : 0),
      ),
    );
    final ceiling = maxKcal * 1.16;
    final chartWidth = size.width;
    final count = snapshot.days.length;
    final gap = count <= 7 ? 9.0 : 3.0;
    final barWidth = math.max(2.0, (chartWidth - gap * (count - 1)) / count);
    final chartTop = 8.0;
    final chartBottom = chartTop + _chartHeight;

    for (var i = 0; i < count; i++) {
      final day = snapshot.days[i];
      final x = i * (barWidth + gap);
      final grow = _barProgress(i, count);
      if (!day.hasRecord) {
        final missing = Paint()
          ..color = AppColors.borderDash.withValues(alpha: grow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        final outline = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, chartTop, barWidth, _chartHeight),
              const Radius.circular(3),
            ),
          );
        _drawDashed(canvas, outline, missing);
      } else {
        final barHeight = _chartHeight * metric.value(day) / ceiling * grow;
        final bar = Paint()
          ..color = metric.color.withValues(
            alpha: selectedIndex == null || selectedIndex == i ? 1 : 0.5,
          );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, chartBottom - barHeight, barWidth, barHeight),
            const Radius.circular(4),
          ),
          bar,
        );
      }

      final label = _labelFor(day.date, count, i);
      if (label == null) continue;
      final labelWidth = count <= 7 ? barWidth : 40.0;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: AppFonts.text(
            size: 10,
            color: day.hasRecord ? AppColors.ink3 : AppColors.ink4,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: labelWidth, maxWidth: labelWidth);
      labelPainter.paint(
        canvas,
        Offset(
          (x + barWidth / 2 - labelWidth / 2).clamp(
            0.0,
            chartWidth - labelWidth,
          ),
          chartBottom + 6,
        ),
      );
    }

    final targetPath = Path();
    for (var i = 0; i < count; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      final y =
          chartBottom -
          _chartHeight * metric.target(snapshot.days[i]) / ceiling;
      if (i == 0) {
        targetPath.moveTo(x, y);
      } else {
        targetPath.lineTo(x, y);
      }
    }
    final targetPaint = Paint()
      ..color = AppColors.ink4.withValues(alpha: progress.clamp(0.0, 1.0))
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashed(canvas, targetPath, targetPaint);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final pathMetric in path.computeMetrics()) {
      for (var distance = 0.0; distance < pathMetric.length; distance += 7) {
        canvas.drawPath(
          pathMetric.extractPath(
            distance,
            math.min(distance + 4, pathMetric.length),
          ),
          paint,
        );
      }
    }
  }

  String? _labelFor(DateTime date, int count, int index) {
    if (count <= 7) {
      return const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1];
    }
    if (index == 0 || index == count ~/ 2 || index == count - 1) {
      return '${date.month}/${date.day}';
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _CaloriesChartPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.metric != metric ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.progress != progress;
}

/// Intake against estimated burn, and whether the scale agrees.
class _EnergyBalanceCard extends StatelessWidget {
  const _EnergyBalanceCard({
    required this.balance,
    required this.targetWeightKg,
  });

  final EnergyBalance? balance;
  final double targetWeightKg;

  @override
  Widget build(BuildContext context) {
    final balance = this.balance;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '体重与摄入对照',
            style: AppFonts.text(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          if (balance == null)
            Text(
              '这段时间没有饮食记录，无法推算',
              style: AppFonts.text(size: 12, color: AppColors.ink3),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    value: '${balance.averageIntake}',
                    label: '日均摄入 kcal',
                  ),
                ),
                Expanded(
                  child: _Figure(
                    value: '${balance.estimatedBurn}',
                    label: '估算消耗 kcal',
                  ),
                ),
                Expanded(
                  child: _Figure(
                    value: '${balance.dailyBalance.abs()}',
                    label: balance.dailyBalance < 0 ? '日均缺口 kcal' : '日均盈余 kcal',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.lineSoft),
            const SizedBox(height: 14),
            _BalanceRow(
              label: '按摄入推算（${balance.spanDays} 天）',
              value: '${_signed(balance.expectedChangeKg, decimals: 1)} kg',
            ),
            const SizedBox(height: 8),
            _BalanceRow(
              label: balance.hasWeightChange
                  ? '实际称重（${_md(balance.startWeight!.date)} → ${_md(balance.endWeight!.date)}）'
                  : '实际称重',
              value: balance.hasWeightChange
                  ? '${_signed(balance.actualChangeKg!, decimals: 1)} kg'
                  : '—',
            ),
            const SizedBox(height: 12),
            Text(
              _verdict(balance),
              style: AppFonts.text(
                size: 12,
                color: AppColors.ink2,
                height: 1.7,
              ),
            ),
            if (balance.weights.length >= 2) ...[
              const SizedBox(height: 12),
              WeightChart(points: balance.weights, targetKg: targetWeightKg),
            ],
            const SizedBox(height: 8),
            Text(
              '消耗按当前档案估算，未记录的日子按日均摄入推算',
              style: AppFonts.text(size: 11, color: AppColors.ink4),
            ),
          ],
        ],
      ),
    );
  }

  static String _verdict(EnergyBalance balance) {
    final actual = balance.actualChangeKg;
    if (actual == null) {
      return '这段时间称重不足两次，多称几次就能对照推算和实际。';
    }
    final gap = actual - balance.expectedChangeKg;
    if (gap.abs() <= 0.5) {
      return '实际变化和按摄入推算的基本吻合。';
    }
    final kg = gap.abs().toStringAsFixed(1);
    if (gap > 0) {
      return '体重比推算高 $kg kg：可能有漏记或份量估小了，也可能消耗被估高了；'
          '几天内的水分波动也会造成偏差。';
    }
    return '体重比推算低 $kg kg：消耗可能被估低了，也可能是水分波动；'
        '持续如此可以考虑把活动水平调高一档。';
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumText(value, size: 18),
        const SizedBox(height: 2),
        Text(label, style: AppFonts.text(size: 11, color: AppColors.ink3)),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppFonts.text(size: 12, color: AppColors.ink2),
          ),
        ),
        Text(value, style: AppFonts.number(size: 14)),
      ],
    );
  }
}

class _HitRateCard extends StatelessWidget {
  const _HitRateCard({required this.snapshot, required this.previous});

  final TrendSnapshot snapshot;
  final TrendSnapshot previous;

  @override
  Widget build(BuildContext context) {
    final percent = snapshot.hitRate;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        children: [
          RingProgress(
            size: 104,
            strokeWidth: 10,
            value: percent / 100,
            color: AppColors.positive,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                NumText('$percent', size: 26),
                Text(
                  '%',
                  style: AppFonts.text(size: 13, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '达标率',
                  style: AppFonts.text(size: 14, weight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot.loggedDays == 0
                      ? '这段时间还没有饮食记录'
                      : '${snapshot.hitDays}/${snapshot.loggedDays} 天热量在目标 ±10% 内',
                  style: AppFonts.text(
                    size: 12,
                    color: AppColors.ink2,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 4),
                _Delta(
                  snapshot.deltaFrom(previous, (s) => s.hitRate),
                  unit: '%',
                  upIsGood: true,
                ),
                const SizedBox(height: 4),
                Text(
                  '统计口径：有记录的天数',
                  style: AppFonts.text(size: 11, color: AppColors.ink4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Training and rest days side by side. Their targets differ, and the
/// difference is all carbs, so that is the number shown next to calories.
class _DayTypeCard extends StatelessWidget {
  const _DayTypeCard({required this.snapshot});

  final TrendSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final training = snapshot.trainingDays;
    final rest = snapshot.restDays;
    final hint = _hint(training, rest);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '训练日 vs 休息日',
            style: AppFonts.text(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DayTypeColumn(label: '训练日', stats: training),
                ),
                const VerticalDivider(
                  width: 24,
                  thickness: 1,
                  color: AppColors.lineSoft,
                ),
                Expanded(
                  child: _DayTypeColumn(label: '休息日', stats: rest),
                ),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 14),
            Text(
              hint,
              style: AppFonts.text(
                size: 12,
                color: AppColors.ink2,
                height: 1.7,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _hint(DayGroupStats training, DayGroupStats rest) {
    if (training.loggedDays == 0 || rest.loggedDays == 0) return null;
    final lines = <String>[];
    final trainingGap = training.averageKcal - training.averageTargetKcal;
    final restGap = rest.averageKcal - rest.averageTargetKcal;
    if (trainingGap < -training.averageTargetKcal * 0.1) {
      lines.add('训练日平均少吃 ${-trainingGap} kcal，训练后记得补足碳水。');
    } else if (trainingGap > training.averageTargetKcal * 0.1) {
      lines.add('训练日平均多吃 $trainingGap kcal。');
    }
    if (restGap > rest.averageTargetKcal * 0.1) {
      lines.add('休息日平均多吃 $restGap kcal，可以减一点主食。');
    } else if (restGap < -rest.averageTargetKcal * 0.1) {
      lines.add('休息日平均少吃 ${-restGap} kcal。');
    }
    return lines.isEmpty ? '训练日和休息日都在目标附近。' : lines.join('\n');
  }
}

class _DayTypeColumn extends StatelessWidget {
  const _DayTypeColumn({required this.label, required this.stats});

  final String label;
  final DayGroupStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label · ${stats.totalDays} 天',
          style: AppFonts.text(size: 12, color: AppColors.ink3),
        ),
        const SizedBox(height: 6),
        if (stats.loggedDays == 0)
          Text(
            stats.totalDays == 0 ? '这段时间没有$label' : '没有记录',
            style: AppFonts.text(size: 12, color: AppColors.ink4),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              NumText('${stats.averageKcal}', size: 20),
              Flexible(
                child: Text(
                  ' / ${stats.averageTargetKcal}',
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.number(
                    size: 12,
                    weight: FontWeight.w400,
                    color: AppColors.ink3,
                  ),
                ),
              ),
            ],
          ),
          Text(
            '日均 kcal / 目标',
            style: AppFonts.text(size: 11, color: AppColors.ink4),
          ),
          const SizedBox(height: 8),
          Text(
            '碳水 ${stats.averageCarb.round()} / ${stats.averageTargetCarb.round()} g',
            style: AppFonts.text(size: 12, color: AppColors.ink2),
          ),
          Text(
            '达标 ${stats.hitDays}/${stats.loggedDays} 天',
            style: AppFonts.text(size: 12, color: AppColors.ink2),
          ),
        ],
      ],
    );
  }
}

/// Each day as a coloured cell, laid out Monday-first like a calendar.
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.snapshot, required this.today});

  final TrendSnapshot snapshot;
  final DateTime today;

  static (Color, Color, Color?) _colors(DayStatus status) => switch (status) {
    DayStatus.hit => (AppColors.positiveBg, AppColors.positive, null),
    DayStatus.under => (AppColors.warnBg, AppColors.warn, null),
    DayStatus.over => (AppColors.dangerBg, AppColors.danger, null),
    DayStatus.missing => (
      Colors.transparent,
      AppColors.ink4,
      AppColors.borderDash,
    ),
  };

  static const _labels = {
    DayStatus.hit: '达标',
    DayStatus.under: '偏低',
    DayStatus.over: '超出',
    DayStatus.missing: '未记录',
  };

  @override
  Widget build(BuildContext context) {
    final leading = snapshot.startDate.weekday - 1;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('达标日历', style: AppFonts.text(size: 14, weight: FontWeight.w500)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: AppFonts.text(size: 10, color: AppColors.ink4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            children: [
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (final day in snapshot.days) _cell(day),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final status in DayStatus.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _swatch(status),
                    const SizedBox(width: 5),
                    Text(
                      '${_labels[status]} ${snapshot.countOf(status)}',
                      style: AppFonts.text(size: 11, color: AppColors.ink3),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(TrendDay day) {
    final (background, foreground, border) = _colors(day.status);
    final isToday = day.date == today;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: AppColors.ink, width: 1.2)
            : border == null
            ? null
            : Border.all(color: border),
      ),
      child: Text(
        '${day.date.day}',
        style: AppFonts.number(
          size: 11,
          weight: isToday ? FontWeight.w700 : FontWeight.w500,
          color: foreground,
        ),
      ),
    );
  }

  Widget _swatch(DayStatus status) {
    final (background, foreground, border) = _colors(status);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: border == null ? foreground : background,
        borderRadius: BorderRadius.circular(3),
        border: border == null ? null : Border.all(color: border),
      ),
    );
  }
}

class _MacroAverageCard extends StatelessWidget {
  const _MacroAverageCard({required this.snapshot, required this.previous});

  final TrendSnapshot snapshot;
  final TrendSnapshot previous;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '三大项日均 vs 目标',
            style: AppFonts.text(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          _MacroTrendRow(
            label: '蛋白质',
            value: snapshot.averageProtein,
            target: snapshot.targetProtein,
            color: AppColors.protein,
            delta: snapshot.deltaFrom(previous, (s) => s.averageProtein),
          ),
          const SizedBox(height: 18),
          _MacroTrendRow(
            label: '碳水',
            value: snapshot.averageCarb,
            target: snapshot.targetCarb,
            color: AppColors.carb,
            delta: snapshot.deltaFrom(previous, (s) => s.averageCarb),
          ),
          const SizedBox(height: 18),
          _MacroTrendRow(
            label: '脂肪',
            value: snapshot.averageFat,
            target: snapshot.targetFat,
            color: AppColors.fat,
            delta: snapshot.deltaFrom(previous, (s) => s.averageFat),
          ),
        ],
      ),
    );
  }
}

class _MacroTrendRow extends StatelessWidget {
  const _MacroTrendRow({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    this.delta,
  });

  final String label;
  final double value;
  final double target;
  final Color color;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final ratio = target <= 0 ? 0.0 : value / target;
    final over = ratio > 1;
    final shownValue = value.round();
    final shownTarget = target.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: AppFonts.text(size: 13, color: AppColors.ink2),
                ),
              ],
            ),
            RichText(
              text: TextSpan(
                style: AppFonts.number(size: 13),
                children: [
                  TextSpan(text: '$shownValue'),
                  TextSpan(
                    text: ' / $shownTarget g',
                    style: AppFonts.number(
                      size: 13,
                      weight: FontWeight.w400,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ThinProgressBar(
          value: ratio,
          color: color,
          height: AppSizes.barThick,
          showGoalMark: over,
        ),
        if (over || delta != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                if (over)
                  Text(
                    '日均超 ${(value - target).round()}g',
                    style: AppFonts.text(size: 11, color: AppColors.danger),
                  ),
                const Spacer(),
                _Delta(delta, unit: 'g'),
              ],
            ),
          ),
      ],
    );
  }
}

/// Water on its own line; below it, which meal the calories came from.
class _WaterMealCard extends StatelessWidget {
  const _WaterMealCard({required this.snapshot});

  final TrendSnapshot snapshot;

  static const _mealColors = {
    MealType.breakfast: AppColors.ink,
    MealType.lunch: AppColors.ink2,
    MealType.dinner: AppColors.ink3,
    MealType.snack: AppColors.ink4,
  };

  @override
  Widget build(BuildContext context) {
    final water = snapshot.averageWaterMl;
    final waterTarget = snapshot.averageWaterTargetMl;
    final meals = snapshot.mealKcal;
    final mealTotal = meals.values.fold<int>(0, (sum, kcal) => sum + kcal);
    final mealHint = _mealHint(meals, mealTotal);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '饮水与餐次',
            style: AppFonts.text(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          if (snapshot.waterLoggedDays == 0)
            Text(
              '这段时间没有饮水记录',
              style: AppFonts.text(size: 12, color: AppColors.ink3),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '日均饮水',
                  style: AppFonts.text(size: 13, color: AppColors.ink2),
                ),
                const Spacer(),
                NumText('$water', size: 16),
                Text(
                  ' / $waterTarget ml',
                  style: AppFonts.number(
                    size: 12,
                    weight: FontWeight.w400,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ThinProgressBar(
              value: waterTarget == 0 ? 0 : water / waterTarget,
              color: AppColors.water,
            ),
            const SizedBox(height: 6),
            Text(
              '${snapshot.waterHitDays}/${snapshot.waterLoggedDays} 天喝够'
              '${snapshot.totalDays > snapshot.waterLoggedDays ? ' · ${snapshot.totalDays - snapshot.waterLoggedDays} 天没记饮水' : ''}',
              style: AppFonts.text(size: 11, color: AppColors.ink3),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.lineSoft),
          const SizedBox(height: 14),
          Text(
            '热量来自哪一餐',
            style: AppFonts.text(size: 13, color: AppColors.ink2),
          ),
          const SizedBox(height: 10),
          if (mealTotal == 0)
            Text(
              '这段时间没有饮食记录',
              style: AppFonts.text(size: 12, color: AppColors.ink3),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final meal in MealType.values)
                      if (meals[meal]! > 0)
                        Expanded(
                          flex: meals[meal]!,
                          child: ColoredBox(
                            color: _mealColors[meal]!,
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final meal in MealType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _mealColors[meal],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      meal.label,
                      style: AppFonts.text(size: 12, color: AppColors.ink2),
                    ),
                    const Spacer(),
                    Text(
                      '日均 ${(meals[meal]! / snapshot.loggedDays).round()} kcal',
                      style: AppFonts.number(
                        size: 12,
                        weight: FontWeight.w400,
                        color: AppColors.ink3,
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(meals[meal]! * 100 / mealTotal).round()}%',
                        textAlign: TextAlign.right,
                        style: AppFonts.number(size: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (mealHint != null) ...[
              const SizedBox(height: 4),
              Text(
                mealHint,
                style: AppFonts.text(size: 11, color: AppColors.warnInk),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String? _mealHint(Map<MealType, int> meals, int total) {
    if (total == 0) return null;
    final dinner = meals[MealType.dinner]! * 100 / total;
    final snack = meals[MealType.snack]! * 100 / total;
    if (dinner > 45) return '晚餐占了 ${dinner.round()}%，热量集中在一天的末尾。';
    if (snack > 25) return '加餐占了 ${snack.round()}%，零食可能是不少热量的来源。';
    return null;
  }
}

/// The handful of foods that supplied most of the calories or protein.
class _TopFoodsCard extends StatefulWidget {
  const _TopFoodsCard({required this.snapshot});

  final TrendSnapshot snapshot;

  @override
  State<_TopFoodsCard> createState() => _TopFoodsCardState();
}

class _TopFoodsCardState extends State<_TopFoodsCard> {
  var _byProtein = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final foods = snapshot.topFoods(byProtein: _byProtein);
    double valueOf(FoodTally food) =>
        _byProtein ? food.protein : food.kcal.toDouble();
    final total = snapshot.recordedDays.fold<double>(
      0,
      (sum, day) =>
          sum + (_byProtein ? day.totals.protein : day.totals.kcal.toDouble()),
    );
    final top = foods.isEmpty ? 0.0 : valueOf(foods.first);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '主要来源',
                  style: AppFonts.text(size: 14, weight: FontWeight.w500),
                ),
              ),
              for (final (label, protein) in const [
                ('按热量', false),
                ('按蛋白质', true),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _byProtein == protein,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _byProtein = protein),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (foods.isEmpty)
            Text(
              '这段时间没有饮食记录',
              style: AppFonts.text(size: 12, color: AppColors.ink3),
            )
          else
            for (var i = 0; i < foods.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                child: _FoodRow(
                  rank: i + 1,
                  food: foods[i],
                  value: _byProtein
                      ? '${foods[i].protein.round()} g'
                      : '${foods[i].kcal} kcal',
                  share: total == 0 ? 0 : valueOf(foods[i]) / total,
                  relative: top == 0 ? 0 : valueOf(foods[i]) / top,
                  color: _byProtein ? AppColors.protein : AppColors.ink,
                ),
              ),
        ],
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.rank,
    required this.food,
    required this.value,
    required this.share,
    required this.relative,
    required this.color,
  });

  final int rank;
  final FoodTally food;
  final String value;
  final double share;
  final double relative;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 18,
              child: Text(
                '$rank',
                style: AppFonts.number(size: 12, color: AppColors.ink4),
              ),
            ),
            Expanded(
              child: Text(
                food.name,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.text(size: 13),
              ),
            ),
            Text(value, style: AppFonts.number(size: 13)),
            SizedBox(
              width: 40,
              child: Text(
                '${(share * 100).round()}%',
                textAlign: TextAlign.right,
                style: AppFonts.number(
                  size: 12,
                  weight: FontWeight.w400,
                  color: AppColors.ink3,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 18, top: 2),
          child: Text(
            '${food.times} 次 · 共 ${food.grams}g',
            style: AppFonts.text(size: 11, color: AppColors.ink4),
          ),
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: ThinProgressBar(value: relative, color: color),
        ),
      ],
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({required this.snapshot, required this.previous});

  final TrendSnapshot snapshot;
  final TrendSnapshot previous;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('记录习惯', style: AppFonts.text(size: 14, weight: FontWeight.w500)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HabitValue(
                  value: snapshot.loggedDays,
                  suffix: '/${snapshot.totalDays}',
                  label: '有记录天数',
                ),
              ),
              Expanded(
                child: _HabitValue(
                  value: snapshot.currentStreak,
                  label: '连续记录',
                ),
              ),
              Expanded(
                child: _HabitValue(
                  value: snapshot.photoEntryPercent,
                  suffix: '%',
                  label: '拍照记录占比',
                ),
              ),
            ],
          ),
          if (previous.loggedDays > 0) ...[
            const SizedBox(height: 10),
            _Delta(
              (snapshot.loggedDays - previous.loggedDays).toDouble(),
              unit: ' 天有记录',
              upIsGood: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _HabitValue extends StatelessWidget {
  const _HabitValue({
    required this.value,
    required this.label,
    this.suffix = '',
  });

  final int value;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            NumText('$value', size: 22),
            if (suffix.isNotEmpty)
              Text(
                suffix,
                style: AppFonts.number(
                  size: 12,
                  weight: FontWeight.w400,
                  color: AppColors.ink3,
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(label, style: AppFonts.text(size: 11, color: AppColors.ink3)),
      ],
    );
  }
}
