import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../util/color_utils.dart';
import 'geometry.dart';

/// 元素类型。序列化时用 [name]，增删枚举会让旧文档读不出来，所以只在
/// 末尾追加，不改名。
enum ElementKind { stroke, shape, arrow, text, note, image }

enum ShapeKind { rectangle, ellipse, diamond }

enum StrokeStyle { solid, dashed, dotted }

// ── JSON 读取的容错小工具 ────────────────────────────────────────────────────
// 文档可能来自用户手改、旧版本、别的分支。字段缺失或类型不对时用默认值，
// 而不是抛异常——「打不开」比「打开后少一个字段」严重得多。
double _num(Object? v, [double fallback = 0]) =>
    v is num && v.isFinite ? v.toDouble() : fallback;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;
Color _color(Object? v, Color fallback) => v is num ? colorOf(v.toInt()) : fallback;
Offset _offset(Object? v) {
  if (v is List && v.length >= 2) return Offset(_num(v[0]), _num(v[1]));
  if (v is Map) return Offset(_num(v['x']), _num(v['y']));
  return Offset.zero;
}

/// 白板元素。
///
/// ── 为什么要 sealed ────────────────────────────────────────────────────────
/// 渲染、序列化、命中测试里到处要按类型分支。普通 abstract class 的 switch
/// 默认要求 default 分支，于是新增一种元素时，编译器不会告诉你「有 7 处
/// 绘制代码还没处理它」——只会在运行时画不出来。sealed 强制穷尽检查，把
/// 这个错误提前到编译期。
///
/// ── 坐标约定 ───────────────────────────────────────────────────────────────
/// [frame] 是**未旋转**的轴对齐框，[rotation] 绕 frame.center 旋转。
/// 子类内部几何（笔迹点、箭头端点）一律存**本地坐标**（相对 frame.topLeft，
/// 范围 0..width），这样平移元素只改 frame，不用同步改每个点。
sealed class WbElement {
  const WbElement({
    required this.id,
    required this.frame,
    this.rotation = 0,
    this.opacity = 1,
  });

  final String id;
  final Rect frame;
  final double rotation;
  final double opacity;

  ElementKind get kind;

  WbElement copyWith({String? id, Rect? frame, double? rotation, double? opacity});

  /// 本地坐标下的轮廓，用于绘制与填充命中。
  Path localPath();

  /// 缩放到新框。子类要同步缩放内部几何，默认只改框。
  WbElement resized(Rect next) => copyWith(frame: next);

  WbElement translated(Offset delta) => copyWith(frame: frame.shift(delta));

  WbElement withOpacity(double value) =>
      copyWith(opacity: value.clamp(0.0, 1.0).toDouble());

  /// 旋转后仍轴对齐的包围盒。框选用。
  Rect get worldBounds => rotatedBounds(frame, rotation);

  /// 世界坐标 → 去掉旋转后的世界坐标。
  ///
  /// 返回值仍在世界坐标系里（不是相对 frame），这样 [hitTestLocal] 里
  /// 减一次 topLeft 即可，减少一次容易写错的坐标转换。
  Offset toLocal(Offset world) {
    if (rotation == 0) return world;
    return rotatePoint(world, frame.center, -rotation);
  }

  Offset toWorld(Offset local) {
    if (rotation == 0) return local;
    return rotatePoint(local, frame.center, rotation);
  }

  bool hitTest(Offset world, {double tolerance = 4}) {
    final local = toLocal(world);
    // 先做包围盒粗筛：绝大多数点击落在空白处，这一步能省掉路径运算。
    if (!frame.inflate(tolerance).contains(local)) return false;
    return hitTestLocal(local - frame.topLeft, tolerance);
  }

  bool hitTestLocal(Offset p, double tolerance);

  Map<String, Object?> toJson();

  Map<String, Object?> baseJson(String type) => <String, Object?>{
        'type': type,
        'id': id,
        'x': frame.left,
        'y': frame.top,
        'w': frame.width,
        'h': frame.height,
        if (rotation != 0) 'rotation': rotation,
        if (opacity != 1) 'opacity': opacity,
      };

