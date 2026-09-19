import 'package:flutter/material.dart';

/// 设计令牌 —— 与 design/Style.dc.html 一一对应。
/// 改这里等于改设计规范，不要在页面里写字面量颜色或尺寸。
abstract final class AppColors {
  // 底色与文字
  static const bg = Color(0xFFFBFAF7); // 页面底
  static const surface = Color(0xFFFFFFFF); // 卡片面
  static const surfaceAlt = Color(0xFFF4F1EA); // 次级面
  static const surfaceDark = Color(0xFF23201C); // 深色卡片 / 主行动

  static const ink = Color(0xFF23201C); // 主文字
  static const ink2 = Color(0xFF6B655C); // 次要文字
  static const ink3 = Color(0xFF9A948A); // 辅助文字
  static const ink4 = Color(0xFFB5AB9C); // 占位 / 禁用

  static const line = Color(0xFFEAE6DF); // 分隔线
  static const lineSoft = Color(0xFFF2EFE9); // 进度轨道 / 内部分隔
  static const lineFaint = Color(0xFFF5F2EC); // 列表行分隔
  static const border = Color(0xFFE6E2DA); // 控件描边
  static const borderCard = Color(0xFFEFEBE4); // 卡片描边
  static const borderDash = Color(0xFFDCD6CB); // 虚线描边

  // 数据色 —— 四个色相，明度与彩度一致，只用于标识营养素
  static const protein = Color(0xFF4A6B4F);
  static const carb = Color(0xFFA8763E);
  static const fat = Color(0xFF8A5A6B);
  static const water = Color(0xFF4A6480);

  // 深色卡片上的提亮版
  static const proteinLight = Color(0xFF7AA080);
  static const carbLight = Color(0xFFC99A5E);
  static const fatLight = Color(0xFFB0808F);

  // 语义色
  static const positive = Color(0xFF4A6B4F);
  static const positiveBg = Color(0xFFEDF1EC);
  static const warn = Color(0xFFA8763E);
  static const warnBg = Color(0xFFF7F1EA);
  static const warnChipBg = Color(0xFFFBF2E8);
  static const danger = Color(0xFFB0554F);
  static const dangerBg = Color(0xFFF9EFEE);
  static const dangerInk = Color(0xFF8A4842);
  static const warnInk = Color(0xFF6B5B49);

  /// 深色卡片上的文字透明度阶梯
  static const onDark = Color(0xFFFBFAF7);
  static Color onDarkMuted = const Color(0xFFFBFAF7).withValues(alpha: 0.55);
  static Color onDarkFaint = const Color(0xFFFBFAF7).withValues(alpha: 0.45);
  static Color onDarkLine = const Color(0xFFFBFAF7).withValues(alpha: 0.13);
}

abstract final class AppRadius {
  static const hero = 20.0; // 主卡
  static const card = 18.0; // 常规卡
  static const listCard = 16.0; // 列表卡
  static const button = 15.0; // 按钮
  static const field = 14.0; // 输入框
  static const control = 12.0; // 小控件
  static const chip = 11.0; // 快捷块
  static const pill = 999.0; // 标签 / 开关
}

abstract final class AppSpacing {
  static const page = 20.0; // 页边距
  static const pageWide = 28.0; // 引导页页边距
  static const cardGap = 12.0; // 卡片之间
  static const section = 26.0; // 分区之间
  static const cardPad = 20.0; // 卡片内边距
  static const topSafe = 52.0; // 顶部安全区（状态栏之下）
}

abstract final class AppSizes {
  static const button = 52.0; // 主按钮高
  static const control = 44.0; // 最小点击区
  static const chip = 38.0; // 快捷块高
  static const barThin = 5.0; // 细进度条
  static const barThick = 7.0; // 带刻度的进度条
  static const icon = 22.0;
  static const iconSmall = 17.0;
}

/// 字号阶梯。数字一律用 [AppText.num]，中文用默认字体。
abstract final class AppText {
  static const display = 32.0; // 页面主标题
  static const title = 26.0; // 分区标题
  static const cardTitle = 16.0; // 卡片标题
  static const body = 15.0; // 正文 / 列表项
  static const label = 13.0; // 次要说明
  static const caption = 11.0; // 标签 / 单位
}
