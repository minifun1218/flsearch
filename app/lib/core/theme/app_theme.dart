
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// 数字、单位、日期一律用 Archivo + 等宽数字；中文走系统字体。
/// 设计规范见 design/Style.dc.html。
abstract final class AppFonts {
  static TextStyle number({
    double size = AppText.body,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.ink,
    double? height,
  }) {
    return GoogleFonts.archivo(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: -0.01 * size,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle text({
    double size = AppText.body,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double height = 1.5,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// 页面主标题：32 / 700 / 收紧字距。
  static TextStyle get display => text(
        size: AppText.display,
        weight: FontWeight.w700,
        height: 1.28,
        letterSpacing: -0.03 * AppText.display,
      );

  /// 分区标题：26 / 700。
  static TextStyle get title => text(
        size: AppText.title,
        weight: FontWeight.w700,
        height: 1.32,
        letterSpacing: -0.025 * AppText.title,
      );

  /// 卡片标题：16 / 600。
  static TextStyle get cardTitle => text(
        size: AppText.cardTitle,
        weight: FontWeight.w600,
        letterSpacing: -0.01 * AppText.cardTitle,
      );

  static TextStyle get body => text();

  static TextStyle get label =>
      text(size: AppText.label, color: AppColors.ink2);

  static TextStyle get caption =>
      text(size: AppText.caption, color: AppColors.ink3);
}

abstract final class AppTheme {
  static ThemeData build() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.ink,
        onPrimary: AppColors.onDark,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.danger,
      ),
      splashFactory: InkRipple.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lineSoft,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
