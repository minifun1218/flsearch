import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/portion_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';
import '../../domain/models/food.dart';

/// 手动录入。拍照之外的兜底路径 —— 没网、拍不了、不同意上传时，
/// 这里是完整可用的（PRD R-023 / R-027 / R-028）。
class AddFoodPage extends ConsumerStatefulWidget {
  const AddFoodPage({super.key, required this.meal, required this.date});

  final MealType meal;
  final DateTime date;

  @override
  ConsumerState<AddFoodPage> createState() => _AddFoodPageState();
}

class _AddFoodPageState extends ConsumerState<AddFoodPage> {
  final _controller = TextEditingController();
  int _tab = 0;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addFood(FoodNutrition food, {int initialGrams = 100}) async {
    final picked = await showPortionSheet(
      context,
      food: food,
      initialMeal: widget.meal,
      initialGrams: initialGrams,
    );
    if (picked == null || !mounted) return;

    final store = ref.read(logStoreProvider.notifier);
    store.addEntry(
      widget.date,
      store.newEntry(
        food: food,
        grams: picked.grams,
        meal: picked.meal,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  void _copyMeal(PastMeal past) {
    final store = ref.read(logStoreProvider.notifier);
    store.addAll(
      widget.date,
      [
        for (final e in past.entries)
          store.newEntry(
            food: e.food,
            grams: e.grams,
            meal: widget.meal,
          ),
      ],
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // 搜的是服务端那张营养缓存表；断网时 provider 自己退回内置食物表，
    // 手动录入这条兜底路径不能断（PRD R-023、N-4）。
    final search = ref.watch(foodSearchProvider(_query));
    final results = search.value ?? const <FoodNutrition>[];
    final favourites = ref.watch(favouriteFoodsProvider);
    final recent = ref.watch(recentMealsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            PageHeader(
              title: '添加到${widget.meal.label}',
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 0, AppSpacing.page, 18),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: _SearchField(
                controller: _controller,
                onChanged: (v) => setState(() {
                  _query = v;
                  if (v.isNotEmpty) _tab = 0;
                }),
              ),
            ),
            const SizedBox(height: 22),
            _Tabs(
              current: _tab,
              onChanged: (i) => setState(() => _tab = i),
              labels: [
                '搜索结果',
                '常吃 ${favourites.length}',
                '最近几餐',
              ],
            ),
            Expanded(
              child: switch (_tab) {
                0 => _SearchResults(
                    results: results,
                    query: _query,
                    loading: search.isLoading,
                    onPick: _addFood,
                    onCustom: _createCustomFood,
                  ),
                1 => _Favourites(foods: favourites, onPick: _addFood),
                _ => _RecentMeals(
                    meals: recent,
                    targetMeal: widget.meal,
                    onCopy: _copyMeal,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCustomFood() async {
    final food = await showModalBottomSheet<FoodNutrition>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _CustomFoodSheet(),
    );
    if (food == null || !mounted) return;

    // 自定义食物写进营养缓存表，此后所有人搜得到（PRD R-023）。
    // 写失败不挡着记这一餐：记录自带营养快照，本来就不依赖缓存表。
    var saved = food;
    try {
      saved = await ref.read(repositoryProvider).createFood(food);
    } on Object catch (e) {
      if (mounted) {
        ref.read(appMessageProvider.notifier).show(describeError(e));
      }
    }
    if (!mounted) return;
    await _addFood(saved);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              controller: controller,
              onChanged: onChanged,
              style: AppFonts.text(size: AppText.body),
              cursorColor: AppColors.ink,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜食物名，比如「鸡胸」',
                hintStyle:
                    AppFonts.text(size: AppText.body, color: AppColors.ink4),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            InkResponse(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              radius: 18,
              child: const Icon(Icons.close, size: 17, color: AppColors.ink3),
            ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.current,
    required this.onChanged,
    required this.labels,
  });

  final int current;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderCard)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.only(bottom: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == current
                          ? AppColors.ink
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: AppFonts.text(
                    size: 14,
                    weight:
                        i == current ? FontWeight.w500 : FontWeight.w400,
                    color: i == current ? AppColors.ink : AppColors.ink3,
                  ),
                ),
              ),
            ),
            if (i != labels.length - 1) const SizedBox(width: 22),
          ],
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.query,
    required this.loading,
    required this.onPick,
    required this.onCustom,
  });

  final List<FoodNutrition> results;
  final String query;
  final bool loading;
  final void Function(FoodNutrition) onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        if (results.isEmpty && loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
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
          _FoodRow(food: food, onTap: () => onPick(food)),
        Container(
          margin: const EdgeInsets.fromLTRB(
              AppSpacing.page, 20, AppSpacing.page, 0),
          child: AppCard(
            padding: const EdgeInsets.all(18),
            radius: AppRadius.listCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  results.isEmpty ? '没搜到「$query」' : '没有你要的？',
                  style:
                      AppFonts.text(size: 14, weight: FontWeight.w500),
                ),
                const SizedBox(height: 5),
                Text(
                  '自己填一条，营养值填一次就会被记住，下次直接可选。',
                  style: AppFonts.text(
                      size: 12, color: AppColors.ink3, height: 1.6),
                ),
                const SizedBox(height: 14),
                AppButton(
                  '自定义食物',
                  kind: AppButtonKind.secondary,
                  height: AppSizes.control,
                  icon: Icons.edit_outlined,
                  onPressed: onCustom,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Favourites extends StatelessWidget {
  const _Favourites({required this.foods, required this.onPick});

  final List<FoodNutrition> foods;
  final void Function(FoodNutrition) onPick;

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return const _EmptyState(
        icon: Icons.star_outline,
        title: '还没有常吃的食物',
        body: '在记录详情页把食物加入常吃，之后就能一步记一份。',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, 20, 10),
          child: Text(
            '点一下选份量，常吃的默认份量记得住',
            style: AppFonts.text(size: 12, color: AppColors.ink3),
          ),
        ),
        for (final food in foods)
          _FoodRow(food: food, favourite: true, onTap: () => onPick(food)),
      ],
    );
  }
}

class _RecentMeals extends StatelessWidget {
  const _RecentMeals({
    required this.meals,
    required this.targetMeal,
    required this.onCopy,
  });

