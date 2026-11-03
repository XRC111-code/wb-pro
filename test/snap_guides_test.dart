import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/snap_guides.dart';

void main() {
  group('元素间吸附', () {
    test('左边缘靠近时吸过去', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(103, 200, 80, 60),
        targets: const <Rect>[Rect.fromLTWH(100, 40, 120, 50)],
        threshold: 6,
      );
      expect(result.delta.dx, closeTo(-3, 0.001));
      expect(result.delta.dy, 0);
      expect(result.guides, hasLength(1));
      expect(result.guides.single.vertical, isTrue);
      expect(result.guides.single.position, closeTo(100, 0.001));
    });

    test('中心对中心', () {
      // 目标中心 x = 150，移动框中心 x = 147
      final result = computeSnap(
        moving: const Rect.fromLTWH(107, 200, 80, 60),
        targets: const <Rect>[Rect.fromLTWH(100, 40, 100, 50)],
        threshold: 6,
      );
      expect(result.delta.dx, closeTo(3, 0.001));
    });

    test('右边贴左边也算对齐', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(18, 200, 80, 60), // right = 98
        targets: const <Rect>[Rect.fromLTWH(100, 40, 100, 50)],
        threshold: 6,
      );
      expect(result.delta.dx, closeTo(2, 0.001));
      expect(result.guides.single.position, closeTo(100, 0.001));
    });

    test('超出阈值不吸附', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(120, 200, 40, 40),
        targets: const <Rect>[Rect.fromLTWH(100, 40, 100, 50)],
        threshold: 6,
      );
      expect(result.delta, Offset.zero);
      expect(result.guides, isEmpty);
    });

    test('取最近的那条线', () {
      // 左边距 100 有 9 个单位，右边距 210（目标右边缘）有 2 个单位
      final result = computeSnap(
        moving: const Rect.fromLTWH(109, 0, 99, 20), // right = 208
        targets: const <Rect>[Rect.fromLTWH(100, 0, 110, 20)], // right = 210
        threshold: 6,
      );
      expect(result.delta.dx, closeTo(2, 0.001));
      final vertical = result.guides.firstWhere((g) => g.vertical);
      expect(vertical.position, closeTo(210, 0.001));
    });

    test('横竖同时吸附，两条参考线', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(102, 43, 50, 50),
        targets: const <Rect>[Rect.fromLTWH(100, 40, 100, 60)],
        threshold: 6,
      );
      expect(result.delta.dx, closeTo(-2, 0.001));
      expect(result.delta.dy, closeTo(2, 0.001));
      expect(result.guides, hasLength(2));
      expect(result.guides.where((g) => g.vertical), hasLength(1));
      expect(result.guides.where((g) => !g.vertical), hasLength(1));
    });

    test('参考线只跨过参与对齐的元素', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(101, 300, 50, 40), // 300..340
        targets: const <Rect>[Rect.fromLTWH(100, 100, 50, 40)], // 100..140
        threshold: 6,
      );
      final guide = result.guides.single;
      // 覆盖两个元素，外扩 6
      expect(guide.from, closeTo(94, 0.001));
      expect(guide.to, closeTo(346, 0.001));
    });

    test('同一条线上有多个元素时合并成一条', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(101, 400, 50, 40),
        targets: const <Rect>[
          Rect.fromLTWH(100, 100, 50, 40),
          Rect.fromLTWH(100, 200, 50, 40),
        ],
        threshold: 6,
      );
      expect(result.guides, hasLength(1));
      expect(result.guides.single.from, closeTo(94, 0.001));
      expect(result.guides.single.to, closeTo(446, 0.001));
    });

    test('只吸附被拖动的边', () {
      // 左边缘差 1 个单位、右边缘差 1 个单位；限定只吸右边，结果必须按右边算
      final result = computeSnap(
        moving: const Rect.fromLTWH(101, 0, 99, 20), // right = 200
        targets: const <Rect>[Rect.fromLTWH(100, 0, 101, 20)], // right = 201
        threshold: 6,
        edges: const <SnapEdge>{SnapEdge.right},
      );
      expect(result.delta.dx, closeTo(1, 0.001));
      expect(result.guides.single.vertical, isTrue);
      expect(result.guides.single.position, closeTo(201, 0.001));
    });

    test('没有其他元素时不吸附', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(101, 400, 50, 40),
        targets: const <Rect>[],
        threshold: 6,
      );
      expect(result.delta, Offset.zero);
      expect(result.guides, isEmpty);
    });

    test('阈值为 0 时直接返回', () {
      final result = computeSnap(
        moving: const Rect.fromLTWH(100, 100, 50, 40),
        targets: const <Rect>[Rect.fromLTWH(100, 100, 50, 40)],
        threshold: 0,
      );
      expect(result.guides, isEmpty);
    });
  });
}
