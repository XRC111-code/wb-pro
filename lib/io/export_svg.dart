import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../model/element.dart';
import '../model/text_metrics.dart';
import '../util/color_utils.dart';

/// 把白板场景导出成 SVG。
///
/// 为什么不用 `flutter_svg` 之类的库：导出是**单向**的，只需要把已知的六种
/// 元素翻译成路径/文本/图片标签，自己写一份反而比引入依赖更可控 —— 也能
/// 保证导出结果和画布上的渲染用的是同一套几何计算（虚线长度、箭头夹角）。
///
/// 坐标系直接用世界坐标，通过 viewBox 承载偏移与尺寸，元素本身不需要做
/// 平移；这样导出的 SVG 在 Illustrator/Figma 里打开时坐标是「真实」的。
class SvgExportOptions {
  const SvgExportOptions({
    this.padding = 32,
    this.background = const Color(0xFFFFFFFF),
    this.includeGrid = false,
    this.gridSize = 24,
  });

  final double padding;

  /// null 表示透明背景。
  final Color? background;
  final bool includeGrid;
  final double gridSize;
}

/// 计算需要导出的区域（内容包围盒 + padding）。内容为空时给一块 800×600
/// 的空白画布，避免生成 width="0" 的非法 SVG。
Rect exportAreaFor(List<WbElement> elements, {double padding = 32}) {
  if (elements.isEmpty) {
    return Rect.fromLTWH(-padding, -padding, 800 + padding * 2, 600 + padding * 2);
  }
  Rect bounds = elements.first.worldBounds;
  for (var i = 1; i < elements.length; i++) {
    bounds = bounds.expandToInclude(elements[i].worldBounds);
  }
  // 线宽、箭头头部、便签阴影都会超出 worldBounds，统一留一点余量。
  return bounds.inflate(padding + 8);
}

