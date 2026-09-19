import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';
import '../../domain/models/profile.dart';
import '../../domain/nutrition_calculator.dart';

/// 每日目标。把 BMR → TDEE → 缺口 → 碳水周期化 → 三大项整条链路摊开——
/// 目标用户会质疑数字怎么来的，藏起来就不用了。
class TargetsPage extends ConsumerStatefulWidget {
  const TargetsPage({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  ConsumerState<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends ConsumerState<TargetsPage> {
  bool _trainingDay = true;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final parts = ref.watch(breakdownProvider);

    final kcal = _trainingDay ? parts.trainingDayKcal : parts.restDayKcal;
    final macros = NutritionCalculator.macros(
      kcal: kcal,
      weightKg: profile.weightKg,
      proteinPerKg: profile.proteinPerKg,
      fatPercentOfKcal: profile.fatPercentOfKcal,
      fatBasisKcal: parts.dailyKcal,
    );
    final water = NutritionCalculator.waterMl(
      weightKg: profile.weightKg,
      isTrainingDay: _trainingDay,
    );

    final days = profile.plan.days.toList()..sort();
    final restDays = [
      for (var d = 1; d <= 7; d++)
        if (!profile.plan.days.contains(d)) d,
    ];
    final shown = _trainingDay ? days : restDays;
    final hint = shown.isEmpty
        ? '本周没有这类日子'
        : '每周${shown.map((d) => _weekdayLabels[d - 1]).join(' · ')}';

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.topSafe, bottom: 40),
      children: [
        if (widget.showBackButton)
          const PageHeader(
            title: '我的每日目标',
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Text('我的每日目标', style: AppFonts.cardTitle),
          ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: SegmentedTabs(
            labels: const ['训练日', '休息日'],
            selected: _trainingDay ? 0 : 1,
            onChanged: (i) => setState(() => _trainingDay = i == 0),
          ),
        ),
        const SizedBox(height: 9),
        Center(
          child: Text(
            hint,
            style: AppFonts.text(size: 11, color: AppColors.ink4),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: _TargetHeroCard(
            kcal: kcal,
            macros: macros,
            waterMl: water,
            isTrainingDay: _trainingDay,
          ),
        ),
        const SizedBox(height: AppSpacing.section + 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Text('这个数字怎么来的', style: AppFonts.cardTitle),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: _BreakdownCard(
            profile: profile,
            parts: parts,
            macros: macros,
            trainingDaySelected: _trainingDay,
            onPickDay: (training) => setState(() => _trainingDay = training),
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('自己调', style: AppFonts.cardTitle),
              const SizedBox(height: 4),
              Text(
                '改了之后碳水自动补齐，总热量不变。',
                style: AppFonts.text(size: 12, color: AppColors.ink3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: _MacroSplitCard(profile: profile),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppButton(
            '恢复推荐值',
            kind: AppButtonKind.secondary,
            height: 50,
            onPressed:
                (profile.proteinPerKg - 1.8).abs() < 0.001 &&
                    (profile.fatPercentOfKcal - 25).abs() < 0.001
                ? null
                : () => ref.read(profileProvider.notifier).resetMacroSplit(),
          ),
        ),
      ],
    );
  }
}

class _TargetHeroCard extends StatelessWidget {
  const _TargetHeroCard({
    required this.kcal,
    required this.macros,
    required this.waterMl,
    required this.isTrainingDay,
  });

  final int kcal;
  final MacroTargets macros;
  final int waterMl;
  final bool isTrainingDay;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Column(
        children: [
          Text(
            '每日目标热量',
            style: AppFonts.text(
              size: 12,
              color: AppColors.onDarkMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          NumText('$kcal', size: 54, height: 1.08, color: AppColors.onDark),
          NumText(
            'kcal',
            size: 13,
            weight: FontWeight.w400,
            color: AppColors.onDarkMuted,
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: AppColors.onDarkLine),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _DarkMacro(
                  label: '蛋白质',
                  grams: macros.proteinG,
                  color: AppColors.proteinLight,
                ),
              ),
              Expanded(
                child: _DarkMacro(
                  label: '碳水',
                  grams: macros.carbG,
                  color: AppColors.carbLight,
                ),
              ),
              Expanded(
                child: _DarkMacro(
                  label: '脂肪',
                  grams: macros.fatG,
                  color: AppColors.fatLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(height: 1, color: AppColors.onDarkLine),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 15,
                color: AppColors.onDarkMuted,
              ),
              const SizedBox(width: 8),
              NumText(
                '饮水 $waterMl ml',
                size: AppText.label,
                weight: FontWeight.w400,
                color: AppColors.onDark.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 8),
              Text(
                isTrainingDay ? '含训练补水 500' : '按 35 ml/kg',
                style: AppFonts.text(size: 11, color: AppColors.onDarkFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkMacro extends StatelessWidget {
  const _DarkMacro({
    required this.label,
    required this.grams,
    required this.color,
  });

  final String label;
  final int grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 22,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            NumText('$grams', size: 22, color: AppColors.onDark),
            NumText(
              'g',
              size: 11,
              weight: FontWeight.w400,
              color: AppColors.onDarkMuted,
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppFonts.text(size: 11, color: AppColors.onDarkMuted),
        ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.profile,
    required this.parts,
    required this.macros,
    required this.trainingDaySelected,
    required this.onPickDay,
  });

  final UserProfile profile;
  final TargetBreakdown parts;
  final MacroTargets macros;
  final bool trainingDaySelected;
  final ValueChanged<bool> onPickDay;

  @override
  Widget build(BuildContext context) {
    final age = profile.ageOn(DateTime.now());
    final weight = profile.weightKg;
    final height = profile.heightCm;

    final bmrFormula = parts.usedKatchMcArdle
        ? 'Katch-McArdle：370 + 21.6 × '
              '${(weight * (1 - profile.bodyFatPercent! / 100)).toStringAsFixed(2)} 去脂体重'
        : 'Mifflin-St Jeor：10×$weight + 6.25×$height − 5×$age '
              '${profile.sex == Sex.male ? '+ 5' : '− 161'}';

    final goalWord = switch (profile.goal) {
      GoalType.cut => '减去减脂缺口',
      GoalType.bulk => '加上增肌盈余',
      GoalType.maintain => '维持，不加不减',
    };

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        children: [
          _Step(
            index: '1',
            title: '基础代谢 BMR',
            value: '${parts.bmr}',
            note: bmrFormula,
            hint: parts.usedKatchMcArdle ? null : '填了体脂率会换用 Katch-McArdle',
          ),
          _Step(
            index: '2',
            title: '每日总消耗 TDEE',
            value: '${parts.tdee}',
            note:
                '${parts.bmr} × ${parts.activityFactor}'
                '（${profile.activityLevel.label}）',
          ),
          _Step(
            index: '3',
            title: goalWord,
            value: '${parts.dailyKcal}',
            note: profile.goal == GoalType.maintain
                ? '目标是维持，直接吃到消耗水平'
                : '${parts.tdee} ${parts.dailyDeltaKcal >= 0 ? '+' : '−'} '
                      '${parts.dailyDeltaKcal.abs()}'
                      '（每周 ${profile.weeklyRateKg} kg）· 日均目标',
            warning: parts.clampedToBmr
                ? '算出的热量低于基础代谢，已按 ${parts.bmr} kcal 兜底'
                : null,
          ),
          _StepCustom(
            index: '4',
            active: true,
            title: '按训练日拆开',
            note: '热量挪到训练日，蛋白和脂肪两天一样，差异全在碳水上。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _DayChip(
                        label: '训练日 ×${profile.plan.trainingDayCount}',
                        kcal: parts.trainingDayKcal,
                        selected: trainingDaySelected,
                        onTap: () => onPickDay(true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DayChip(
                        label: '休息日 ×${profile.plan.restDayCount}',
                        kcal: parts.restDayKcal,
                        selected: !trainingDaySelected,
                        onTap: () => onPickDay(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                NumText(
                  '(${parts.trainingDayKcal}×${profile.plan.trainingDayCount}'
                  ' + ${parts.restDayKcal}×${profile.plan.restDayCount})'
                  ' ÷ 7 = ${parts.dailyKcal}',
                  size: 10,
                  weight: FontWeight.w400,
                  color: AppColors.ink4,
                ),
              ],
            ),
          ),
          _StepCustom(
            index: '5',
            last: true,
            title: '分到三大项',
            child: Column(
              children: [
                const SizedBox(height: 11),
                _MacroLine(
                  color: AppColors.protein,
                  formula:
                      '${profile.proteinPerKg.toStringAsFixed(1)} g/kg × $weight',
                  grams: macros.proteinG,
                ),
                const SizedBox(height: 9),
                _MacroLine(
                  color: AppColors.fat,
                  formula: '${profile.fatPercentOfKcal.round()}% 热量 ÷ 9',
                  grams: macros.fatG,
                ),
                const SizedBox(height: 9),
                _MacroLine(
                  color: AppColors.carb,
                  formula: '剩余热量 ÷ 4',
                  grams: macros.carbG,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.value,
    required this.note,
    this.hint,
    this.warning,
  });

  final String index;
  final String title;
  final String value;
  final String note;
  final String? hint;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return _StepCustom(
      index: index,
      title: title,
      value: value,
      note: note,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 11,
                    color: AppColors.ink3,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    hint!,
                    style: AppFonts.text(size: 10, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
          ],
          if (warning != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                warning!,
                style: AppFonts.text(size: 11, color: AppColors.dangerInk),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepCustom extends StatelessWidget {
  const _StepCustom({
    required this.index,
    required this.title,
    this.value,
    this.note,
    this.child,
    this.active = false,
    this.last = false,
  });

  final String index;
  final String title;
  final String? value;
  final String? note;
  final Widget? child;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.surfaceDark
                      : const Color(0xFFF0ECE4),
                  shape: BoxShape.circle,
                ),
                child: NumText(
                  index,
                  size: 11,
                  color: active ? AppColors.onDark : AppColors.ink2,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.only(top: 7),
                    color: AppColors.borderCard,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 18, 0, last ? 20 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppFonts.text(
                            size: 14,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (value != null) NumText(value!, size: 16),
                    ],
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      note!,
                      style: AppFonts.text(
                        size: 11,
                        color: AppColors.ink3,
                        height: 1.6,
                      ),
                    ),
                  ],
                  ?child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.kcal,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int kcal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceDark : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppFonts.text(
                size: 11,
                color: selected ? AppColors.onDarkMuted : AppColors.ink3,
              ),
            ),
            const SizedBox(height: 2),
            NumText(
              '$kcal',
              size: 17,
              color: selected ? AppColors.onDark : AppColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroLine extends StatelessWidget {
  const _MacroLine({
    required this.color,
    required this.formula,
    required this.grams,
  });

  final Color color;
  final String formula;
  final int grams;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
            NumText(
              formula,
              size: 12,
              weight: FontWeight.w400,
              color: AppColors.ink2,
            ),
          ],
        ),
        NumText('$grams g', size: AppText.label, weight: FontWeight.w500),
      ],
    );
  }
}

class _MacroSplitCard extends ConsumerWidget {
  const _MacroSplitCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(profileProvider.notifier);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SliderRow(
            label: '蛋白质',
            valueLabel: profile.proteinPerKg.toStringAsFixed(1),
            unit: 'g/kg',
            value: profile.proteinPerKg,
            min: 1.2,
            max: 2.4,
            divisions: 12,
            color: AppColors.protein,
            onChanged: notifier.setProteinPerKg,
          ),
          if (profile.proteinPerKg > 2.2)
            const _Notice(
              text: '超过 2.2 g/kg 对增肌没有额外收益，碳水会被挤得很少。',
              background: AppColors.warnBg,
              foreground: AppColors.warnInk,
              icon: Icons.info_outline,
            ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.lineSoft),
          const SizedBox(height: 20),
          _SliderRow(
            label: '脂肪占总热量',
            valueLabel: profile.fatPercentOfKcal.round().toString(),
            unit: '%',
            value: profile.fatPercentOfKcal,
            min: 10,
            max: 40,
            divisions: 30,
            color: AppColors.fat,
            onChanged: notifier.setFatPercent,
          ),
          if (profile.fatPercentOfKcal < 15)
            const _Notice(
              text: '脂肪低于 15% 会影响激素水平，长期不建议。',
              background: AppColors.dangerBg,
              foreground: AppColors.dangerInk,
              icon: Icons.warning_amber_rounded,
            ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final String unit;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: AppFonts.text(size: 13, color: const Color(0xFF3A3630)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                NumText(valueLabel, size: AppText.body),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: AppFonts.text(size: 11, color: AppColors.ink3),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: AppColors.line,
            thumbColor: AppColors.surface,
            overlayColor: color.withValues(alpha: 0.12),
            thumbShape: _RingThumb(color: color),
            trackShape: const RoundedRectSliderTrackShape(),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              NumText(
                min.toStringAsFixed(min == min.roundToDouble() ? 0 : 1),
                size: 10,
                weight: FontWeight.w400,
                color: AppColors.ink4,
              ),
              NumText(
                max.toStringAsFixed(max == max.roundToDouble() ? 0 : 1),
                size: 10,
                weight: FontWeight.w400,
                color: AppColors.ink4,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 白心 + 彩色描边的滑块拇指，对应设计稿。
class _RingThumb extends SliderComponentShape {
  const _RingThumb({required this.color});

  final Color color;

  static const _radius = 12.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      _radius,
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, _radius, Paint()..color = AppColors.surface);
    canvas.drawCircle(
      center,
      _radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppFonts.text(size: 12, color: foreground, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
