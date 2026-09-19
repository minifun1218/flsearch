import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/portion_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';
import '../../data/recognition_service.dart';
import '../../domain/models/food.dart';

/// 确认识别结果。
///
/// 这页刻意不做「一键保存」的捷径：AI 估份量一定会错，所以份量控件永远在
/// 手边，改一下合计立刻跟着变（PRD R-021）。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({
    super.key,
    required this.items,
    required this.meal,
    required this.date,
  });

  final List<RecognizedItem> items;
  final MealType meal;
  final DateTime date;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _Draft {
  _Draft({
    required this.food,
    required this.grams,
    required this.uncertain,
    required this.fromCache,
  });

  final FoodNutrition food;
  int grams;
  bool uncertain;
  final bool fromCache;

  int get kcal => (food.kcalPer100g * grams / 100).round();

  double get protein => food.proteinPer100g * grams / 100;

  double get carb => food.carbPer100g * grams / 100;

  double get fat => food.fatPer100g * grams / 100;
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late final List<_Draft> _drafts = [
    for (final item in widget.items)
      _Draft(
        food: item.food,
        grams: item.estimatedGrams,
        uncertain: item.portionUncertain,
        fromCache: item.nutritionFromCache,
      ),
  ];

  late MealType _meal = widget.meal;
  late int _focused = _drafts.indexWhere((d) => d.uncertain);

  @override
  Widget build(BuildContext context) {
    var kcal = 0, count = 0;
    var protein = 0.0, carb = 0.0, fat = 0.0;
    for (final d in _drafts) {
      kcal += d.kcal;
      protein += d.protein;
      carb += d.carb;
      fat += d.fat;
      count++;
    }

    final cached = _drafts.where((d) => d.fromCache).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 34),
          children: [
            PageHeader(
              title: '确认这一餐',
              trailing: InkWell(
                onTap: () => Navigator.of(context).pop(false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('重拍',
                      style: AppFonts.text(size: 14, color: AppColors.ink2)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 0, AppSpacing.page, 20),
            ),

            // 照片 + 说明
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Row(
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECE7DE),
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: const Icon(Icons.restaurant,
                        size: 30, color: Color(0xFFB5AB9C)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _drafts.isEmpty
                              ? '没有可保存的项目'
                              : '识别到 $count 项食物',
                          style: AppFonts.text(
                              size: AppText.body, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '份量由 AI 估算，与实际可能有出入——请核对后再保存。',
                          style: AppFonts.text(
                              size: 12,
                              color: AppColors.ink3,
                              height: 1.55),
                        ),
                        if (cached > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '其中 $cached 项用了此前记住的营养值',
                            style: AppFonts.text(
                                size: 11, color: AppColors.positive),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 条目
            for (var i = 0; i < _drafts.length; i++) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: _DraftCard(
                  draft: _drafts[i],
                  focused: i == _focused,
                  onChanged: (g) => setState(() {
                    _drafts[i].grams = g;
                    _drafts[i].uncertain = false;
                    _focused = i;
                  }),
                  onDelete: () => setState(() {
                    _drafts.removeAt(i);
                    if (_focused >= _drafts.length) {
                      _focused = _drafts.length - 1;
                    }
                  }),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // 补加
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppButton(
                '漏了什么？手动补一项',
                kind: AppButtonKind.dashed,
                height: 50,
                icon: Icons.add,
                onPressed: _addManually,
              ),
            ),
            const SizedBox(height: 20),

            // 合计
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppCard(
                color: AppColors.surfaceAlt,
                border: null,
                radius: AppRadius.listCard,
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('这一餐合计',
                            style: AppFonts.text(
                                size: 14, weight: FontWeight.w500)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            NumText('$kcal', size: 24),
                            NumText(' kcal',
                                size: 13,
                                weight: FontWeight.w400,
                                color: AppColors.ink2),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _TotalMacro(
                            label: '蛋白质',
                            value: protein,
                            color: AppColors.protein,
                          ),
                        ),
                        Expanded(
                          child: _TotalMacro(
                            label: '碳水',
                            value: carb,
                            color: AppColors.carb,
                          ),
                        ),
                        Expanded(
                          child: _TotalMacro(
                            label: '脂肪',
                            value: fat,
                            color: AppColors.fat,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 归属
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('记入',
                      style:
                          AppFonts.text(size: 12, color: AppColors.ink3)),
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
                                borderRadius: BorderRadius.circular(
                                    AppRadius.control),
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
                        if (m != MealType.values.last)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    radius: AppRadius.control,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('日期',
                            style: AppFonts.text(
                                size: 13, color: AppColors.ink2)),
                        NumText(
                          '${widget.date.month}月${widget.date.day}日'
                          '${_isToday ? ' 今天' : ''}',
                          size: 13,
                          weight: FontWeight.w500,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppButton(
                _drafts.isEmpty ? '没有可保存的项目' : '保存到${_meal.label}',
                onPressed: _drafts.isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isToday =>
      dayKey(widget.date) == dayKey(DateTime.now());

  Future<void> _addManually() async {
    final food = await showModalBottomSheet<FoodNutrition>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _PickFoodSheet(),
    );
    if (food == null || !mounted) return;

    final picked = await showPortionSheet(
      context,
      food: food,
      initialMeal: _meal,
      allowMealChange: false,
      confirmLabel: '加入',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _drafts.add(_Draft(
        food: food,
        grams: picked.grams,
        uncertain: false,
        fromCache: false,
      ));
      _focused = _drafts.length - 1;
    });
  }

  void _save() {
    final store = ref.read(logStoreProvider.notifier);
    store.addAll(
      widget.date,
      [
        for (final d in _drafts)
          store.newEntry(
            food: d.food,
            grams: d.grams,
            meal: _meal,
            fromPhoto: true,
          ),
      ],
    );
    Navigator.of(context).pop(true);
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.focused,
    required this.onChanged,
    required this.onDelete,
  });

  final _Draft draft;
  final bool focused;
  final ValueChanged<int> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      radius: AppRadius.listCard,
      border: focused ? AppColors.borderDash : AppColors.borderCard,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            draft.food.name,
                            style: AppFonts.text(
                                size: AppText.body,
                                weight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (draft.uncertain) ...[
                          const SizedBox(width: 8),
                          const AppChip(
                            '份量待确认',
                            dense: true,
                            background: AppColors.warnChipBg,
                            foreground: AppColors.warn,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    NumText(
                      draft.food.summary,
                      size: 12,
                      weight: FontWeight.w400,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkResponse(
                onTap: onDelete,
                radius: 20,
                child: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.ink4),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              QuantityStepper(
                grams: draft.grams,
                focused: focused,
                onChanged: onChanged,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  NumText('${draft.kcal}', size: 17),
                  NumText(' kcal',
                      size: 12,
                      weight: FontWeight.w400,
                      color: AppColors.ink3),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalMacro extends StatelessWidget {
  const _TotalMacro({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                NumText('${value.round()}', size: AppText.body),
                NumText('g',
                    size: 11,
                    weight: FontWeight.w400,
                    color: AppColors.ink3),
              ],
            ),
            Text(label,
                style: AppFonts.text(size: 11, color: AppColors.ink3)),
          ],
        ),
      ],
    );
  }
}

/// 从食物库里挑一项补进识别结果。
class _PickFoodSheet extends ConsumerStatefulWidget {
  const _PickFoodSheet();

  @override
  ConsumerState<_PickFoodSheet> createState() => _PickFoodSheetState();
}

class _PickFoodSheetState extends ConsumerState<_PickFoodSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(foodSearchProvider(_query));
    // 搜索走服务端的营养缓存表；断网时 provider 自己退回内置食物表。
    final results = search.value ?? const <FoodNutrition>[];

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderDash,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('补一项', style: AppFonts.title),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: AppColors.ink3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      autofocus: false,
                      onChanged: (v) => setState(() => _query = v),
                      style: AppFonts.text(size: AppText.body),
                      cursorColor: AppColors.ink,
                      cursorWidth: 1.5,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜食物名',
                        hintStyle: AppFonts.text(
                            size: AppText.body, color: AppColors.ink4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (results.isEmpty && search.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.ink4),
                      ),
                    ),
                  ),
                for (final food in results)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(food),
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: AppColors.lineSoft)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(food.name,
                              style: AppFonts.text(size: AppText.body)),
                          const SizedBox(height: 3),
                          NumText(
                            food.summary,
                            size: 12,
                            weight: FontWeight.w400,
                            color: AppColors.ink3,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
