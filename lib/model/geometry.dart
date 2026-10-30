import 'dart:math' as math;
import 'dart:ui';

/// 一条线段的包围盒（允许两点顺序任意）。
Rect rectFromPoints(Offset a, Offset b) => Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    );

/// 点 [p] 到线段 [a]-[b] 的最短距离。
///
/// 白板的命中测试全靠它：线段没有面积，只能判「离得够近」。分母为 0 时
/// 退化成到端点的距离，这里显式处理，否则退化线段会算出 NaN，接着
/// `NaN <= tolerance` 恒为 false —— 一条画在正中心的线永远点不中。
double distanceToSegment(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  return (p - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
}

/// 绕 [center] 旋转 [angle] 弧度。
Offset rotatePoint(Offset point, Offset center, double angle) {
  if (angle == 0) return point;
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  final d = point - center;
  return center + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
}

/// 一个（可能旋转过的）矩形四个角，顺序为左上、右上、右下、左下。
List<Offset> cornersOf(Rect rect, double rotation) {
  final center = rect.center;
  final corners = <Offset>[
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];
  if (rotation == 0) return corners;
  return corners.map((c) => rotatePoint(c, center, rotation)).toList();
}

/// 旋转矩形的轴对齐包围盒。
Rect rotatedBounds(Rect rect, double rotation) {
  if (rotation == 0) return rect;
  final corners = cornersOf(rect, rotation);
  var left = corners.first.dx;
  var right = corners.first.dx;
  var top = corners.first.dy;
  var bottom = corners.first.dy;
  for (final c in corners) {
    left = math.min(left, c.dx);
    right = math.max(right, c.dx);
    top = math.min(top, c.dy);
    bottom = math.max(bottom, c.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// 把 [inner] 限制在 [outer] 内部（宽高不够时不缩放，只对齐左上）。
Rect clampRect(Rect inner, Rect outer) {
  var left = inner.left.clamp(outer.left, outer.right);
  var top = inner.top.clamp(outer.top, outer.bottom);
  return Rect.fromLTWH(left, top, inner.width, inner.height);
}

/// 由两个任意角点构造规范化矩形（拖拽创建形状时用）。
Rect normalizedRect(Offset a, Offset b) => Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    );

/// 让 [rect] 至少是 [minSize] 见方，避免出现宽高为 0 的元素。
///
/// 宽高为 0 的矩形会让缩放比例除零、`Path.contains` 恒假，元素从此再也
/// 选不中——看起来像「画了一个矩形但它消失了」。
Rect ensureMinSize(Rect rect, {double minSize = 1}) {
  final w = rect.width < minSize ? minSize : rect.width;
  final h = rect.height < minSize ? minSize : rect.height;
  return Rect.fromLTWH(rect.left, rect.top, w, h);
}
