import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/geometry.dart';

void main() {
  group('distanceToSegment', () {
    test('垂直投影落在段内', () {
      expect(
        distanceToSegment(const Offset(5, 3), Offset.zero, const Offset(10, 0)),
        closeTo(3, 1e-9),
      );
    });

    test('投影落在段外时退化成到端点距离', () {
      expect(
        distanceToSegment(const Offset(13, 4), Offset.zero, const Offset(10, 0)),
        closeTo(5, 1e-9),
      );
    });

    test('退化线段不会算出 NaN', () {
      final distance = distanceToSegment(
        const Offset(3, 4),
        const Offset(1, 1),
        const Offset(1, 1),
      );
      expect(distance.isNaN, isFalse);
      // (3,4) 到 (1,1) 的直线距离。
      expect(distance, closeTo(math.sqrt(13), 1e-9));
    });

    test('点在线段上时距离为 0', () {
      expect(
        distanceToSegment(const Offset(5, 0), Offset.zero, const Offset(10, 0)),
        closeTo(0, 1e-9),
      );
    });
  });

  group('rotatePoint', () {
    test('绕原点旋转 90 度', () {
      final result = rotatePoint(const Offset(1, 0), Offset.zero, math.pi / 2);
      expect(result.dx, closeTo(0, 1e-9));
      expect(result.dy, closeTo(1, 1e-9));
    });

    test('旋转 0 度返回原对象', () {
      const point = Offset(3, 4);
      expect(identical(rotatePoint(point, const Offset(1, 1), 0), point), isTrue);
    });

    test('绕非原点旋转后到圆心的距离不变', () {
      const center = Offset(10, -4);
      const point = Offset(17, 9);
      final rotated = rotatePoint(point, center, 0.73);
      expect((rotated - center).distance, closeTo((point - center).distance, 1e-9));
    });
  });

  group('cornersOf / rotatedBounds', () {
    test('未旋转时四个角就是矩形的角', () {
      const rect = Rect.fromLTWH(10, 20, 30, 40);
      expect(cornersOf(rect, 0), <Offset>[
        const Offset(10, 20),
        const Offset(40, 20),
        const Offset(40, 60),
        const Offset(10, 60),
      ]);
    });

    test('正方形旋转 90 度后包围盒不变', () {
      const rect = Rect.fromLTWH(0, 0, 10, 10);
      final bounds = rotatedBounds(rect, math.pi / 2);
      expect(bounds.width, closeTo(10, 1e-9));
      expect(bounds.height, closeTo(10, 1e-9));
      expect(bounds.center.dx, closeTo(rect.center.dx, 1e-9));
      expect(bounds.center.dy, closeTo(rect.center.dy, 1e-9));
    });

    test('长条旋转 90 度后宽高互换', () {
      const rect = Rect.fromLTWH(0, 0, 40, 10);
      final bounds = rotatedBounds(rect, math.pi / 2);
      expect(bounds.width, closeTo(10, 1e-9));
      expect(bounds.height, closeTo(40, 1e-9));
    });
  });

  group('normalizedRect / ensureMinSize', () {
    test('反向拖拽也能得到正矩形', () {
      final rect = normalizedRect(const Offset(30, 40), const Offset(10, 5));
      expect(rect, const Rect.fromLTRB(10, 5, 30, 40));
    });

    test('零尺寸被撑到最小尺寸', () {
      final rect = ensureMinSize(const Rect.fromLTWH(5, 5, 0, 0), minSize: 2);
      expect(rect.width, 2);
      expect(rect.height, 2);
      expect(rect.left, 5);
    });

    test('已足够大的矩形不受影响', () {
      const source = Rect.fromLTWH(0, 0, 30, 4);
      expect(ensureMinSize(source, minSize: 2), source);
    });
  });

  group('clampRect', () {
    test('把内框推回外框内部', () {
      const inner = Rect.fromLTWH(-20, -20, 10, 10);
      const outer = Rect.fromLTWH(0, 0, 100, 100);
      final clamped = clampRect(inner, outer);
      expect(clamped.left, 0);
      expect(clamped.top, 0);
      expect(clamped.width, 10);
    });
  });
}
