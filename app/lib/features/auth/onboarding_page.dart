import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';
import '../../domain/models/profile.dart';
import '../../domain/nutrition_calculator.dart';

/// 建档引导（PRD R-005 ~ R-008）。
///
/// 登录了但服务端还没有档案时走这一屏。字段范围和服务端校验一致，
/// 而且底部实时把算出来的目标热量摆出来 —— 填完就知道自己每天吃多少，
/// 不用先保存再去别的页面找。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _height = TextEditingController(text: '175');
  final _weight = TextEditingController(text: '70');
  final _targetWeight = TextEditingController(text: '66');
  final _bodyFat = TextEditingController();

  Sex _sex = Sex.male;
  DateTime _birthDate = DateTime(1995, 1, 1);
  ActivityLevel _activity = ActivityLevel.moderate;
  GoalType _goal = GoalType.cut;
  Set<int> _trainingDays = {1, 3, 5};
  TrainingType _trainingType = TrainingType.strength;
  int _minutes = 60;
  double _rate = 0.5;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _targetWeight.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  /// 校验与组装是同一件事：成功给档案，失败给一句话。
  ({UserProfile? profile, String? error}) _evaluate() {
    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    final target = double.tryParse(_targetWeight.text.trim());
    final fatText = _bodyFat.text.trim();
    final fat = fatText.isEmpty ? null : double.tryParse(fatText);

    if (height == null || height < 100 || height > 230) {
      return (profile: null, error: '身高填 100–230 之间');
    }
    if (weight == null || weight < 20 || weight > 300) {
      return (profile: null, error: '体重填 20–300 之间');
    }
    if (target == null || target < 20 || target > 300) {
      return (profile: null, error: '目标体重填 20–300 之间');
    }
    if (fatText.isNotEmpty && (fat == null || fat < 3 || fat > 60)) {
      return (profile: null, error: '体脂率填 3–60，或者留空');
    }
    if (_goal == GoalType.cut && target >= weight) {
      return (profile: null, error: '减脂目标体重需要低于当前体重');
    }
    if (_goal == GoalType.bulk && target <= weight) {
      return (profile: null, error: '增肌目标体重需要高于当前体重');
    }

    return (
      profile: UserProfile(
        sex: _sex,
        birthDate: _birthDate,
        heightCm: height,
        weightKg: weight,
        bodyFatPercent: fat,
        activityLevel: _activity,
        plan: TrainingPlan(
          days: _trainingDays,
          type: _trainingType,
          minutes: _minutes,
        ),
        goal: _goal,
        targetWeightKg: target,
        weeklyRateKg: _goal == GoalType.maintain ? 0 : _rate,
      ),
      error: null,
    );
  }

  Future<void> _save() async {
    final result = _evaluate();
    if (result.profile == null) {
      setState(() => _error = result.error);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .completeOnboarding(result.profile!);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _touch() => setState(() => _error = null);

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: '选择出生日期',
      cancelText: '取消',
      confirmText: '好',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _evaluate().profile;
    final preview = draft == null
        ? null
        : NutritionCalculator.targetsFor(draft, DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 28, AppSpacing.page, 20),
                children: [
                  Text('先建个档案',
                      style: AppFonts.number(
                          size: AppText.title, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    '每日目标全部由这些数字算出来，之后随时可以改。',
                    style: AppFonts.text(
                        size: AppText.body, color: AppColors.ink2),
                  ),
                  const SizedBox(height: 24),

                  _Section('基本信息'),
                  AppCard(
                    child: Column(
                      children: [
                        _ChoiceRow<Sex>(
                          label: '性别',
                          value: _sex,
                          options: const {Sex.male: '男', Sex.female: '女'},
                          onChanged: (v) => setState(() {
                            _sex = v;
                            _error = null;
                          }),
                        ),
                        const _Line(),
                        _TapRow(
                          label: '出生日期',
                          value: '${_birthDate.year} 年 '
                              '${_birthDate.month} 月 ${_birthDate.day} 日',
                          onTap: _pickBirthDate,
                        ),
                        const _Line(),
                        _NumberRow(
                          label: '身高',
                          unit: 'cm',
                          controller: _height,
                          onChanged: _touch,
                        ),
                        const _Line(),
                        _NumberRow(
                          label: '当前体重',
                          unit: 'kg',
                          controller: _weight,
                          onChanged: _touch,
                        ),
                        const _Line(),
                        _NumberRow(
                          label: '体脂率',
                          unit: '%',
                          hint: '可不填',
                          controller: _bodyFat,
                          onChanged: _touch,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '填了体脂率就改用 Katch-McArdle 公式算基础代谢，比身高体重更准。',
                    style: AppFonts.text(
                        size: AppText.caption, color: AppColors.ink3),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('日常活动'),
                  AppCard(
                    child: Column(
                      children: [
                        for (final level in ActivityLevel.values) ...[
                          _OptionRow(
                            title: level.label,
                            subtitle: level.description,
                            trailing: '×${level.factor}',
                            selected: _activity == level,
                            onTap: () => setState(() {
                              _activity = level;
                              _error = null;
                            }),
                          ),
                          if (level != ActivityLevel.values.last) const _Line(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('训练计划'),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('每周哪几天练',
                            style: AppFonts.text(
                                size: AppText.label, color: AppColors.ink2)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var day = 1; day <= 7; day++)
                              _DayToggle(
                                label: const ['一', '二', '三', '四', '五', '六', '日'][day - 1],
                                selected: _trainingDays.contains(day),
                                onTap: () => setState(() {
                                  _trainingDays = Set.of(_trainingDays);
                                  if (!_trainingDays.remove(day)) {
                                    _trainingDays.add(day);
                                  }
                                  _error = null;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _Line(),
                        _ChoiceRow<TrainingType>(
                          label: '训练类型',
                          value: _trainingType,
                          options: {
                            for (final t in TrainingType.values) t: t.label,
                          },
                          onChanged: (v) => setState(() {
                            _trainingType = v;
                            _error = null;
                          }),
                        ),
                        const _Line(),
                        _StepperRow(
                          label: '单次时长',
                          value: '$_minutes 分钟',
                          onMinus: _minutes <= 15
                              ? null
                              : () => setState(() => _minutes -= 15),
                          onPlus: _minutes >= 180
                              ? null
                              : () => setState(() => _minutes += 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('目标'),
                  AppCard(
                    child: Column(
                      children: [
                        for (final goal in GoalType.values) ...[
                          _OptionRow(
                            title: goal.label,
                            subtitle: goal.description,
                            selected: _goal == goal,
                            onTap: () => setState(() {
                              _goal = goal;
                              _error = null;
                            }),
                          ),
                          if (goal != GoalType.values.last) const _Line(),
                        ],
                        if (_goal != GoalType.maintain) ...[
                          const _Line(),
                          _NumberRow(
                            label: '目标体重',
                            unit: 'kg',
                            controller: _targetWeight,
                            onChanged: _touch,
                          ),
                          const _Line(),
                          _StepperRow(
                            label: '每周变化',
                            value: '${_rate.toStringAsFixed(2)} kg',
                            onMinus: _rate <= 0.25
                                ? null
                                : () => setState(() => _rate -= 0.25),
                            onPlus: _rate >= 1.0
                                ? null
                                : () => setState(() => _rate += 0.25),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_goal == GoalType.cut && _rate > 0.75) ...[
                    const SizedBox(height: 10),
                    Text(
                      '每周掉 0.75 kg 以上很难只掉脂肪，肌肉也会跟着走。',
                      style: AppFonts.text(
                          size: AppText.caption, color: AppColors.warnInk),
                    ),
                  ],
                ],
              ),
            ),
            _Footer(
              kcal: preview?.kcal,
              protein: preview?.macros.proteinG,
              error: _error,
              busy: _busy,
              // 按钮始终可点：填得不对就说明哪里不对，而不是给一颗
              // 灰掉的按钮让人自己猜。
              onSave: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.kcal,
    required this.protein,
    required this.error,
    required this.busy,
    required this.onSave,
  });

  final int? kcal;
  final int? protein;

  /// 哪里填得不对。放在按钮正上方 —— 页面很长，错误提示不能藏在滚动区里。
  final String? error;
  final bool busy;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, 14, AppSpacing.page, 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderCard)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('今天的目标',
                  style: AppFonts.text(
                      size: AppText.label, color: AppColors.ink2)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  NumText(kcal == null ? '—' : '$kcal', size: 20),
                  const SizedBox(width: 4),
                  Text('kcal',
                      style: AppFonts.text(
                          size: AppText.caption, color: AppColors.ink3)),
                  if (protein != null) ...[
                    const SizedBox(width: 12),
                    Text('蛋白 $protein g',
                        style: AppFonts.text(
                            size: AppText.caption, color: AppColors.ink3)),
                  ],
                ],
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 15, color: AppColors.dangerInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: AppFonts.text(
                        size: AppText.label, color: AppColors.dangerInk),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          AppButton(busy ? '保存中…' : '开始记录', onPressed: onSave),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 小件

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: AppFonts.text(size: AppText.label, color: AppColors.ink3),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 1, color: AppColors.lineSoft),
      );
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.unit,
    required this.controller,
    required this.onChanged,
    this.hint = '',
  });

  final String label;
  final String unit;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppFonts.text(size: AppText.body))),
        SizedBox(
          width: 90,
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: AppFonts.number(size: AppText.body),
            cursorColor: AppColors.ink,
            cursorWidth: 1.5,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: AppFonts.text(
                  size: AppText.label, color: AppColors.ink4),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 26,
          child: Text(unit,
              style: AppFonts.text(
                  size: AppText.caption, color: AppColors.ink3)),
        ),
      ],
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppFonts.text(size: AppText.body))),
          Text(value,
              style: AppFonts.text(size: AppText.body, color: AppColors.ink2)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 17, color: AppColors.ink4),
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppFonts.text(size: AppText.body))),
        for (final option in options.entries)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: InkWell(
              onTap: () => onChanged(option.key),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: option.key == value
                      ? AppColors.surfaceDark
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  option.value,
                  style: AppFonts.text(
                    size: AppText.label,
                    color: option.key == value
                        ? AppColors.onDark
                        : AppColors.ink2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? AppColors.positive : AppColors.ink4,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppFonts.text(size: AppText.body)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppFonts.text(
                        size: AppText.caption, color: AppColors.ink3)),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: AppFonts.number(
                    size: AppText.label, color: AppColors.ink3)),
        ],
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceDark : AppColors.surfaceAlt,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: AppFonts.text(
            size: AppText.label,
            color: selected ? AppColors.onDark : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppFonts.text(size: AppText.body))),
        _Round(icon: Icons.remove, onTap: onMinus),
        SizedBox(
          width: 86,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: AppFonts.number(size: AppText.label),
          ),
        ),
        _Round(icon: Icons.add, onTap: onPlus),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 15,
          color: onTap == null ? AppColors.ink4 : AppColors.ink,
        ),
      ),
    );
  }
}