  final List<PastMeal> meals;
  final MealType targetMeal;
  final void Function(PastMeal) onCopy;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) {
      return const _EmptyState(
        icon: Icons.content_copy_outlined,
        title: '最近 7 天还没有记录',
        body: '记过几餐之后，这里可以整餐复制过来。',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, 18, AppSpacing.page, 40),
      children: [
        Text(
          '整餐复制到${targetMeal.label} · 最近 7 天',
          style: AppFonts.text(size: 12, color: AppColors.ink3),
        ),
        const SizedBox(height: 12),
        for (final past in meals) ...[
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            radius: AppRadius.listCard,
            onTap: () => onCopy(past),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${past.date.month}月${past.date.day}日 '
                            '${past.meal.label}',
                            style: AppFonts.text(
                                size: 14, weight: FontWeight.w500),
                          ),
                          const SizedBox(width: 9),
                          NumText(
                            '${past.entries.length} 项 · ${past.kcal} kcal',
                            size: 12,
                            weight: FontWeight.w400,
                            color: AppColors.ink3,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        past.names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.text(
                            size: 12, color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: AppSizes.control,
                  height: AppSizes.control,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Icon(Icons.copy_outlined,
                      size: 16, color: AppColors.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.food,
    required this.onTap,
    this.favourite = false,
  });

  final FoodNutrition food;
  final VoidCallback onTap;
  final bool favourite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          food.name,
                          style: AppFonts.text(size: AppText.body),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (favourite) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.star,
                            size: 13, color: AppColors.carb),
                      ],
                    ],
                  ),
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
            const SizedBox(width: 12),
            Container(
              width: AppSizes.control,
              height: AppSizes.control,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: const Icon(Icons.add, size: 17, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.ink4),
            const SizedBox(height: 16),
            Text(title, style: AppFonts.text(size: 15, weight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppFonts.text(
                  size: 13, color: AppColors.ink3, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义食物：手填每 100g 营养值。热量不用填，由三大项折算。
class _CustomFoodSheet extends StatefulWidget {
  const _CustomFoodSheet();

  @override
  State<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends State<_CustomFoodSheet> {
  final _name = TextEditingController();
  final _protein = TextEditingController();
  final _carb = TextEditingController();
  final _fat = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
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
    final valid = _name.text.trim().isNotEmpty && kcal > 0;

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
          Text('自定义食物', style: AppFonts.title),
          const SizedBox(height: 8),
          Text(
            '填每 100g 的营养值。热量由三大项折算，不用另填。',
            style:
                AppFonts.text(size: 13, color: AppColors.ink2, height: 1.65),
          ),
          const SizedBox(height: 22),
          _Field(
            label: '食物名',
            controller: _name,
            hint: '比如「妈妈做的红烧肉」',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: '蛋白质 g',
                  controller: _protein,
                  numeric: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: '碳水 g',
                  controller: _carb,
                  numeric: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: '脂肪 g',
                  controller: _fat,
                  numeric: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '折算热量',
                style: AppFonts.text(size: 13, color: AppColors.ink2),
              ),
              NumText(
                '${kcal.round()} kcal / 100g',
                size: AppText.body,
                color: valid ? AppColors.ink : AppColors.ink4,
              ),
            ],
          ),
          const SizedBox(height: 22),
          AppButton(
            '下一步：选份量',
            onPressed: valid
                ? () => Navigator.of(context).pop(
                      FoodNutrition(
                        name: _name.text.trim(),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.numeric = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool numeric;

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
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            style: numeric
                ? AppFonts.number(size: AppText.body)
                : AppFonts.text(size: AppText.body),
            cursorColor: AppColors.ink,
            cursorWidth: 1.5,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.only(top: 4),
              border: InputBorder.none,
              hintText: hint ?? '0',
              hintStyle:
                  AppFonts.text(size: AppText.body, color: AppColors.ink4),
            ),
          ),
        ],
      ),
    );
  }
}
