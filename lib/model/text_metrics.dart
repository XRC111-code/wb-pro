import 'package:flutter/painting.dart';

/// 白板里的文本样式。
///
/// 不引入自定义字体：桌面端用系统 UI 字体、Android 用 Roboto/思源，体积为零。
/// 代价是同一文档在不同平台的字宽略有差异——对白板这种自由布局的工具可以
/// 接受，对排版工具不行。这个取舍写在 README 的「已知差异」里。
TextStyle buildTextStyle({
  required double fontSize,
  required Color color,
  bool bold = false,
  bool italic = false,
  double lineHeight = 1.35,
  TextDecoration decoration = TextDecoration.none,
  Color? decorationColor,
}) =>
    TextStyle(
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
