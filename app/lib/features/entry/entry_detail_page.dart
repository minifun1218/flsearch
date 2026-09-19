import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';
import '../../domain/models/food.dart';

/// 编辑一条记录。除了改份量，这里还是「修正每 100g 营养值」的入口 ——
/// 修正会写回缓存，之后再记这个食物就用新值，历史记录不受影响（PRD R-025）。
class EntryDetailPage extends ConsumerStatefulWidget {
  const EntryDetailPage({
    super.key,
    required this.entry,
    required this.date,
  });

  final FoodEntry entry;
  final DateTime date;

  @override
  ConsumerState<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends ConsumerState<EntryDetailPage> {
  late int _grams = widget.entry.grams;
  late FoodNutrition _food = widget.entry.food;

  /// 改过营养值 —— 保存时要一并写回缓存表（PRD R-025）。
  bool _nutritionCorrected = false;

  static const _quick = [80, 120, 150, 200];

  bool get _dirty =>
      _grams != widget.entry.grams || _food != widget.entry.food;

  @override
  Widget build(BuildContext context) {
    final ratio = _grams / 100;
    final kcal = (_food.kcalPer100g * ratio).round();
    final favourites = ref.watch(favouritesProvider);
    final isFavourite = favourites.contains(_food.name);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 34),
          children: [
            PageHeader(
              title: '编辑记录',
              trailing: InkResponse(
                onTap: _confirmDelete,
                radius: 22,
                child: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.danger),
              ),
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 0, AppSpacing.page, 24),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _food.name,
                    style: AppFonts.text(
                      size: AppText.title,
                      weight: FontWeight.w600,
                      letterSpacing: -0.02 * AppText.title,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${widget.date.month}月${widget.date.day}日 · '
                    '${widget.entry.meal.label} · '
                    '${widget.entry.fromPhoto ? '由拍照识别添加' : '手动添加'}',
                    style:
                        AppFonts.text(size: 13, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            // 份量
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('份量',
                        style: AppFonts.text(
                            size: 13, color: AppColors.ink3)),
                    const SizedBox(height: 14),
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
                            Text('g',
                                style: AppFonts.text(
                                    size: 17, color: AppColors.ink2)),
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
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.chip),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),

            // 换算结果
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: DarkCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 22),
                radius: AppRadius.card,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('这份的实际摄入',
                            style: AppFonts.text(
                                size: 13, color: AppColors.onDarkMuted)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            NumText('$kcal',
                                size: 30, color: AppColors.onDark),
                            NumText(' kcal',
                                size: 13,
                                weight: FontWeight.w400,
                                color: AppColors.onDarkMuted),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Divider(height: 1, color: AppColors.onDarkLine),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _DarkMacro(
                            label: '蛋白质',
                            value: _food.proteinPer100g * ratio,
                          ),
                        ),
                        Expanded(
                          child: _DarkMacro(
                            label: '碳水',
                            value: _food.carbPer100g * ratio,
                          ),
                        ),
                        Expanded(
                          child: _DarkMacro(
                            label: '脂肪',
                            value: _food.fatPer100g * ratio,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),

            // 每 100g 营养值
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('每 100g 营养值',
                            style: AppFonts.text(
                                size: 14, weight: FontWeight.w500)),
                        InkWell(
                          onTap: _editNutrition,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Text(
                              '修正',
                              style: AppFonts.text(
                                size: 13,
                                weight: FontWeight.w500,
                                color: AppColors.positive,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '修正后这个食物以后都按新数值计算，历史记录不受影响。',
                      style: AppFonts.text(
                          size: 12, color: AppColors.ink3, height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    _NutritionRow(
                      label: '热量',
                      value: '${_food.kcalPer100g.round()} kcal',
                    ),
                    _NutritionRow(
                      label: '蛋白质',
                      value: '${_food.proteinPer100g.toStringAsFixed(1)} g',
                      color: AppColors.protein,
                    ),
                    _NutritionRow(
                      label: '碳水',
                      value: '${_food.carbPer100g.toStringAsFixed(1)} g',
                      color: AppColors.carb,
                    ),
                    _NutritionRow(
                      label: '脂肪',
                      value: '${_food.fatPer100g.toStringAsFixed(1)} g',
                      color: AppColors.fat,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),

            // 常吃
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                radius: AppRadius.listCard,
                onTap: () => ref
                    .read(favouritesProvider.notifier)
                    .toggle(_food.name),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isFavourite ? Icons.star : Icons.star_outline,
                          size: 18,
                          color: isFavourite
                              ? AppColors.carb
                              : AppColors.ink4,
                        ),
                        const SizedBox(width: 11),
                        Text(
                          isFavourite ? '已加入常吃' : '加入常吃',
                          style: AppFonts.text(size: 14),
                        ),
                      ],
                    ),
                    _Switch(value: isFavourite),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppButton(
                _dirty ? '保存修改' : '没有改动',
                onPressed: _dirty ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    ref.read(logStoreProvider.notifier).updateEntry(
          widget.date,
          widget.entry.copyWith(grams: _grams, food: _food),
          updateFoodCache: _nutritionCorrected,
        );
    Navigator.of(context).pop(true);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        title: Text('删掉这条记录？', style: AppFonts.cardTitle),
        content: Text(
          '${_food.name} $_grams g 会从${widget.entry.meal.label}里移除。',
          style: AppFonts.text(size: 14, color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消',
                style: AppFonts.text(size: 14, color: AppColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('删除',
                style: AppFonts.text(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    ref
        .read(logStoreProvider.notifier)
        .removeEntry(widget.date, widget.entry.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _editNutrition() async {
    final corrected = await showModalBottomSheet<FoodNutrition>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CorrectNutritionSheet(food: _food),
    );
    if (corrected == null || !mounted) return;

    // 只改这一屏；保存时随记录一起提交，并写回缓存表 ——
    // 之后再记这个食物就用新值，已保存的历史记录不受影响。
    setState(() {
      _food = corrected;
      _nutritionCorrected = true;
    });
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

class _DarkMacro extends StatelessWidget {
  const _DarkMacro({required this.label, required this.value});

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
            NumText(value.toStringAsFixed(1),
                size: 18, color: AppColors.onDark),
            NumText('g',
                size: 11,
                weight: FontWeight.w400,
                color: AppColors.onDarkMuted),
          ],
        ),
        const SizedBox(height: 3),
        Text(label,
            style: AppFonts.text(size: 11, color: AppColors.onDarkMuted)),
      ],
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lineFaint)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (color != null) ...[
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Text(label,
                  style: AppFonts.text(size: 14, color: AppColors.ink2)),
            ],
          ),
          NumText(value, size: 14, weight: FontWeight.w500),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? AppColors.surfaceDark : AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// 修正每 100g 营养值。热量由三大项折算，避免出现自相矛盾的数据。
class _CorrectNutritionSheet extends StatefulWidget {
  const _CorrectNutritionSheet({required this.food});

  final FoodNutrition food;

  @override
  State<_CorrectNutritionSheet> createState() =>
      _CorrectNutritionSheetState();
}

class _CorrectNutritionSheetState extends State<_CorrectNutritionSheet> {
  late final _protein = TextEditingController(
      text: widget.food.proteinPer100g.toStringAsFixed(1));
  late final _carb =
      TextEditingController(text: widget.food.carbPer100g.toStringAsFixed(1));
  late final _fat =
      TextEditingController(text: widget.food.fatPer100g.toStringAsFixed(1));

  @override
  void dispose() {
    _protein.dispose();
    _carb.dispose();
    _fat.dispose();
    super.dispose();
  }

  double _read(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final p = _read(_protein);
    final c = _read(_carb);
    final f = _read(_fat);
    final kcal = p * 4 + c * 4 + f * 9;
    final changed = p != widget.food.proteinPer100g ||
        c != widget.food.carbPer100g ||
        f != widget.food.fatPer100g;

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
          Text('修正营养值', style: AppFonts.title),
          const SizedBox(height: 8),
          Text(
            '${widget.food.name} 每 100g。改完之后这个食物都按新值算，'
            '已经记过的不动。',
            style:
                AppFonts.text(size: 13, color: AppColors.ink2, height: 1.65),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: '蛋白质 g',
                  controller: _protein,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  label: '碳水 g',
                  controller: _carb,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  label: '脂肪 g',
                  controller: _fat,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('折算热量',
                  style: AppFonts.text(size: 13, color: AppColors.ink2)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (changed) ...[
                    NumText(
                      '${widget.food.kcalPer100g.round()}',
                      size: AppText.body,
                      weight: FontWeight.w400,
                      color: AppColors.ink4,
                    ),
                    const SizedBox(width: 7),
                    const Icon(Icons.arrow_forward,
                        size: 13, color: AppColors.ink2),
                    const SizedBox(width: 7),
                  ],
                  NumText('${kcal.round()} kcal', size: AppText.body),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          AppButton(
            changed ? '保存并记住' : '没有改动',
            onPressed: changed && kcal > 0
                ? () => Navigator.of(context).pop(
                      widget.food.copyWith(
                        kcalPer100g: kcal,
                        proteinPer100g: p,
                        carbPer100g: c,
                        fatPer100g: f,
                      ),
                    )
                : null,
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppFonts.text(size: 11, color: AppColors.ink3)),
          TextField(
            controller: controller,
            onChanged: onChanged,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: AppFonts.number(size: AppText.body),
            cursorColor: AppColors.ink,
            cursorWidth: 1.5,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.only(top: 4),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}
