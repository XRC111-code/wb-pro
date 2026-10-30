import 'package:flutter/material.dart';

/// 视觉常量与主题。
///
/// 单独抽一层而不是散落在各个 widget 里：白板的「浮层 + 画布」结构里，
/// 面板圆角、阴影、间距一旦不一致，看起来就像三个不同的人拼出来的。
class WbTheme {
  const WbTheme._();

  static const Color accent = Color(0xFF2F6BFF);
  static const Color accentDark = Color(0xFF7AA2FF);
  static const Color canvasLight = Color(0xFFF7F7F8);

  static const double railWidth = 52;
  static const double inspectorWidth = 268;
  static const double topBarHeight = 52;
  static const double statusBarHeight = 26;
  static const double radius = 12;
  static const double radiusSmall = 8;

  /// 低于这个宽度就切成「手机布局」：工具条挪到底部、属性面板改成弹出层。
  static const double compactBreakpoint = 860;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? const Color(0xFF111318) : const Color(0xFFF1F2F4),
    );
    return base.copyWith(
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 420),
        textStyle: TextStyle(
          fontSize: 12,
          color: brightness == Brightness.dark ? Colors.black : Colors.white,
        ),
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  /// 浮层面板统一的背景 + 边框 + 阴影。
  static BoxDecoration panelDecoration(BuildContext context, {double radius = radius}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? const Color(0xFF1E2128) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.42 : 0.09),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static Color panelColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E2128)
          : Colors.white;

  static Color subtleText(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  static Color hairline(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5);

  static Color activeColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? accentDark : accent;
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