  static WbElement fromJson(Map<String, Object?> json) {
    final type = _str(json['type']);
    final frame = Rect.fromLTWH(
      _num(json['x']),
      _num(json['y']),
      math.max(_num(json['w']), 0),
      math.max(_num(json['h']), 0),
    );
    final id = _str(json['id'], 'el-${frame.left}-${frame.top}');
    final rotation = _num(json['rotation']);
    final opacity = _num(json['opacity'], 1).clamp(0.0, 1.0).toDouble();
    switch (type) {
      case 'stroke':
        return StrokeElement.fromJson(json, id, frame, rotation, opacity);
      case 'shape':
        return ShapeElement.fromJson(json, id, frame, rotation, opacity);
      case 'arrow':
        return ArrowElement.fromJson(json, id, frame, rotation, opacity);
      case 'text':
        return TextElement.fromJson(json, id, frame, rotation, opacity);
      case 'note':
        return NoteElement.fromJson(json, id, frame, rotation, opacity);
      case 'image':
        return ImageElement.fromJson(json, id, frame, rotation, opacity);
      default:
        throw FormatException('未知的元素类型：$type');
    }
  }
}

// ── 笔迹 ─────────────────────────────────────────────────────────────────────

class StrokeElement extends WbElement {
  const StrokeElement({
    required super.id,
    required super.frame,
    required this.points,
    required this.color,
    required this.strokeWidth,
    super.rotation,
    super.opacity,
  });

  /// 本地坐标（0..frame.width / 0..frame.height）。
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  @override
  ElementKind get kind => ElementKind.stroke;

