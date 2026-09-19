import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 二级页的标题栏：左返回、中标题、右可选动作。刻意不用 AppBar ——
/// 设计上这些页没有分隔线和阴影，标题只是页面内容的第一行。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.page,
      0,
      AppSpacing.page,
      22,
    ),
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Tooltip(
            message: MaterialLocalizations.of(context).backButtonTooltip,
            child: InkResponse(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              radius: 24,
              child: const SizedBox(
                width: 32,
                height: 40,
                child: Icon(Icons.chevron_left, size: 24, color: AppColors.ink),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppFonts.cardTitle,
            ),
          ),
          SizedBox(
            width: 32,
            height: 40,
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一级页的大标题（统计、我的）。
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        20,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppFonts.title),
          ?trailing,
        ],
      ),
    );
  }
}
