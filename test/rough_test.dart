import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/element.dart';
import 'package:wb_pro/model/rough.dart';

ShapeElement _rect({double roughness = 1, int seed = 42}) => ShapeElement(
      id: 's1',
      frame: const Rect.fromLTWH(0, 0, 200, 120),
      shape: ShapeKind.rectangle,
      stroke: const Color(0xFF1F2933),
      strokeWidth: 2,
      roughness: roughness,
      seed: seed,
    );

void main() {
  group('手绘轮廓', () {
    test('沿周长采样出足够多的点', () {
      final path = Path()..addRect(const Rect.fromLTWH(0, 0, 200, 100));
      final points = roughOutline(path, seed: 1, amplitude: 1.5);
      // 周长 600，步长 7 → 至少 85 个点
      expect(points.length, greaterThan(80));
    });

    test('抖动幅度不超过设定值', () {
      const amplitude = 2.0;
      final path = Path()..addRect(const Rect.fromLTWH(0, 0, 200, 100));
      for (final p in roughOutline(path, seed: 7, amplitude: amplitude)) {
        // 点落在原矩形边界外侧 2 个单位以内
        final onEdge = p.dx < amplitude + 1e-6 ||
            p.dx > 200 - amplitude - 1e-6 ||
            p.dy < amplitude + 1e-6 ||
            p.dy > 100 - amplitude - 1e-6;
        expect(onEdge, isTrue, reason: '点 $p 偏离矩形边界太远');
      }
    });

    test('同一个种子得到同一组点', () {
      final path = Path()..addOval(const Rect.fromLTWH(0, 0, 160, 90));
      final a = roughOutline(path, seed: 99, amplitude: 1.2);
      final b = roughOutline(path, seed: 99, amplitude: 1.2);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].dx, closeTo(b[i].dx, 1e-9));
        expect(a[i].dy, closeTo(b[i].dy, 1e-9));
      }
    });

    test('不同种子的形状不一样', () {
      final path = Path()..addRect(const Rect.fromLTWH(0, 0, 200, 100));
      final a = roughOutline(path, seed: 1, amplitude: 1.2);
      final b = roughOutline(path, seed: 2, amplitude: 1.2);
      var maxDiff = 0.0;
      for (var i = 0; i < math.min(a.length, b.length); i++) {
        maxDiff = math.max(maxDiff, (a[i] - b[i]).distance);
      }
      expect(maxDiff, greaterThan(0.2));
    });

    test('幅度为 0 时返回空', () {
      final path = Path()..addRect(const Rect.fromLTWH(0, 0, 200, 100));
      expect(roughOutline(path, seed: 1, amplitude: 0), isEmpty);
    });

    test('点的顺序沿路径连续，不会跳回起点', () {
      final path = Path()..addRect(const Rect.fromLTWH(0, 0, 200, 100));
      final points = roughOutline(path, seed: 3, amplitude: 1);
      // 相邻点的间距应该接近步长（抖动会让它略大，但不该出现跨半张画布的跳跃）
      for (var i = 1; i < points.length; i++) {
        expect((points[i] - points[i - 1]).distance, lessThan(20));
      }
    });
  });

  group('平滑闭合路径', () {
    test('少于三个点返回空路径', () {
      expect(smoothClosedPath(const <Offset>[]).computeMetrics().isEmpty, isTrue);
      expect(
        smoothClosedPath(const <Offset>[Offset.zero, Offset(10, 0)])
            .computeMetrics()
            .isEmpty,
        isTrue,
      );
    });

    test('四个点围成一个闭合区域', () {
      final path = smoothClosedPath(const <Offset>[
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 60),
        Offset(0, 60),
      ]);
      expect(path.getBounds().isEmpty, isFalse);
      expect(path.contains(const Offset(50, 30)), isTrue);
      expect(path.contains(const Offset(-10, 30)), isFalse);
    });
  });

  group('手绘形状的序列化', () {
    test('roughness 与 seed 往返保留', () {
      final original = _rect(roughness: 1.4, seed: 123456);
      final restored = ShapeElement.fromJson(
        original.toJson(),
        original.id,
        original.frame,
        original.rotation,
        original.opacity,
      );
      expect(restored.roughness, closeTo(1.4, 1e-9));
      expect(restored.seed, 123456);
    });

    test('没有手绘字段的旧文档按几何处理', () {
      final json = <String, Object?>{
        'type': 'shape',
        'id': 'old',
        'x': 0,
        'y': 0,
        'w': 100,
        'h': 60,
        'shape': 'rectangle',
      };
      final restored = ShapeElement.fromJson(
        json,
        'old',
        const Rect.fromLTWH(0, 0, 100, 60),
        0,
        1,
      );
      expect(restored.roughness, 0);
      expect(restored.seed, 0);
    });

    test('roughness 被限制在合理范围', () {
      final json = <String, Object?>{
        'type': 'shape',
        'id': 'x',
        'x': 0,
        'y': 0,
        'w': 100,
        'h': 60,
        'shape': 'ellipse',
        'roughness': 99,
      };
      final restored = ShapeElement.fromJson(
        json,
        'x',
        const Rect.fromLTWH(0, 0, 100, 60),
        0,
        1,
      );
      expect(restored.roughness, lessThanOrEqualTo(3));
    });
  });
}
