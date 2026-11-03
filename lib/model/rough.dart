import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

/// 强度 1.0 对应的抖动幅度（世界单位）。
///
/// 定在 2.6 是试出来的：1.0 左右时在 3px 线宽下几乎看不出手绘感，看起
/// 像渲染有毛刺；再大（4 以上）边角开始互相穿过去，像画错了。
const double kRoughAmplitude = 2.6;

/// 手绘描边：把一条规整的几何路径变成「手画的」。
///
/// 做法不是给曲线加噪声点（那样只会变成毛刺），而是**沿弧长重采样**，再把
/// 每个采样点沿法线方向推一个由种子决定的小偏移，最后用中点法重新连成平滑
/// 曲线。推法线而不是推坐标，是为了让所有边都往外抖同样的量——推坐标的话，
/// 竖直边会横向抖、水平边会纵向抖，看起来像被拉扯过。
///
/// 每个形状画两遍（两个不同种子、幅度略有差别），模仿笔画来回描了一下的
/// 效果。rough.js 也是这么干的。
///
/// 采样点本身就是最终轮廓，所以屏幕渲染和 SVG 导出可以共用同一组点，
/// 不会出现「屏幕上抖、导出后不抖」。
List<Offset> roughOutline(
  Path source, {
  required int seed,
  required double amplitude,
  double step = 7,
}) {
  if (amplitude <= 0) return const <Offset>[];
  final points = <Offset>[];
  var index = 0;
  for (final metric in source.computeMetrics()) {
    final length = metric.length;
    if (length <= 0.01) continue;
    final count = math.max(3, (length / step).ceil());
    for (var i = 0; i < count; i++) {
      final tangent = metric.getTangentForOffset(length * i / count);
      if (tangent == null) continue;
      // 法线 = 切线逆时针转 90°
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final offset = _noise(seed, index++) * amplitude;
      points.add(tangent.position + normal * offset);
    }
  }
  return points;
}

/// 把点序列连成平滑的闭合路径。
///
/// 和笔迹用的是同一套中点法：只用相邻两点求中点作为控制点，急转弯处不会
/// 像 Catmull-Rom 那样过冲出去。
Path smoothClosedPath(List<Offset> points) {
  final path = Path();
  if (points.length < 3) return path;
  final n = points.length;
  final start = Offset(
    (points[0].dx + points[1].dx) / 2,
    (points[0].dy + points[1].dy) / 2,
  );
  path.moveTo(start.dx, start.dy);
  for (var i = 1; i <= n; i++) {
    final p = points[i % n];
    final next = points[(i + 1) % n];
    path.quadraticBezierTo(
      p.dx,
      p.dy,
      (p.dx + next.dx) / 2,
      (p.dy + next.dy) / 2,
    );
  }
  path.close();
  return path;
}

/// 确定性噪声，返回 [-1, 1]。
///
/// 不能用 `Random()`：每次重绘都换一组数，形状会持续抖动，看着像在呼吸。
/// 这里的哈希保证同一个种子永远得到同一串值。
double _noise(int seed, int index) {
  var h = (seed * 374761393 + index * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  h = h ^ (h >> 16);
  return ((h & 0xffff) / 0xffff) * 2 - 1;
}

/// 手绘路径的缓存。
///
/// 每个形状每帧都重采样一遍路径，元素一多就是纯浪费——形状没变，结果就不会
/// 变。键里带上框、强度、种子，任何一项变了自然重建。
class RoughPathCache {
  RoughPathCache._();

  static const int _limit = 500;
  static final LinkedHashMap<String, Path> _cache = LinkedHashMap<String, Path>();

  static Path resolve(String key, Path Function() build) {
    // 命中的条目挪到末尾，队头就是最久没用的。不能用「满了就 clear」：
    // 清空之后同一帧要重建所有形状，几百个元素的画布会卡一下。
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final path = build();
    _cache[key] = path;
    while (_cache.length > _limit) {
      _cache.remove(_cache.keys.first);
    }
    return path;
  }

  static void clear() => _cache.clear();
}
