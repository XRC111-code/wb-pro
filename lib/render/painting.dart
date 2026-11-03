import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/element.dart';
import '../model/ink.dart';
import '../model/text_metrics.dart';
import '../util/color_utils.dart';
import '../model/rough.dart';

/// 把路径切成虚线。
///
/// Flutter 没有内置 dash 支持（`Paint` 上没有 dashPattern），只能按路径长度
/// 逐段提取。用 `computeMetrics` 而不是自己采样，曲线段也能切得均匀。
Path dashPath(Path source, {required double dash, required double gap}) {
  if (dash <= 0) return source;
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final end = math.min(distance + dash, metric.length);
      if (end > distance) {
        result.addPath(metric.extractPath(distance, end), Offset.zero);
      }
      distance = end + gap;
    }
  }
  return result;
}

Paint _strokePaint(Color color, double width, double opacity) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = withOpacityValue(color, opacity)
  ..isAntiAlias = true;

Paint _fillPaint(Color color, double opacity) => Paint()
  ..style = PaintingStyle.fill
  ..color = withOpacityValue(color, opacity)
  ..isAntiAlias = true;

/// 按描边样式把轮廓画出来。
void _paintOutline(
  Canvas canvas,
  Path path,
  Color color,
  double width,
  StrokeStyle style,
  double opacity,
) {
  final paint = _strokePaint(color, width, opacity);
  switch (style) {
    case StrokeStyle.solid:
      canvas.drawPath(path, paint);
    case StrokeStyle.dashed:
      canvas.drawPath(
        dashPath(path, dash: width * 3 + 6, gap: width * 2 + 5),
        paint,
      );
    case StrokeStyle.dotted:
      // 极短的一段配 round cap 就是一个圆点；gap 取线宽的 2 倍才看得出间隔。
      canvas.drawPath(
        dashPath(path, dash: width * 0.05, gap: width * 2.2),
        paint,
      );
  }
}

/// 画一个元素（已含旋转与透明度）。
void paintElement(Canvas canvas, WbElement element) {
  if (element.opacity <= 0) return;
  final frame = element.frame;
  canvas.save();
  canvas.translate(frame.left, frame.top);
  canvas.translate(frame.width / 2, frame.height / 2);
  canvas.rotate(element.rotation);
  canvas.translate(-frame.width / 2, -frame.height / 2);

  switch (element) {
    case StrokeElement stroke:
      _paintStroke(canvas, stroke);
    case ShapeElement shape:
      _paintShape(canvas, shape);
    case ArrowElement arrow:
      _paintArrow(canvas, arrow);
    case TextElement text:
      _paintText(canvas, text);
    case NoteElement note:
      _paintNote(canvas, note);
    case ImageElement image:
      _paintImage(canvas, image);
  }
  canvas.restore();
}

void _paintStroke(Canvas canvas, StrokeElement stroke) {
  if (stroke.points.isEmpty) return;
  if (stroke.hasPressure) {
    // 有压感时画的是填充轮廓，不是描边：粗细沿笔画变化，一条 stroke 做
    // 不到。两端各补一个圆盖，否则轮廓的起止是平的，看着像被切了一刀。
    final paint = _fillPaint(stroke.color, stroke.opacity);
    canvas.drawPath(
      inkOutlinePath(stroke.points, stroke.pressures, stroke.strokeWidth),
      paint,
    );
    final last = stroke.points.length - 1;
    // 半径多给 0.15：轮廓边缘和圆盖之间不能有肉眼可见的缝。
    canvas.drawCircle(
      stroke.points.first,
      inkCapRadius(stroke.pressures, 0, stroke.strokeWidth) + 0.15,
      paint,
    );
    canvas.drawCircle(
      stroke.points.last,
      inkCapRadius(stroke.pressures, last, stroke.strokeWidth) + 0.15,
      paint,
    );
    return;
  }
  final paint = _strokePaint(stroke.color, stroke.strokeWidth, stroke.opacity);
  if (stroke.points.length == 1) {
    canvas.drawCircle(
      stroke.points.first,
      stroke.strokeWidth / 2,
      _fillPaint(stroke.color, stroke.opacity),
    );
    return;
  }
  canvas.drawPath(stroke.buildPath(), paint);
}