  /// 用二次贝塞尔把折线磨圆。
  ///
  /// 直接 lineTo 会让手写笔画在低采样率下出现明显折角；中点法只用相邻三点
  /// 就能得到足够顺滑的曲线，且不会像 Catmull-Rom 那样在急转弯处过冲。
  Path buildPath() {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.addOval(Rect.fromCircle(center: points.first, radius: strokeWidth / 2));
      return path;
    }
    path.moveTo(points[0].dx, points[0].dy);
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset(
        (points[i].dx + points[i + 1].dx) / 2,
        (points[i].dy + points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  Path localPath() => buildPath();

  @override
  bool hitTestLocal(Offset p, double tolerance) {
    final threshold = strokeWidth / 2 + tolerance;
    if (points.length == 1) return (p - points.first).distance <= threshold;
    for (var i = 0; i < points.length - 1; i++) {
      if (distanceToSegment(p, points[i], points[i + 1]) <= threshold) return true;
    }
    return false;
  }

  @override
  StrokeElement copyWith({
    String? id,
    Rect? frame,
    double? rotation,
    double? opacity,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
  }) =>
      StrokeElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        points: points ?? this.points,
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  @override
  StrokeElement resized(Rect next) {
    final sx = frame.width == 0 ? 1.0 : next.width / frame.width;
    final sy = frame.height == 0 ? 1.0 : next.height / frame.height;
    return copyWith(
      frame: next,
      points: points
          .map((p) => Offset(p.dx * sx, p.dy * sy))
          .toList(growable: false),
    );
  }

  @override
  Map<String, Object?> toJson() => baseJson('stroke')
    ..addAll(<String, Object?>{
      'points': <double>[
        for (final p in points) ...[p.dx, p.dy],
      ],
      'color': argbOf(color),
      'width': strokeWidth,
    });

  static StrokeElement fromJson(
    Map<String, Object?> json,
    String id,
    Rect frame,
    double rotation,
    double opacity,
  ) {
    final flat = json['points'];
    final points = <Offset>[];
    if (flat is List) {
      for (var i = 0; i + 1 < flat.length; i += 2) {
        points.add(Offset(_num(flat[i]), _num(flat[i + 1])));
      }
    }
    return StrokeElement(
      id: id,
      frame: frame,
      points: points,
      color: _color(json['color'], const Color(0xFF1F2933)),
      strokeWidth: math.max(_num(json['width'], 3), 0.5),
      rotation: rotation,
      opacity: opacity,
    );
  }
}

// ── 形状 ─────────────────────────────────────────────────────────────────────

class ShapeElement extends WbElement {
  const ShapeElement({
    required super.id,
    required super.frame,
    required this.shape,
    required this.stroke,
    required this.strokeWidth,
    this.fill,
    this.strokeStyle = StrokeStyle.solid,
    this.cornerRadius = 12,
    super.rotation,
    super.opacity,
  });

  final ShapeKind shape;
  final Color stroke;
  final Color? fill;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final double cornerRadius;

  @override
  ElementKind get kind => ElementKind.shape;

  @override
  Path localPath() {
    final r = Rect.fromLTWH(0, 0, frame.width, frame.height);
    switch (shape) {
      case ShapeKind.rectangle:
        final radius = math.min(cornerRadius, math.min(r.width, r.height) / 2);
        return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
      case ShapeKind.ellipse:
        return Path()..addOval(r);
      case ShapeKind.diamond:
        return Path()
          ..moveTo(r.center.dx, 0)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(0, r.center.dy)
          ..close();
    }
  }

  /// 到轮廓的距离（用于只有描边、没有填充时的命中）。
  double _distanceToOutline(Offset p) {
    final r = Rect.fromLTWH(0, 0, frame.width, frame.height);
    switch (shape) {
      case ShapeKind.rectangle:
        return _distanceToRectBorder(p, r);
      case ShapeKind.ellipse:
        // 椭圆没有解析的最近点公式；用「按半径归一化后的隐函数值」换算成
        // 近似距离，精度足够判定几个像素的点击。
        final rx = r.width / 2;
        final ry = r.height / 2;
        if (rx <= 0 || ry <= 0) return (p - r.center).distance;
        final nx = (p.dx - r.center.dx) / rx;
        final ny = (p.dy - r.center.dy) / ry;
        final value = math.sqrt(nx * nx + ny * ny);
        final scale = math.min(rx, ry);
        return (value - 1).abs() * scale;
      case ShapeKind.diamond:
        final points = <Offset>[
          Offset(r.center.dx, 0),
          Offset(r.right, r.center.dy),
          Offset(r.center.dx, r.bottom),
          Offset(0, r.center.dy),
        ];
        var best = double.infinity;
        for (var i = 0; i < 4; i++) {
          best = math.min(best, distanceToSegment(p, points[i], points[(i + 1) % 4]));
        }
        return best;
    }
  }

  static double _distanceToRectBorder(Offset p, Rect r) {
    final inside = r.contains(p);
    if (inside) {
      return math.min(
        math.min(p.dx - r.left, r.right - p.dx),
        math.min(p.dy - r.top, r.bottom - p.dy),
      );
    }
    final dx = math.max(math.max(r.left - p.dx, 0), p.dx - r.right);
    final dy = math.max(math.max(r.top - p.dy, 0), p.dy - r.bottom);
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool hitTestLocal(Offset p, double tolerance) {
    final path = localPath();
    if (fill != null && path.contains(p)) return true;
    return _distanceToOutline(p) <= strokeWidth / 2 + tolerance;
  }

  @override
  ShapeElement copyWith({
    String? id,
    Rect? frame,
    double? rotation,
    double? opacity,
    ShapeKind? shape,
    Color? stroke,
    Color? fill,
    bool clearFill = false,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    double? cornerRadius,
  }) =>
      ShapeElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        shape: shape ?? this.shape,
        stroke: stroke ?? this.stroke,
        fill: clearFill ? null : (fill ?? this.fill),
        strokeWidth: strokeWidth ?? this.strokeWidth,
        strokeStyle: strokeStyle ?? this.strokeStyle,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  @override
  Map<String, Object?> toJson() => baseJson('shape')
    ..addAll(<String, Object?>{
      'shape': shape.name,
      'stroke': argbOf(stroke),
      'fill': fill == null ? null : argbOf(fill!),
      'width': strokeWidth,
      'style': strokeStyle.name,
      'radius': cornerRadius,
    });

  static ShapeElement fromJson(
    Map<String, Object?> json,
    String id,
    Rect frame,
    double rotation,
    double opacity,
  ) {
    final shapeName = _str(json['shape'], 'rectangle');
    final styleName = _str(json['style'], 'solid');
    return ShapeElement(
      id: id,
      frame: frame,
      shape: ShapeKind.values.firstWhere(
        (s) => s.name == shapeName,
        orElse: () => ShapeKind.rectangle,
      ),
      stroke: _color(json['stroke'], const Color(0xFF1F2933)),
      fill: json['fill'] == null ? null : _color(json['fill'], const Color(0xFFFFFFFF)),
      strokeWidth: math.max(_num(json['width'], 2), 0.5),
      strokeStyle: StrokeStyle.values.firstWhere(
        (s) => s.name == styleName,
        orElse: () => StrokeStyle.solid,
      ),
      cornerRadius: _num(json['radius'], 12),
      rotation: rotation,
      opacity: opacity,
    );
  }
}

// ── 箭头 / 直线 ──────────────────────────────────────────────────────────────

class ArrowElement extends WbElement {
  const ArrowElement({
    required super.id,
    required super.frame,
    required this.start,
    required this.end,
    required this.stroke,
    required this.strokeWidth,
    this.startHead = false,
    this.endHead = true,
    this.strokeStyle = StrokeStyle.solid,
    super.rotation,
    super.opacity,
  });

  /// 本地坐标。
  final Offset start;
  final Offset end;
  final Color stroke;
  final double strokeWidth;
  final bool startHead;
  final bool endHead;
  final StrokeStyle strokeStyle;

  @override
  ElementKind get kind => ElementKind.arrow;

  @override
  Path localPath() => Path()
    ..moveTo(start.dx, start.dy)
    ..lineTo(end.dx, end.dy);

  @override
  bool hitTestLocal(Offset p, double tolerance) =>
      distanceToSegment(p, start, end) <= strokeWidth / 2 + tolerance;

  @override
  ArrowElement copyWith({
    String? id,
    Rect? frame,
    double? rotation,
    double? opacity,
    Offset? start,
    Offset? end,
    Color? stroke,
    double? strokeWidth,
    bool? startHead,
    bool? endHead,
    StrokeStyle? strokeStyle,
  }) =>
      ArrowElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        start: start ?? this.start,
        end: end ?? this.end,
        stroke: stroke ?? this.stroke,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        startHead: startHead ?? this.startHead,
        endHead: endHead ?? this.endHead,
        strokeStyle: strokeStyle ?? this.strokeStyle,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  @override
  ArrowElement resized(Rect next) {
    final sx = frame.width == 0 ? 1.0 : next.width / frame.width;
    final sy = frame.height == 0 ? 1.0 : next.height / frame.height;
    return copyWith(
      frame: next,
      start: Offset(start.dx * sx, start.dy * sy),
      end: Offset(end.dx * sx, end.dy * sy),
    );
  }

  @override
  Map<String, Object?> toJson() => baseJson('arrow')
    ..addAll(<String, Object?>{
      'start': <double>[start.dx, start.dy],
      'end': <double>[end.dx, end.dy],
      'stroke': argbOf(stroke),
      'width': strokeWidth,
      'startHead': startHead,
      'endHead': endHead,
      'style': strokeStyle.name,
    });

  static ArrowElement fromJson(
    Map<String, Object?> json,
    String id,
    Rect frame,
    double rotation,
    double opacity,
  ) {
    final styleName = _str(json['style'], 'solid');
    return ArrowElement(
      id: id,
      frame: frame,
      start: _offset(json['start']),
      end: _offset(json['end']),
      stroke: _color(json['stroke'], const Color(0xFF1F2933)),
      strokeWidth: math.max(_num(json['width'], 2), 0.5),
      startHead: _bool(json['startHead']),
      endHead: _bool(json['endHead'], true),
      strokeStyle: StrokeStyle.values.firstWhere(
        (s) => s.name == styleName,
        orElse: () => StrokeStyle.solid,
      ),
      rotation: rotation,
      opacity: opacity,
    );
  }
}

// ── 文本 ─────────────────────────────────────────────────────────────────────

class TextElement extends WbElement {
  const TextElement({
    required super.id,
    required super.frame,
    required this.text,
    required this.color,
    this.fontSize = 24,
    this.bold = false,
    this.italic = false,
    this.align = TextAlign.left,
    this.lineHeight = 1.35,
    this.autoWidth = true,
    super.rotation,
    super.opacity,
  });

  final String text;
  final Color color;
  final double fontSize;
  final bool bold;
  final bool italic;
  final TextAlign align;
  final double lineHeight;

  /// 宽度是否跟随内容。
  ///
  /// 新建的文本框初始只有几十像素宽，如果一直按这个宽度排版，用户打一行字会
  /// 被折成十几个短行。手动拖过宽度之后这个标记就关掉 —— 此时宽度是用户的
  /// 明确意图，不该被内容再改回去。
  final bool autoWidth;

  @override
  ElementKind get kind => ElementKind.text;

  @override
  Path localPath() =>
      Path()..addRect(Rect.fromLTWH(0, 0, math.max(frame.width, 1), math.max(frame.height, 1)));

  @override
  bool hitTestLocal(Offset p, double tolerance) =>
      Rect.fromLTWH(0, 0, frame.width, frame.height).inflate(tolerance).contains(p);

  @override
  TextElement copyWith({
    String? id,
    Rect? frame,
    double? rotation,
    double? opacity,
    String? text,
    Color? color,
    double? fontSize,
    bool? bold,
    bool? italic,
    TextAlign? align,
    double? lineHeight,
    bool? autoWidth,
  }) =>
      TextElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        text: text ?? this.text,
        color: color ?? this.color,
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        align: align ?? this.align,
        lineHeight: lineHeight ?? this.lineHeight,
        autoWidth: autoWidth ?? this.autoWidth,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  /// 缩放文本时改字号而不是拉伸框 —— 拉伸会让字形变扁，字号变化才是
  /// 用户期待的「放大这段字」。
  @override
  TextElement resized(Rect next) {
    final scale = frame.width == 0 ? 1.0 : next.width / frame.width;
    return copyWith(
      frame: next,
      fontSize: (fontSize * scale).clamp(6.0, 400.0).toDouble(),
      autoWidth: false,
    );
  }

  @override
  Map<String, Object?> toJson() => baseJson('text')
    ..addAll(<String, Object?>{
      'text': text,
      'color': argbOf(color),
      'fontSize': fontSize,
      'bold': bold,
      'italic': italic,
      'align': align.name,
      'lineHeight': lineHeight,
      if (!autoWidth) 'autoWidth': false,
    });

  static TextElement fromJson(
    Map<String, Object?> json,
    String id,
    Rect frame,
    double rotation,
    double opacity,
  ) {
    final alignName = _str(json['align'], 'left');
    return TextElement(
      id: id,
      frame: frame,
      text: _str(json['text']),
      color: _color(json['color'], const Color(0xFF1F2933)),
      fontSize: math.max(_num(json['fontSize'], 24), 4),
      bold: _bool(json['bold']),
      italic: _bool(json['italic']),
      align: TextAlign.values.firstWhere(
        (a) => a.name == alignName,
        orElse: () => TextAlign.left,
      ),
      lineHeight: _num(json['lineHeight'], 1.35),
      autoWidth: _bool(json['autoWidth'], true),
      rotation: rotation,
      opacity: opacity,
    );
  }
}

// ── 便签 ─────────────────────────────────────────────────────────────────────

class NoteElement extends WbElement {
  const NoteElement({
    required super.id,
    required super.frame,
    required this.text,
    required this.fill,
    this.textColor = const Color(0xFF3B2F1B),
    this.fontSize = 18,
    super.rotation,
    super.opacity,
  });

  final String text;
  final Color fill;
  final Color textColor;
  final double fontSize;

  @override
  ElementKind get kind => ElementKind.note;

  @override
  Path localPath() =>
      Path()..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, math.max(frame.width, 1), math.max(frame.height, 1)),
        const Radius.circular(6),
      ));

