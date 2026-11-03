import 'dart:math' as math;
import 'dart:ui';

/// 一条对齐参考线。
///
/// [vertical] 为真时表示竖线，[position] 是它的 x；否则是横线，[position]
/// 是它的 y。[from] / [to] 是它在另一个轴上的可见范围——只覆盖真正贴在这条
/// 线上的元素，而不是贯穿整个画布。贯穿线在元素一多时会变成一张网格，
/// 反而看不清到底跟谁对齐了。
class SnapGuide {
  const SnapGuide({
    required this.vertical,
    required this.position,
    required this.from,
    required this.to,
  });

  final bool vertical;
  final double position;
  final double from;
  final double to;

  @override
  bool operator ==(Object other) =>
      other is SnapGuide &&
      other.vertical == vertical &&
      (other.position - position).abs() < 0.001 &&
      (other.from - from).abs() < 0.001 &&
      (other.to - to).abs() < 0.001;

  @override
  int get hashCode =>
      Object.hash(vertical, (position * 100).round(), (from * 100).round(), (to * 100).round());

  @override
  String toString() => 'SnapGuide(${vertical ? 'v' : 'h'} @$position, $from..$to)';
}

/// 吸附结果。
class SnapResult {
  const SnapResult({this.delta = Offset.zero, this.guides = const <SnapGuide>[]});

  /// 在原始位移之上还需要补的偏移。调用方应该用 `raw + delta` 移动元素。
  final Offset delta;

  /// 需要画出来的参考线，已按位置去重、范围已合并。
  final List<SnapGuide> guides;

  bool get isEmpty => guides.isEmpty;
}

/// 两条线判为「重合」的容差。比吸附阈值小得多：吸附之后残余误差应该接近 0，
/// 只有浮点误差。
const double _kCoincide = 0.5;

/// 参与吸附的基准线。移动时六条全用；缩放时只用被拖动的那几条 —— 否则
/// 拖右边时左边缘碰巧对齐了别的元素，整个框会被平移，锚点就飞了。
enum SnapEdge { left, centerX, right, top, centerY, bottom }

/// 六条线全开。`SnapEdge.values` 是 List，不能直接当 Set 的默认值。
const Set<SnapEdge> kAllSnapEdges = <SnapEdge>{
  SnapEdge.left,
  SnapEdge.centerX,
  SnapEdge.right,
  SnapEdge.top,
  SnapEdge.centerY,
  SnapEdge.bottom,
};

/// 计算拖拽时的元素间吸附。
///
/// [moving] 是拖拽中的包围盒（已经应用了原始位移），[targets] 是其他元素的
/// 包围盒，[threshold] 是吸附距离（世界单位，调用方按 `屏幕像素 / zoom` 折算，
/// 这样放大后不会变得「很难对齐」）。
///
/// 只取每个轴上最近的一条基准线作为吸附目标：同时吸两条会互相打架，结果是
/// 元素在两个位置之间抖。但一旦吸附值定下来，所有恰好重合的线都会画出来。
SnapResult computeSnap({
  required Rect moving,
  required Iterable<Rect> targets,
  required double threshold,
  Set<SnapEdge> edges = kAllSnapEdges,
}) {
  if (threshold <= 0) return const SnapResult();
  final list = targets.toList(growable: false);
  if (list.isEmpty) return const SnapResult();

  final verticals = <double>[];
  final horizontals = <double>[];
  for (final r in list) {
    verticals
      ..add(r.left)
      ..add(r.center.dx)
      ..add(r.right);
    horizontals
      ..add(r.top)
      ..add(r.center.dy)
      ..add(r.bottom);
  }

  final movingX = <double>[
    if (edges.contains(SnapEdge.left)) moving.left,
    if (edges.contains(SnapEdge.centerX)) moving.center.dx,
    if (edges.contains(SnapEdge.right)) moving.right,
  ];
  final movingY = <double>[
    if (edges.contains(SnapEdge.top)) moving.top,
    if (edges.contains(SnapEdge.centerY)) moving.center.dy,
    if (edges.contains(SnapEdge.bottom)) moving.bottom,
  ];

  final dx = _bestShift(movingX, verticals, threshold);
  final dy = _bestShift(movingY, horizontals, threshold);

  final guides = <SnapGuide>[
    if (dx != null)
      ..._guidesAlong(
        vertical: true,
        shift: dx,
        moving: moving,
        targets: list,
        edges: edges,
        includeCenter: edges.contains(SnapEdge.centerX),
      ),
    if (dy != null)
      ..._guidesAlong(
        vertical: false,
        shift: dy,
        moving: moving,
        targets: list,
        edges: edges,
        includeCenter: edges.contains(SnapEdge.centerY),
      ),
  ];

  return SnapResult(
    delta: Offset(dx ?? 0, dy ?? 0),
    guides: guides,
  );
}

