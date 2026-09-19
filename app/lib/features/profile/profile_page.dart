import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/weight_chart.dart';
import '../../data/app_state.dart';
import '../../domain/models/profile.dart';
import '../../domain/nutrition_calculator.dart';
import '../../data/reminders_state.dart';
import '../capture/consent_sheet.dart';
import '../reminders/reminder_settings_page.dart';
import '../targets/targets_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final now = DateTime.now();
    final training = NutritionCalculator.targetsFor(
      profile,
      now,
      overrideTrainingDay: true,
    );
    final rest = NutritionCalculator.targetsFor(
      profile,
      now,
      overrideTrainingDay: false,
    );
    final weights = ref.watch(weightSeriesProvider);

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.topSafe, bottom: 36),
      children: [
        const LargeTitle('我的'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('我的档案', style: AppFonts.cardTitle),
                        const SizedBox(height: 4),
                        Text(
                          '${profile.sex == Sex.male ? '男' : '女'} · ${profile.activityLevel.label}',
                          style: AppFonts.text(size: 12, color: AppColors.ink3),
                        ),
                      ],
                    ),
                    _EditButton(
                      onTap: () => _editProfile(context, ref, profile),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1, color: AppColors.lineSoft),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _ProfileMetric('${profile.ageOn(now)}', '岁'),
                    ),
                    Expanded(
                      child: _ProfileMetric(_number(profile.heightCm), 'cm'),
                    ),
                    Expanded(
                      child: _ProfileMetric(_number(profile.weightKg), 'kg'),
                    ),
                    Expanded(
                      child: _ProfileMetric(
                        '${profile.activityLevel.factor}',
                        '活动系数',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppCard(
            onTap: () => _openTargets(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '每日目标',
                      style: AppFonts.text(size: 14, weight: FontWeight.w500),
                    ),
                    Row(
                      children: [
                        Text(
                          '详情',
                          style: AppFonts.text(
                            size: 13,
                            color: AppColors.positive,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 17,
                          color: AppColors.positive,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${profile.goal.label} · 目标 ${_number(profile.targetWeightKg)} kg${profile.goal == GoalType.maintain ? '' : ' · 每周 ${_number(profile.weeklyRateKg)} kg'}',
                  style: AppFonts.text(size: 12, color: AppColors.ink3),
                ),
                const SizedBox(height: 16),
                _TargetSummary(target: training, days: profile.plan.days),
                const SizedBox(height: 10),
                _TargetSummary(
                  target: rest,
                  days: {
                    for (var day = 1; day <= 7; day++)
                      if (!profile.plan.days.contains(day)) day,
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('体重记录', style: AppFonts.cardTitle),
                    TextButton(
                      onPressed: () => _recordWeight(context, ref, profile),
                      child: const Text('记录体重'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (weights.isEmpty)
                  Text(
                    '还没有体重记录，记录一次开始跟踪变化。',
                    style: AppFonts.text(size: 13, color: AppColors.ink3),
                  )
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      NumText(weights.last.kg.toStringAsFixed(1), size: 30),
                      const SizedBox(width: 5),
                      Text(
                        'kg',
                        style: AppFonts.text(size: 13, color: AppColors.ink3),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${weights.last.date.month}/${weights.last.date.day} 最近记录',
                          textAlign: TextAlign.end,
                          style: AppFonts.text(size: 12, color: AppColors.ink3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  WeightChart(
                    points: weights,
                    targetKg: profile.targetWeightKg,
                  ),
                  const SizedBox(height: 10),
                  for (final point in weights.reversed.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          NumText(
                            '${point.date.year}/${point.date.month}/${point.date.day}',
                            size: 12,
                            weight: FontWeight.w400,
                            color: AppColors.ink3,
                          ),
                          NumText(
                            '${point.kg.toStringAsFixed(1)} kg',
                            size: 13,
                            weight: FontWeight.w500,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 9),
                  Text(
                    '同一天再次记录会更新当天体重。',
                    style: AppFonts.text(size: 11, color: AppColors.ink4),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('训练安排', style: AppFonts.cardTitle),
                const SizedBox(height: 10),
                Text(
                  profile.plan.days.isEmpty
                      ? '每周均为休息日'
                      : '${profile.plan.type.label} · 每周 ${profile.plan.trainingDayCount} 天 · 每次 ${profile.plan.minutes} 分钟',
                  style: AppFonts.text(size: 13, color: AppColors.ink2),
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        label: Text('周${_weekdays[day - 1]}'),
                        selected: profile.plan.days.contains(day),
                        showCheckmark: false,
                        onSelected: (selected) {
                          final days = {...profile.plan.days};
                          selected ? days.add(day) : days.remove(day);
                          ref
                              .read(profileProvider.notifier)
                              .update(
                                (value) => value.copyWith(
                                  plan: value.plan.copyWith(days: days),
                                ),
                              );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '点选训练日，目标会按新的周计划重新计算。',
                  style: AppFonts.text(size: 11, color: AppColors.ink4),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<TrainingType>(
                  initialValue: profile.plan.type,
                  decoration: const InputDecoration(labelText: '训练类型'),
                  items: [
                    for (final type in TrainingType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (type) {
                    if (type != null) {
                      ref
                          .read(profileProvider.notifier)
                          .update(
                            (value) => value.copyWith(
                              plan: value.plan.copyWith(type: type),
                            ),
                          );
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  '单次时长 ${profile.plan.minutes} 分钟',
                  style: AppFonts.text(size: 13, color: AppColors.ink2),
                ),
                Slider(
                  min: 15,
                  max: 180,
                  divisions: 33,
                  value: profile.plan.minutes.toDouble().clamp(15, 180),
                  label: '${profile.plan.minutes} 分钟',
                  onChanged: (minutes) => ref
                      .read(profileProvider.notifier)
                      .update(
                        (value) => value.copyWith(
                          plan: value.plan.copyWith(minutes: minutes.round()),
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.notifications_none,
                    color: AppColors.ink2,
                  ),
                  title: Text('提醒', style: AppFonts.text(size: 14)),
                  subtitle: Text(
                    _nextReminderLabel(ref),
                    style: AppFonts.text(size: 11, color: AppColors.ink3),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.ink3,
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const ReminderSettingsPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.lineFaint),
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.ink2,
                  ),
                  title: Text('隐私政策', style: AppFonts.text(size: 14)),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.ink3,
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const _PrivacyPolicyPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.lineFaint),
                SwitchListTile(
                  value: ref.watch(photoConsentProvider),
                  onChanged: (enabled) {
                    if (enabled) {
                      _showPhotoConsent(context, ref);
                    } else {
                      ref.read(photoConsentProvider.notifier).revoke();
                    }
                  },
                  title: Text('照片识别授权', style: AppFonts.text(size: 14)),
                  subtitle: Text(
                    '关闭后，下次识别会重新征求同意',
                    style: AppFonts.text(size: 11, color: AppColors.ink3),
                  ),
                  activeThumbColor: AppColors.positive,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.account_circle_outlined,
                    color: AppColors.ink2,
                  ),
                  title: Text('账号', style: AppFonts.text(size: 14)),
                  subtitle: Text(
                    ref.watch(accountEmailProvider) ?? '已登录',
                    style: AppFonts.text(size: 11, color: AppColors.ink3),
                  ),
                ),
                const Divider(height: 1, color: AppColors.lineFaint),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.ink2),
                  title: Text('退出登录', style: AppFonts.text(size: 14)),
                  onTap: () => _signOut(context, ref),
                ),
                const Divider(height: 1, color: AppColors.lineFaint),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    '注销账号',
                    style: AppFonts.text(size: 14, color: AppColors.danger),
                  ),
                  subtitle: Text(
                    '删除全部记录与照片，不可恢复',
                    style: AppFonts.text(size: 11, color: AppColors.ink3),
                  ),
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            'FitMeal 0.1.0',
            style: AppFonts.text(size: 11, color: AppColors.ink4),
          ),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(sessionProvider.notifier).signOut();
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  /// 注销是不可逆的，所以要求把「注销」两个字打出来（PRD R-004）。
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 「我的」页上那行小字：下一条提醒什么时候发。
  static String _nextReminderLabel(WidgetRef ref) {
    final next = ref.watch(nextReminderProvider);
    if (next == null) return '暂时没有要发的提醒';
    final at = next.at;
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return sameDay
        ? '下一条：今天 $time · ${next.title}'
        : '下一条：${at.month}月${at.day}日 $time · ${next.title}';
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  void _openTargets(BuildContext context) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const _TargetsRoute()));
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    final updated = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.32),
      builder: (_) => _ProfileEditor(profile: profile),
    );
    if (!context.mounted || updated == null) return;
    ref.read(profileProvider.notifier).update((_) => updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('档案已更新，每日目标已重新计算')));
  }

  Future<void> _recordWeight(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    final kg = await showDialog<double>(
      context: context,
      builder: (_) => _WeightDialog(profile: profile),
    );
    if (!context.mounted || kg == null) return;

    final recorded =
        await ref.read(weightStoreProvider.notifier).record(DateTime.now(), kg);
    if (recorded == null) return; // 失败的提示已经由仓储层冒出来了

    // 服务端记体重时就把档案里的体重改了，这里只对齐本地。
    ref.read(profileProvider.notifier).applyWeight(recorded.kg);
    if (!context.mounted) return;

    final delta = recorded.dailyKcalAfter - recorded.dailyKcalBefore;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          delta == 0
              ? '体重已记录，每日目标不变'
              : '体重已记录，每日目标 ${recorded.dailyKcalBefore} → '
                  '${recorded.dailyKcalAfter} kcal',
        ),
      ),
    );
  }

  Future<void> _showPhotoConsent(BuildContext context, WidgetRef ref) async {
    final accepted = await showPhotoConsentSheet(context);
    if (context.mounted && accepted == true) {
      ref.read(photoConsentProvider.notifier).accept();
    }
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      NumText(value, size: 17),
      const SizedBox(height: 3),
      Text(label, style: AppFonts.text(size: 10, color: AppColors.ink3)),
    ],
  );
}

class _TargetSummary extends StatelessWidget {
  const _TargetSummary({required this.target, required this.days});
  final DayTargets target;
  final Set<int> days;

  @override
  Widget build(BuildContext context) {
    final sorted = days.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                target.isTrainingDay
                    ? Icons.fitness_center
                    : Icons.bedtime_outlined,
                size: 14,
                color: target.isTrainingDay
                    ? AppColors.positive
                    : AppColors.ink3,
              ),
              const SizedBox(width: 7),
              Text(
                target.isTrainingDay ? '训练日' : '休息日',
                style: AppFonts.text(size: 13, weight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sorted.isEmpty
                      ? '无'
                      : sorted
                            .map((day) => ProfilePage._weekdays[day - 1])
                            .join(' '),
                  style: AppFonts.text(size: 11, color: AppColors.ink3),
                ),
              ),
              NumText('${target.kcal}', size: 16),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '蛋白 ${target.macros.proteinG}g · 碳水 ${target.macros.carbG}g · 脂肪 ${target.macros.fatG}g',
            style: AppFonts.text(size: 11, color: AppColors.ink2),
          ),
          const SizedBox(height: 4),
          Text(
            '饮水 ${target.waterMl} ml',
            style: AppFonts.text(size: 11, color: AppColors.water),
          ),
        ],
      ),
    );
  }
}

