import 'package:flutter/material.dart';

import '../../domain/models/food.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// 选份量。从搜索结果、常吃、自定义食物添加时都走这里 ——
/// 份量是这个 App 唯一需要用户动手的数字，所以给它一整屏的空间。
Future<({int grams, MealType meal})?> showPortionSheet(
  BuildContext context, {
  required FoodNutrition food,
  required MealType initialMeal,
  int initialGrams = 100,
  bool allowMealChange = true,
  String confirmLabel = '添加',
}) {
  return showModalBottomSheet<({int grams, MealType meal})>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PortionSheet(
      food: food,
      initialMeal: initialMeal,
      initialGrams: initialGrams,
      allowMealChange: allowMealChange,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PortionSheet extends StatefulWidget {
  const _PortionSheet({
    required this.food,
    required this.initialMeal,
    required this.initialGrams,
    required this.allowMealChange,
    required this.confirmLabel,
  });

  final FoodNutrition food;
  final MealType initialMeal;
  final int initialGrams;
  final bool allowMealChange;
  final String confirmLabel;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  late int _grams = widget.initialGrams;
  late MealType _meal = widget.initialMeal;

  static const _quick = [50, 100, 150, 200];

  @override
  Widget build(BuildContext context) {
    final ratio = _grams / 100;
    final kcal = (widget.food.kcalPer100g * ratio).round();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 34,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDash,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(widget.food.name, style: AppFonts.title),
          const SizedBox(height: 6),
          NumText(
            widget.food.summary,
            size: 12,
            weight: FontWeight.w400,
            color: AppColors.ink3,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _BigStep(
                icon: Icons.remove,
                onTap: () => setState(
                    () => _grams = (_grams - 10).clamp(0, 5000)),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  NumText('$_grams', size: 42, height: 1),
                  const SizedBox(width: 5),
                  Text(
                    'g',
                    style: AppFonts.text(size: 17, color: AppColors.ink2),
                  ),
                ],
              ),
              _BigStep(
                icon: Icons.add,
                onTap: () => setState(() => _grams += 10),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final g in _quick) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _grams = g),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: AppSizes.chip,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _grams == g
                            ? AppColors.surfaceDark
                            : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: NumText(
                        '$g g',
                        size: AppText.label,
                        weight: _grams == g
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: _grams == g
                            ? AppColors.onDark
                            : AppColors.ink2,
                      ),
                    ),
                  ),
                ),
                if (g != _quick.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          DarkCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            radius: AppRadius.card,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '这份的摄入',
                      style: AppFonts.text(
                          size: 13, color: AppColors.onDarkMuted),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        NumText('$kcal', size: 28, color: AppColors.onDark),
                        NumText(
                          ' kcal',
                          size: 13,
                          weight: FontWeight.w400,
                          color: AppColors.onDarkMuted,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: AppColors.onDarkLine),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SheetMacro(
                        label: '蛋白质',
                        value: widget.food.proteinPer100g * ratio,
                      ),
                    ),
                    Expanded(
                      child: _SheetMacro(
                        label: '碳水',
                        value: widget.food.carbPer100g * ratio,
                      ),
                    ),
                    Expanded(
                      child: _SheetMacro(
                        label: '脂肪',
                        value: widget.food.fatPer100g * ratio,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.allowMealChange) ...[
            const SizedBox(height: 18),
            Text('记入', style: AppFonts.text(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 9),
            Row(
              children: [
                for (final m in MealType.values) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _meal = m),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: AppSizes.control,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _meal == m
                              ? AppColors.surfaceDark
                              : Colors.transparent,
                          border: Border.all(
                            color: _meal == m
                                ? AppColors.surfaceDark
                                : AppColors.border,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                        ),
                        child: Text(
                          m.label,
                          style: AppFonts.text(
                            size: AppText.label,
                            weight: _meal == m
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: _meal == m
                                ? AppColors.onDark
                                : AppColors.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (m != MealType.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
          const SizedBox(height: 22),
          AppButton(
            _grams == 0
                ? '份量不能为 0'
                : '${widget.confirmLabel}到${_meal.label}',
            onPressed: _grams == 0
                ? null
                : () => Navigator.of(context)
                    .pop((grams: _grams, meal: _meal)),
          ),
        ],
      ),
    );
  }
}

class _BigStep extends StatelessWidget {
  const _BigStep({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Icon(icon, size: 17, color: const Color(0xFF3A3630)),
      ),
    );
  }
}

class _SheetMacro extends StatelessWidget {
  const _SheetMacro({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            NumText(
              value.toStringAsFixed(1),
              size: 18,
              color: AppColors.onDark,
            ),
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
