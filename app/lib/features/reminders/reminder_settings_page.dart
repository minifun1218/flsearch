import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/primitives.dart';
import '../../data/notifications/reminder_scheduler.dart';
import '../../data/reminders_state.dart';
import '../../domain/models/food.dart';
import '../../domain/reminders.dart';

/// 提醒设置（PRD R-039）：每类独立开关、可调时间，外加全局免打扰。
///
/// 底部把「接下来会发的几条」直接列出来 —— 提醒这种东西最怕的就是设完不知道
/// 到底会不会响，与其让人等到明天，不如当场把排期摆出来。
class ReminderSettingsPage extends ConsumerWidget {
  const ReminderSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    final notifier = ref.read(reminderSettingsProvider.notifier);
    final permission = ref.watch(notificationPermissionProvider);
    final plan = ref.watch(reminderCoordinatorProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const PageHeader(title: '提醒'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 0, AppSpacing.page, 36),
                children: [
                  if (permission == NotificationPermission.denied)
                    const _PermissionNotice(),

                  _Section('进度检查'),
                  AppCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: '每日进度检查',
                          subtitle: '到点看看今天还差多少',
                          value: settings.dailyCheckEnabled,
                          onChanged: (v) => notifier
                              .update((s) => s.copyWith(dailyCheckEnabled: v)),
                        ),
                        if (settings.dailyCheckEnabled) ...[
                          const _Line(),
                          _TimeRow(
                            label: '检查时间',
                            value: settings.dailyCheckAt,
                            onPicked: (t) => notifier
                                .update((s) => s.copyWith(dailyCheckAt: t)),
                          ),
                          const _Line(),
                          _StepperRow(
                            label: '不足阈值',
                            value: '${(settings.shortfallRatio * 100).round()}%',
                            onMinus: settings.shortfallRatio <= 0.5
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    shortfallRatio: s.shortfallRatio - 0.05)),
                            onPlus: settings.shortfallRatio >= 0.95
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    shortfallRatio: s.shortfallRatio + 0.05)),
                          ),
                          const _Hint('热量或蛋白质低于目标的这个比例时才提醒。'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('超标提醒'),
                  AppCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: '超标时提醒',
                          subtitle: '保存记录当下就提醒',
                          value: settings.overLimitEnabled,
                          onChanged: (v) => notifier
                              .update((s) => s.copyWith(overLimitEnabled: v)),
                        ),
                        if (settings.overLimitEnabled) ...[
                          const _Line(),
                          _StepperRow(
                            label: '超标阈值',
                            value: '${(settings.overLimitRatio * 100).round()}%',
                            onMinus: settings.overLimitRatio <= 1.0
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    overLimitRatio: s.overLimitRatio - 0.05)),
                            onPlus: settings.overLimitRatio >= 1.5
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    overLimitRatio: s.overLimitRatio + 0.05)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('漏记提醒'),
                  AppCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: '某餐过点还没记',
                          subtitle: '只管早中晚三餐，加餐不提醒',
                          value: settings.missedMealEnabled,
                          onChanged: (v) => notifier
                              .update((s) => s.copyWith(missedMealEnabled: v)),
                        ),
                        if (settings.missedMealEnabled) ...[
                          const _Line(),
                          _StepperRow(
                            label: '宽限',
                            value: '${settings.missedMealGraceMinutes} 分钟',
                            onMinus: settings.missedMealGraceMinutes <= 15
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    missedMealGraceMinutes:
                                        s.missedMealGraceMinutes - 15)),
                            onPlus: settings.missedMealGraceMinutes >= 180
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    missedMealGraceMinutes:
                                        s.missedMealGraceMinutes + 15)),
                          ),
                          for (final meal in reminderMeals) ...[
                            const _Line(),
                            _TimeRow(
                              label: '${meal.label}截止',
                              value: settings.mealWindows[meal]!.end,
                              onPicked: (t) => notifier.update((s) {
                                final windows =
                                    Map<MealType, MealWindow>.of(s.mealWindows);
                                windows[meal] = MealWindow(
                                  start: windows[meal]!.start,
                                  end: t,
                                );
                                return s.copyWith(mealWindows: windows);
                              }),
                            ),
                          ],
                          _Hint('截止时间再加上宽限，就是提醒发出的时刻。'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('饮水提醒'),
                  AppCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: '按间隔提醒喝水',
                          subtitle: '只在活动时段内发',
                          value: settings.waterEnabled,
                          onChanged: (v) => notifier
                              .update((s) => s.copyWith(waterEnabled: v)),
                        ),
                        if (settings.waterEnabled) ...[
                          const _Line(),
                          _StepperRow(
                            label: '间隔',
                            value: '${settings.waterIntervalHours} 小时',
                            onMinus: settings.waterIntervalHours <= 1
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    waterIntervalHours:
                                        s.waterIntervalHours - 1)),
                            onPlus: settings.waterIntervalHours >= 6
                                ? null
                                : () => notifier.update((s) => s.copyWith(
                                    waterIntervalHours:
                                        s.waterIntervalHours + 1)),
                          ),
                          const _Line(),
                          _TimeRow(
                            label: '活动时段开始',
                            value: settings.waterStart,
                            onPicked: (t) =>
                                notifier.update((s) => s.copyWith(waterStart: t)),
                          ),
                          const _Line(),
                          _TimeRow(
                            label: '活动时段结束',
                            value: settings.waterEnd,
                            onPicked: (t) =>
                                notifier.update((s) => s.copyWith(waterEnd: t)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('称重提醒'),
                  AppCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: '每周称一次',
                          subtitle: '本周已经称过就不提醒',
                          value: settings.weighInEnabled,
                          onChanged: (v) => notifier
                              .update((s) => s.copyWith(weighInEnabled: v)),
                        ),
                        if (settings.weighInEnabled) ...[
                          const _Line(),
                          _WeekdayRow(
                            selected: settings.weighInWeekday,
                            onChanged: (day) => notifier
                                .update((s) => s.copyWith(weighInWeekday: day)),
                          ),
                          const _Line(),
                          _TimeRow(
                            label: '提醒时间',
                            value: settings.weighInAt,
                            onPicked: (t) =>
                                notifier.update((s) => s.copyWith(weighInAt: t)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('免打扰'),
                  AppCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: '免打扰时段',
                          subtitle: '这段时间内任何提醒都不发，结束后也不补发',
                          value: settings.quietHours.enabled,
                          onChanged: (v) => notifier.update((s) =>
                              s.copyWith(quietHours: s.quietHours.copyWith(enabled: v))),
                        ),
                        if (settings.quietHours.enabled) ...[
                          const _Line(),
                          _TimeRow(
                            label: '开始',
                            value: settings.quietHours.start,
                            onPicked: (t) => notifier.update((s) => s.copyWith(
                                quietHours: s.quietHours.copyWith(start: t))),
                          ),
                          const _Line(),
                          _TimeRow(
                            label: '结束',
                            value: settings.quietHours.end,
                            onPicked: (t) => notifier.update((s) => s.copyWith(
                                quietHours: s.quietHours.copyWith(end: t))),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  _Section('接下来会发的'),
                  AppCard(
                    child: plan.isEmpty
                        ? Text(
                            settings.anyEnabled
                                ? '接下来三天没有要发的提醒。'
                                : '所有提醒都关着。',
                            style: AppFonts.text(
                                size: AppText.label, color: AppColors.ink3),
                          )
                        : Column(
                            children: [
                              for (final reminder in plan.take(6)) ...[
                                _PlanRow(reminder: reminder),
                                if (reminder != plan.take(6).last) const _Line(),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 权限被拒之后的说明。不再弹系统权限框，只讲清楚现在会怎样（R-035）。
class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.section),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppRadius.listCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_off_outlined,
              size: 17, color: AppColors.warnInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '系统通知权限被关掉了。提醒会在你打开应用时以横幅出现；'
              '想收到系统通知，请到系统设置里为 FitMeal 打开通知。',
              style:
                  AppFonts.text(size: AppText.label, color: AppColors.warnInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.reminder});

  final PlannedReminder reminder;

  @override
  Widget build(BuildContext context) {
    final at = reminder.at;
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final when = sameDay
        ? '今天 ${_two(at.hour)}:${_two(at.minute)}'
        : '${at.month}月${at.day}日 ${_two(at.hour)}:${_two(at.minute)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(when, style: AppFonts.number(size: AppText.label)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reminder.title, style: AppFonts.text(size: AppText.label)),
              const SizedBox(height: 2),
              Text(
                reminder.body,
                style: AppFonts.text(
                    size: AppText.caption, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

// ---------------------------------------------------------------- 小件

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: AppFonts.text(size: AppText.label, color: AppColors.ink3)),
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

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(text,
            style:
                AppFonts.text(size: AppText.caption, color: AppColors.ink4)),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // 整行都能点 —— 开关那么小一块，没必要非得戳中它。
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.positive,
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final ClockTime value;
  final ValueChanged<ClockTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
          helpText: label,
          cancelText: '取消',
          confirmText: '好',
        );
        if (picked != null) onPicked(ClockTime(picked.hour, picked.minute));
      },
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppFonts.text(size: AppText.body))),
          Text(value.label, style: AppFonts.number(size: AppText.body)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 17, color: AppColors.ink4),
        ],
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
          width: 82,
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
        child: Icon(icon,
            size: 15, color: onTap == null ? AppColors.ink4 : AppColors.ink),
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('星期',
            style: AppFonts.text(size: AppText.label, color: AppColors.ink2)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var day = 1; day <= 7; day++)
              InkResponse(
                onTap: () => onChanged(day),
                radius: 26,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: day == selected
                        ? AppColors.surfaceDark
                        : AppColors.surfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _labels[day - 1],
                    style: AppFonts.text(
                      size: AppText.label,
                      color: day == selected ? AppColors.onDark : AppColors.ink2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