void _paintShape(Canvas canvas, ShapeElement shape) {
  if (shape.fill != null) {
    // 填充用原始几何路径。抖动的边界加上实心填充，边缘会出现细小的锯齿状
    // 色带，反而显得脏。
    canvas.drawPath(shape.localPath(), _fillPaint(shape.fill!, shape.opacity));
  }
  _paintOutline(
    canvas,
    outlinePathOf(shape),
    shape.stroke,
    shape.strokeWidth,
    shape.strokeStyle,
    shape.opacity,
  );
}

/// 形状的描边路径。手绘风格时返回两条抖动曲线叠加的结果。
///
/// 抖动幅度见 [kRoughAmplitude]。
Path outlinePathOf(ShapeElement shape) {
  if (shape.roughness <= 0) return shape.localPath();
  final frame = shape.frame;
  final key = '${shape.id}|${frame.left.round()},${frame.top.round()},'
      '${frame.width.round()},${frame.height.round()}|'
      '${shape.roughness.toStringAsFixed(2)}|${shape.seed}|'
      '${shape.cornerRadius.toStringAsFixed(1)}|${shape.shape.name}';
  return RoughPathCache.resolve(key, () {
    final base = shape.localPath();
    final amplitude = kRoughAmplitude * shape.roughness;
    final path = Path();
    path.addPath(
      smoothClosedPath(roughOutline(base, seed: shape.seed, amplitude: amplitude)),
      Offset.zero,
    );
    path.addPath(
      smoothClosedPath(
        roughOutline(base, seed: shape.seed + 977, amplitude: amplitude * 0.72),
      ),
      Offset.zero,
    );
    return path;
  });
}

void _paintArrow(Canvas canvas, ArrowElement arrow) {
  final paint = _strokePaint(arrow.stroke, arrow.strokeWidth, arrow.opacity);
  final path = Path()
    ..moveTo(arrow.start.dx, arrow.start.dy)
    ..lineTo(arrow.end.dx, arrow.end.dy);
  switch (arrow.strokeStyle) {
    case StrokeStyle.solid:
      canvas.drawPath(path, paint);
    case StrokeStyle.dashed:
      canvas.drawPath(
        dashPath(path, dash: arrow.strokeWidth * 3 + 6, gap: arrow.strokeWidth * 2 + 5),
        paint,
      );
    case StrokeStyle.dotted:
      canvas.drawPath(
        dashPath(path, dash: arrow.strokeWidth * 0.05, gap: arrow.strokeWidth * 2.2),
        paint,
      );
  }
  final headLength = 9 + arrow.strokeWidth * 2.2;
  final headPaint = _fillPaint(arrow.stroke, arrow.opacity);
  if (arrow.endHead) {
    _paintHead(canvas, arrow.start, arrow.end, headLength, headPaint);
  }
  if (arrow.startHead) {
    _paintHead(canvas, arrow.end, arrow.start, headLength, headPaint);
  }
}

/// 在 [tip] 处画一个指向 [tip] 的箭头（[from] 是线的另一端）。
void _paintHead(Canvas canvas, Offset from, Offset tip, double length, Paint paint) {
  final angle = math.atan2(tip.dy - from.dy, tip.dx - from.dx);
  const spread = 0.42;
  final left = tip -
      Offset(math.cos(angle - spread), math.sin(angle - spread)) * length;
  final right = tip -
      Offset(math.cos(angle + spread), math.sin(angle + spread)) * length;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close(),
    paint,
  );
}

void _paintText(Canvas canvas, TextElement text) {
  final style = buildTextStyle(
    fontSize: text.fontSize,
    color: text.color,
    bold: text.bold,
    italic: text.italic,
    lineHeight: text.lineHeight,
  );
  final painter = layoutTextBlock(
    text.text,
    style,
    maxWidth: text.frame.width,
    align: text.align,
  );
  painter.paint(canvas, Offset.zero);
  painter.dispose();
}

void _paintNote(Canvas canvas, NoteElement note) {
  final rect = Rect.fromLTWH(0, 0, note.frame.width, note.frame.height);
  // 便签用一点点投影把它从画布上「抬起来」。导出 PNG 时也会带上，观感一致。
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect.shift(const Offset(0, 2)), const Radius.circular(6)),
    Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    _fillPaint(note.fill, note.opacity),
  );

  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(6)));
  final style = buildTextStyle(
    fontSize: note.fontSize,
    color: note.textColor,
    lineHeight: 1.4,
  );
  final painter = layoutTextBlock(
    note.text.isEmpty ? '双击输入…' : note.text,
    style,
    maxWidth: math.max(20, rect.width - 28),
  );
  if (note.text.isEmpty) {
    painter.paint(canvas, const Offset(14, 14));
  } else {
    painter.paint(canvas, const Offset(14, 14));
  }
  painter.dispose();
  canvas.restore();
}

