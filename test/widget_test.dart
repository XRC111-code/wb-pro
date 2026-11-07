import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/app.dart';
import 'package:wb_pro/model/canvas_style.dart';
import 'package:wb_pro/ui/canvas_view.dart';
import 'package:wb_pro/ui/layer_panel.dart';
import 'package:wb_pro/ui/widgets.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const WbApp());
  await tester.pumpAndSettle();
}

Finder _iconButton(String tooltip) => find.byWidgetPredicate(
      (widget) => widget is WbIconButton && widget.tooltip == tooltip,
    );

/// 工具按钮的提示走 miuix 的 Overlay，不再是 Material 的 Tooltip，
/// 所以按 widget 本身定位，而不是 find.byTooltip。
///
/// 参照「快捷白板」之后，工具条换成了带短标签的卡片（[WbToolCard]）：
/// `label` 只放 2~3 个字（「矩形」），快捷键挪进了 `tooltip`。所以这里既
/// 支持按 label 精确匹配，也支持按 label 前缀匹配。
Finder _toolButton(String label) => find.byWidgetPredicate(
      (widget) => widget is WbToolCard && widget.label == label,
    );

WbToolCard _tool(WidgetTester tester, String prefix) {
  return tester
      .widgetList<WbToolCard>(find.byType(WbToolCard))
      .firstWhere((card) => card.label.startsWith(prefix));
}

/// 画布底色不在 Widget 树的可读属性上，只能从画笔里取。
Color _canvasBackground(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<ScenePainter>()
      .first
      .background;
}

