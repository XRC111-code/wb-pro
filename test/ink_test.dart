import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/element.dart';
import 'package:wb_pro/model/ink.dart';

void main() {
  const points = <Offset>[
    Offset(0, 0),
    Offset(20, 10),
    Offset(40, 0),
    Offset(60, 10),
  ];

  group('压感轮廓', () {
    test('一圈轮廓的点数是采样点的两倍', () {
      final contour = inkContour(points, const <double>[1, 1, 1, 1], 8);
      expect(contour.length, points.length * 2);
    });

    test('压力越大轮廓越宽', () {
      const thin = <double>[0.1, 0.1, 0.1, 0.1];
      const thick = <double>[1, 1, 1, 1];
      double spread(List<Offset> contour) {
        final n = contour.length ~/ 2;
        var max = 0.0;
        // 左半侧正序、右半侧逆序：left[i] 对应 contour[2n-1-i]
        for (var i = 0; i < n; i++) {
          final d = (contour[i] - contour[2 * n - 1 - i]).distance;
          if (d > max) max = d;
        }
        return max;
      }

      expect(spread(inkContour(points, thick, 10)), greaterThan(spread(inkContour(points, thin, 10))));
      // 最粗处正好是线宽
      expect(spread(inkContour(points, thick, 10)), closeTo(10, 0.001));
    });

    test('压力数组比点短时按满压力补齐', () {
      final contour = inkContour(points, const <double>[1], 8);
      expect(contour.length, points.length * 2);
    });

    test('少于两个点不产生轮廓', () {
      expect(inkContour(const <Offset>[], const <double>[], 8), isEmpty);
      expect(inkContour(const <Offset>[Offset.zero], const <double>[1], 8), isEmpty);
    });

    test('单点笔迹是一个圆', () {
      final path = inkOutlinePath(
        const <Offset>[Offset(10, 10)],
        const <double>[1],
        12,
      );
      final bounds = path.getBounds();
      expect(bounds.center.dx, closeTo(10, 0.001));
      expect(bounds.width, closeTo(12, 0.001));
    });

    test('闭合路径覆盖中线附近', () {
      final path = inkOutlinePath(points, const <double>[1, 1, 1, 1], 10);
      expect(path.contains(const Offset(10, 5)), isTrue);
      expect(path.contains(const Offset(30, 5)), isTrue);
      expect(path.contains(const Offset(30, 40)), isFalse);
    });
  });

  group('压感序列化', () {
    StrokeElement stroke({List<double> pressures = const <double>[]}) => StrokeElement(
          id: 's1',
          frame: const Rect.fromLTWH(0, 0, 60, 10),
          points: points,
          color: const Color(0xFF1F2933),
          strokeWidth: 8,
          pressures: pressures,
        );

    test('压力往返保留', () {
      final original = stroke(pressures: const <double>[1, 0.6, 0.8, 0.2]);
      final restored = StrokeElement.fromJson(
        original.toJson(),
        original.id,
        original.frame,
        original.rotation,
        original.opacity,
      );
      expect(restored.pressures, hasLength(4));
      expect(restored.pressures[1], closeTo(0.6, 0.001));
      expect(restored.hasPressure, isTrue);
    });

    test('没有压力字段的旧笔迹按等宽处理', () {
      final json = <String, Object?>{
        'type': 'stroke',
        'id': 'old',
        'x': 0,
        'y': 0,
        'w': 60,
        'h': 10,
        'points': <double>[0, 0, 20, 5, 40, 0, 60, 5],
        'width': 6,
      };
      final restored = StrokeElement.fromJson(
        json,
        'old',
        const Rect.fromLTWH(0, 0, 60, 10),
        0,
        1,
      );
      expect(restored.pressures, isEmpty);
      expect(restored.hasPressure, isFalse);
    });

    test('压力数量与点不符时整组丢弃', () {
      final json = <String, Object?>{
        'type': 'stroke',
        'id': 'bad',
        'x': 0,
        'y': 0,
        'w': 60,
        'h': 10,
        'points': <double>[0, 0, 20, 5, 40, 0, 60, 5],
        'width': 6,
        'pressures': <double>[1, 0.5],
      };
      final restored = StrokeElement.fromJson(
        json,
        'bad',
        const Rect.fromLTWH(0, 0, 60, 10),
        0,
        1,
      );
      expect(restored.pressures, isEmpty);
    });

    test('压力值被夹到 0..1', () {
      final json = <String, Object?>{
        'type': 'stroke',
        'id': 'x',
        'x': 0,
        'y': 0,
        'w': 60,
        'h': 10,
        'points': <double>[0, 0, 20, 5, 40, 0, 60, 5],
        'pressures': <double>[9, -3, 0.5, 0.5],
      };
      final restored = StrokeElement.fromJson(
        json,
        'x',
        const Rect.fromLTWH(0, 0, 60, 10),
        0,
        1,
      );
      expect(restored.pressures.first, 1);
      expect(restored.pressures[1], 0);
    });
  });
}
