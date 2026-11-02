import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../io/document.dart';
import '../io/document_store.dart';
import '../io/export_png.dart';
import '../io/export_svg.dart';
import '../model/canvas_style.dart';
import '../model/element.dart';
import '../render/painting.dart';
import '../state/editor_controller.dart';
import '../util/id.dart';
import 'actions.dart';
import 'canvas_view.dart';
import 'inspector_panel.dart';
import 'shortcut_sheet.dart';
import 'status_bar.dart';
import 'text_overlay.dart';
import 'theme.dart';
import 'tool_rail.dart';
import 'top_bar.dart';
import 'widgets.dart';

/// 主界面。
///
/// 职责边界：这里只做「把 IO、对话框、布局串起来」，所有编辑规则都在
/// [EditorController] 里。这样 90% 的行为可以脱离 Widget 测试。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onToggleTheme,
    this.initialCanvasColor = kCanvasPaper,
  });

  final VoidCallback onToggleTheme;

  /// 首次打开时空白文档的底色，由 [WbApp] 按当前主题给出。
  final Color initialCanvasColor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final EditorController _controller;
  late final WbActions _actions;

  String? _editingId;
  final GlobalKey<TextEditorOverlayState> _editorKey =
      GlobalKey<TextEditorOverlayState>();
  Timer? _autosaveTimer;
  bool _inspectorOpen = true;
  bool _busy = false;

  WbDocument? _recovery;
  DateTime? _recoveryAt;

  @override
  void initState() {
    super.initState();
    _controller = EditorController();
    // 先定底色再挂监听：这一步会顺带把默认笔色翻到能看清的一面，但它不是
    // 用户的编辑，不该触发自动保存。
    _controller.setCanvasColor(widget.initialCanvasColor, markDirty: false);
    _controller.addListener(_onControllerChanged);
    _actions = _buildActions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutosave());
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  // ── 自动保存 ───────────────────────────────────────────────────────────────

  void _onControllerChanged() {
    if (!_controller.dirty) return;
    _autosaveTimer?.cancel();
    // 2 秒静默期：连续落笔时不写盘，停手之后才落一次。
    _autosaveTimer = Timer(const Duration(seconds: 2), _writeAutosave);
  }

  Future<void> _writeAutosave() async {
    if (!_controller.dirty) return;
    await AutosaveStore.write(_buildDocument().encode());
  }

  Future<void> _checkAutosave() async {
    final raw = await AutosaveStore.read();
    if (raw == null || !mounted) return;
    try {
      final result = WbDocument.decode(raw);
      if (result.document.elements.isEmpty) return;
      final at = await AutosaveStore.modifiedAt();
      if (!mounted) return;
      setState(() {
        _recovery = result.document;
        _recoveryAt = at;
      });
    } on DocumentException {
      // 存档坏了就当没有，不要用一个错误弹窗迎接用户。
    }
  }

  // ── 文档 ───────────────────────────────────────────────────────────────────

  WbDocument _buildDocument() => WbDocument(
        name: _controller.name,
        elements: _controller.elements,
        canvasColor: _controller.canvasColor,
        pan: _controller.viewport.pan,
        zoom: _controller.viewport.zoom,
      );

  void _loadDocument(WbDocument document, {String? path}) {
    _cancelEditing();
    ImageRegistry.clear();
    _controller.loadDocument(
      name: document.name,
      elements: document.elements,
      filePath: path,
      pan: document.pan,
      zoom: document.zoom,
      canvasColor: document.canvasColor,
    );
  }

  /// 新文档的底色跟随当前主题：深色界面下新建一张黑纸，才不会一打开就是
  /// 一块刺眼的白。之后它归文档所有，切主题不会再变。
  Color get _freshCanvasColor =>
      Theme.of(context).brightness == Brightness.dark ? kCanvasInk : kCanvasPaper;

  Future<void> _newDocument() async {
    if (!await _confirmDiscard()) return;
    _loadDocument(WbDocument(
      name: '未命名白板',
      elements: const <WbElement>[],
      canvasColor: _freshCanvasColor,
    ));
    await AutosaveStore.clear();
  }

  Future<void> _openDocument() async {
    if (!await _confirmDiscard()) return;
    final file = await DocumentStore.openDocument();
    if (file == null) return;
    await _openContent(file.content, name: file.name, path: file.path);
  }

  Future<void> _openContent(String content,
      {required String name, String? path}) async {
    try {
      final result = WbDocument.decode(content);
      _loadDocument(result.document, path: path);
      if (result.hasWarnings) _notice(result.warnings.join(' '));
    } on DocumentException catch (error) {
      _notice('打开失败：${error.message}');
    }
  }

  Future<void> _save() async {
    final path = _controller.filePath;
    if (path == null) {
      await _saveAs();
      return;
    }
    await _writeDocument(path);
  }

  Future<void> _saveAs() async {
    final path = await DocumentStore.chooseSavePath(_controller.name);
    if (path == null) return;
    await _writeDocument(path);
  }

  Future<void> _writeDocument(String path) async {
    final content = _buildDocument().encode();
    var saved = path;
    if (!await DocumentStore.writeText(path, content)) {
      // Android 的 SAF 路径无法直接写；降级到应用目录，至少不丢内容。
      final fallback = await DocumentStore.writeToDocuments(
        '${_controller.name}.wbpro',
        Uint8List.fromList(utf8.encode(content)),
      );
      if (fallback == null) {
        _notice('保存失败：没有写入权限');
        return;
      }
      saved = fallback;
    }
    _controller.markSaved(saved);
    await AutosaveStore.clear();
    _notice('已保存到 $saved');
  }

  Future<void> _renameDocument() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: _controller.name),
    );
    if (name != null) {
      _controller.rename(name);
      _controller.setDirty(true);
    }
  }

  Future<void> _clearCanvas() async {
    if (_controller.elements.isEmpty) return;
    final ok = await _confirm(
      '清空画布',
      '将删除全部 ${_controller.elements.length} 个元素。可以用 Ctrl+Z 撤销。',
      confirmLabel: '清空',
      danger: true,
    );
    if (ok) _controller.clearCanvas();
  }

  /// 换画布底色。
  ///
  /// 只改底色和「下一次新建」的笔色，不动已有元素。切换后如果默认笔色被
  /// 翻转了，明确说一句 —— 用户看到工具栏颜色变了却不知道为什么，比看不见
  /// 线条更让人困惑。
  Future<void> _chooseCanvasColor() async {
    final preset = await showDialog<CanvasPreset>(
      context: context,
      builder: (context) => _CanvasColorDialog(current: _controller.canvasColor),
    );
    if (preset == null) return;
    final before = _controller.style.stroke;
    _controller.setCanvasColor(preset.color);
    final inkChanged = _controller.style.stroke.toARGB32() != before.toARGB32();
    if (_controller.elements.isNotEmpty && inkChanged) {
      _notice('画布已换成「${preset.name}」。已画的内容不会自动换色，'
          '选中后可在属性面板里调；新画的笔已改为${isDarkCanvas(preset.color) ? '浅色' : '深色'}。');
    } else if (inkChanged) {
      _notice('画布已换成「${preset.name}」，默认画笔改为${isDarkCanvas(preset.color) ? '浅色' : '深色'}。');
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
    return _confirm(
      '放弃未保存的修改？',
      '当前白板有尚未保存的修改。继续操作会丢弃它们（自动存档仍会保留最近一份）。',
      confirmLabel: '放弃修改',
      danger: true,
    );
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirmLabel = '确定',
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 360, child: Text(message)),
        actions: <Widget>[
          MiuixTextButton(
            '取消',
            onPressed: () => Navigator.of(context).pop(false),
            minWidth: 0,
            minHeight: 0,
            cornerRadius: 10,
            insideMargin:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            textStyle: const TextStyle(fontSize: 14),
          ),
          MiuixButton(
            onPressed: () => Navigator.of(context).pop(true),
            minWidth: 0,
            minHeight: 0,
            cornerRadius: 10,
            insideMargin:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            colors: danger
                ? const MiuixButtonColors(
                    color: Color(0xFFE94634),
                    disabledColor: Color(0xFFF3C9C4),
                    contentColor: Colors.white,
                    disabledContentColor: Colors.white,
                  )
                : MiuixButtonDefaults.buttonColorsPrimary(context),
            child: Text(confirmLabel, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── 导出 / 导入 ────────────────────────────────────────────────────────────

  Future<void> _exportPng() async {
    if (_controller.elements.isEmpty) {
      _notice('画布上还没有内容');
      return;
    }
    final path = await DocumentStore.chooseSavePath(
      _controller.name,
      extension: 'png',
      label: 'PNG 图片',
    );
    if (path == null) return;

    setState(() => _busy = true);
    try {
      // 导出就是「把这块画布拍下来」：底色跟着文档走，否则深色画布导出来是
      // 一张白底图，和在屏幕上看到的不是同一件东西。
      final bytes = await exportPng(
        _controller.elements,
        options: PngExportOptions(background: _controller.canvasColor),
      );
      await _writeBytesWithFallback(
          path, bytes, '${_controller.name}.png', 'PNG');
    } catch (error) {
      _notice('导出 PNG 失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSvg() async {
    if (_controller.elements.isEmpty) {
      _notice('画布上还没有内容');
      return;
    }
    final path = await DocumentStore.chooseSavePath(
      _controller.name,
      extension: 'svg',
      label: 'SVG 矢量图',
    );
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final svg = exportSvg(
        _controller.elements,
        options: SvgExportOptions(background: _controller.canvasColor),
      );
      await _writeBytesWithFallback(
        path,
        Uint8List.fromList(utf8.encode(svg)),
        '${_controller.name}.svg',
        'SVG',
      );
    } catch (error) {
      _notice('导出 SVG 失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeBytesWithFallback(
    String path,
    Uint8List bytes,
    String name,
    String label,
  ) async {
    if (await DocumentStore.writeBytes(path, bytes)) {
      _notice('$label 已导出到 $path');
      return;
    }
    final fallback = await DocumentStore.writeToDocuments(name, bytes);
    if (fallback == null) {
      _notice('$label 导出失败：没有写入权限');
      return;
    }
    _notice('$label 已保存到 $fallback');
  }

  Future<void> _importImage() async {
    final picked = await DocumentStore.pickImage();
    if (picked == null) return;

    int width;
    int height;
    try {
      final codec = await ui.instantiateImageCodec(picked.bytes);
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      _notice('这张图片无法解码：${picked.name}');
      return;
    }
    if (width <= 0 || height <= 0) return;

    const maxSide = 480.0;
    final scale = math.min(1.0, maxSide / math.max(width, height));
    final size = Size(width * scale, height * scale);
    final viewport = _controller.viewport;
    final center = viewport.size.isEmpty
        ? Offset.zero
        : viewport
            .toWorld(Offset(viewport.size.width / 2, viewport.size.height / 2));

    final element = ImageElement(
      id: newId('el'),
      frame: Rect.fromCenter(
          center: center, width: size.width, height: size.height),
      bytes: picked.bytes,
      mimeType: picked.mimeType,
      label: picked.name,
    );
    _controller.addElement(element);
    ImageRegistry.ensure(element, () {});
  }

  // ── 文本编辑 ───────────────────────────────────────────────────────────────

  void _beginEditing(WbElement element) {
    setState(() => _editingId = element.id);
  }

  void _cancelEditing() {
    if (_editingId == null) return;
    setState(() => _editingId = null);
  }

  void _submitEditing(String text) {
    final id = _editingId;
    if (id == null) return;
    setState(() => _editingId = null);
    _controller.setTextContent(id, text);
  }

  // ── 其它动作 ───────────────────────────────────────────────────────────────

  Future<void> _copySelection() async {
    if (_controller.selection.isEmpty) {
      _notice('还没有选中任何元素');
      return;
    }
    await _controller.copySelection();
    _notice('已复制 ${_controller.selection.length} 个元素');
  }

  Future<void> _cutSelection() async {
    if (_controller.selection.isEmpty) return;
    await _controller.cutSelection();
    _notice('已剪切');
  }

  Future<void> _paste() async {
    final count = await _controller.paste();
    if (count == 0) _notice('剪贴板里没有可粘贴的白板内容');
  }

  Future<void> _duplicateSelection() async {
    if (_controller.selection.isEmpty) return;
    await _controller.duplicateSelection();
  }

  void _nudge(Offset delta) {
    if (_controller.selection.isEmpty) return;
    _controller.nudgeSelection(delta);
  }

  void _zoomIn() {
    final viewport = _controller.viewport;
    if (viewport.size.isEmpty) return;
    viewport.zoomAt(
      Offset(viewport.size.width / 2, viewport.size.height / 2),
      1.25,
    );
  }

  void _zoomOut() {
    final viewport = _controller.viewport;
    if (viewport.size.isEmpty) return;
    viewport.zoomAt(
      Offset(viewport.size.width / 2, viewport.size.height / 2),
      1 / 1.25,
    );
  }

  void _zoomReset() {
    final viewport = _controller.viewport;
    if (viewport.size.isEmpty) return;
    viewport.resetZoom(
      focus: Offset(viewport.size.width / 2, viewport.size.height / 2),
    );
  }

  void _zoomToFit() {
    final bounds = _controller.contentBounds;
    if (bounds == null) {
      _notice('画布上还没有内容');
      return;
    }
    _controller.viewport.fit(bounds);
  }

  void _notice(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        // 不用 SnackBar.width：它和 margin 互斥，而底部这条横条必须抬到
        // 工具条上方 —— 否则提示一出现就把十三个工具按钮全盖住。
        content: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 460,
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  WbActions _buildActions() => WbActions(
        newDocument: _newDocument,
        openDocument: _openDocument,
        save: _save,
        saveAs: _saveAs,
        exportPng: _exportPng,
        exportSvg: _exportSvg,
        importImage: _importImage,
        renameDocument: _renameDocument,
        showShortcuts: () => showShortcutsDialog(context),
        showAbout: () => showAboutWbPro(context),
        toggleTheme: widget.onToggleTheme,
        toggleInspector: () => setState(() => _inspectorOpen = !_inspectorOpen),
        clearCanvas: _clearCanvas,
        copySelection: _copySelection,
        cutSelection: _cutSelection,
        paste: _paste,
        duplicateSelection: _duplicateSelection,
        deleteSelection: _controller.deleteSelection,
        selectAll: _controller.selectAll,
        undo: _controller.undo,
        redo: _controller.redo,
        zoomIn: _zoomIn,
        zoomOut: _zoomOut,
        zoomReset: _zoomReset,
        zoomToFit: _zoomToFit,
        toggleGrid: () => _controller.setShowGrid(!_controller.showGrid),
        toggleSnap: () => _controller.setSnapToGrid(!_controller.snapToGrid),
        chooseCanvasColor: _chooseCanvasColor,
      );

  // ── 快捷键 ─────────────────────────────────────────────────────────────────

  Map<ShortcutActivator, VoidCallback> _bindings() {
    final map = <ShortcutActivator, VoidCallback>{};

    void bind(
      LogicalKeyboardKey key,
      VoidCallback action, {
      bool ctrl = false,
      bool shift = false,
      bool alt = false,
    }) {
      if (ctrl) {
        map[SingleActivator(key, control: true, shift: shift, alt: alt)] =
            action;
        // macOS 上习惯用 Command；两套都注册，用户不用记平台差异。
        map[SingleActivator(key, meta: true, shift: shift, alt: alt)] = action;
      } else {
        map[SingleActivator(key, shift: shift, alt: alt)] = action;
      }
    }

    // 工具
    bind(LogicalKeyboardKey.keyV, () => _controller.setTool(ToolKind.select));
    bind(LogicalKeyboardKey.keyH, () => _controller.setTool(ToolKind.hand));
    bind(LogicalKeyboardKey.keyP, () => _controller.setTool(ToolKind.pen));
    bind(LogicalKeyboardKey.keyE, () => _controller.setTool(ToolKind.eraser));
    bind(
        LogicalKeyboardKey.keyR, () => _controller.setTool(ToolKind.rectangle));
    bind(LogicalKeyboardKey.keyO, () => _controller.setTool(ToolKind.ellipse));
    bind(LogicalKeyboardKey.keyD, () => _controller.setTool(ToolKind.diamond));
    bind(LogicalKeyboardKey.keyA, () => _controller.setTool(ToolKind.arrow));
    bind(LogicalKeyboardKey.keyL, () => _controller.setTool(ToolKind.line));
    bind(LogicalKeyboardKey.keyT, () => _controller.setTool(ToolKind.text));
    bind(LogicalKeyboardKey.keyN, () => _controller.setTool(ToolKind.note));

    // 文件
    bind(LogicalKeyboardKey.keyN, _newDocument, ctrl: true);
    bind(LogicalKeyboardKey.keyO, _openDocument, ctrl: true);
    bind(LogicalKeyboardKey.keyS, _save, ctrl: true);
    bind(LogicalKeyboardKey.keyS, _saveAs, ctrl: true, shift: true);
    bind(LogicalKeyboardKey.keyE, _exportPng, ctrl: true);

    // 编辑
    bind(LogicalKeyboardKey.keyZ, _controller.undo, ctrl: true);
    bind(LogicalKeyboardKey.keyZ, _controller.redo, ctrl: true, shift: true);
    bind(LogicalKeyboardKey.keyY, _controller.redo, ctrl: true);
    bind(LogicalKeyboardKey.keyC, _copySelection, ctrl: true);
    bind(LogicalKeyboardKey.keyX, _cutSelection, ctrl: true);
    bind(LogicalKeyboardKey.keyV, _paste, ctrl: true);
    bind(LogicalKeyboardKey.keyD, _duplicateSelection, ctrl: true);
    bind(LogicalKeyboardKey.keyA, _controller.selectAll, ctrl: true);
    bind(LogicalKeyboardKey.delete, _controller.deleteSelection);
    bind(LogicalKeyboardKey.backspace, _controller.deleteSelection);

    bind(LogicalKeyboardKey.bracketRight, _controller.bringForward, ctrl: true);
    bind(LogicalKeyboardKey.bracketLeft, _controller.sendBackward, ctrl: true);
    bind(LogicalKeyboardKey.bracketRight, _controller.bringToFront,
        ctrl: true, shift: true);
    bind(LogicalKeyboardKey.bracketLeft, _controller.sendToBack,
        ctrl: true, shift: true);

    // 方向键微移
    const step = 1.0;
    const fast = 10.0;
    bind(LogicalKeyboardKey.arrowLeft, () => _nudge(const Offset(-step, 0)));
    bind(LogicalKeyboardKey.arrowRight, () => _nudge(const Offset(step, 0)));
    bind(LogicalKeyboardKey.arrowUp, () => _nudge(const Offset(0, -step)));
    bind(LogicalKeyboardKey.arrowDown, () => _nudge(const Offset(0, step)));
    bind(LogicalKeyboardKey.arrowLeft, () => _nudge(const Offset(-fast, 0)),
        shift: true);
    bind(LogicalKeyboardKey.arrowRight, () => _nudge(const Offset(fast, 0)),
        shift: true);
    bind(LogicalKeyboardKey.arrowUp, () => _nudge(const Offset(0, -fast)),
        shift: true);
    bind(LogicalKeyboardKey.arrowDown, () => _nudge(const Offset(0, fast)),
        shift: true);

    // 视图
    bind(LogicalKeyboardKey.equal, _zoomIn, ctrl: true);
    bind(LogicalKeyboardKey.equal, _zoomIn, ctrl: true, shift: true);
    bind(LogicalKeyboardKey.minus, _zoomOut, ctrl: true);
    bind(LogicalKeyboardKey.digit0, _zoomReset, ctrl: true);
    bind(LogicalKeyboardKey.digit1, _zoomToFit, shift: true);
    bind(LogicalKeyboardKey.keyG,
        () => _controller.setShowGrid(!_controller.showGrid),
        ctrl: true);
    bind(
      LogicalKeyboardKey.keyG,
      () => _controller.setSnapToGrid(!_controller.snapToGrid),
      ctrl: true,
      shift: true,
    );

    // 帮助
    bind(LogicalKeyboardKey.slash, () => showShortcutsDialog(context),
        shift: true);

    bind(LogicalKeyboardKey.escape, () {
      _controller.setTool(ToolKind.select);
      _controller.clearSelection();
    });

    return map;
  }

  // ── 布局 ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < WbTheme.compactBreakpoint;

    // 底部一条线上要并排放三块：左下统计、中间工具条、右下缩放。
    // 窗口不够宽时不硬挤，把两侧的状态收起来，只留工具条。
    final roomForFooter = width >= 940;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: _editingId == null
            ? _bindings()
            : const <ShortcutActivator, VoidCallback>{},
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // 属性面板跟着选中走：选中什么就显示什么，取消选中自动收起。
              final showInspector = !compact &&
                  _inspectorOpen &&
                  _controller.selection.isNotEmpty;
              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CanvasView(
                      controller: _controller,
                      onEditText: _beginEditing,
                      onNotice: _notice,
                      ignorePointers: _editingId != null,
                      onOutsidePointer: () => _editorKey.currentState?.submit(),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _controller.elements.isEmpty
                          ? _emptyHint(context)
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (_recovery != null) _recoveryBanner(context),

                  // 顶部两角
                  Positioned(
                    top: WbTheme.inset,
                    left: WbTheme.inset,
                    right: WbTheme.inset,
                    child: TopBar(
                      controller: _controller,
                      actions: _actions,
                      compact: compact,
                    ),
                  ),

                  // 属性面板：浮在右侧，不推挤画布
                  if (showInspector)
                    Positioned(
                      top: 72,
                      right: WbTheme.inset,
                      // 高度跟着内容走，只在超出可视区时才截断并滚动。写死
                      // bottom 会让分区少的元素（比如一张图片）也撑成满屏。
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.sizeOf(context).height - 72 - 68,
                        ),
                        child: InspectorPanel(
                          controller: _controller,
                          onClose: () => setState(() => _inspectorOpen = false),
                        ),
                      ),
                    ),

                  // 底部
                  if (roomForFooter)
                    Positioned(
                      left: WbTheme.inset,
                      right: WbTheme.inset,
                      bottom: WbTheme.inset,
                      child: StatusBar(
                        controller: _controller,
                        actions: _actions,
                        compact: compact,
                      ),
                    ),
                  // 工具条放最后：万一和两侧状态在窄窗口下碰上了，压在下面
                  // 的应该是文字而不是按钮。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: WbTheme.inset,
                    child: Center(
                      child: ToolRail(
                        controller: _controller,
                        onImportImage: _importImage,
                        inspectorOpen: showInspector,
                        onOpenInspector: () {
                          if (compact) {
                            _openInspectorSheet();
                          } else {
                            setState(() => _inspectorOpen = !_inspectorOpen);
                          }
                        },
                      ),
                    ),
                  ),

                  if (_editingId != null)
                    TextEditorOverlay(
                      key: _editorKey,
                      controller: _controller,
                      elementId: _editingId!,
                      onSubmit: _submitEditing,
                      onCancel: _cancelEditing,
                    ),
                  if (_busy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.18),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(BuildContext context) {
    // 提示色从画布底色算出来，不能取 chrome 的「次要文字」——那套颜色跟着
    // 主题走，深色主题下是浅灰，摆在纸白画布上看不见；墨色画布上又反过来。
    final ink = inkOnCanvas(_controller.canvasColor);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.gesture, size: 40, color: ink.withValues(alpha: 0.16)),
          const SizedBox(height: 12),
          Text(
            '空白画布',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: ink.withValues(alpha: 0.48),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '按 P 开始手绘，或从下方选一个形状工具',
            style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.34)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _hintChip('空格 + 拖动', '平移'),
              const SizedBox(width: 8),
              _hintChip('Ctrl + 滚轮', '缩放'),
              const SizedBox(width: 8),
              _hintChip('?', '快捷键'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hintChip(String keys, String label) {
    final ink = inkOnCanvas(_controller.canvasColor);
    final darkCanvas = isDarkCanvas(_controller.canvasColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: darkCanvas
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ink.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            keys,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ink.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.36)),
          ),
        ],
      ),
    );
  }

  Widget _recoveryBanner(BuildContext context) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: WbPanel(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MiuixIcon(
                icon: Icons.restore,
                size: 15,
                tint: WbTheme.activeColor(context),
              ),
              const SizedBox(width: 8),
              MiuixText(
                '发现 ${_formatAgo(_recoveryAt)}的自动存档',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(width: 4),
              MiuixTextButton(
                '恢复',
                onPressed: () {
                  final document = _recovery;
                  if (document == null) return;
                  _loadDocument(document);
                  // 恢复出来的内容还没落到用户文件上，标脏让「保存」有意义。
                  _controller.setDirty(true);
                  setState(() => _recovery = null);
                  _notice('已恢复自动存档');
                },
                minWidth: 0,
                minHeight: 0,
                cornerRadius: 8,
                insideMargin:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(width: 2),
              WbIconButton(
                icon: Icons.close,
                tooltip: '忽略',
                size: 26,
                iconSize: 15,
                onPressed: () => setState(() => _recovery = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAgo(DateTime? at) {
    if (at == null) return '刚才';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '刚才';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  void _openInspectorSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.62,
        child: InspectorPanel(
          controller: _controller,
          embedded: true,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }
}

class _CanvasColorDialog extends StatelessWidget {
  const _CanvasColorDialog({required this.current});

  final Color current;

  @override
  Widget build(BuildContext context) {
    final subtle = WbTheme.subtleText(context);
    return AlertDialog(
      title: const Text('画布底色'),
      content: SizedBox(
        width: 372,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final preset in kCanvasPresets)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _presetCard(context, preset),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '底色随文档保存：换主题不会改变它，导出图片时也会带上。',
              style: TextStyle(fontSize: 12, height: 1.55, color: subtle),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        MiuixTextButton(
          '取消',
          onPressed: () => Navigator.of(context).pop(),
          minWidth: 0,
          minHeight: 0,
          cornerRadius: 10,
          insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          textStyle: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Widget _presetCard(BuildContext context, CanvasPreset preset) {
    final selected = preset.matches(current);
    final accent = WbTheme.activeColor(context);
    final subtle = WbTheme.subtleText(context);
    return MiuixPressable(
      onPressed: () => Navigator.of(context).pop(preset),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: preset.color,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? accent : WbTheme.hairline(context),
                width: selected ? 2 : 1,
              ),
            ),
            // 勾的颜色按色卡自己算，不能用主题色：深色卡上白勾，浅色卡上墨勾。
            child: selected
                ? Icon(Icons.check_rounded,
                    size: 20, color: inkOnCanvas(preset.color))
                : null,
          ),
          const SizedBox(height: 7),
          Text(
            preset.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(preset.hint, style: TextStyle(fontSize: 10.5, color: subtle)),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名白板'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _text,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: '名称',
            counterText: '',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        MiuixTextButton(
          '取消',
          onPressed: () => Navigator.of(context).pop(),
          minWidth: 0,
          minHeight: 0,
          cornerRadius: 10,
          insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          textStyle: const TextStyle(fontSize: 14),
        ),
        MiuixButton(
          onPressed: _submit,
          minWidth: 0,
          minHeight: 0,
          cornerRadius: 10,
          insideMargin: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          colors: MiuixButtonDefaults.buttonColorsPrimary(context),
          child: const Text('确定', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}