String exportSvg(
  List<WbElement> elements, {
  SvgExportOptions options = const SvgExportOptions(),
}) {
  final area = exportAreaFor(elements, padding: options.padding);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="${_n(area.width)}" height="${_n(area.height)}" '
        'viewBox="${_n(area.left)} ${_n(area.top)} ${_n(area.width)} ${_n(area.height)}">')
    ..writeln('  <title>wb-pro 白板导出</title>');

  final background = options.background;
  if (background != null) {
    buffer.writeln('  <rect x="${_n(area.left)}" y="${_n(area.top)}" '
        'width="${_n(area.width)}" height="${_n(area.height)}" '
        'fill="${_hex(background)}" fill-opacity="${_n(background.a)}"/>');
  }

  if (options.includeGrid) {
    _writeGrid(buffer, area, options.gridSize);
  }

  for (final element in elements) {
    if (element.opacity <= 0) continue;
    buffer.write(_elementToSvg(element));
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

// ── 元素分发 ─────────────────────────────────────────────────────────────────

String _elementToSvg(WbElement element) {
  final body = switch (element) {
    StrokeElement e => _strokeToSvg(e),
    ShapeElement e => _shapeToSvg(e),
    ArrowElement e => _arrowToSvg(e),
    TextElement e => _textToSvg(e),
    NoteElement e => _noteToSvg(e),
    ImageElement e => _imageToSvg(e),
  };
  if (body.isEmpty) return '';

  final transform = element.rotation == 0
      ? ''
      : ' transform="rotate(${_n(element.rotation * 180 / math.pi)} '
          '${_n(element.frame.center.dx)} ${_n(element.frame.center.dy)})"';
  final opacity = element.opacity >= 1 ? '' : ' opacity="${_n(element.opacity)}"';
  return '  <g$transform$opacity>\n$body  </g>\n';
}

String _strokeToSvg(StrokeElement e) {
  if (e.points.isEmpty) return '';
  final buffer = StringBuffer();
  final left = e.frame.left;
  final top = e.frame.top;
  final color = _hex(e.color);
  final alpha = _n(e.color.a * e.opacity);

  if (e.points.length == 1) {
    final p = e.points.first;
    buffer.writeln('    <circle cx="${_n(left + p.dx)}" cy="${_n(top + p.dy)}" '
        'r="${_n(e.strokeWidth / 2)}" fill="$color" fill-opacity="$alpha"/>');
    return buffer.toString();
  }

  buffer.writeln('    <path d="${_strokePathData(e, left, top)}" fill="none" '
      'stroke="$color" stroke-opacity="$alpha" stroke-width="${_n(e.strokeWidth)}" '
      'stroke-linecap="round" stroke-linejoin="round"/>');
  return buffer.toString();
}

/// 与 [StrokeElement.buildPath] 相同的「中点二次贝塞尔」算法，只是输出 SVG 的
/// `d` 字符串。两边必须同步改，否则画布上是一条曲线、导出的是另一条。
String _strokePathData(StrokeElement e, double left, double top) {
  final pts = e.points;
  final buffer = StringBuffer();
  Offset world(Offset p) => Offset(p.dx + left, p.dy + top);
  final first = world(pts[0]);
  buffer.write('M ${_n(first.dx)} ${_n(first.dy)}');
  if (pts.length == 2) {
    final second = world(pts[1]);
    buffer.write(' L ${_n(second.dx)} ${_n(second.dy)}');
    return buffer.toString();
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final control = world(pts[i]);
    final next = world(pts[i + 1]);
    final mid = Offset((control.dx + next.dx) / 2, (control.dy + next.dy) / 2);
    buffer.write(' Q ${_n(control.dx)} ${_n(control.dy)} ${_n(mid.dx)} ${_n(mid.dy)}');
  }
  final last = world(pts.last);
  buffer.write(' L ${_n(last.dx)} ${_n(last.dy)}');
  return buffer.toString();
}

String _shapeToSvg(ShapeElement e) {
  final rect = e.frame;
  final buffer = StringBuffer();
  final fill = e.fill;
  final fillAttr = fill == null
      ? 'fill="none"'
      : 'fill="${_hex(fill)}" fill-opacity="${_n(fill.a * e.opacity)}"';
  final stroke = _strokeAttrs(e.stroke, e.strokeWidth, e.opacity, e.strokeStyle);

  switch (e.shape) {
    case ShapeKind.rectangle:
      final radius = math.min(
        e.cornerRadius,
        math.min(rect.width, rect.height) / 2,
      );
      buffer.writeln('    <rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
          'width="${_n(rect.width)}" height="${_n(rect.height)}" '
          'rx="${_n(radius)}" $fillAttr $stroke/>');
    case ShapeKind.ellipse:
      buffer.writeln('    <ellipse cx="${_n(rect.center.dx)}" cy="${_n(rect.center.dy)}" '
          'rx="${_n(rect.width / 2)}" ry="${_n(rect.height / 2)}" $fillAttr $stroke/>');
    case ShapeKind.diamond:
      final points = <Offset>[
        Offset(rect.center.dx, rect.top),
        Offset(rect.right, rect.center.dy),
        Offset(rect.center.dx, rect.bottom),
        Offset(rect.left, rect.center.dy),
      ].map((p) => '${_n(p.dx)},${_n(p.dy)}').join(' ');
      buffer.writeln('    <polygon points="$points" $fillAttr $stroke/>');
  }
  return buffer.toString();
}

String _arrowToSvg(ArrowElement e) {
  final buffer = StringBuffer();
  final start = Offset(e.frame.left + e.start.dx, e.frame.top + e.start.dy);
  final end = Offset(e.frame.left + e.end.dx, e.frame.top + e.end.dy);
  final stroke = _strokeAttrs(e.stroke, e.strokeWidth, e.opacity, e.strokeStyle);

  buffer.writeln('    <line x1="${_n(start.dx)}" y1="${_n(start.dy)}" '
      'x2="${_n(end.dx)}" y2="${_n(end.dy)}" $stroke/>');

  final headLength = 9 + e.strokeWidth * 2.2;
  final headPaint = 'fill="${_hex(e.stroke)}" fill-opacity="${_n(e.stroke.a * e.opacity)}"';
  if (e.endHead) {
    buffer.writeln('    <polygon points="${_headPoints(start, end, headLength)}" $headPaint/>');
  }
  if (e.startHead) {
    buffer.writeln('    <polygon points="${_headPoints(end, start, headLength)}" $headPaint/>');
  }
  return buffer.toString();
}

/// 与 `_paintHead` 完全一致的三角形，避免导出后箭头胖一圈瘦一圈。
String _headPoints(Offset from, Offset tip, double length) {
  final angle = math.atan2(tip.dy - from.dy, tip.dx - from.dx);
  const spread = 0.42;
  final left = tip - Offset(math.cos(angle - spread), math.sin(angle - spread)) * length;
  final right = tip - Offset(math.cos(angle + spread), math.sin(angle + spread)) * length;
  return '${_n(tip.dx)},${_n(tip.dy)} ${_n(left.dx)},${_n(left.dy)} '
      '${_n(right.dx)},${_n(right.dy)}';
}

String _textToSvg(TextElement e) {
  final style = buildTextStyle(
    fontSize: e.fontSize,
    color: e.color,
    bold: e.bold,
    italic: e.italic,
    lineHeight: e.lineHeight,
  );
  final painter = layoutTextBlock(
    e.text,
    style,
    maxWidth: e.frame.width,
    align: e.align,
  );
  if (e.text.isEmpty) {
    painter.dispose();
    return '';
  }
  final lines = _linesOf(e.text, painter);
  final firstBaseline = painter.computeLineMetrics().isEmpty
      ? e.fontSize
      : painter.computeLineMetrics().first.baseline;
  painter.dispose();

  final anchor = switch (e.align) {
    TextAlign.center => 'middle',
    TextAlign.right || TextAlign.end => 'end',
    _ => 'start',
  };
  final x = switch (e.align) {
    TextAlign.center => e.frame.left + e.frame.width / 2,
    TextAlign.right || TextAlign.end => e.frame.right,
    _ => e.frame.left,
  };
  final lineStep = e.fontSize * e.lineHeight;
  final buffer = StringBuffer()
    ..writeln('    <text x="${_n(x)}" y="${_n(e.frame.top + firstBaseline)}" '
        'fill="${_hex(e.color)}" fill-opacity="${_n(e.color.a * e.opacity)}" '
        'font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif" '
        'font-size="${_n(e.fontSize)}" text-anchor="$anchor"'
        '${e.bold ? ' font-weight="700"' : ''}'
        '${e.italic ? ' font-style="italic"' : ''}>');
  for (var i = 0; i < lines.length; i++) {
    final dy = i == 0 ? 0.0 : lineStep;
    buffer.writeln('      <tspan x="${_n(x)}" dy="${_n(dy)}">'
        '${_escape(lines[i])}</tspan>');
  }
  buffer.writeln('    </text>');
  return buffer.toString();
}

String _noteToSvg(NoteElement e) {
  final rect = e.frame;
  final buffer = StringBuffer();
  // 阴影用一块偏移的半透明圆角矩形近似；SVG 滤镜在不同查看器里效果差异太大。
  buffer.writeln('    <rect x="${_n(rect.left)}" y="${_n(rect.top + 2)}" '
      'width="${_n(rect.width)}" height="${_n(rect.height)}" rx="6" '
      'fill="#000000" fill-opacity="${_n(0.13 * e.opacity)}"/>');
  buffer.writeln('    <rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
      'width="${_n(rect.width)}" height="${_n(rect.height)}" rx="6" '
      'fill="${_hex(e.fill)}" fill-opacity="${_n(e.fill.a * e.opacity)}"/>');

  final text = e.text.isEmpty ? '' : e.text;
  if (text.isEmpty) return buffer.toString();

  final style = buildTextStyle(
    fontSize: e.fontSize,
    color: e.textColor,
    lineHeight: 1.4,
  );
  final painter = layoutTextBlock(text, style, maxWidth: math.max(20.0, rect.width - 28));
  final lines = _linesOf(text, painter);
  final firstBaseline = painter.computeLineMetrics().isEmpty
      ? e.fontSize
      : painter.computeLineMetrics().first.baseline;
  painter.dispose();

  final x = rect.left + 14;
  final y = rect.top + 14 + firstBaseline;
  buffer.writeln('    <text x="${_n(x)}" y="${_n(y)}" '
      'fill="${_hex(e.textColor)}" fill-opacity="${_n(e.opacity)}" '
      'font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif" '
      'font-size="${_n(e.fontSize)}">');
  for (var i = 0; i < lines.length; i++) {
    final dy = i == 0 ? 0.0 : e.fontSize * 1.4;
    buffer.writeln('      <tspan x="${_n(x)}" dy="${_n(dy)}">${_escape(lines[i])}</tspan>');
  }
  buffer.writeln('    </text>');
  return buffer.toString();
}

String _imageToSvg(ImageElement e) {
  if (e.bytes.isEmpty) return '';
  final data = base64Encode(e.bytes);
  final mime = e.mimeType.isEmpty ? 'image/png' : e.mimeType;
  return '    <image x="${_n(e.frame.left)}" y="${_n(e.frame.top)}" '
      'width="${_n(e.frame.width)}" height="${_n(e.frame.height)}" '
      'preserveAspectRatio="none" '
      'xlink:href="data:$mime;base64,$data" '
      'href="data:$mime;base64,$data"/>\n';
}

// ── 公共小工具 ───────────────────────────────────────────────────────────────

String _strokeAttrs(Color color, double width, double opacity, StrokeStyle style) {
  final buffer = StringBuffer('stroke="${_hex(color)}" ')
    ..write('stroke-opacity="${_n(color.a * opacity)}" ')
    ..write('stroke-width="${_n(width)}" ')
    ..write('stroke-linecap="round" stroke-linejoin="round"');
  switch (style) {
    case StrokeStyle.solid:
      break;
    case StrokeStyle.dashed:
      buffer.write(' stroke-dasharray="${_n(width * 3 + 6)} ${_n(width * 2 + 5)}"');
    case StrokeStyle.dotted:
      // round cap + 极短 dash 就是圆点，和画布上的画法一致。
      buffer.write(' stroke-dasharray="0.1 ${_n(width * 2.2)}"');
  }
  return buffer.toString();
}

/// 用 [TextPainter] 的行边界还原每一行的文本，自动换行与手动换行都能覆盖。
List<String> _linesOf(String text, TextPainter painter) {
  final lines = <String>[];
  var offset = 0;
  var guard = 0;
  while (offset < text.length && guard++ <= text.length + 8) {
    final boundary = painter.getLineBoundary(TextPosition(offset: offset));
    var end = boundary.end;
    if (end <= offset) {
      // 空行 / 行尾正好在换行符上：手动前进一个字符，避免死循环。
      final nextBreak = text.indexOf('\n', offset);
      end = nextBreak < 0 ? text.length : nextBreak;
      lines.add(text.substring(offset, end));
      offset = end + 1;
      continue;
    }
    lines.add(text.substring(offset, end).replaceAll('\n', ''));
    offset = end;
  }
  if (lines.isEmpty) lines.add(text);
  return lines;
}

void _writeGrid(StringBuffer buffer, Rect area, double spacing) {
  if (spacing <= 0) return;
  final dots = StringBuffer();
  final startX = (area.left / spacing).floor() * spacing;
  final startY = (area.top / spacing).floor() * spacing;
  for (var x = startX; x <= area.right; x += spacing) {
    for (var y = startY; y <= area.bottom; y += spacing) {
      dots.writeln('    <circle cx="${_n(x)}" cy="${_n(y)}" r="0.9" '
          'fill="#000000" fill-opacity="0.10"/>');
    }
  }
  buffer.write(dots);
}

String _hex(Color color) {
  final argb = argbOf(color);
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// 数字格式化：整数不写小数点，小数最多两位。SVG 体积能小一大截。
String _n(double value) {
  if (!value.isFinite) return '0';
  if (value == value.roundToDouble()) return value.toInt().toString();
  final text = value.toStringAsFixed(2);
  return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
}
