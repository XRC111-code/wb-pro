import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../model/text_metrics.dart';

/// 视觉常量与主题。
///
/// 单独抽一层而不是散落在各个 widget 里：白板的「浮层 + 画布」结构里，
/// 面板圆角、阴影、间距一旦不一致，看起来就像三个不同的人拼出来的。
///
/// 布局语言是「无框」：没有顶栏条、没有状态栏条、没有分隔线。所有控件都是
/// 浮在画布上的一小块，靠间距和阴影分层。占位越少，画布越大。
class WbTheme {
  const WbTheme._();

  /// 界面字体。HarmonyOS Sans SC 随包内置，见 pubspec 的 fonts 段。
  static const String fontFamily = kWbFontFamily;

  /// 强调色。选绿而不是蓝：白板里蓝色和「链接 / 选中框」撞得太厉害，
  /// 绿色只出现在「当前状态」上，一眼就能定位。
  ///
  /// 取色对齐「快捷白板」：激活态的实底绿是 `#2DC360`，比原来的 `#00BE6E`
  /// 更偏冷、更沉，压在白色卡片上对比更稳。
  static const Color accent = Color(0xFF2DC360);
  static const Color accentDark = Color(0xFF2FD98A);

  // ---------------------------------------------------------------------------
  // 快捷白板视觉体系
  // ---------------------------------------------------------------------------

  /// 外壳底色：底部工具条与画布四周的深绿。
  ///
  /// 这是**界面**的颜色，不是文档的底色——画布底色仍然属于文档
  /// （见 `model/canvas_style.dart`），两者互不影响。
  static const Color shell = Color(0xFF0F261E);

  /// 工具卡片组（白色圆角条）的底色。
  static const Color cardSurface = Color(0xCCFFFFFF);

  /// 卡片内文字与图标（压在白色卡片上）。
  static const Color onCard = Color(0xFF1A1A1A);

  /// 激活态卡片上的文字与图标。
  static const Color onCardActive = Color(0xFFFFFFFF);

  /// 卡片组高度。快捷白板实测 50px，对应图标 18 + 文字 11 + 间距 3。
  static const double cardBarHeight = 50;

  /// 单个工具卡片的圆角。
  static const double cardRadius = 6;

  /// 底部工具条总高度（含上下内边距）。
  static const double shellBarHeight = 70;

  // 画布底色不在这里：它属于文档（见 model/canvas_style.dart），同一份 .wbpro
  // 在深浅色界面里打开必须长得一样。主题只管外围的 chrome。

  static const double inspectorWidth = 272;
  static const double radius = 12;
  static const double radiusSmall = 9;

  /// 浮动控件距离窗口边缘的留白。
  static const double inset = 12;

  /// 工具条高度。按钮 34 + 上下内边距 5。
  static const double barHeight = 44;

  /// 低于这个宽度就切成「紧凑布局」：文档名收起，属性面板改成底部弹层。
  static const double compactBreakpoint = 780;

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
      tertiaryContainer: dark ? const Color(0xFF16342A) : const Color(0xFFE6F9F0),
      onTertiaryContainer: dark ? accentDark : accent,
      background: dark ? const Color(0xFF18191C) : const Color(0xFFF2F2F4),
      // surface 是窗口底色，容器的底色由 surfaceContainer 给。
      surface: dark ? const Color(0xFF1C1D21) : Colors.white,
      surfaceVariant: dark ? const Color(0xFF24262B) : Colors.white,
      surfaceContainer: dark ? const Color(0xFF24262B) : Colors.white,
      onSurfaceContainer: dark ? const Color(0xFFEDEEF0) : const Color(0xFF16181C),
      surfaceContainerHigh: dark ? const Color(0xFF2E3036) : const Color(0xFFEEEFF2),
      outline: dark ? const Color(0xFF34373D) : const Color(0xFFE3E5E9),
      dividerLine: dark ? const Color(0xFF303338) : const Color(0xFFE9EBEE),
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
          borderRadius: BorderRadius.circular(20),
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
        elevation: 10,
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

  // ---------------------------------------------------------------------------
  // 浮层
  // ---------------------------------------------------------------------------

  /// 浮动控件的底色。深色下比画布亮一档，浅色下是纯白。
  ///
  /// 不做半透明 + 模糊：工具条压在内容上，模糊会让底下的线条糊成一片，
  /// 反而看不清自己画到哪了。实色 + 一圈极淡的描边更干净。
  static Color chrome(BuildContext context) {
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    return dark ? const Color(0xFF24262B) : Colors.white;
  }

  /// 浮动控件上的图标与文字。
  static Color onChrome(BuildContext context, {double alpha = 1}) {
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFFE7E8EC) : const Color(0xFF33363C);
    return alpha >= 1 ? base : base.withValues(alpha: alpha);
  }

  /// 浮动控件之间、控件内部的分隔线。比描边还淡，只是「提一下」。
  static Color chromeHairline(BuildContext context) {
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    return dark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.08);
  }

  /// 浮动控件的统一装饰：圆角 + 底色 + 一道描边 + 轻阴影。
  static BoxDecoration chromeDecoration(
    BuildContext context, {
    double radius = WbTheme.radius,
  }) {
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: chrome(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.22 : 0.10),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  /// 工具卡片组（白色圆角条）的装饰。
  ///
  /// 与 [chromeDecoration] 的区别：这个**永远**是浅色卡片，因为它压在一块
  /// 固定的深绿外壳上。跟着系统深色模式反转会让底栏在深色下变成一整片灰，
  /// 反而丢掉「深底 + 白卡」的层次。
  static BoxDecoration cardGroupDecoration() {
    return BoxDecoration(
      color: cardSurface,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 5,
          offset: const Offset(0, 2),
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
