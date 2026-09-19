import 'package:fitmeal/data/api/api_exception.dart';
import 'package:fitmeal/data/app_state.dart';
import 'package:fitmeal/data/demo_repository.dart';
import 'package:fitmeal/domain/models/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 在 [DemoRepository] 上按测试需要改几处行为 —— 其余照旧，省得每次重写一整套。
class _Fake extends DemoRepository {
  _Fake({
    this.signedIn = true,
    this.hasProfile = true,
    this.offline = false,
  });

  bool signedIn;
  bool hasProfile;
  bool offline;

  int loginCalls = 0;
  UserProfile? savedProfile;

  @override
  Future<bool> restoreSession() async => signedIn;

  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls++;
    if (password != 'fitmeal2026') {
      throw ApiException(401, '邮箱或密码不对');
    }
    signedIn = true;
  }

  @override
  Future<UserProfile?> loadProfile() async {
    if (offline) throw NetworkException('连接被拒绝');
    return hasProfile ? super.loadProfile() : null;
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    savedProfile = profile;
    hasProfile = true;
    return super.saveProfile(profile);
  }
}

void main() {
  testWidgets('没有登录态时停在登录页，可以切到注册', (tester) async {
    await pumpApp(tester, height: 1200, repository: _Fake(signedIn: false));

    expect(find.text('登录'), findsWidgets);
    expect(find.text('今日记录'), findsNothing);

    await tester.tap(find.text('还没有账号？注册一个'));
    await tester.pumpAndSettle();
    expect(find.text('注册并开始'), findsOneWidget);
  });

  testWidgets('密码不对时把服务端那句话摆出来，不往下走', (tester) async {
    final repo = _Fake(signedIn: false);
    await pumpApp(tester, height: 1200, repository: repo);

    await tester.enterText(find.byType(TextField).first, 'lifter@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-pass-1');
    await tester.tap(find.text('登录').last);
    await tester.pumpAndSettle();

    expect(repo.loginCalls, 1);
    expect(find.text('邮箱或密码不对'), findsOneWidget);
    expect(find.text('今日记录'), findsNothing);
  });

  testWidgets('登录成功后进主界面', (tester) async {
    await pumpApp(tester, height: 1600, repository: _Fake(signedIn: false));

    await tester.enterText(find.byType(TextField).first, 'lifter@example.com');
    await tester.enterText(find.byType(TextField).last, 'fitmeal2026');
    await tester.tap(find.text('登录').last);
    await tester.pumpAndSettle();

    expect(find.text('今日记录'), findsOneWidget);
  });

  testWidgets('登录了但没建档 —— 走建档引导，填完进主界面（R-005）', (tester) async {
    final repo = _Fake(hasProfile: false);
    final container =
        await pumpApp(tester, height: 1600, repository: repo);

    expect(find.text('先建个档案'), findsOneWidget);

    // 默认减脂 66kg / 当前 70kg，本来就成立，直接保存。
    await tester.tap(find.text('开始记录'));
    await tester.pumpAndSettle();

    expect(repo.savedProfile, isNotNull);
    expect(repo.savedProfile!.goal, GoalType.cut);
    expect(find.text('今日记录'), findsOneWidget);
    expect(container.read(profileProvider).weightKg, 70);
  });

  testWidgets('建档时减脂目标体重高于当前体重会被挡住', (tester) async {
    final repo = _Fake(hasProfile: false);
    await pumpApp(tester, height: 1600, repository: repo);

    final target = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '66',
    );
    await tester.enterText(target, '80');
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始记录'));
    await tester.pumpAndSettle();

    expect(find.text('减脂目标体重需要低于当前体重'), findsOneWidget);
    expect(repo.savedProfile, isNull);
  });

  testWidgets('连不上且本地没有快照时给失败页，可以重试', (tester) async {
    final repo = _Fake(offline: true);
    final container = await pumpApp(tester, height: 1200, repository: repo);

    expect(container.read(sessionProvider).stage, AuthStage.failed);
    expect(find.textContaining('连不上服务端'), findsOneWidget);

    repo.offline = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('今日记录'), findsOneWidget);
  });
}