  @override
  bool hitTestLocal(Offset p, double tolerance) =>
      Rect.fromLTWH(0, 0, frame.width, frame.height).inflate(tolerance).contains(p);

  @override
  NoteElement copyWith({
    String? id,
    Rect? frame,
    double? rotation,
    double? opacity,
    String? text,
    Color? fill,
    Color? textColor,
    double? fontSize,
  }) =>
      NoteElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        text: text ?? this.text,
        fill: fill ?? this.fill,
        textColor: textColor ?? this.textColor,
        fontSize: fontSize ?? this.fontSize,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  @override
  Map<String, Object?> toJson() => baseJson('note')
    ..addAll(<String, Object?>{
      'text': text,
      'fill': argbOf(fill),
      'textColor': argbOf(textColor),
      'fontSize': fontSize,
    });

  static NoteElement fromJson(
    Map<String, Object?> json,
    String id,
    Rect frame,
    double rotation,
    double opacity,
  ) =>
      NoteElement(
        id: id,
        frame: frame,
        text: _str(json['text']),
        fill: _color(json['fill'], const Color(0xFFFFE08A)),
        textColor: _color(json['textColor'], const Color(0xFF3B2F1B)),
        fontSize: math.max(_num(json['fontSize'], 18), 4),
        rotation: rotation,
        opacity: opacity,
      );
}

