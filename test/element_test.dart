import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/element.dart';

const Color _black = Color(0xFF1F2933);

void main() {
  group('StrokeElement', () {
    test('JSON 往返保留点、颜色与线宽', () {
      final stroke = StrokeElement(
        id: 's1',
        frame: const Rect.fromLTWH(10, 20, 100, 50),
        points: const <Offset>[Offset(0, 0), Offset(30, 40), Offset(100, 50)],
        color: const Color(0xFFE03131),
        strokeWidth: 4.5,
      );
      final restored = WbElement.fromJson(stroke.toJson()) as StrokeElement;

      expect(restored.id, 's1');
      expect(restored.frame, const Rect.fromLTWH(10, 20, 100, 50));
      expect(restored.points.length, 3);
      expect(restored.points[1], const Offset(30, 40));
      expect(restored.color.toARGB32(), 0xFFE03131);
      expect(restored.strokeWidth, 4.5);
    });

    test('点被扁平化存储以减小体积', () {
      final stroke = StrokeElement(
        id: 's1',
        frame: const Rect.fromLTWH(0, 0, 10, 10),
        points: const <Offset>[Offset(1, 2), Offset(3, 4)],
        color: _black,
        strokeWidth: 2,
      );
      expect(stroke.toJson()['points'], <double>[1, 2, 3, 4]);
    });

    test('命中测试只认线附近', () {
      final stroke = StrokeElement(
        id: 's1',
        frame: const Rect.fromLTWH(0, 0, 100, 10),
        points: const <Offset>[Offset(0, 0), Offset(100, 0)],
        color: _black,
        strokeWidth: 2,
      );
      expect(stroke.hitTest(const Offset(50, 1), tolerance: 2), isTrue);
      expect(stroke.hitTest(const Offset(50, 8), tolerance: 2), isFalse);
    });

    test('缩放时内部点同步缩放', () {
      final stroke = StrokeElement(
        id: 's1',
        frame: const Rect.fromLTWH(0, 0, 100, 100),
        points: const <Offset>[Offset(50, 50)],
        color: _black,
        strokeWidth: 2,
      );
      final scaled = stroke.resized(const Rect.fromLTWH(0, 0, 200, 50));
      expect(scaled.points.single, const Offset(100, 25));
    });

    test('单点笔迹退化为圆点也能命中', () {
      final dot = StrokeElement(
        id: 'dot',
        frame: const Rect.fromLTWH(0, 0, 4, 4),
        points: const <Offset>[Offset(2, 2)],
        color: _black,
        strokeWidth: 4,
      );
      expect(dot.hitTest(const Offset(2, 2)), isTrue);
      expect(dot.hitTest(const Offset(20, 20)), isFalse);
    });
  });

  group('ShapeElement', () {
    ShapeElement rect({Color? fill}) => ShapeElement(
          id: 'r1',
          frame: const Rect.fromLTWH(0, 0, 100, 50),
          shape: ShapeKind.rectangle,
          stroke: _black,
          strokeWidth: 2,
          fill: fill,
        );

    test('有填充时内部点击命中', () {
      expect(rect(fill: const Color(0xFFFFFFFF)).hitTest(const Offset(50, 25)), isTrue);
    });

    test('无填充时内部点击不命中，边框附近命中', () {
      final shape = rect();
      expect(shape.hitTest(const Offset(50, 25)), isFalse);
      expect(shape.hitTest(const Offset(50, 1), tolerance: 2), isTrue);
      expect(shape.hitTest(const Offset(200, 200)), isFalse);
    });

    test('椭圆按椭圆轮廓判定，四角不命中', () {
      final ellipse = ShapeElement(
        id: 'e1',
        frame: const Rect.fromLTWH(0, 0, 100, 100),
        shape: ShapeKind.ellipse,
        stroke: _black,
        strokeWidth: 2,
        fill: const Color(0xFFFFFFFF),
      );
      expect(ellipse.hitTest(const Offset(50, 50)), isTrue);
      // 左上角在包围盒内、椭圆外。
      expect(ellipse.hitTest(const Offset(4, 4), tolerance: 1), isFalse);
    });

    test('菱形四角不命中、中心命中', () {
      final diamond = ShapeElement(
        id: 'd1',
        frame: const Rect.fromLTWH(0, 0, 100, 100),
        shape: ShapeKind.diamond,
        stroke: _black,
        strokeWidth: 2,
        fill: const Color(0xFFFFFFFF),
      );
      expect(diamond.hitTest(const Offset(50, 50)), isTrue);
      expect(diamond.hitTest(const Offset(6, 6), tolerance: 1), isFalse);
    });

    test('旋转 90 度后命中位置跟着转', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: const Rect.fromLTWH(0, 0, 100, 50),
        shape: ShapeKind.rectangle,
        stroke: _black,
        strokeWidth: 2,
        fill: const Color(0xFFFFFFFF),
        rotation: math.pi / 2,
      );
      // frame 中心 (50,25)，旋转后原来 (95,25) 落在 (50,70)。
      expect(shape.hitTest(const Offset(50, 70)), isTrue);
      expect(shape.hitTest(const Offset(95, 25)), isFalse);
    });

    test('worldBounds 覆盖旋转后的范围', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: const Rect.fromLTWH(0, 0, 100, 50),
        shape: ShapeKind.rectangle,
        stroke: _black,
        strokeWidth: 2,
        rotation: math.pi / 2,
      );
      final bounds = shape.worldBounds;
      expect(bounds.width, closeTo(50, 1e-6));
      expect(bounds.height, closeTo(100, 1e-6));
    });

    test('圆角不会超过短边的一半', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: const Rect.fromLTWH(0, 0, 20, 10),
        shape: ShapeKind.rectangle,
        stroke: _black,
        strokeWidth: 2,
        cornerRadius: 40,
      );
      // 不应抛异常，路径仍然可用。
      expect(shape.localPath().getBounds().width, closeTo(20, 1e-6));
    });

    test('JSON 往返保留填充与线型', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: const Rect.fromLTWH(3, 4, 30, 40),
        shape: ShapeKind.diamond,
        stroke: const Color(0xFF2F6BFF),
        fill: const Color(0xFFFFE08A),
        strokeWidth: 3.5,
        strokeStyle: StrokeStyle.dashed,
        cornerRadius: 6,
      );
      final restored = WbElement.fromJson(shape.toJson()) as ShapeElement;
      expect(restored.shape, ShapeKind.diamond);
      expect(restored.fill!.toARGB32(), 0xFFFFE08A);
      expect(restored.strokeStyle, StrokeStyle.dashed);
      expect(restored.strokeWidth, 3.5);
    });

    test('clearFill 能真的清掉填充', () {
      final shape = rect(fill: const Color(0xFFFFFFFF));
      expect(shape.copyWith(clearFill: true).fill, isNull);
    });
  });

  group('ArrowElement', () {
    test('命中判定在连线附近', () {
      final arrow = ArrowElement(
        id: 'a1',
        frame: const Rect.fromLTWH(0, 0, 100, 100),
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        stroke: _black,
        strokeWidth: 2,
      );
      expect(arrow.hitTest(const Offset(50, 50), tolerance: 2), isTrue);
      expect(arrow.hitTest(const Offset(50, 90), tolerance: 2), isFalse);
    });

    test('缩放时端点同步', () {
      final arrow = ArrowElement(
        id: 'a1',
        frame: const Rect.fromLTWH(0, 0, 100, 100),
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        stroke: _black,
        strokeWidth: 2,
      );
      final scaled = arrow.resized(const Rect.fromLTWH(0, 0, 200, 50));
      expect(scaled.start, Offset.zero);
      expect(scaled.end, const Offset(200, 50));
    });

    test('缺失字段时默认末端带箭头', () {
      final restored = WbElement.fromJson(<String, Object?>{
        'type': 'arrow',
        'x': 0,
        'y': 0,
        'w': 10,
        'h': 10,
      }) as ArrowElement;
      expect(restored.endHead, isTrue);
      expect(restored.startHead, isFalse);
    });
  });

  group('TextElement', () {
    test('缩放改字号而不是拉伸', () {
      final text = TextElement(
        id: 't1',
        frame: const Rect.fromLTWH(0, 0, 100, 30),
        text: '你好',
        color: _black,
        fontSize: 20,
      );
      final scaled = text.resized(const Rect.fromLTWH(0, 0, 200, 60));
      expect(scaled.fontSize, 40);
      expect(scaled.text, '你好');
    });

    test('字号有上下限', () {
      final text = TextElement(
        id: 't1',
        frame: const Rect.fromLTWH(0, 0, 100, 30),
        text: 'x',
        color: _black,
        fontSize: 20,
      );
      expect(text.resized(const Rect.fromLTWH(0, 0, 1, 30)).fontSize, greaterThan(4));
    });

    test('JSON 往返保留对齐方式', () {
      final text = TextElement(
        id: 't1',
        frame: const Rect.fromLTWH(0, 0, 100, 30),
        text: '多行\n文本',
        color: _black,
        fontSize: 18,
        bold: true,
        italic: true,
        align: TextAlign.center,
      );
      final restored = WbElement.fromJson(text.toJson()) as TextElement;
      expect(restored.text, '多行\n文本');
      expect(restored.align, TextAlign.center);
      expect(restored.bold, isTrue);
      expect(restored.italic, isTrue);
    });
  });

  group('NoteElement', () {
    test('JSON 往返保留便签底色', () {
      final note = NoteElement(
        id: 'n1',
        frame: const Rect.fromLTWH(0, 0, 200, 200),
        text: '待办',
        fill: const Color(0xFFFFC9C9),
      );
      final restored = WbElement.fromJson(note.toJson()) as NoteElement;
      expect(restored.text, '待办');
      expect(restored.fill.toARGB32(), 0xFFFFC9C9);
    });
  });

  group('ImageElement', () {
    test('图片以 base64 内嵌并完整还原', () {
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);
      final image = ImageElement(
        id: 'i1',
        frame: const Rect.fromLTWH(0, 0, 40, 30),
        bytes: bytes,
        mimeType: 'image/png',
        label: 'shot.png',
      );
      final json = image.toJson();
      expect(json['data'], isA<String>());

      final restored = WbElement.fromJson(json) as ImageElement;
      expect(restored.bytes, bytes);
      expect(restored.mimeType, 'image/png');
      expect(restored.label, 'shot.png');
    });

    test('坏掉的 base64 退化成空字节而不是抛异常', () {
      final restored = WbElement.fromJson(<String, Object?>{
        'type': 'image',
        'x': 0,
        'y': 0,
        'w': 10,
        'h': 10,
        'data': '!!!not-base64!!!',
      }) as ImageElement;
      expect(restored.bytes, isEmpty);
    });
  });

  group('容错与通用行为', () {
    test('未知类型抛 FormatException', () {
      expect(
        () => WbElement.fromJson(<String, Object?>{'type': 'hologram'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺字段时用默认值', () {
      final restored = WbElement.fromJson(<String, Object?>{'type': 'shape'});
      expect(restored.frame, Rect.zero);
      expect(restored.opacity, 1);
      expect(restored.rotation, 0);
    });

    test('负数宽高被夹到 0', () {
      final restored = WbElement.fromJson(<String, Object?>{
        'type': 'shape',
        'w': -50,
        'h': -10,
      });
      expect(restored.frame.width, 0);
      expect(restored.frame.height, 0);
    });

    test('translated 只改位置', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: const Rect.fromLTWH(10, 10, 20, 20),
        shape: ShapeKind.rectangle,
        stroke: _black,
        strokeWidth: 1,
      );
      final moved = shape.translated(const Offset(5, -5));
      expect(moved.frame, const Rect.fromLTWH(15, 5, 20, 20));
      expect(moved.id, shape.id);
    });

    test('withOpacity 夹在 0..1', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: Rect.zero,
        shape: ShapeKind.rectangle,
        stroke: _black,
        strokeWidth: 1,
      );
      expect(shape.withOpacity(2).opacity, 1);
      expect(shape.withOpacity(-1).opacity, 0);
    });

    test('copyWith 可以换 id 用于粘贴', () {
      final shape = ShapeElement(
        id: 'r1',
        frame: Rect.zero,
        shape: ShapeKind.rectangle,
        stroke: _black,
        strokeWidth: 1,
      );
      final copy = shape.copyWith(id: 'r2');
      expect(copy.id, 'r2');
      expect(shape.id, 'r1');
    });
  });
}
