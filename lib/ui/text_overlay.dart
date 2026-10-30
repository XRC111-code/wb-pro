import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/element.dart';
import '../state/editor_controller.dart';
import 'theme.dart';

/// 画布上的行内文本编辑框。
///
/// 用浮层而不是弹窗：编辑便签时用户要能看见周围的图，弹一个居中的对话框
/// 会挡住正在写的东西，也让「这段字放不放得下」完全失去判断依据。
class TextEditorOverlay extends StatefulWidget {
  const TextEditorOverlay({
    super.key,
    required this.controller,
    required this.elementId,
    required this.onSubmit,
    required this.onCancel,
  });

  final EditorController controller;
  final String elementId;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<TextEditorOverlay> createState() => TextEditorOverlayState();
}

/// 公开是为了让外层用 GlobalKey 触发提交 —— 点画布空白处结束编辑时，
/// 只有这里知道输入框里的最新文本。
class TextEditorOverlayState extends State<TextEditorOverlay> {
  late final TextEditingController _text;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    final element = _element;
    _text = TextEditingController(text: _initialText(element));
    _focus = FocusNode(debugLabel: 'wb-text-editor');
    // 新建的空文本元素直接用全选没有意义，把光标放到末尾更自然。
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    // 只靠 TextField.autofocus 不够稳：浮层是在指针按下的同一帧插进 Stack 的，
    // 紧接着的 pointer-up 可能抢走焦点，用户打第一行字就丢到画布快捷键上了。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  String _initialText(WbElement? element) => switch (element) {
        TextElement e => e.text,
        NoteElement e => e.text,
        _ => '',
      };

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  WbElement? get _element {
    for (final element in widget.controller.elements) {
      if (element.id == widget.elementId) return element;
    }
    return null;
  }

  void submit() => widget.onSubmit(_text.text);

  void _submit() => submit();

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final element = _element;
    if (element == null) return const SizedBox.shrink();

    final isNote = element is NoteElement;
    final (baseFont, padding, color, bold, italic) = switch (element) {
      TextElement e => (e.fontSize, const EdgeInsets.symmetric(horizontal: 2), e.color, e.bold, e.italic),
      NoteElement e => (e.fontSize, const EdgeInsets.all(12), e.textColor, false, false),
      _ => (18.0, EdgeInsets.zero, const Color(0xFF000000), false, false),
    };

    return AnimatedBuilder(
      animation: widget.controller.viewport,
      builder: (context, _) {
        final viewport = widget.controller.viewport;
        final zoom = viewport.zoom;
        final screen = viewport.rectToScreen(element.frame);
        // 屏幕上 10px 以下的字没法编辑（别说看清光标了），编辑时给个下限，
        // 关掉编辑框后画布上仍然是真实的缩放比例。
        final fontSize = (baseFont * zoom).clamp(10.0, 400.0).toDouble();
        // 文本框比元素本身宽一点。TextField 除了文字还要放光标，内部行宽
        // 计算和 TextPainter 差几像素，宽度刚好卡在文字宽度上时会莫名折行——
        // 双击编辑的瞬间文字突然变成两行，非常刺眼。便签不加，它本来就
        // 该按固定宽度换行。
        final width =
            (screen.width + (isNote ? 0 : 24)).clamp(72.0, 4000.0).toDouble();

        return Positioned(
          left: screen.left,
          top: screen.top,
          width: width,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: isNote ? null : WbTheme.panelColor(context),
              borderRadius: BorderRadius.circular(isNote ? 6 : 4),
              border: Border.all(color: WbTheme.activeColor(context), width: 1.2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                controller: _text,
                focusNode: _focus,
                autofocus: true,
                maxLines: null,
                minLines: 1,
                cursorWidth: 1.6,
                cursorColor: WbTheme.activeColor(context),
                style: TextStyle(
                  fontSize: fontSize,
                  height: isNote ? 1.4 : 1.35,
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: isNote ? '写点什么…' : '输入文字，Ctrl+Enter 完成',
                  hintStyle: TextStyle(
                    fontSize: fontSize,
                    color: WbTheme.subtleText(context).withValues(alpha: 0.55),
                  ),
                ),
                onTapOutside: (_) => _submit(),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
        );
      },
    );
  }
}
