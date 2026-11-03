// 压感笔迹的轮廓几何。
//
// 等宽笔迹是一条 stroke 的路径，粗细处处相同。真人用笔不是这样：落笔重、
// 收笔轻、转弯处变慢会变粗。所以有压力数据时改成**填充多边形** —— 沿每个
// 点向法线两侧各推一个「当时的半径」，左边一串、右边一串，围成一个封闭
// 区域。
//
// 没有压力数据时（鼠标、部分触屏）调用方不应该走这里：等宽描边比模拟出来
// 的「假压感」更诚实。
import 'dart:math' as math;
import 'dart:ui';

// 压感笔迹的轮廓几何。
///
// 等宽笔迹是一条 `stroke` 的路径，两端圆、中间一边粗。真人用笔不是这样：
// 落笔重、收笔轻、转弯处变慢会变粗。所以有压力数据时改成**填充多边形**
// —— 沿每个点向法线两侧各推一个「当时的半径」，左边一串、右边一串，围成
// 一个封闭区域。
///
// 没有压力数据时（鼠标、部分触屏）调用方不应该走这里：等宽描边比模拟出来
// 的「假压感」更诚实。

/// 压力 → 半径系数。
///
/// 不用 0..1 的线性映射：压力为 0 时如果半径也是 0，笔画中间会出现断点，
/// 看起来像虚线。留 0.42 的底，最细的地方仍然连贯。
double inkRadiusFactor(double pressure) {
  final p = pressure.isFinite ? pressure.clamp(0.0, 1.0) : 1.0;
  return 0.42 + 0.58 * p;
}

/// 生成压感笔迹的填充轮廓。
///
/// 返回的是闭合多边形的一圈点：左半侧正序，右半侧逆序。渲染侧连成 Path，
/// 导出侧连成 SVG 路径，两边用的是同一组数，不会出现「屏幕上有粗细变化、
/// 导出后变成等宽」。
///
/// [points] 与 [pressures] 按索引对应；压力数组可以比点短，缺的部分按 1
/// 处理（老文档、或采样时丢了几帧）。
List<Offset> inkContour(
  List<Offset> points,
  List<double> pressures,
  double width,
) {
  if (points.length < 2) return const <Offset>[];
  final base = math.max(width, 0.5) / 2;
  final n = points.length;
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = points[i == 0 ? 0 : i - 1];
    final next = points[i == n - 1 ? n - 1 : i + 1];
    var tangent = next - prev;
    if (tangent.distance < 1e-6) tangent = const Offset(1, 0);
    final length = tangent.distance;
    final normal = Offset(-tangent.dy / length, tangent.dx / length);
    final radius = base * _pressureAt(pressures, i);
    left.add(points[i] + normal * radius);
    right.add(points[i] - normal * radius);
  }
  return <Offset>[...left, ...right.reversed];
}

Path inkOutlinePath(
  List<Offset> points,
  List<double> pressures,
  double width,
) {
  final path = Path();
  if (points.isEmpty) return path;
  if (points.length == 1) {
    final r = math.max(width, 0.5) / 2 * _pressureAt(pressures, 0);
    path.addOval(Rect.fromCircle(center: points.first, radius: r));
    return path;
  }
  final contour = inkContour(points, pressures, width);
  path.moveTo(contour.first.dx, contour.first.dy);
  for (var i = 1; i < contour.length; i++) {
    path.lineTo(contour[i].dx, contour[i].dy);
  }
  path.close();
  return path;
}

/// 两端的圆头半径，渲染时在首尾各画一个圆把平头补圆。
double inkCapRadius(List<double> pressures, int index, double width) =>
    math.max(width, 0.5) / 2 * _pressureAt(pressures, index);

double _pressureAt(List<double> pressures, int index) =>
    index < pressures.length ? inkRadiusFactor(pressures[index]) : 1.0;

