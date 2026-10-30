import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/state/viewport.dart';

void main() {
  group('坐标变换', () {
    test('屏幕与世界坐标互为逆变换', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      viewport.panByScreen(const Offset(-120, 40));
      viewport.zoomAt(const Offset(200, 150), 1.7);

      for (final point in const <Offset>[
        Offset.zero,
        Offset(13.5, -8),
        Offset(-400, 900),
      ]) {
        final round = viewport.toWorld(viewport.toScreen(point));
        expect((round - point).distance, closeTo(0, 1e-9));
      }
    });

    test('首次拿到尺寸时原点落在画布中心', () {
      final viewport = Viewport();
      viewport.setSize(const Size(800, 600));
      final screenZero = viewport.toScreen(Offset.zero);
      expect(screenZero.dx, closeTo(400, 1e-9));
      expect(screenZero.dy, closeTo(300, 1e-9));
    });
  });

  group('缩放', () {
    test('锚点下的世界坐标在缩放后保持不动', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      const anchor = Offset(123, 456);
      final before = viewport.toWorld(anchor);
      viewport.zoomAt(anchor, 2.4);
      final after = viewport.toWorld(anchor);
      expect((after - before).distance, closeTo(0, 1e-9));
    });

    test('缩放被限制在上下限之内', () {
      final viewport = Viewport()..setSize(const Size(400, 400));
      viewport.zoomAt(const Offset(200, 200), 1000);
      expect(viewport.zoom, Viewport.maxZoom);

      viewport.zoomAt(const Offset(200, 200), 0.0001);
      expect(viewport.zoom, Viewport.minZoom);
    });

    test('反复放大缩小可以回到原比例', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      const anchor = Offset(300, 200);
      final startPan = viewport.pan;
      viewport.zoomAt(anchor, 1.5);
      viewport.zoomAt(anchor, 1 / 1.5);
      expect(viewport.zoom, closeTo(1, 1e-9));
      expect((viewport.pan - startPan).distance, closeTo(0, 1e-6));
    });
  });

  group('可见区域', () {
    test('visibleWorld 与屏幕尺寸成反比', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      expect(viewport.visibleWorld.width, closeTo(800, 1e-9));

      viewport.zoomAt(const Offset(0, 0), 2);
      expect(viewport.visibleWorld.width, closeTo(400, 1e-9));
      expect(viewport.visibleWorld.height, closeTo(300, 1e-9));
    });

    test('rectToScreen 与 toScreen 一致', () {
      final viewport = Viewport()..setSize(const Size(500, 500));
      const rect = Rect.fromLTWH(10, 20, 30, 40);
      final screen = viewport.rectToScreen(rect);
      expect(screen.topLeft, viewport.toScreen(rect.topLeft));
      expect(screen.bottomRight, viewport.toScreen(rect.bottomRight));
      final world = viewport.rectToWorld(screen);
      expect(world.left, closeTo(rect.left, 1e-9));
      expect(world.top, closeTo(rect.top, 1e-9));
      expect(world.right, closeTo(rect.right, 1e-9));
      expect(world.bottom, closeTo(rect.bottom, 1e-9));
    });
  });

  group('fit', () {
    test('内容被完整放进可视区域', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      const content = Rect.fromLTWH(-1000, -500, 2000, 1000);
      viewport.fit(content, padding: 40);

      final visible = viewport.visibleWorld;
      expect(visible.left, lessThanOrEqualTo(content.left));
      expect(visible.top, lessThanOrEqualTo(content.top));
      expect(visible.right, greaterThanOrEqualTo(content.right));
      expect(visible.bottom, greaterThanOrEqualTo(content.bottom));
    });

    test('空内容不会改动视口', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      final zoom = viewport.zoom;
      viewport.fit(Rect.zero);
      expect(viewport.zoom, zoom);
    });
  });

  group('通知', () {
    test('值没变时不发通知', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      var notifications = 0;
      viewport.addListener(() => notifications++);

      viewport.setSize(const Size(800, 600));
      viewport.panByScreen(Offset.zero);
      expect(notifications, 0);

      viewport.panByScreen(const Offset(10, 0));
      expect(notifications, 1);
    });

    test('restore 会夹住越界的缩放', () {
      final viewport = Viewport()..setSize(const Size(800, 600));
      viewport.restore(const Offset(5, 5), 1000);
      expect(viewport.zoom, Viewport.maxZoom);
      expect(viewport.pan, const Offset(5, 5));
    });
  });
}
