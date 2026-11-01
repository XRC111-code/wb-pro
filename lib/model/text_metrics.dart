import 'package:flutter/painting.dart';

/// 白板使用的字体族。
///
/// 内置 HarmonyOS Sans SC（见 pubspec 的 fonts 段），界面与画布上的文字用
/// 同一套字形。常量放在 model 层而不是 ui 层：画布排版属于模型，不该反过来
/// 依赖界面主题；`WbTheme.fontFamily` 引用这里。
const String kWbFontFamily = 'HarmonyOS Sans SC';

/// SVG 导出时写的字体栈。首选内置字体，再按平台回退，避免在没装字体的机器上
/// 直接变成衬线体。
const String kWbSvgFontStack =
    'HarmonyOS Sans SC, system-ui, -apple-system, Segoe UI, Roboto, sans-serif';

/// 白板里的文本样式。
TextStyle buildTextStyle({
  required double fontSize,
  required Color color,
  bool bold = false,
  bool italic = false,
  double lineHeight = 1.35,
  TextDecoration decoration = TextDecoration.none,
  Color? decorationColor,
  String fontFamily = kWbFontFamily,
}) =>
    TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: lineHeight,
      decoration: decoration,
      decorationColor: decorationColor ?? color,
      leadingDistribution: TextLeadingDistribution.even,
    );

/// 排版一段文本。
///
/// [maxWidth] 为 null 表示不限宽（用于测量「这段字自然有多宽」）。
TextPainter layoutTextBlock(
  String text,
  TextStyle style, {
  double? maxWidth,
  TextAlign align = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  painter.layout(maxWidth: maxWidth ?? double.infinity);
  return painter;
}

/// 文本在给定宽度下的自然尺寸。
Size measureTextBlock(
  String text,
  TextStyle style, {
  double? maxWidth,
  TextAlign align = TextAlign.left,
}) {
  final painter = layoutTextBlock(text, style, maxWidth: maxWidth, align: align);
  final size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}