class _TargetsRoute extends StatelessWidget {
  const _TargetsRoute();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: const TargetsPage(showBackButton: true));
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog({required this.profile});
  final UserProfile profile;

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late final _controller = TextEditingController(
    text: widget.profile.weightKg.toStringAsFixed(1),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final weight = double.tryParse(_controller.text.trim());
    if (weight == null || !weight.isFinite || weight < 20 || weight > 300) {
      setState(() => _error = '请输入 20–300 kg 之间的体重');
      return;
    }
    Navigator.of(context).pop(weight);
  }

  @override
  Widget build(BuildContext context) {
    final weight = double.tryParse(_controller.text.trim());
    final valid =
        weight != null && weight.isFinite && weight >= 20 && weight <= 300;
    final before = NutritionCalculator.breakdown(widget.profile).dailyKcal;
    final after = valid
        ? NutritionCalculator.breakdown(
            widget.profile.copyWith(weightKg: weight),
          ).dailyKcal
        : before;
    final delta = after - before;
    return AlertDialog(
      title: const Text('记录今天的体重'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '体重',
              suffixText: 'kg',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          if (valid) ...[
            const SizedBox(height: 18),
            Text(
              '日均目标 $before → $after kcal',
              style: AppFonts.text(size: 13, weight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              delta == 0
                  ? '与当前目标相同'
                  : '${delta > 0 ? '增加' : '减少'} ${delta.abs()} kcal，保存后生效',
              style: AppFonts.text(size: 12, color: AppColors.ink3),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _save, child: const Text('保存并更新目标')),
      ],
    );
  }
}

/// 档案卡右上角的入口。
class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 15, color: AppColors.ink2),
            const SizedBox(width: 6),
            Text(
              '编辑',
              style: AppFonts.text(
                size: 13,
                weight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑档案。
///
/// 这张表单里每改一个字段，每日目标都会跟着变 —— 所以它是一张底部大表单，
/// 而不是一个挤在屏幕中间的对话框：字段分组、有解释、底部常驻一条热量预览，
/// 让用户在按保存之前就知道这次改动值多少千卡。
class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.profile});
  final UserProfile profile;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _height = TextEditingController(
    text: ProfilePage._number(widget.profile.heightCm),
  );
  late final _targetWeight = TextEditingController(
    text: ProfilePage._number(widget.profile.targetWeightKg),
  );
  late final _bodyFat = TextEditingController(
    text: widget.profile.bodyFatPercent?.toStringAsFixed(1) ?? '',
  );
  late Sex _sex = widget.profile.sex;
  late ActivityLevel _activity = widget.profile.activityLevel;
  late GoalType _goal = widget.profile.goal;
  late DateTime _birthDate = widget.profile.birthDate;
  late double _rate = widget.profile.weeklyRateKg;
  String? _error;

  @override
  void dispose() {
    _height.dispose();
    _targetWeight.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  /// 校验和组装是一回事：成功给档案，失败给错误文案。
  /// 底部预览用它算「保存后」的热量，保存按钮用它决定能不能走。
  ({UserProfile? profile, String? error}) _evaluate() {
    final height = double.tryParse(_height.text.trim());
    final target = double.tryParse(_targetWeight.text.trim());
    final fatText = _bodyFat.text.trim();
    final fat = fatText.isEmpty ? null : double.tryParse(fatText);

    if (height == null ||
        !height.isFinite ||
        height < 100 ||
        height > 230 ||
        target == null ||
        !target.isFinite ||
        target < 20 ||
        target > 300 ||
        (fatText.isNotEmpty &&
            (fat == null || !fat.isFinite || fat < 3 || fat > 60))) {
      return (profile: null, error: '请检查身高（100–230）、目标体重（20–300）和体脂率（3–60）');
    }
    if ((_goal == GoalType.cut && target >= widget.profile.weightKg) ||
        (_goal == GoalType.bulk && target <= widget.profile.weightKg)) {
      return (
        profile: null,
        error: _goal == GoalType.cut ? '减脂目标体重需要低于当前体重' : '增肌目标体重需要高于当前体重',
      );
    }
    return (
      profile: widget.profile.copyWith(
        sex: _sex,
        birthDate: _birthDate,
        heightCm: height,
        targetWeightKg: target,
        bodyFatPercent: fat,
        activityLevel: _activity,
        goal: _goal,
        weeklyRateKg: _rate,
      ),
      error: null,
    );
  }

  void _save() {
    final result = _evaluate();
    if (result.profile == null) {
      setState(() => _error = result.error);
      return;
    }
    Navigator.of(context).pop(result.profile);
  }

  void _touch() => setState(() => _error = null);

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: '选择出生日期',
      cancelText: '取消',
      confirmText: '好',
      fieldLabelText: '出生日期',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final draft = _evaluate().profile;
    final before = NutritionCalculator.breakdown(widget.profile).dailyKcal;
    final after = draft == null
        ? null
        : NutritionCalculator.breakdown(draft).dailyKcal;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDash,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                18,
                AppSpacing.page,
                14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('编辑档案', style: AppFonts.title),
                        const SizedBox(height: 4),
                        Text(
                          '改完保存，训练日和休息日的目标都会重新算一遍',
                          style: AppFonts.text(size: 12, color: AppColors.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkResponse(
                    onTap: () => Navigator.of(context).pop(),
                    radius: 22,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceAlt,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 17,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Flexible(
              // 表单一次全建出来：字段少，键盘跳转和测试都指望得上它们都在树里。
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  18,
                  AppSpacing.page,
                  22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: '基本信息',
                      hint: '用来算基础代谢',
                      child: Column(
                        children: [
                          SegmentedTabs(
                            labels: const ['男', '女'],
                            selected: _sex == Sex.male ? 0 : 1,
                            onChanged: (i) => setState(
                              () => _sex = i == 0 ? Sex.male : Sex.female,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _BirthDateRow(
                            date: _birthDate,
                            age: widget.profile
                                .copyWith(birthDate: _birthDate)
                                .ageOn(DateTime.now()),
                            onTap: _pickBirthDate,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _NumberField(
                                  controller: _height,
                                  label: '身高',
                                  suffix: 'cm',
                                  onChanged: _touch,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _NumberField(
                                  controller: _bodyFat,
                                  label: '体脂率（选填）',
                                  suffix: '%',
                                  hint: '不填',
                                  onChanged: _touch,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _Note(
                            _bodyFat.text.trim().isEmpty
                                ? '填了体脂率就改用 Katch-McArdle 公式，基础代谢更准。'
                                : '已按体脂率用 Katch-McArdle 公式估算基础代谢。',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.cardGap),
                    _Section(
                      title: '日常活动水平',
                      hint: '不含训练',
                      child: Column(
                        children: [
                          for (final level in ActivityLevel.values) ...[
                            _OptionTile(
                              title: level.label,
                              subtitle: level.description,
                              trailing: '×${level.factor}',
                              selected: level == _activity,
                              onTap: () => setState(() => _activity = level),
                            ),
                            if (level != ActivityLevel.values.last)
                              const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.cardGap),
                    _Section(
                      title: '目标',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              for (final goal in GoalType.values) ...[
                                Expanded(
                                  child: _GoalCard(
                                    goal: goal,
                                    selected: goal == _goal,
                                    onTap: () => setState(() {
                                      _goal = goal;
                                      _error = null;
                                      if (goal == GoalType.maintain) {
                                        _targetWeight.text =
                                            ProfilePage._number(
                                              widget.profile.weightKg,
                                            );
                                      }
                                    }),
                                  ),
                                ),
                                if (goal != GoalType.values.last)
                                  const SizedBox(width: 8),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          _Note(_goal.description),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _NumberField(
                                  controller: _targetWeight,
                                  label: '目标体重',
                                  suffix: 'kg',
                                  onChanged: _touch,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ReadOnlyField(
                                  label: '当前体重',
                                  value: ProfilePage._number(
                                    widget.profile.weightKg,
                                  ),
                                  suffix: 'kg',
                                ),
                              ),
                            ],
                          ),
                          if (_goal != GoalType.maintain) ...[
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '每周${_goal == GoalType.cut ? '减重' : '增重'}',
                                  style: AppFonts.text(
                                    size: 13,
                                    color: AppColors.ink2,
                                  ),
                                ),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    NumText(_rate.toStringAsFixed(2), size: 17),
                                    const SizedBox(width: 3),
                                    Text(
                                      'kg',
                                      style: AppFonts.text(
                                        size: 11,
                                        color: AppColors.ink3,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.ink,
                                inactiveTrackColor: AppColors.lineSoft,
                                thumbColor: AppColors.surface,
                                trackHeight: 4,
                                overlayColor: AppColors.ink.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                              child: Slider(
                                min: 0.25,
                                max: 1,
                                divisions: 15,
                                value: _rate.clamp(0.25, 1),
                                onChanged: (rate) =>
                                    setState(() => _rate = rate),
                              ),
                            ),
                            _Note(
                              _rate <= 0.5
                                  ? '这个速度比较稳，肌肉和状态都好保住。'
                                  : '速度偏快，注意蛋白质摄入和训练强度。',
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.cardGap),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: AppColors.dangerInk,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _error!,
                                style: AppFonts.text(
                                  size: 12.5,
                                  color: AppColors.dangerInk,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _EditorFooter(
              before: before,
              after: after,
              onCancel: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单分组：白卡 + 组标题，字段之间不再挤成一条。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.hint});

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: AppFonts.cardTitle),
              if (hint != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hint!,
                    style: AppFonts.text(size: 11, color: AppColors.ink4),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: AppFonts.text(size: 11, color: AppColors.ink4, height: 1.6),
    ),
  );
}

/// 数字输入框。标签常驻在框内左上角，单位贴右侧，数字用等宽字体。
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onChanged,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final VoidCallback onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );

    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppFonts.number(size: 18),
      cursorColor: AppColors.ink,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: AppFonts.text(size: 15, color: AppColors.ink4),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: AppFonts.text(size: 12, color: AppColors.ink3),
        floatingLabelStyle: AppFonts.text(size: 12, color: AppColors.ink3),
        suffixText: suffix,
        suffixStyle: AppFonts.text(size: 12, color: AppColors.ink3),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(14, 26, 14, 12),
        border: border(Colors.transparent, 0),
        enabledBorder: border(Colors.transparent, 0),
        focusedBorder: border(AppColors.ink, 1.4),
      ),
    );
  }
}

/// 只读的参照值（当前体重）—— 和输入框同一形状，但明显不可编辑。
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.suffix,
  });

  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.text(size: 12, color: AppColors.ink3),
          ),
          const SizedBox(height: 6),
          // 窄屏上数字优先缩放，不要撑破这一格。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                NumText(value, size: 18, color: AppColors.ink2),
                const SizedBox(width: 4),
                Text(
                  suffix,
                  style: AppFonts.text(size: 12, color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthDateRow extends StatelessWidget {
  const _BirthDateRow({
    required this.date,
    required this.age,
    required this.onTap,
  });

  final DateTime date;
  final int age;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '出生日期',
                  style: AppFonts.text(size: 12, color: AppColors.ink3),
                ),
                const SizedBox(height: 5),
                NumText('${date.year}/${date.month}/${date.day}', size: 17),
              ],
            ),
            const Spacer(),
            AppChip('$age 岁', dense: true),
            const SizedBox(width: 10),
            const Icon(
              Icons.calendar_today_outlined,
              size: 17,
              color: AppColors.ink2,
            ),
          ],
        ),
      ),
    );
  }
}

