import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 画布视口：世界坐标 ↔ 屏幕坐标。
///
/// 用「左上角对应的世界坐标 + 缩放」表示，而不是矩阵。白板的变换只有平移
/// 和等比缩放，矩阵会引入旋转/斜切这些永远用不到的自由度，反而让
/// `toWorld(toScreen(p)) == p` 这种最基本的断言难以验证。
class Viewport extends ChangeNotifier {
  static const double minZoom = 0.05;
  static const double maxZoom = 8;

  Offset _pan = Offset.zero;
  double _zoom = 1;
  Size _size = Size.zero;

  Offset get pan => _pan;
  double get zoom => _zoom;
  Size get size => _size;

  /// 屏幕左上角对应的世界坐标。
  Offset get origin => _pan;

  Rect get visibleWorld =>
      Rect.fromLTWH(_pan.dx, _pan.dy, _size.width / _zoom, _size.height / _zoom);

  Offset toScreen(Offset world) => (world - _pan) * _zoom;

  Offset toWorld(Offset screen) => screen / _zoom + _pan;

  Rect rectToScreen(Rect world) => Rect.fromLTRB(
        toScreen(world.topLeft).dx,
        toScreen(world.topLeft).dy,
        toScreen(world.bottomRight).dx,
        toScreen(world.bottomRight).dy,
      );

  Rect rectToWorld(Rect screen) => Rect.fromLTRB(
        toWorld(screen.topLeft).dx,
        toWorld(screen.topLeft).dy,
        toWorld(screen.bottomRight).dx,
        toWorld(screen.bottomRight).dy,
      );

  void setSize(Size value) {
    if (value == _size) return;
    final first = _size == Size.zero;
    _size = value;
    // 首次拿到尺寸时把原点放到画布中央附近，新建的白板不会从左上角开始，
    // 用户往任何方向画都有空间。
    if (first) {
      _pan = Offset(-value.width / 2 / _zoom, -value.height / 2 / _zoom);
    }
    notifyListeners();
  }

  void panByScreen(Offset delta) {
    if (delta == Offset.zero) return;
    _pan -= delta / _zoom;
    notifyListeners();
  }

  /// 以屏幕上的 [focus] 为锚点缩放：锚点下的世界坐标保持不动。
  ///
  /// 不做这个锚定的话，滚轮缩放会让内容整体往左上角漂，用户每缩放一次就要
  /// 重新找刚才在看的地方。
  void zoomAt(Offset focus, double factor) {
    final next = (_zoom * factor).clamp(minZoom, maxZoom).toDouble();
    if (next == _zoom) return;
    final worldBefore = toWorld(focus);
    _zoom = next;
    _pan = worldBefore - focus / _zoom;
    notifyListeners();
  }

  void setZoom(double value, {Offset? focus}) {
    final anchor = focus ?? Offset(_size.width / 2, _size.height / 2);
    final target = value.clamp(minZoom, maxZoom).toDouble();
    if (target == _zoom) return;
    zoomAt(anchor, target / _zoom);
  }

  void resetZoom({Offset? focus}) => setZoom(1, focus: focus);

  /// 让 [content] 完整落在可视区域内。
  void fit(Rect content, {double padding = 64}) {
    if (_size.isEmpty || content.isEmpty) return;
    final scale = math.min(
      (_size.width - padding * 2) / content.width,
      (_size.height - padding * 2) / content.height,
    );
    _zoom = scale.clamp(minZoom, maxZoom).toDouble();
    _pan = content.center - Offset(_size.width / 2 / _zoom, _size.height / 2 / _zoom);
    notifyListeners();
  }

  void centerOn(Offset world) {
    _pan = world - Offset(_size.width / 2 / _zoom, _size.height / 2 / _zoom);
    notifyListeners();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'panX': _pan.dx,
        'panY': _pan.dy,
        'zoom': _zoom,
      };

  void restore(Offset pan, double zoom) {
    _pan = pan;
    _zoom = zoom.clamp(minZoom, maxZoom).toDouble();
    notifyListeners();
  }
}
