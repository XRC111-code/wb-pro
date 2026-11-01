import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../model/text_metrics.dart';

/// 视觉常量与主题。
///
/// 单独抽一层而不是散落在各个 widget 里：白板的「浮层 + 画布」结构里，
/// 面板圆角、阴影、间距一旦不一致，看起来就像三个不同的人拼出来的。
///
/// 配色与控件语言来自 miuix（HyperOS 风格）：圆角更大、描边更淡、按压有
/// 回弹。Material 只保留作底层（Navigator / Overlay / TextField 这些还没有
/// 对等实现的部件）。
class WbTheme {
  const WbTheme._();

  /// 界面字体。HarmonyOS Sans SC 随包内置，见 pubspec 的 fonts 段。
  static const String fontFamily = kWbFontFamily;

  static const Color accent = Color(0xFF2F6BFF);
  static const Color accentDark = Color(0xFF7AA2FF);
  static const Color canvasLight = Color(0xFFF7F7F8);

  static const double railWidth = 52;
  static const double inspectorWidth = 268;
  static const double topBarHeight = 52;
  static const double statusBarHeight = 26;
  static const double radius = 16;
  static const double radiusSmall = 10;

  /// 低于这个宽度就切成「手机布局」：工具条挪到底部、属性面板改成弹出层。
  static const double compactBreakpoint = 860;

  // ---------------------------------------------------------------------------
  // miuix 主题
  // ---------------------------------------------------------------------------

  /// miuix 的语义配色。只覆盖品牌色与几个面板底色，其余沿用 HyperOS 规范值，
  /// 这样自带组件的圆角、按压反馈、深浅色对比度都不用重新调。
  static MiuixColors miuixColors(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = dark ? darkColorScheme() : lightColorScheme();
    return base.copy(
      primary: dark ? accentDark : accent,
      primaryVariant: dark ? accentDark : accent,
      tertiaryContainer: dark ? const Color(0xFF1F2C47) : const Color(0xFFEAF1FF),
      onTertiaryContainer: dark ? accentDark : accent,
      background: dark ? const Color(0xFF111318) : Colors.white,
      // surface 是窗口底色，容器的底色由 surfaceContainer 给。
      surface: dark ? const Color(0xFF16181D) : canvasLight,
      surfaceVariant: dark ? const Color(0xFF1E2128) : Colors.white,
      surfaceContainer: dark ? const Color(0xFF1E2128) : Colors.white,
      onSurfaceContainer: dark ? const Color(0xFFE8E8E8) : Colors.black,
      surfaceContainerHigh: dark ? const Color(0xFF262A31) : const Color(0xFFEFF1F4),
      outline: dark ? const Color(0xFF3A3F47) : const Color(0xFFDDE1E6),
      dividerLine: dark ? const Color(0xFF33383F) : const Color(0xFFE6E9ED),
    );
  }

  /// 把内置字体套到 miuix 的全部文本样式上。
  ///
  /// miuix 组件的字号/字重写在 [MiuixTextStyles] 里，只给 Material 的
  /// `ThemeData.fontFamily` 是不够的——它管不到 `MiuixText` 这类组件。
  static MiuixTextStyles miuixTextStyles() {
    final base = defaultTextStyles();
    TextStyle f(TextStyle s) => s.copyWith(fontFamily: fontFamily);
    return base.copy(
      main: f(base.main),
      paragraph: f(base.paragraph),
      body1: f(base.body1),
      body2: f(base.body2),
      button: f(base.button),
      footnote1: f(base.footnote1),
      footnote2: f(base.footnote2),
      headline1: f(base.headline1),
      headline2: f(base.headline2),
      subtitle: f(base.subtitle),
      title1: f(base.title1),
      title2: f(base.title2),
      title3: f(base.title3),
      title4: f(base.title4),
    );
  }

  static MiuixThemeData miuixThemeData(Brightness brightness) => MiuixThemeData(
        colors: miuixColors(brightness),
        textStyles: miuixTextStyles(),
        brightness: brightness,
      );

  // ---------------------------------------------------------------------------
  // Material 兜底主题
  // ---------------------------------------------------------------------------

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final miuix = miuixColors(brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: miuix.primary,
      onPrimary: miuix.onPrimary,
      surface: miuix.surface,
      onSurface: miuix.onSurface,
      outlineVariant: miuix.outline,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: miuix.background,
    );
    return base.copyWith(
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 420),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          color: dark ? Colors.black : Colors.white,
        ),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: miuix.dividerLine,
      ),
      // 下面这几个是 Material 的浮层，miuix 里还没有一一对等的实现（对话框
      // 和菜单都靠宿主组件挂载）。把圆角、底色、字号对齐过去，至少不会出现
      // 「面板是 miuix、弹出来的框还是 Material」的割裂感。
      dialogTheme: DialogThemeData(
        backgroundColor: miuix.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: miuix.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: miuix.onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: miuix.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: miuix.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: miuix.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: miuix.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: miuix.surfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: miuix.onSurface,
        ),
      ),
    );
  }

  /// 浮层面板统一的背景 + 边框 + 阴影。
  static BoxDecoration panelDecoration(BuildContext context, {double radius = radius}) {
    final c = MiuixTheme.of(context).colors;
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: c.surfaceContainer,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.outline.withValues(alpha: 0.75)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.38 : 0.06),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static Color panelColor(BuildContext context) =>
      MiuixTheme.of(context).colors.surfaceContainer;

  static Color subtleText(BuildContext context) =>
      MiuixTheme.of(context).colors.onSurfaceVariantSummary;

  static Color hairline(BuildContext context) =>
      MiuixTheme.of(context).colors.dividerLine;

  static Color activeColor(BuildContext context) =>
      MiuixTheme.of(context).colors.primary;
}

/// 白板里可选的描边/填充色。
///
/// 不做自由取色器：白板的配色需求是「几套协调的颜色」，给 12 个色板比给一个
/// 色轮更快出结果，也避免用户在同一张图里堆出 30 种互相打架的颜色。
const List<Color> kStrokePalette = <Color>[
  Color(0xFF1F2933),
  Color(0xFF5B6472),
  Color(0xFF9AA3AF),
  Color(0xFFE03131),
  Color(0xFFF08C00),
  Color(0xFFF5C518),
  Color(0xFF2F9E44),
  Color(0xFF0CA678),
  Color(0xFF1C7ED6),
  Color(0xFF2F6BFF),
  Color(0xFF7048E8),
  Color(0xFFD6336C),
];

const List<Color> kFillPalette = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFFF1F3F5),
  Color(0xFFFFE3E3),
  Color(0xFFFFF0D9),
  Color(0xFFFFF9DB),
  Color(0xFFE6F7E9),
  Color(0xFFE3F7F2),
  Color(0xFFE3F0FF),
  Color(0xFFE8E4FF),
  Color(0xFFFFE6F0),
];

const List<Color> kNotePalette = <Color>[
  Color(0xFFFFE08A),
  Color(0xFFFFC9C9),
  Color(0xFFC9E4FF),
  Color(0xFFD8F5C9),
  Color(0xFFEAD9FF),
  Color(0xFFFFD9B0),
];
