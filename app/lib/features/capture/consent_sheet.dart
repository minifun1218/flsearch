import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';

/// 首次拍照识别前的告知与同意（PRD R-048）。
///
/// 不同意也能继续用 App —— 手动录入、常吃、复制历史都不需要上传照片，
/// 所以这里给的是一个真实的选择，不是走过场。
Future<bool?> showPhotoConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _ConsentSheet(),
  );
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 38),
      child: SingleChildScrollView(
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
            const SizedBox(height: 26),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF0ECE4),
                borderRadius: BorderRadius.circular(AppRadius.listCard),
              ),
              child: const Icon(Icons.photo_camera_outlined,
                  size: 24, color: AppColors.ink),
            ),
            const SizedBox(height: 20),
            Text(
              '照片会发到云端识别',
              style: AppFonts.text(
                size: 22,
                weight: FontWeight.w700,
                height: 1.35,
                letterSpacing: -0.02 * 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '识别在服务器上完成，需要把这张照片交给第三方 AI 服务。'
              '开始之前想让你知道这几件事。',
              style: AppFonts.text(
                  size: 14, color: AppColors.ink2, height: 1.7),
            ),
            const SizedBox(height: 26),
            const _Point(
              icon: Icons.verified_user_outlined,
              title: '只用来认食物',
              body: '照片不会用于训练模型，也不会出现在任何公开的地方。',
            ),
            const SizedBox(height: 18),
            const _Point(
              icon: Icons.schedule,
              title: '30 天后自动删除',
              body: '识别完成后照片还留 30 天方便你回看，到期服务器自动清理。',
            ),
            const SizedBox(height: 18),
            const _Point(
              icon: Icons.edit_note,
              title: '不同意也能用',
              body: '手动搜索、常吃食物、复制历史餐都不需要上传任何照片。',
            ),
            const SizedBox(height: 26),
            const Divider(height: 1, color: AppColors.borderCard),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('完整说明',
                    style:
                        AppFonts.text(size: 13, color: AppColors.ink2)),
                Row(
                  children: [
                    Text(
                      '隐私政策',
                      style: AppFonts.text(
                          size: 13, weight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.ink),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            AppButton(
              '同意，开始识别',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            AppButton(
              '不同意，改用手动记录',
              kind: AppButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 19, color: AppColors.positive),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style:
                      AppFonts.text(size: 14, weight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(
                body,
                style: AppFonts.text(
                    size: 12.5, color: AppColors.ink2, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
