import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/element.dart';
import 'package:wb_pro/state/editor_controller.dart';

const Color _black = Color(0xFF1F2933);

WbElement _shape(
  String id, {
  double x = 0,
  double y = 0,
  double size = 20,
  bool filled = true,
  ShapeKind shape = ShapeKind.rectangle,
}) =>
    ShapeElement(
      id: id,
      frame: Rect.fromLTWH(x, y, size, size),
      shape: shape,
      stroke: _black,
      strokeWidth: 2,
      fill: filled ? const Color(0xFFFFFFFF) : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('增删与历史', () {
    test('添加元素后可撤销', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      expect(controller.elements.length, 1);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.elements, isEmpty);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.elements.length, 1);
      controller.dispose();
    });

    test('删除选中元素后可撤销', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.selectOnly('a');
      controller.deleteSelection();
      expect(controller.elements, isEmpty);

      controller.undo();
      expect(controller.elements.length, 1);
      controller.dispose();
    });

    test('连续手势只产生一条历史', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.selectOnly('a');
      final baseline = controller.elements;

      controller.beginGesture();
      for (var i = 1; i <= 20; i++) {
        controller.updateLive(<WbElement>[_shape('a', x: i.toDouble())]);
      }
      controller.endGesture();

      expect(controller.history.undoDepth, 2); // addElement + 手势
      controller.undo();
      expect(controller.elements.single.frame.left, 0);
      expect(identical(controller.elements.single, baseline.single), isTrue);
      controller.dispose();
    });

    test('取消手势回到起始状态', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.beginGesture();
      controller.updateLive(<WbElement>[_shape('a', x: 500)]);
      expect(controller.elements.single.frame.left, 500);

      controller.cancelGesture();
      expect(controller.elements.single.frame.left, 0);
      controller.dispose();
    });

    test('没有实际改动的手势不写历史', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      final depth = controller.history.undoDepth;

      controller.beginGesture();
      controller.endGesture();
      expect(controller.history.undoDepth, depth);
      controller.dispose();
    });
  });

  group('选择', () {
    test('后画的元素优先命中', () {
      final controller = EditorController();
      controller.addElement(_shape('bottom'));
      controller.addElement(_shape('top'));
      expect(controller.hitTest(const Offset(10, 10))!.id, 'top');
      controller.dispose();
    });

    test('框选命中所有相交元素', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: 0));
      controller.addElement(_shape('b', x: 100));
      final hits = controller.hitTestRect(const Rect.fromLTWH(-5, -5, 40, 40));
      expect(hits.map((e) => e.id), <String>['a']);
      controller.dispose();
    });

    test('空心矩形点内部也能选中', () {
      final controller = EditorController();
      controller.addElement(_shape('hollow', size: 200, filled: false));
      // 正中间离四条边各有 100px，精确命中必然落空
      expect(controller.hitTest(const Offset(100, 100))!.id, 'hollow');
      controller.dispose();
    });

    test('空心椭圆按真路径判断，包围盒角落不命中', () {
      final controller = EditorController();
      controller.addElement(
        _shape('oval', size: 200, filled: false, shape: ShapeKind.ellipse),
      );
      expect(controller.hitTest(const Offset(4, 4)), isNull);
      expect(controller.hitTest(const Offset(100, 100))!.id, 'oval');
      controller.dispose();
    });

    test('上层的空心框不挡住下面元素的边线', () {
      final controller = EditorController();
      controller.addElement(_shape('under', x: 100, y: 100, size: 40));
      controller.addElement(_shape('over', size: 400, filled: false));
      // (100,100) 既在 under 的填充里，也在 over 的内部。
      // 精确命中要先跑完一圈，才轮到宽松命中。
      expect(controller.hitTest(const Offset(100, 100))!.id, 'under');
      controller.dispose();
    });

    test('关掉宽松命中后空心形状内部不再算命中', () {
      final controller = EditorController();
      controller.addElement(_shape('hollow', size: 200, filled: false));
      // 橡皮擦用这一档：在空心矩形中间划一下不该把整个矩形删掉
      expect(controller.hitTest(const Offset(100, 100), loose: false), isNull);
      expect(controller.hitTest(const Offset(0, 100), loose: false)!.id, 'hollow');
      controller.dispose();
    });

    test('切换工具会清空选择', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.setTool(ToolKind.pen);
      expect(controller.selection, isEmpty);
      controller.dispose();
    });

    test('选中元素的包围盒覆盖全部', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: 0));
      controller.addElement(_shape('b', x: 100, y: 50));
      controller.selectMany(<String>['a', 'b']);
      final bounds = controller.selectionBounds!;
      expect(bounds.left, 0);
      expect(bounds.right, 120);
      expect(bounds.bottom, 70);
      controller.dispose();
    });
  });

  group('样式', () {
    test('无选中时只改默认值', () {
      final controller = EditorController();
      controller.applyStyle(stroke: const Color(0xFFE03131));
      expect(controller.style.stroke.toARGB32(), 0xFFE03131);
      expect(controller.canUndo, isFalse);
      controller.dispose();
    });

    test('有选中时同时改元素', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.applyStyle(stroke: const Color(0xFF2F9E44), strokeWidth: 6);
      final shape = controller.elements.single as ShapeElement;
      expect(shape.stroke.toARGB32(), 0xFF2F9E44);
      expect(shape.strokeWidth, 6);
      controller.dispose();
    });

    test('滑块拖动用 record=false 时不写历史', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      final depth = controller.history.undoDepth;

      controller.beginGesture();
      for (var i = 1; i <= 10; i++) {
        controller.applyStyle(strokeWidth: i.toDouble(), record: false);
      }
      controller.endGesture();

      expect(controller.history.undoDepth, depth + 1);
      controller.dispose();
    });

    test('不透明度作用于全部选中元素', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.addElement(_shape('b', x: 40));
      controller.selectAll();
      controller.setSelectionOpacity(0.5);
      expect(controller.elements.every((e) => e.opacity == 0.5), isTrue);
      controller.dispose();
    });

    test('文本内容为空时删除元素', () {
      final controller = EditorController();
      final text = controller.createText(Offset.zero, text: '临时');
      controller.addElement(text);
      controller.setTextContent(text.id, '   ');
      expect(controller.elements, isEmpty);
      controller.dispose();
    });

    test('新文本框按内容自动加宽', () {
      final controller = EditorController();
      final text = controller.createText(Offset.zero);
      controller.addElement(text);
      controller.setTextContent(text.id, '这是一段足够长的文字，应该把文本框撑开而不是折成很多短行');
      final updated = controller.elements.single as TextElement;
      expect(updated.autoWidth, isTrue);
      expect(updated.frame.width, greaterThan(text.frame.width));
      expect(updated.frame.width, lessThanOrEqualTo(600));
      controller.dispose();
    });

    test('手动拖过宽度后不再自动加宽', () {
      final controller = EditorController();
      final text = controller.createText(Offset.zero, text: '短');
      controller.addElement(text);
      final resized = text.resized(const Rect.fromLTWH(0, 0, 300, 40));
      expect(resized.autoWidth, isFalse);
      controller.updateElement(resized);
      controller.setTextContent(text.id, '这是一段足够长的文字，应该被折行而不是继续撑开文本框');
      final updated = controller.elements.single as TextElement;
      expect(updated.frame.width, 300);
      controller.dispose();
    });

    test('文本内容更新后高度重算', () {
      final controller = EditorController();
      final text = controller.createText(Offset.zero);
      controller.addElement(text);
      controller.setTextContent(text.id, '第一行\n第二行\n第三行');
      final updated = controller.elements.single as TextElement;
      expect(updated.text.split('\n').length, 3);
      expect(updated.frame.height, greaterThan(text.frame.height));
      controller.dispose();
    });
  });

  group('层级', () {
    test('置顶把选中元素移到最后', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.addElement(_shape('b'));
      controller.selectOnly('a');
      controller.bringToFront();
      expect(controller.elements.map((e) => e.id), <String>['b', 'a']);
      controller.dispose();
    });

    test('上移一层只换一位', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.addElement(_shape('b'));
      controller.addElement(_shape('c'));
      controller.selectOnly('a');
      controller.bringForward();
      expect(controller.elements.map((e) => e.id), <String>['b', 'a', 'c']);
      controller.dispose();
    });

    test('相邻两个都选中时交换不会互相抵消', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.addElement(_shape('b'));
      controller.addElement(_shape('c'));
      controller.selectMany(<String>['a', 'b']);
      controller.bringForward();
      expect(controller.elements.map((e) => e.id), <String>['c', 'a', 'b']);
      controller.dispose();
    });
  });

  group('对齐', () {
    test('左对齐把元素推到最左', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: 0));
      controller.addElement(_shape('b', x: 50));
      controller.selectMany(<String>['a', 'b']);
      controller.alignSelection(AlignKind.left);
      expect(controller.elements.every((e) => e.frame.left == 0), isTrue);
      controller.dispose();
    });

    test('顶对齐保留 x', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: 10, y: 0));
      controller.addElement(_shape('b', x: 60, y: 40));
      controller.selectMany(<String>['a', 'b']);
      controller.alignSelection(AlignKind.top);
      expect(controller.elements.every((e) => e.frame.top == 0), isTrue);
      expect(controller.elements.last.frame.left, 60);
      controller.dispose();
    });

    test('少于两个元素时对齐无效', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: 7));
      controller.alignSelection(AlignKind.left);
      expect(controller.elements.single.frame.left, 7);
      controller.dispose();
    });

    test('水平等距需要至少三个元素', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: 0));
      controller.addElement(_shape('b', x: 100));
      controller.selectMany(<String>['a', 'b']);
      controller.alignSelection(AlignKind.distributeX);
      expect(controller.elements.map((e) => e.frame.left), <double>[0, 100]);
      controller.dispose();
    });
  });

  group('微移与旋转', () {
    test('方向键微移选中元素', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.nudgeSelection(const Offset(1, -1));
      expect(controller.elements.single.frame.topLeft, const Offset(1, -1));
      controller.dispose();
    });

    test('旋转只作用于单选', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.addElement(_shape('b', x: 40));
      controller.selectAll();
      controller.setRotation(math.pi / 4);
      expect(controller.elements.every((e) => e.rotation == 0), isTrue);

      controller.selectOnly('a');
      controller.setRotation(math.pi / 4);
      expect(controller.elements.first.rotation, closeTo(math.pi / 4, 1e-9));
      controller.dispose();
    });
  });

  group('元素工厂', () {
    test('Shift 约束拖出正方形', () {
      final controller = EditorController();
      final shape = controller.createShape(
        ToolKind.rectangle,
        Offset.zero,
        const Offset(100, 30),
        constrain: true,
      );
      expect(shape.frame.width, closeTo(100, 1e-9));
      expect(shape.frame.height, closeTo(100, 1e-9));
      controller.dispose();
    });

    test('直线工具默认不带箭头', () {
      final controller = EditorController();
      final line = controller.createShape(ToolKind.line, Offset.zero, const Offset(50, 50));
      expect((line as ArrowElement).endHead, isFalse);
      controller.dispose();
    });

    test('吸附到网格', () {
      final controller = EditorController()
        ..setSnapToGrid(true)
        ..setGridSize(20);
      final shape = controller.createShape(
        ToolKind.rectangle,
        const Offset(3, 4),
        const Offset(57, 43),
      );
      expect(shape.frame.left, 0);
      expect(shape.frame.top, 0);
      expect(shape.frame.width, closeTo(60, 1e-9));
      expect(shape.frame.height, closeTo(40, 1e-9));
      controller.dispose();
    });

    test('笔迹的框包含线宽的一半', () {
      final controller = EditorController();
      final stroke = controller.createStroke(const <Offset>[
        Offset(0, 0),
        Offset(100, 100),
      ]);
      expect(stroke.frame.left, lessThan(0));
      expect(stroke.frame.right, greaterThan(100));
      controller.dispose();
    });
  });

  group('文档', () {
    test('新建文档清空元素与历史', () {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.newDocument();
      expect(controller.elements, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.dirty, isFalse);
      controller.dispose();
    });

    test('loadDocument 会恢复视口', () {
      final controller = EditorController()..viewport.setSize(const Size(800, 600));
      controller.loadDocument(
        name: 'x',
        elements: <WbElement>[_shape('a')],
        pan: const Offset(10, 20),
        zoom: 2,
      );
      expect(controller.viewport.zoom, 2);
      expect(controller.viewport.pan, const Offset(10, 20));
      controller.dispose();
    });

    test('contentBounds 覆盖所有元素', () {
      final controller = EditorController();
      controller.addElement(_shape('a', x: -50));
      controller.addElement(_shape('b', x: 100));
      final bounds = controller.contentBounds!;
      expect(bounds.left, -50);
      expect(bounds.right, 120);
      controller.dispose();
    });
  });

  group('剪贴板', () {
    String? clipboard;

    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboard};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('复制粘贴产生偏移的新元素', () async {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.selectOnly('a');
      await controller.copySelection();
      expect(clipboard, contains('wb-pro/clipboard:'));

      final count = await controller.paste();
      expect(count, 1);
      expect(controller.elements.length, 2);
      expect(controller.elements.last.id, isNot('a'));
      expect(controller.elements.last.frame.left, 24);
      controller.dispose();
    });

    test('剪贴板是普通文本时不粘贴', () async {
      clipboard = '一段普通文字';
      final controller = EditorController();
      expect(await controller.paste(), 0);
      expect(controller.elements, isEmpty);
      controller.dispose();
    });

    test('剪切等于复制加删除', () async {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.selectOnly('a');
      await controller.cutSelection();
      expect(controller.elements, isEmpty);
      expect(await controller.paste(), 1);
      controller.dispose();
    });

    test('创建副本不依赖系统剪贴板', () async {
      final controller = EditorController();
      controller.addElement(_shape('a'));
      controller.selectOnly('a');
      await controller.duplicateSelection();
      expect(controller.elements.length, 2);
      expect(controller.elements.last.frame.left, 20);
      controller.dispose();
    });
  });
}