// ── 图片 ─────────────────────────────────────────────────────────────────────

class ImageElement extends WbElement {
  const ImageElement({
    required super.id,
    required super.frame,
    required this.bytes,
    required this.mimeType,
    this.label = '',
    super.rotation,
    super.opacity,
  });

  /// 原始文件字节。白板文档是自包含的（一个 .wbpro 走天下），所以图片
  /// 内嵌 base64，而不是存外部路径 —— 路径在换机器、换平台后几乎必然失效。
  final Uint8List bytes;
  final String mimeType;
  final String label;

  @override
  ElementKind get kind => ElementKind.image;

  @override
  Path localPath() =>
      Path()..addRect(Rect.fromLTWH(0, 0, math.max(frame.width, 1), math.max(frame.height, 1)));

  @override
  bool hitTestLocal(Offset p, double tolerance) =>
      Rect.fromLTWH(0, 0, frame.width, frame.height).inflate(tolerance).contains(p);

  @override
  ImageElement copyWith({
    String? id,
    Rect? frame,
    double? rotation,
    double? opacity,
    Uint8List? bytes,
    String? mimeType,
    String? label,
  }) =>
      ImageElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        bytes: bytes ?? this.bytes,
        mimeType: mimeType ?? this.mimeType,
        label: label ?? this.label,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  @override
  Map<String, Object?> toJson() => baseJson('image')
    ..addAll(<String, Object?>{
      'mime': mimeType,
      'label': label,
      'data': base64Encode(bytes),
    });

  static ImageElement fromJson(
    Map<String, Object?> json,
    String id,
    Rect frame,
    double rotation,
    double opacity,
  ) {
    Uint8List bytes;
    try {
      bytes = base64Decode(_str(json['data']));
    } on FormatException {
      bytes = Uint8List(0);
    }
    return ImageElement(
      id: id,
      frame: frame,
      bytes: bytes,
      mimeType: _str(json['mime'], 'image/png'),
      label: _str(json['label']),
      rotation: rotation,
      opacity: opacity,
    );
  }
}
