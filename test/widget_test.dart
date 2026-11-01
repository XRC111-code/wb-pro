import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/app.dart';
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
Finder _toolButton(String label) => find.byWidgetPredicate(
      (widget) => widget is WbToolButton && widget.label == label,
    );

WbToolButton _tool(WidgetTester tester, String prefix) {
  return tester
      .widgetList<WbToolButton>(find.byType(WbToolButton))
      .firstWhere((button) => button.label.startsWith(prefix));
}

void main() {
  testWidgets('空画布显示引导与工具栏', (tester) async {
    await _pumpApp(tester);

    expect(find.text('未命名白板'), findsOneWidget);
    expect(find.text('空白画布'), findsOneWidget);
    expect(find.byType(WbToolButton), findsNWidgets(13));
    expect(find.text('0 个元素'), findsOneWidget);
  });

  testWidgets('点击工具按钮切换当前工具', (tester) async {
    await _pumpApp(tester);
    expect(_tool(tester, '选择').selected, isTrue);

    await tester.tap(_toolButton('矩形  R'));
    await tester.pumpAndSettle();

    expect(_tool(tester, '矩形').selected, isTrue);
    expect(_tool(tester, '选择').selected, isFalse);
  });

  testWidgets('键盘快捷键切换工具', (tester) async {
    await _pumpApp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(_tool(tester, '画笔').selected, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(_tool(tester, '选择').selected, isTrue);
  });

  testWidgets('拖拽画出一个矩形', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('矩形  R'));
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

    await tester.tap(_toolButton('矩形  R'));
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

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('导出 PNG…'), findsOneWidget);
    expect(find.text('导出 SVG…'), findsOneWidget);
    expect(find.text('另存为…'), findsOneWidget);
  });

  testWidgets('选中元素后才出现属性面板', (tester) async {
    await _pumpApp(tester);

    // 没选中任何东西时面板不占画布——它现在是浮层，常驻会白白压掉右侧。
    expect(find.text('样式'), findsNothing);

    await tester.tap(_toolButton('矩形  R'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(180, 120));
    await tester.pumpAndSettle();

    await tester.tap(_toolButton('选择  V'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(490, 360));
    await tester.pumpAndSettle();

    expect(find.text('样式'), findsOneWidget);
    expect(find.text('描边'), findsOneWidget);
    expect(find.text('填充'), findsOneWidget);
  });

  testWidgets('文本工具在画布上点出编辑框', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('文本  T'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(600, 320));
    // TextField 的光标动画会让 pumpAndSettle 一直等下去，这里只推进有限帧。
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('1 个元素'), findsOneWidget);
  });

  testWidgets('文本编辑期间点击画布只结束编辑', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_toolButton('文本  T'));
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

  testWidgets('窄屏切换到底部工具条', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WbApp());
    await tester.pumpAndSettle();

    // 紧凑模式仍然有 12 个工具按钮（含「样式」入口后为 13 个）。
    expect(find.byType(WbToolButton), findsAtLeastNWidgets(12));
    expect(find.text('空白画布'), findsOneWidget);
  });
}
