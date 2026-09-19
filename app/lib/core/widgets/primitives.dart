import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 数字文本。凡是数字都走这里，保证等宽对齐。
class NumText extends StatelessWidget {
  const NumText(
    this.value, {
    super.key,
    this.size = AppText.body,
    this.weight = FontWeight.w600,
    this.color = AppColors.ink,
    this.height,
  });

  final String value;
  final double size;
  final FontWeight weight;
  final Color color;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: AppFonts.number(
        size: size,
        weight: weight,
        color: color,
        height: height,
      ),
    );
  }
}

/// 白底描边卡片 —— 页面的默认容器。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPad),
    this.radius = AppRadius.card,
    this.color = AppColors.surface,
    this.border = AppColors.borderCard,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: child,
    );

    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: box,
    );
  }
}

/// 深色主卡 —— 一屏最多一个，用来放当天最重要的那组数字。
class DarkCard extends StatelessWidget {
  const DarkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
    this.radius = AppRadius.hero,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

enum AppButtonKind { primary, secondary, dashed }

class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.height = AppSizes.button,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final (bg, fg, border) = switch (kind) {
      AppButtonKind.primary => (
          enabled ? AppColors.surfaceDark : AppColors.line,
          enabled ? AppColors.onDark : AppColors.ink4,
          null,
        ),
      AppButtonKind.secondary => (
          Colors.transparent,
          AppColors.ink,
          const BorderSide(color: AppColors.border),
        ),
      AppButtonKind.dashed => (
          Colors.transparent,
          AppColors.ink2,
          const BorderSide(color: AppColors.borderDash),
        ),
    };

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            decoration: border == null
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.fromBorderSide(border),
                  ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppFonts.text(
                    size: AppText.body,
                    weight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 分段控件（训练日 / 休息日、近 7 天 / 近 30 天）。
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.height = 40,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final double height;

  static const _slideDuration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0ECE4),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // 白色滑块在选项之间平移，而不是逐个淡入淡出。
            AnimatedAlign(
              duration: _slideDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                labels.length <= 1
                    ? 0
                    : -1 + 2 * selected / (labels.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.07),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(i),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: _slideDuration,
                          curve: Curves.easeOutCubic,
                          style: AppFonts.text(
                            size: 14,
                            weight: i == selected
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: i == selected
                                ? AppColors.ink
                                : AppColors.ink2,
                          ),
                          child: Text(labels[i]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 细进度条。[value] 超过 1 时进入超标视觉，并在目标位置画一道刻度。
class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = AppSizes.barThin,
    this.showGoalMark = false,
  });

  final double value;
  final Color color;
  final double height;
  final bool showGoalMark;

  @override
  Widget build(BuildContext context) {
    final over = value > 1;
    final width = over ? 1.0 : value.clamp(0.0, 1.0);
    final markAt = over ? (1 / value).clamp(0.0, 1.0) : 1.0;

    return LayoutBuilder(
      builder: (context, box) {
        return SizedBox(
          height: showGoalMark ? height + 6 : height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: showGoalMark ? 3 : 0,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.lineSoft,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: showGoalMark ? 3 : 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  height: height,
                  width: box.maxWidth * width,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              if (showGoalMark && over)
                Positioned(
                  left: box.maxWidth * markAt - 1,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: height + 6,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 小标签（训练日 / 份量待确认 / 选填）。
class AppChip extends StatelessWidget {
  const AppChip(
    this.label, {
    super.key,
    this.background = AppColors.positiveBg,
    this.foreground = AppColors.positive,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(dense ? 6 : AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppFonts.text(
              size: dense ? 10 : 12,
              weight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 份量加减控件。识别结果和记录编辑共用。
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.grams,
    required this.onChanged,
    this.step = 10,
    this.focused = false,
  });

  final int grams;
  final ValueChanged<int> onChanged;
  final int step;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: focused ? AppColors.ink : AppColors.border,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove,
            onTap: () => onChanged((grams - step).clamp(0, 9999)),
          ),
          Container(
            width: 74,
            height: AppSizes.control,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                NumText('$grams', size: AppText.body),
                const SizedBox(width: 3),
                Text(
                  'g',
                  style: AppFonts.text(size: 12, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onTap: () => onChanged(grams + step),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: AppSizes.control,
        height: AppSizes.control,
        child: Icon(icon, size: 15, color: const Color(0xFF3A3630)),
      ),
    );
  }
}