void main() {
  testWidgets('空画布显示引导与工具栏', (tester) async {
    await _pumpApp(tester);

    expect(find.text('未命名白板'), findsOneWidget);
    expect(find.text('空白画布'), findsOneWidget);
    // 底栏共 18 张卡片：中组 13（11 个工具 + 图片 + 样式）+ 左组 2（菜单/保存）
    // + 右组 3（撤销/清屏/更多）。数量固定：禁用态卡片仍然占位渲染，
    // 位置不该随状态跳动。
    expect(find.byType(WbToolCard), findsNWidgets(18));
    expect(find.text('0 个元素'), findsOneWidget);
  });

  testWidgets('点击工具按钮切换当前工具', (tester) async {
    await _pumpApp(tester);
    expect(_tool(tester, '选择').selected, isTrue);

    await tester.tap(_toolButton('矩形'));
    await tester.pumpAndSettle();

    expect(_tool(tester, '矩形').selected, isTrue);
    expect(_tool(tester, '选择').selected, isFalse);
  });

  testWidgets('键盘快捷键切换工具', (tester) async {
    await _pumpApp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(_tool(tester, '笔').selected, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(_tool(tester, '选择').selected, isTrue);
  });

  testWidgets('拖拽画出一个矩形', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('矩形'));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(500, 300), const Offset(140, 90));
    await tester.pumpAndSettle();

    expect(find.text('1 个元素'), findsOneWidget);
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.text('空白画布'), findsNothing);
  });

  testWidgets('撤销按钮在画完之前是禁用的', (tester) async {
    await _pumpApp(tester);

    final undo = tester.widget<WbIconButton>(_iconButton('撤销  Ctrl+Z'));
    expect(undo.onPressed, isNull);

    await tester.tap(_toolButton('矩形'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(100, 100));
    await tester.pumpAndSettle();

    final enabledUndo = tester.widget<WbIconButton>(_iconButton('撤销  Ctrl+Z'));
    expect(enabledUndo.onPressed, isNotNull);

    await tester.tap(_iconButton('撤销  Ctrl+Z'));
    await tester.pumpAndSettle();
    expect(find.text('0 个元素'), findsOneWidget);
  });

  testWidgets('菜单里能找到导出项', (tester) async {
    await _pumpApp(tester);

    // 菜单已从顶栏下沉到底栏左组的「菜单」卡片（快捷白板的结构），
    // 所以这里点底栏那张卡片而不是顶栏的 Icons.menu。
    await tester.tap(_toolButton('菜单'));
    await tester.pumpAndSettle();

    expect(find.text('导出 PNG…'), findsOneWidget);
    expect(find.text('导出 SVG…'), findsOneWidget);
    expect(find.text('另存为…'), findsOneWidget);
  });

  testWidgets('菜单里可以换画布底色', (tester) async {
    await _pumpApp(tester);

    // 深色界面新建的空白文档是墨黑画布。
    expect(_canvasBackground(tester).toARGB32(), kCanvasInk.toARGB32());

    await tester.tap(_toolButton('菜单'));
    await tester.pumpAndSettle();
    // 底部弹层有足够高度，不再需要「视图与帮助」这层子菜单。
    await tester.tap(find.text('画布底色…'));
    await tester.pumpAndSettle();

    expect(find.text('纸白'), findsOneWidget);
    expect(find.text('墨黑'), findsOneWidget);

    await tester.tap(find.text('纸白'));
    await tester.pumpAndSettle();

    expect(_canvasBackground(tester).toARGB32(), kCanvasPaper.toARGB32());
  });

  testWidgets('选中元素后才出现属性面板', (tester) async {
    await _pumpApp(tester);

    // 没选中任何东西时面板不占画布——它现在是浮层，常驻会白白压掉右侧。
    // ⚠️ 不能用 find.text('样式') 判断：底栏常驻一张「样式」卡片（快捷白板
    // 的结构），那个文字一直都在。改用只有属性面板才有的分区标题。
    expect(find.text('描边'), findsNothing);

    await tester.tap(_toolButton('矩形'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(180, 120));
    await tester.pumpAndSettle();

    await tester.tap(_toolButton('选择'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(490, 360));
    await tester.pumpAndSettle();

    expect(find.text('描边'), findsOneWidget);
    expect(find.text('填充'), findsOneWidget);
  });

  testWidgets('文本工具在画布上点出编辑框', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('文本'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(600, 320));
    // TextField 的光标动画会让 pumpAndSettle 一直等下去，这里只推进有限帧。
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('1 个元素'), findsOneWidget);
  });

  testWidgets('文本编辑期间点击画布只结束编辑', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('文本'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(600, 320));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('1 个元素'), findsOneWidget);

    // 点画布空白处：应当只提交并结束编辑，不能顺手再建一个文本框。
    await tester.tapAt(const Offset(900, 600));
    await tester.pump(const Duration(milliseconds: 200));
    // 空文本元素在提交时会被删掉，所以最终是 0 个而不是 1 个。
    expect(find.text('0 个元素'), findsOneWidget);
  });

  testWidgets('拖动时出现对齐参考线', (tester) async {
    await _pumpApp(tester);

    // 上面一个矩形
    await tester.tap(_toolButton('矩形'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(300, 200), const Offset(200, 100));
    await tester.pumpAndSettle();
    // 下面一个矩形，左边缘对齐
    await tester.dragFrom(const Offset(300, 520), const Offset(200, 100));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // 按住上面那个，往下拖到和下面那个左边缘对齐的位置
    final gesture = await tester.startGesture(const Offset(400, 250));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
    }

    final controller = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .controller;
    expect(controller.activeGuides, isNotEmpty);
    final guide = controller.activeGuides.firstWhere((g) => g.vertical);
    // 世界坐标的原点在视口中心，不能拿屏幕坐标当断言
    final bottomLeft = controller.elements.last.worldBounds.left;
    expect(guide.position, closeTo(bottomLeft, 0.5));
    // 参考线必须覆盖两个元素的高度，而不是只盖住其中一个
    expect(guide.to - guide.from, greaterThan(200));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.activeGuides, isEmpty);
  });

  testWidgets('图层面板可以打开并隐藏元素', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('矩形'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(420, 300), const Offset(140, 90));
    await tester.pumpAndSettle();
    expect(find.text('1 个元素'), findsOneWidget);

    // Ctrl+Shift+L
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(LayerPanel), findsOneWidget);
    expect(find.text('矩形'), findsWidgets);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // 再点一次恢复显示
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('窄屏切换到底部工具条', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WbApp());
    await tester.pumpAndSettle();

    // 紧凑模式只收顶栏，底栏仍是完整的 18 张卡片。
    expect(find.byType(WbToolCard), findsNWidgets(18));
    expect(find.text('空白画布'), findsOneWidget);
  });
}