/// 活动水平那样「一句话解释 + 单选」的选项行。
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.positiveBg : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColors.positive : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.circle_outlined,
              size: 17,
              color: selected ? AppColors.positive : AppColors.ink4,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppFonts.text(
                      size: 14,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppFonts.text(size: 11, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            NumText(
              trailing,
              size: 12,
              weight: FontWeight.w500,
              color: selected ? AppColors.positive : AppColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final GoalType goal;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = {
    GoalType.cut: Icons.trending_down,
    GoalType.bulk: Icons.trending_up,
    GoalType.maintain: Icons.trending_flat,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColors.surfaceDark : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _icons[goal],
              size: 18,
              color: selected ? AppColors.onDark : AppColors.ink3,
            ),
            const SizedBox(height: 6),
            Text(
              goal.label,
              style: AppFonts.text(
                size: 13,
                weight: FontWeight.w500,
                color: selected ? AppColors.onDark : AppColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常驻页脚：先告诉用户这次改动把日均目标带到哪里，再给保存。
class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.before,
    required this.after,
    required this.onCancel,
    required this.onSave,
  });

  final int before;
  final int? after;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final delta = after == null ? 0 : after! - before;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        14,
        AppSpacing.page,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '日均目标',
                style: AppFonts.text(size: 12, color: AppColors.ink3),
              ),
              const SizedBox(width: 12),
              // 这一串「旧值 → 新值 差额」在窄屏上整体缩放，宁可小一号也不换行。
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      NumText(
                        '$before',
                        size: 14,
                        weight: FontWeight.w500,
                        color: AppColors.ink3,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Icon(
                          Icons.arrow_right_alt,
                          size: 16,
                          color: after == null
                              ? AppColors.ink4
                              : AppColors.ink2,
                        ),
                      ),
                      if (after == null)
                        Text(
                          '待确认',
                          style: AppFonts.text(size: 13, color: AppColors.ink4),
                        )
                      else ...[
                        NumText('$after', size: 18),
                        const SizedBox(width: 3),
                        Text(
                          'kcal',
                          style: AppFonts.text(size: 11, color: AppColors.ink3),
                        ),
                        if (delta != 0) ...[
                          const SizedBox(width: 8),
                          AppChip(
                            '${delta > 0 ? '+' : '−'}${delta.abs()}',
                            dense: true,
                            background: delta > 0
                                ? AppColors.warnChipBg
                                : AppColors.positiveBg,
                            foreground: delta > 0
                                ? AppColors.warn
                                : AppColors.positive,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  '取消',
                  kind: AppButtonKind.secondary,
                  height: 48,
                  onPressed: onCancel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppButton('保存', height: 48, onPressed: onSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyPage extends StatelessWidget {
  const _PrivacyPolicyPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('隐私政策'), backgroundColor: AppColors.bg),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Text('FitMeal 隐私说明', style: AppFonts.title),
        const SizedBox(height: 20),
        Text('档案与饮食记录', style: AppFonts.cardTitle),
        const SizedBox(height: 8),
        Text(
          '你填写的性别、出生日期、身高、体重、活动水平和目标，用于计算每日营养与饮水目标。饮食、饮水和体重记录用于展示进度与趋势。',
          style: AppFonts.text(size: 14, color: AppColors.ink2, height: 1.8),
        ),
        const SizedBox(height: 22),
        Text('照片识别', style: AppFonts.cardTitle),
        const SizedBox(height: 8),
        Text(
          '照片识别需先获得你的同意。授权只用于餐食识别，你可以随时在「我的」中关闭授权。当前版本使用本地演示识别，尚未连接第三方服务，也不会上传照片。',
          style: AppFonts.text(size: 14, color: AppColors.ink2, height: 1.8),
        ),
        const SizedBox(height: 22),
        Text('数据存储', style: AppFonts.cardTitle),
        const SizedBox(height: 8),
        Text(
          '当前版本的数据保存在运行内存中，关闭应用后会恢复演示数据。账号同步、持久化存储及正式服务的保存期限将在接入后提供。',
          style: AppFonts.text(size: 14, color: AppColors.ink2, height: 1.8),
        ),
      ],
    ),
  );
}

/// 注销确认。
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _input.text.trim() == '注销';
    return AlertDialog(
      backgroundColor: AppColors.bg,
      title: Text('注销账号？', style: AppFonts.cardTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '全部饮食记录、体重、照片会从服务端删除，无法恢复。'
            '确认请输入「注销」。',
            style: AppFonts.text(size: 14, color: AppColors.ink2),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            onChanged: (_) => setState(() {}),
            autofocus: true,
            style: AppFonts.text(size: 15),
            decoration: const InputDecoration(hintText: '注销'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消',
              style: AppFonts.text(size: 14, color: AppColors.ink2)),
        ),
        TextButton(
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            '确认注销',
            style: AppFonts.text(
              size: 14,
              weight: FontWeight.w500,
              color: ready ? AppColors.danger : AppColors.ink4,
            ),
          ),
        ),
      ],
    );
  }
}