/// 找一个轴上的最佳偏移：绝对值最小、且不超过阈值。
double? _bestShift(List<double> movingLines, List<double> targetLines, double threshold) {
  double? best;
  for (final m in movingLines) {
    for (final t in targetLines) {
      final d = t - m;
      if (d.abs() > threshold) continue;
      if (best == null || d.abs() < best.abs() - 0.0001) best = d;
    }
  }
  return best;
}

/// 吸附值定了之后，把所有真正重合的线收出来。
///
/// 一个元素可能同时左边贴 A、右边贴 B；两个都要画，否则用户不知道这次
/// 拖拽为什么「卡」在这里。
List<SnapGuide> _guidesAlong({
  required bool vertical,
  required double shift,
  required Rect moving,
  required List<Rect> targets,
  required Set<SnapEdge> edges,
  required bool includeCenter,
}) {
  final moved = vertical
      ? moving.shift(Offset(shift, 0))
      : moving.shift(Offset(0, shift));
  final movingLines = vertical
      ? <double>[
          if (edges.contains(SnapEdge.left)) moved.left,
          if (includeCenter) moved.center.dx,
          if (edges.contains(SnapEdge.right)) moved.right,
        ]
      : <double>[
          if (edges.contains(SnapEdge.top)) moved.top,
          if (includeCenter) moved.center.dy,
          if (edges.contains(SnapEdge.bottom)) moved.bottom,
        ];

  // 位置 → 沿另一轴的范围 [min, max]。用整数键避免浮点相等的坑。
  final ranges = <int, List<double>>{};
  void extend(double position, double a, double b) {
    final key = (position * 100).round();
    final existing = ranges[key];
    if (existing == null) {
      ranges[key] = <double>[math.min(a, b), math.max(a, b)];
    } else {
      existing[0] = math.min(existing[0], math.min(a, b));
      existing[1] = math.max(existing[1], math.max(a, b));
    }
  }

  for (final m in movingLines) {
    final others = _otherAxis(moved, vertical);
    for (final r in targets) {
      final lines = vertical
          ? <double>[r.left, r.center.dx, r.right]
          : <double>[r.top, r.center.dy, r.bottom];
      for (final t in lines) {
        if ((t - m).abs() > _kCoincide) continue;
        extend(t, others.$1, others.$2);
        extend(t, _otherAxis(r, vertical).$1, _otherAxis(r, vertical).$2);
      }
    }
  }

  const pad = 6.0;
  final guides = <SnapGuide>[
    for (final entry in ranges.entries)
      SnapGuide(
        vertical: vertical,
        position: entry.key / 100,
        from: entry.value[0] - pad,
        to: entry.value[1] + pad,
      ),
  ];

  // 两个同宽的元素左对齐时，左、中、右三条线会**同时**重合，画出来是三条
  // 并排的竖线，看起来像画错了。范围完全相同的线只留最靠前的一条：它已经
  // 说明了对齐关系，另外两条是同一件事的重复表述。
  //
  // 范围不同则都保留 —— 「左边贴 A、右边贴 B」是两条独立的信息。
  final byRange = <String, SnapGuide>{};
  for (final guide in guides) {
    final key = '${guide.from.round()}:${guide.to.round()}';
    final existing = byRange[key];
    if (existing == null || guide.position < existing.position) {
      byRange[key] = guide;
    }
  }
  return byRange.values.toList(growable: false);
}

(double, double) _otherAxis(Rect r, bool vertical) =>
    vertical ? (r.top, r.bottom) : (r.left, r.right);
