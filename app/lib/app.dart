import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'data/app_state.dart';
import 'data/reminders_state.dart';
import 'domain/models/food.dart';
import 'domain/reminders.dart';
import 'features/add_food/add_food_page.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/onboarding_page.dart';
import 'features/capture/capture_page.dart';
import 'features/profile/profile_page.dart';
import 'features/today/today_page.dart';
import 'features/trends/trends_page.dart';

class FitMealApp extends StatelessWidget {
  const FitMealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitMeal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      // 日期选择器等系统组件要跟着界面说中文。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _SessionGate(),
    );
  }
}

/// 按登录态决定进哪一屏。
///
/// 主界面只在 [AuthStage.ready] 出现 —— 也就是档案和最近 30 天都已经在手上，
/// 页面因此可以一直同步读数据，不必每一处都写「还在加载」。
class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return switch (session.stage) {
      AuthStage.loading => const _Splash(),
      AuthStage.signedOut => AuthPage(notice: session.message),
      AuthStage.needsProfile => const OnboardingPage(),
      AuthStage.failed => _ConnectionFailed(message: session.message),
      AuthStage.ready => const HomeShell(),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.ink3,
          ),
        ),
      ),
    );
  }
}

class _ConnectionFailed extends ConsumerWidget {
  const _ConnectionFailed({this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 30, color: AppColors.ink3),
              const SizedBox(height: 16),
              Text(
                message ?? '连不上服务端',
                textAlign: TextAlign.center,
                style: AppFonts.text(size: 14, color: AppColors.ink2),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: () =>
                    ref.read(sessionProvider.notifier).loadEverything(),
                child: Text(
                  '重试',
                  style: AppFonts.text(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.positive,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                child: Text(
                  '退出登录',
                  style: AppFonts.text(size: 13, color: AppColors.ink3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台时重排一次提醒。
  ///
  /// 排程是在应用活着的时候算的，内容里带着「还差多少」这种会变的数字；
  /// 用户也可能刚在系统设置里把通知打开。两件事都靠这次重算兜住。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(notificationPermissionProvider.notifier).refresh();
    ref.invalidate(reminderCoordinatorProvider);
  }

  @override
  Widget build(BuildContext context) {
    // 写操作失败时的那句提示，从这里统一冒出来。
    ref.listen<String?>(appMessageProvider, (_, message) {
      if (message == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      ref.read(appMessageProvider.notifier).clear();
    });

    final offline = ref.watch(sessionProvider).offline;
    // 挂上提醒调度：记录、体重、设置一变就重排（PRD R-033 ~ R-039）。
    ref.watch(reminderCoordinatorProvider);
    final banner = ref.watch(foregroundReminderProvider);

    return Scaffold(
      body: Column(
        children: [
          if (offline) const _OfflineBanner(),
          if (banner != null) _ReminderBanner(reminder: banner),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [TodayPage(), TrendsPage(), ProfilePage()],
            ),
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SizedBox(
                width: 58,
                height: 58,
                child: FloatingActionButton(
                  onPressed: _capture,
                  backgroundColor: AppColors.surfaceDark,
                  foregroundColor: AppColors.onDark,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(Icons.photo_camera_outlined, size: 25),
                ),
              ),
            )
          : null,
      bottomNavigationBar: _BottomNav(
        current: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
    );
  }

  /// 按当前时间猜一个餐次，省掉一次选择。
  MealType _guessMeal() {
    final hour = DateTime.now().hour;
    if (hour < 10) return MealType.breakfast;
    if (hour < 14) return MealType.lunch;
    if (hour < 17) return MealType.snack;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }

  Future<void> _capture() async {
    final date = ref.read(selectedDateProvider);
    final meal = _guessMeal();

    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => CapturePage(date: date, meal: meal),
      ),
    );

    // 相机页里选了「手动」，或者用户不同意上传 —— 都落到手动录入。
    if (result == 'manual' && mounted) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AddFoodPage(meal: meal, date: date),
        ),
      );
    }
  }
}

/// 没有系统通知权限时的降级路径：到点在应用内摆一条横幅（PRD R-035）。
class _ReminderBanner extends ConsumerWidget {
  const _ReminderBanner({required this.reminder});

  final PlannedReminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.positiveBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notifications_none,
                  size: 16, color: AppColors.positive),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: AppFonts.text(
                        size: 13,
                        weight: FontWeight.w500,
                        color: AppColors.positive,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reminder.body,
                      style: AppFonts.text(size: 12, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
              InkResponse(
                onTap: () =>
                    ref.read(foregroundReminderProvider.notifier).dismiss(),
                radius: 20,
                child: const Icon(Icons.close, size: 16, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前显示的是本地快照。能看，不能改 —— 写操作会直接失败并提示。
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.warnBg,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => ref.read(sessionProvider.notifier).loadEverything(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 15, color: AppColors.warnInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前离线，显示的是上次同步的数据',
                    style: AppFonts.text(size: 12, color: AppColors.warnInk),
                  ),
                ),
                Text(
                  '重试',
                  style: AppFonts.text(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.warnInk,
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

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.home_outlined, Icons.home, '今日'),
    (Icons.bar_chart_outlined, Icons.bar_chart, '统计'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDFCFA),
        border: Border(top: BorderSide(color: AppColors.borderCard)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onChanged(i),
                    radius: 36,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          i == current ? _items[i].$2 : _items[i].$1,
                          size: 22,
                          color: i == current ? AppColors.ink : AppColors.ink3,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _items[i].$3,
                          style: AppFonts.text(
                            size: 10,
                            weight: i == current
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: i == current
                                ? AppColors.ink
                                : AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