/// 图片解码缓存。
///
/// `Canvas.drawImage` 需要已解码的 `ui.Image`，而解码是异步的、绘制是同步的。
/// 这里做一层「按元素 id 缓存 + 解好后重新绘制」：第一次绘制画占位框，解完
/// 通知重绘。比在 setState 里 await 更稳——重绘可能发生在任何时刻。
class ImageRegistry {
  static final Map<String, ui.Image> _images = <String, ui.Image>{};
  static final Set<String> _loading = <String>{};

  static ui.Image? get(String id) => _images[id];

  static void ensure(ImageElement element, VoidCallback onReady) {
    if (_images.containsKey(element.id) || element.bytes.isEmpty) return;
    if (!_loading.add(element.id)) return;
    ui.decodeImageFromList(element.bytes, (image) {
      _images[element.id] = image;
      _loading.remove(element.id);
      onReady();
    });
  }

  /// 导出前把所有图片解码完。
  ///
  /// 画面上的图片是「先画占位框、解好后重绘」，但导出只有一次机会 —— 不等
  /// 解码完成，导出结果里就只剩一堆灰色方框。带超时是因为
  /// `decodeImageFromList` 对损坏数据不会回调，不能让它把导出卡死。
  static Future<void> preload(Iterable<ImageElement> elements) async {
    final pending = <Future<void>>[];
    for (final element in elements) {
      if (element.bytes.isEmpty || _images.containsKey(element.id)) continue;
      if (!_loading.add(element.id)) continue;
      final completer = Completer<void>();
      ui.decodeImageFromList(element.bytes, (image) {
        _images[element.id] = image;
        _loading.remove(element.id);
        if (!completer.isCompleted) completer.complete();
      });
      pending.add(completer.future);
    }
    if (pending.isEmpty) return;
    await Future.wait(pending).timeout(
      const Duration(seconds: 8),
      onTimeout: () => const <void>[],
    );
  }

  static void evict(String id) {
    _images.remove(id)?.dispose();
  }

  static void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _loading.clear();
  }
}

void _paintImage(Canvas canvas, ImageElement element) {
  final rect = Rect.fromLTWH(0, 0, element.frame.width, element.frame.height);
  final image = ImageRegistry.get(element.id);
  if (image == null) {
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0x11000000),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33000000),
    );
    return;
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, element.opacity),
  );
}

/// 画网格背景。
///
/// [zoom] 太小时不画：点间距小于 4px 时网格会变成一片噪点，比没有更糟。
void paintGrid(
  Canvas canvas,
  Rect world,
  double zoom, {
  double spacing = 24,
  Color color = const Color(0x14000000),
  bool dots = true,
}) {
  final step = spacing * zoom;
  if (step < 6) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.1
    ..strokeCap = StrokeCap.round;

  if (dots) {
    final points = <Offset>[];
    final startX = (world.left / spacing).floor() * spacing;
    final startY = (world.top / spacing).floor() * spacing;
    for (var x = startX; x <= world.right; x += spacing) {
      for (var y = startY; y <= world.bottom; y += spacing) {
        points.add(Offset(x, y));
      }
    }
    // 点上万个时 drawPoints 比逐个 drawCircle 快一个数量级。
    if (points.length > 200000) return;
    canvas.drawPoints(ui.PointMode.points, points, paint);
  } else {
    for (var x = (world.left / spacing).floor() * spacing; x <= world.right; x += spacing) {
      canvas.drawLine(
        Offset(x, world.top),
        Offset(x, world.bottom),
        paint..strokeWidth = 0.8,
      );
    }
    for (var y = (world.top / spacing).floor() * spacing; y <= world.bottom; y += spacing) {
      canvas.drawLine(
        Offset(world.left, y),
        Offset(world.right, y),
        paint..strokeWidth = 0.8,
      );
    }
  }
}

/// 画整个场景。视口外的元素直接跳过——无限画布上大部分元素都在屏幕外，
/// 不裁剪的话几千个元素每帧都要走一遍路径构建。
void paintScene(Canvas canvas, List<WbElement> elements, Rect visibleWorld) {
  final cull = visibleWorld.inflate(80);
  for (final element in elements) {
    if (!element.visible) continue;
    if (!element.worldBounds.overlaps(cull)) continue;
    paintElement(canvas, element);
  }
}
