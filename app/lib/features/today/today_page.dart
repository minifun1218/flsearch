import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/ring_progress.dart';
import '../../data/app_state.dart';
import '../../domain/models/food.dart';
import '../../domain/nutrition_calculator.dart';
import '../add_food/add_food_page.dart';
import '../entry/entry_detail_page.dart';

/// 首页。最大的数字永远是「还可摄入」，不是「已摄入」—— 用户在饭点看这页
/// 是为了决定下一口吃什么。
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  bool _showRemaining = true;

  static const _mealShare = {
    MealType.breakfast: 0.25,
    MealType.lunch: 0.35,
    MealType.dinner: 0.30,
    MealType.snack: 0.10,
  };

  Future<void> _addTo(MealType meal) async {
    final date = ref.read(selectedDateProvider);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddFoodPage(meal: meal, date: date),
      ),
    );
  }

  Future<void> _openEntry(FoodEntry entry) async {
    final date = ref.read(selectedDateProvider);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntryDetailPage(entry: entry, date: date),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedDateProvider);
    final log = ref.watch(dayLogProvider);
    final targets = ref.watch(dayTargetsProvider);
    final totals = log.totals;

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.topSafe, bottom: 28),
      children: [
        _DateBar(date: date),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: _CalorieCard(
            targets: targets,
            totals: totals,
            showRemaining: _showRemaining,
            onToggle: () => setState(() => _showRemaining = !_showRemaining),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: _WaterCard(log: log, goalMl: targets.waterMl),
        ),
        const SizedBox(height: AppSpacing.section),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('今日记录', style: AppFonts.cardTitle),
              Text(
                '${log.entries.length} 项',
                style: AppFonts.text(size: 12, color: AppColors.ink3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final meal in MealType.values) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: _MealCard(
              meal: meal,
              entries: log.entriesOf(meal),
              suggestedKcal: (targets.kcal * _mealShare[meal]!).round(),
              onAdd: () => _addTo(meal),
              onOpenEntry: _openEntry,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DateBar extends ConsumerWidget {
  const _DateBar({required this.date});

  final DateTime date;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(dayTargetsProvider);
    final isToday = dayKey(date) == dayKey(DateTime.now());
    final yesterday = dayOf(DateTime.now().subtract(const Duration(days: 1)));

    final relative = isToday
        ? '今天'
        : dayKey(date) == dayKey(yesterday)
        ? '昨天'
        : '${date.year} 年';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _ArrowButton(
                icon: Icons.chevron_left,
                onTap: () => ref.read(selectedDateProvider.notifier).shift(-1),
              ),
              // 点日期直接跳到任意一天，省掉一路点箭头。
              InkWell(
                onTap: () => _pickDate(context, ref),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          NumText('${date.month}月${date.day}日', size: 20),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.expand_more,
                            size: 18,
                            color: AppColors.ink3,
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$relative · 周${_weekdays[date.weekday - 1]}',
                        style: AppFonts.text(size: 12, color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
              ),
              _ArrowButton(
                icon: Icons.chevron_right,
                onTap: isToday
                    ? null
                    : () => ref.read(selectedDateProvider.notifier).shift(1),
              ),
            ],
          ),
          GestureDetector(
            onTap: () {
              final store = ref.read(logStoreProvider.notifier);
              store.setTrainingDayOverride(date, !targets.isTrainingDay);
            },
            child: targets.isTrainingDay
                ? const AppChip('训练日', icon: Icons.fitness_center)
                : const AppChip(
                    '休息日',
                    icon: Icons.bedtime_outlined,
                    background: AppColors.surfaceAlt,
                    foreground: AppColors.ink2,
                  ),
          ),
        ],
      ),
    );
  }

  /// 日期选择器。只开放到今天 —— 未来那几天没有记录可看。
  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final today = dayOf(DateTime.now());
    final first = DateTime(today.year - 2, today.month, today.day);
    // 一路按左箭头可以走到两年之外，初始值必须夹回可选范围里。
    final initial = date.isBefore(first)
        ? first
        : (date.isAfter(today) ? today : date);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '好',
      fieldLabelText: '日期',
      fieldHintText: '年/月/日',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: AppColors.surfaceDark,
            headerForegroundColor: AppColors.onDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.hero),
            ),
            todayBorder: const BorderSide(color: AppColors.positive),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(selectedDateProvider.notifier).set(picked);
    }
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 32,
        height: 40,
        child: Icon(
          icon,
          size: 22,
          color: onTap == null ? AppColors.line : AppColors.ink3,
        ),
      ),
    );
  }
}

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({
    required this.targets,
    required this.totals,
    required this.showRemaining,
    required this.onToggle,
  });

  final DayTargets targets;
  final MacroSum totals;
  final bool showRemaining;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final remaining = targets.kcal - totals.kcal;
    final over = remaining < 0;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
      child: Column(
        children: [
          RingProgress(
            value: targets.kcal == 0 ? 0 : totals.kcal / targets.kcal,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(60),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      showRemaining ? (over ? '已超出' : '还可摄入') : '已摄入',
                      style: AppFonts.text(
                        size: 12,
                        color: AppColors.ink3,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    NumText(
                      showRemaining ? '${remaining.abs()}' : '${totals.kcal}',
                      size: 52,
                      height: 1.05,
                      color: over && showRemaining
                          ? AppColors.danger
                          : AppColors.ink,
                    ),
                    NumText(
                      'kcal',
                      size: 13,
                      weight: FontWeight.w400,
                      color: AppColors.ink2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MiniStat(label: '已摄入', value: '${totals.kcal}'),
                Container(
                  width: 1,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  color: AppColors.lineSoft,
                ),
                _MiniStat(
                  label: targets.isTrainingDay ? '训练日目标' : '休息日目标',
                  value: '${targets.kcal}',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.lineSoft),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MacroColumn(
                  label: '蛋白质',
                  value: totals.protein,
                  goal: targets.macros.proteinG,
                  color: AppColors.protein,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _MacroColumn(
                  label: '碳水',
                  value: totals.carb,
                  goal: targets.macros.carbG,
                  color: AppColors.carb,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _MacroColumn(
                  label: '脂肪',
                  value: totals.fat,
                  goal: targets.macros.fatG,
                  color: AppColors.fat,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NumText(value, size: 17),
        const SizedBox(height: 2),
        Text(label, style: AppFonts.text(size: 11, color: AppColors.ink3)),
      ],
    );
  }
}

class _MacroColumn extends StatelessWidget {
  const _MacroColumn({
    required this.label,
    required this.value,
    required this.goal,
    required this.color,
  });

  final String label;
  final double value;
  final int goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final left = goal - value.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.text(size: 12, color: AppColors.ink2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            NumText(
              left >= 0 ? '剩 $left' : '超 ${left.abs()}',
              size: 11,
              weight: FontWeight.w400,
              color: left >= 0 ? AppColors.ink3 : AppColors.danger,
            ),
          ],
        ),
        const SizedBox(height: 7),
        ThinProgressBar(value: goal == 0 ? 0 : value / goal, color: color),
        const SizedBox(height: 7),
        // 三位数 / 三位数的组合在窄列里会顶出去，等比缩一点而不是截断。
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              NumText('${value.round()}', size: AppText.label),
              NumText(
                '/${goal}g',
                size: AppText.label,
                weight: FontWeight.w400,
                color: AppColors.ink3,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaterCard extends ConsumerWidget {
  const _WaterCard({required this.log, required this.goalMl});

  final DayLog log;
  final int goalMl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(logStoreProvider.notifier);
    final done = log.waterMl >= goalMl;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.water_drop_outlined,
                    size: 17,
                    color: AppColors.water,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '饮水',
                    style: AppFonts.text(size: 14, weight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  NumText('${log.waterMl}', size: AppText.label),
                  NumText(
                    ' / $goalMl ml',
                    size: AppText.label,
                    weight: FontWeight.w400,
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ThinProgressBar(
            value: goalMl == 0 ? 0 : log.waterMl / goalMl,
            color: AppColors.water,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _WaterButton(
                  label: '200 ml',
                  onTap: () => store.pourWater(log.date, 200),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WaterButton(
                  label: '500 ml',
                  onTap: () => store.pourWater(log.date, 500),
                ),
              ),
              const SizedBox(width: 10),
              _UndoButton(
                enabled: log.waterMl > 0,
                // 撤销最近一次，退多少由服务端说了算（PRD R-030）。
                onTap: () => store.undoWater(log.date),
              ),
            ],
          ),
          if (done) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.lineSoft),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.check, size: 14, color: AppColors.water),
                const SizedBox(width: 7),
                Text(
                  '今天的水喝够了',
                  style: AppFonts.text(size: 12, color: AppColors.water),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WaterButton extends StatelessWidget {
  const _WaterButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        height: AppSizes.control,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 13, color: Color(0xFF3A3630)),
                const SizedBox(width: 5),
                NumText(
                  label,
                  size: AppText.label,
                  weight: FontWeight.w400,
                  color: const Color(0xFF3A3630),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          width: AppSizes.control,
          height: AppSizes.control,
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? AppColors.border : AppColors.lineSoft,
            ),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: const Icon(Icons.undo, size: 16, color: AppColors.ink2),
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.entries,
    required this.suggestedKcal,
    required this.onAdd,
    required this.onOpenEntry,
  });

  final MealType meal;
  final List<FoodEntry> entries;
  final int suggestedKcal;
  final VoidCallback onAdd;
  final void Function(FoodEntry) onOpenEntry;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(AppRadius.listCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.listCard),
            border: Border.all(color: AppColors.borderDash),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.label,
                    style: AppFonts.text(size: 14, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '还没有记录 · 建议 $suggestedKcal kcal',
                    style: AppFonts.text(size: 12, color: AppColors.ink3),
                  ),
                ],
              ),
              Container(
                width: AppSizes.control,
                height: AppSizes.control,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Icon(
                  Icons.add,
                  size: 18,
                  color: Color(0xFF3A3630),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final kcal = entries.fold(0, (sum, e) => sum + e.kcal);

    return AppCard(
      padding: EdgeInsets.zero,
      radius: AppRadius.listCard,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 8, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  meal.label,
                  style: AppFonts.text(size: 14, weight: FontWeight.w500),
                ),
                Row(
                  children: [
                    NumText(
                      '$kcal kcal',
                      size: AppText.label,
                      weight: FontWeight.w400,
                      color: AppColors.ink2,
                    ),
                    InkResponse(
                      onTap: onAdd,
                      radius: 20,
                      child: const SizedBox(
                        width: 36,
                        height: 28,
                        child: Icon(Icons.add, size: 17, color: AppColors.ink3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final entry in entries)
            _EntryRow(entry: entry, onTap: () => onOpenEntry(entry)),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onTap});

  final FoodEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.lineFaint)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      entry.food.name,
                      style: AppFonts.text(size: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  NumText(
                    '${entry.grams} g',
                    size: 12,
                    weight: FontWeight.w400,
                    color: AppColors.ink3,
                  ),
                  if (entry.fromPhoto) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.photo_camera_outlined,
                      size: 11,
                      color: AppColors.ink4,
                    ),
                  ],
                ],
              ),
            ),
            NumText(
              '${entry.kcal}',
              size: AppText.label,
              weight: FontWeight.w400,
              color: AppColors.ink2,
            ),
          ],
        ),
      ),
    );
  }
}
