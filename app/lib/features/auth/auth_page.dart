import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';

/// 注册 / 登录（PRD R-001）。
///
/// 密码规则在客户端也校验一遍：让用户在点按钮之前就知道差在哪，
/// 而不是等服务端回一个 422。真正说了算的仍然是服务端。
class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key, this.notice});

  /// 从别处带过来的一句话，比如「登录状态已过期」。
  final String? notice;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.notice;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return '邮箱格式不对';
    }
    if (!_register) return null;

    final password = _password.text;
    if (password.length < 8) return '密码至少 8 位';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return '密码要同时包含字母和数字';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final session = ref.read(sessionProvider.notifier);
    try {
      if (_register) {
        await session.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await session.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // 成功之后这一页会被 _SessionGate 换掉，不用自己 pop。
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageWide,
            vertical: 40,
          ),
          children: [
            const SizedBox(height: 30),
            Text(
              'FitMeal',
              style: AppFonts.number(size: AppText.display, weight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              _register
                  ? '注册一个账号，记录会跟着账号走，换设备也在。'
                  : '登录后继续记录。',
              style: AppFonts.text(size: AppText.body, color: AppColors.ink2),
            ),
            const SizedBox(height: 36),
            _Field(
              label: '邮箱',
              controller: _email,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 16),
            _Field(
              label: '密码',
              controller: _password,
              hint: _register ? '至少 8 位，含字母和数字' : '',
              obscure: _obscure,
              autofillHints: [
                _register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              trailing: InkResponse(
                onTap: () => setState(() => _obscure = !_obscure),
                radius: 18,
                child: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.ink3,
                ),
              ),
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppColors.dangerInk),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppFonts.text(
                          size: AppText.label,
                          color: AppColors.dangerInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            AppButton(
              _busy ? '请稍候…' : (_register ? '注册并开始' : '登录'),
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                child: Text(
                  _register ? '已经有账号了，去登录' : '还没有账号？注册一个',
                  style: AppFonts.text(
                    size: AppText.label,
                    color: AppColors.ink2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              '密码只以哈希形式存放在服务端，我们看不到明文。',
              textAlign: TextAlign.center,
              style: AppFonts.text(size: AppText.caption, color: AppColors.ink4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint = '',
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.trailing,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.text(size: AppText.label, color: AppColors.ink2),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: autofillHints,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.done,
                  style: AppFonts.text(size: AppText.body),
                  cursorColor: AppColors.ink,
                  cursorWidth: 1.5,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: AppFonts.text(
                      size: AppText.body,
                      color: AppColors.ink4,
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}
