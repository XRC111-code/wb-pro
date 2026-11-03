import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/canvas_style.dart';
import '../model/element.dart';
import '../model/geometry.dart';
import '../model/snap_guides.dart';
import '../model/text_metrics.dart';
import '../util/id.dart';
import 'history.dart';
import 'viewport.dart';

/// 工具。`line` 与 `arrow` 共用 [ArrowElement]，只是默认不带箭头。
enum ToolKind {
  select,
  hand,
  pen,
  eraser,
  rectangle,
  ellipse,
  diamond,
  arrow,
  line,
  text,
  note,
}

extension ToolKindLabel on ToolKind {
  String get label => switch (this) {
        ToolKind.select => '选择',
        ToolKind.hand => '抓手',
        ToolKind.pen => '画笔',
        ToolKind.eraser => '橡皮',
        ToolKind.rectangle => '矩形',
        ToolKind.ellipse => '椭圆',
        ToolKind.diamond => '菱形',
        ToolKind.arrow => '箭头',
        ToolKind.line => '直线',
        ToolKind.text => '文本',
        ToolKind.note => '便签',
      };

  /// 是否是「拖出一个框」来创建的工具。
  bool get isShapeTool =>
      this == ToolKind.rectangle ||
      this == ToolKind.ellipse ||
      this == ToolKind.diamond ||
      this == ToolKind.arrow ||
      this == ToolKind.line;
}

/// 当前绘制样式。作用于「下一次新建」，也作用于「当前选中的元素」。
@immutable
class DrawStyle {
  const DrawStyle({
    this.stroke = const Color(0xFF1F2933),
    this.fill,
    this.strokeWidth = 3,
    this.strokeStyle = StrokeStyle.solid,
    this.fontSize = 24,
    this.cornerRadius = 12,
    this.noteColor = const Color(0xFFFFE08A),
    this.roughness = 0,
  });

  final Color stroke;
  final Color? fill;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final double fontSize;
  final double cornerRadius;
  final Color noteColor;

  /// 手绘强度。0 是几何描边，1 左右是「马克笔手绘」。
  final double roughness;

  DrawStyle copyWith({
    Color? stroke,
    Color? fill,
    bool clearFill = false,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    double? fontSize,
    double? cornerRadius,
    Color? noteColor,
    double? roughness,
  }) =>
      DrawStyle(
        stroke: stroke ?? this.stroke,
        fill: clearFill ? null : (fill ?? this.fill),
        strokeWidth: strokeWidth ?? this.strokeWidth,
        strokeStyle: strokeStyle ?? this.strokeStyle,
        fontSize: fontSize ?? this.fontSize,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        noteColor: noteColor ?? this.noteColor,
        roughness: roughness ?? this.roughness,
      );
}

/// 编辑器状态中枢。
///
/// 只做数据与规则，不碰 Widget：手势、绘制、对话框都在 UI 层。这样绝大多数
/// 逻辑能在纯 Dart 测试里跑（`flutter test` 不需要真机），而不是只能靠手点。
class EditorController extends ChangeNotifier {
  EditorController({Viewport? viewport}) : viewport = viewport ?? Viewport() {
    this.viewport.addListener(notifyListeners);
  }

  final Viewport viewport;
  final History history = History();

  List<WbElement> _elements = const <WbElement>[];
  Set<String> _selection = <String>{};
  ToolKind _tool = ToolKind.select;
  DrawStyle _style = const DrawStyle();
  Color _canvasColor = kCanvasPaper;
  String _name = '未命名白板';
  String? _filePath;
  bool _dirty = false;
  bool _showGrid = true;
  bool _snapToGrid = false;
  bool _smartGuides = true;
  double _gridSize = 24;
  List<SnapGuide> _guides = const <SnapGuide>[];

  List<WbElement> get elements => _elements;
  Set<String> get selection => _selection;
  ToolKind get tool => _tool;
  DrawStyle get style => _style;
  Color get canvasColor => _canvasColor;
  String get name => _name;
  String? get filePath => _filePath;
  bool get dirty => _dirty;
  bool get showGrid => _showGrid;
  bool get snapToGrid => _snapToGrid;
  bool get smartGuides => _smartGuides;

  /// 当前正在显示的对齐参考线。拖拽结束后会被清空。
  List<SnapGuide> get activeGuides => _guides;
  double get gridSize => _gridSize;
  final ValueNotifier<Offset?> pointerWorld = ValueNotifier<Offset?>(null);

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  WbElement? get singleSelected {
    if (_selection.length != 1) return null;
    final id = _selection.first;
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<WbElement> get selectedElements =>
      _elements.where((e) => _selection.contains(e.id)).toList(growable: false);

  Rect? get selectionBounds {
    Rect? bounds;
    for (final e in _elements) {
      if (!_selection.contains(e.id)) continue;
      bounds = bounds == null ? e.worldBounds : bounds.expandToInclude(e.worldBounds);
    }
    return bounds;
  }

  /// 所有元素的包围盒（导出、缩放到适合时用）。
  Rect? get contentBounds {
    if (_elements.isEmpty) return null;
    Rect bounds = _elements.first.worldBounds;
    for (var i = 1; i < _elements.length; i++) {
      bounds = bounds.expandToInclude(_elements[i].worldBounds);
    }
    return bounds;
  }

  // ── 基础操作 ───────────────────────────────────────────────────────────────

  void setTool(ToolKind value) {
    if (_tool == value) return;
    _tool = value;
    if (value != ToolKind.select && value != ToolKind.hand) {
      _selection = <String>{};
    }
    notifyListeners();
  }

  void setPointerWorld(Offset? value) {
    // 单独一个 ValueNotifier：鼠标移动每秒几十次，走 notifyListeners 会把
    // 工具栏、属性面板、画布全部重建一遍，纯粹浪费。
    pointerWorld.value = value;
  }

  void setShowGrid(bool value) {
    _showGrid = value;
    notifyListeners();
  }

  void setSnapToGrid(bool value) {
    _snapToGrid = value;
    notifyListeners();
  }

  void setSmartGuides(bool value) {
    if (_smartGuides == value) return;
    _smartGuides = value;
    if (!value) _guides = const <SnapGuide>[];
    notifyListeners();
  }

  void setGridSize(double value) {
    _gridSize = value.clamp(4, 200).toDouble();
    notifyListeners();
  }

  void setStyle(DrawStyle value) {
    _style = value;
    notifyListeners();
  }

  /// 换画布底色。
  ///
  /// 只调整「下一次新建」的笔色，不动已经画好的内容。自动把全篇线条翻面
  /// 看起来聪明，实际上是在改用户明确选过的颜色 —— 他可能就是想要一条深色
  /// 线压在深色底上做层次。
  ///
  /// [markDirty] 给「用主题色初始化空白文档」用：那次换色不是用户的编辑，
  /// 不该让新文档一打开就带着未保存标记。
  void setCanvasColor(Color value, {bool markDirty = true}) {
    final next = value.withValues(alpha: 1);
    if (_canvasColor.toARGB32() == next.toARGB32()) return;
    _canvasColor = next;
    _style = _style.copyWith(stroke: readableInk(_style.stroke, next));
    if (markDirty) _dirty = true;
    notifyListeners();
  }

  void rename(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _name) return;
    _name = trimmed;
    _dirty = true;
    notifyListeners();
  }

  void setDirty(bool value) {
    if (_dirty == value) return;
    _dirty = value;
    notifyListeners();
  }

  void markSaved(String? path) {
    _filePath = path;
    _dirty = false;
    notifyListeners();
  }

  EditorSnapshot snapshot() => EditorSnapshot(
        elements: _elements,
        selection: Set<String>.unmodifiable(_selection),
      );

  void _record() => history.record(snapshot());

  // ── 手势事务 ───────────────────────────────────────────────────────────────

  EditorSnapshot? _gestureStart;

  /// 开始一次连续操作（拖动、缩放、画笔）。
  ///
  /// 只在开始时记一次快照：如果按每帧记录，画一条线会产生几百条历史，
  /// 用户要按几百次撤销才能退回去。
  void beginGesture() {
    _gestureStart ??= snapshot();
  }

  void endGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start == null) return;
    if (start.sameAs(snapshot())) return;
    history.record(start);
    _dirty = true;
    notifyListeners();
  }

  void cancelGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start == null) return;
    _elements = start.elements;
    _selection = start.selection.toSet();
    notifyListeners();
  }

  /// 手势过程中的实时更新：不记历史、不改 dirty（结束时统一处理）。
  void updateLive(List<WbElement> next) {
    _elements = next;
    notifyListeners();
  }

  // ── 元素增删改 ─────────────────────────────────────────────────────────────

  void addElement(WbElement element, {bool select = true, bool record = true}) {
    if (record) _record();
    _elements = <WbElement>[..._elements, element];
    if (select) _selection = <String>{element.id};
    _dirty = true;
    notifyListeners();
  }

  void replaceElement(WbElement element) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index < 0) return;
    final next = List<WbElement>.of(_elements);
    next[index] = element;
    _elements = next;
    _dirty = true;
    notifyListeners();
  }

  /// 可撤销的元素更新。UI 改属性、改文本都走这里。
  void updateElement(WbElement element, {bool record = true}) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index < 0) return;
    if (record) _record();
    final next = List<WbElement>.of(_elements);
    next[index] = element;
    _elements = next;
    _dirty = true;
    notifyListeners();
  }

  /// 提交文本编辑结果。文本元素被清空时直接删除 —— 留下一个看不见也选不中
  /// 的空文本框，比删掉更让人困惑。
  void setTextContent(String id, String text) {
    final index = _elements.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final element = _elements[index];
    if (element is TextElement) {
      if (text.trim().isEmpty) {
        removeElement(id);
        return;
      }
      updateElement(normalizeText(element.copyWith(text: text)));
      return;
    }
    if (element is NoteElement) {
      updateElement(element.copyWith(text: text));
    }
  }

  void setSelectionOpacity(double value, {bool record = true}) {
    if (_selection.isEmpty) return;
    final clamped = value.clamp(0.05, 1.0).toDouble();
    if (record) _record();
    _elements = _elements
        .map((e) => _selection.contains(e.id) ? e.withOpacity(clamped) : e)
        .toList(growable: false);
    _dirty = true;
    notifyListeners();
  }

  void setRotation(double radians) {
    final target = singleSelected;
    if (target == null) return;
    updateElement(target.copyWith(rotation: radians));
  }

  void clearCanvas() {
    if (_elements.isEmpty) return;
    _record();
    _elements = const <WbElement>[];
    _selection = <String>{};
    _dirty = true;
    notifyListeners();
  }

  void removeElement(String id) {
    if (!_elements.any((e) => e.id == id)) return;
    _record();
    _elements = _elements.where((e) => e.id != id).toList(growable: false);
    _selection = <String>{..._selection}..remove(id);
    _dirty = true;
    notifyListeners();
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    _record();
    _elements = _elements.where((e) => !_selection.contains(e.id)).toList(growable: false);
    _selection = <String>{};
    _dirty = true;
    notifyListeners();
  }

  // ── 选择 ───────────────────────────────────────────────────────────────────

  void selectAll() {
    _selection = _elements
        .where((e) => e.visible && !e.locked)
        .map((e) => e.id)
        .toSet();
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection = <String>{};
    notifyListeners();
  }

  void selectOnly(String id) {
    _selection = <String>{id};
    notifyListeners();
  }

  void selectMany(Iterable<String> ids) {
    _selection = ids.toSet();
    notifyListeners();
  }

  void toggleSelection(String id) {
    final next = Set<String>.of(_selection);
    if (!next.remove(id)) next.add(id);
    _selection = next;
    notifyListeners();
  }

  /// 从后往前找命中的元素 —— 后画的在上层，点击应该优先选中它。
  /// 找指针下面的元素。
  ///
  /// [loose] 为 true（选择工具的用法）时，精确命中全部落空后会退一步接受
  /// 「点在元素内部」；橡皮擦要传 false —— 在空心矩形中间划一下就把整个
  /// 矩形删掉，不是「擦」该有的手感。
  /// 命中测试。隐藏和锁定的元素会被跳过：看不见的东西不该点得中，锁定的
  /// 东西点中了也没法动，两边都只会让人以为软件卡了。
  WbElement? hitTest(Offset world, {double tolerance = 4, bool loose = true}) {
    bool pickable(WbElement e) => e.visible && !e.locked;
    for (var i = _elements.length - 1; i >= 0; i--) {
      final element = _elements[i];
      if (!pickable(element)) continue;
      if (element.hitTest(world, tolerance: tolerance)) return element;
    }
    if (!loose) return null;
    // 一圈都没点中边线，再放宽到「点进内部也算」。没有这一遍，空心矩形
    // 只有边框能选中，触摸屏上等于点不到。
    for (var i = _elements.length - 1; i >= 0; i--) {
      final element = _elements[i];
      if (!pickable(element)) continue;
      if (element.hitTestArea(world)) return element;
    }
    return null;
  }

  List<WbElement> hitTestRect(Rect world) {
    return _elements
        .where((e) => e.visible && !e.locked && e.worldBounds.overlaps(world))
        .toList(growable: false);
  }

  // ── 图层 ───────────────────────────────────────────────────────────────────

  void setElementVisible(String id, bool value) {
    final index = _elements.indexWhere((e) => e.id == id);
    if (index < 0 || _elements[index].visible == value) return;
    _record();
    final next = List<WbElement>.of(_elements);
    next[index] = next[index].copyWith(visible: value);
    _elements = next;
    // 藏起来的东西还留在选中集里，属性面板就会对着一个看不见的元素编辑。
    if (!value) _selection = <String>{..._selection}..remove(id);
    _dirty = true;
    notifyListeners();
  }

  void setElementLocked(String id, bool value) {
    final index = _elements.indexWhere((e) => e.id == id);
    if (index < 0 || _elements[index].locked == value) return;
    _record();
    final next = List<WbElement>.of(_elements);
    next[index] = next[index].copyWith(locked: value);
    _elements = next;
    // 锁定即解除选中：留着选中框，用户会以为还能拖。
    if (value) _selection = <String>{..._selection}..remove(id);
    _dirty = true;
    notifyListeners();
  }

  /// 把元素从 [from] 挪到 [to]（下标都在当前列表里）。
  void moveElement(int from, int to) {
    if (from == to) return;
    if (from < 0 || from >= _elements.length) return;
    final target = to.clamp(0, _elements.length - 1);
    _record();
    final next = List<WbElement>.of(_elements);
    final element = next.removeAt(from);
    next.insert(target, element);
    _elements = next;
    _dirty = true;
    notifyListeners();
  }

  // ── 层级 ───────────────────────────────────────────────────────────────────

  void bringToFront() {
    if (_selection.isEmpty) return;
    _record();
    final moving = _elements.where((e) => _selection.contains(e.id)).toList();
    final rest = _elements.where((e) => !_selection.contains(e.id)).toList();
    _elements = <WbElement>[...rest, ...moving];
    _dirty = true;
    notifyListeners();
  }

  void sendToBack() {
    if (_selection.isEmpty) return;
    _record();
    final moving = _elements.where((e) => _selection.contains(e.id)).toList();
    final rest = _elements.where((e) => !_selection.contains(e.id)).toList();
    _elements = <WbElement>[...moving, ...rest];
    _dirty = true;
    notifyListeners();
  }

  void bringForward() {
    if (_selection.isEmpty) return;
    _record();
    final next = List<WbElement>.of(_elements);
    // 从后往前处理，避免同一个元素被连续交换两次。
    for (var i = next.length - 2; i >= 0; i--) {
      if (_selection.contains(next[i].id) && !_selection.contains(next[i + 1].id)) {
        final tmp = next[i];
        next[i] = next[i + 1];
        next[i + 1] = tmp;
      }
    }
    _elements = next;
    _dirty = true;
    notifyListeners();
  }

  void sendBackward() {
    if (_selection.isEmpty) return;
    _record();
    final next = List<WbElement>.of(_elements);
    for (var i = 1; i < next.length; i++) {
      if (_selection.contains(next[i].id) && !_selection.contains(next[i - 1].id)) {
        final tmp = next[i];
        next[i] = next[i - 1];
        next[i - 1] = tmp;
      }
    }
    _elements = next;
    _dirty = true;
    notifyListeners();
  }

  // ── 历史 ───────────────────────────────────────────────────────────────────

  void undo() {
    final restored = history.undo(snapshot());
    if (restored == null) return;
    _elements = restored.elements;
    _selection = restored.selection.toSet();
    _dirty = true;
    notifyListeners();
  }

  void redo() {
    final restored = history.redo(snapshot());
    if (restored == null) return;
    _elements = restored.elements;
    _selection = restored.selection.toSet();
    _dirty = true;
    notifyListeners();
  }

  // ── 剪贴板 ─────────────────────────────────────────────────────────────────

  static const String _clipboardPrefix = 'wb-pro/clipboard:';

  Future<void> copySelection() async {
    final selected = selectedElements;
    if (selected.isEmpty) return;
    final payload = jsonEncode(selected.map((e) => e.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: '$_clipboardPrefix$payload'));
  }

  Future<void> cutSelection() async {
    if (_selection.isEmpty) return;
    await copySelection();
    deleteSelection();
  }

  /// 返回粘贴出的元素数量（0 表示剪贴板里没有白板内容）。
  Future<int> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !text.startsWith(_clipboardPrefix)) return 0;
    final raw = text.substring(_clipboardPrefix.length);
    List<WbElement> parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return 0;
      parsed = <WbElement>[];
      for (final item in decoded) {
        if (item is Map) {
          parsed.add(WbElement.fromJson(Map<String, Object?>.from(item)));
        }
      }
    } on FormatException {
      return 0;
    }
    if (parsed.isEmpty) return 0;

    _record();
    const offset = Offset(24, 24);
    final pasted = parsed
        .map((e) => e.copyWith(id: newId('el'), frame: e.frame.shift(offset)))
        .toList(growable: false);
    _elements = <WbElement>[..._elements, ...pasted];
    _selection = pasted.map((e) => e.id).toSet();
    _dirty = true;
    notifyListeners();
    return pasted.length;
  }

  Future<void> duplicateSelection() async {
    final selected = selectedElements;
    if (selected.isEmpty) return;
    _record();
    final copies = selected
        .map((e) => e.copyWith(id: newId('el'), frame: e.frame.shift(const Offset(20, 20))))
        .toList(growable: false);
    _elements = <WbElement>[..._elements, ...copies];
    _selection = copies.map((e) => e.id).toSet();
    _dirty = true;
    notifyListeners();
  }

  // ── 移动 / 对齐 ────────────────────────────────────────────────────────────

  /// 计算拖拽中的元素间吸附。
  ///
  /// [proposed] 是「完全不吸附时，选中的整体包围盒会落在哪」。返回还要补加
  /// 的偏移和应当显示的参考线；参考线同时写进 [activeGuides]。
  ///
  /// 阈值按屏幕像素换算：`thresholdPx / zoom`。如果用世界单位，放大到 400%
  /// 时 6 个单位只有 1.5 个屏幕像素，用户会觉得「怎么也对不齐」。
  SnapResult snapSelection(
    Rect proposed, {
    double thresholdPx = 6,
    Set<SnapEdge> edges = kAllSnapEdges,
  }) {
    if (!_smartGuides) {
      _guides = const <SnapGuide>[];
      return const SnapResult();
    }
    final targets = <Rect>[];
    for (final e in _elements) {
      if (_selection.contains(e.id)) continue;
      targets.add(e.worldBounds);
    }
    final result = computeSnap(
      moving: proposed,
      targets: targets,
      threshold: thresholdPx / viewport.zoom,
      edges: edges,
    );
    _guides = result.guides;
    return result;
  }

  void clearGuides() {
    if (_guides.isEmpty) return;
    _guides = const <SnapGuide>[];
    notifyListeners();
  }

  void nudgeSelection(Offset delta) {
    if (_selection.isEmpty) return;
    _record();
    _elements = _elements
        .map((e) => _selection.contains(e.id) ? e.translated(delta) : e)
        .toList(growable: false);
    _dirty = true;
    notifyListeners();
  }

  /// 把选中元素按 [align] 对齐到整体包围盒。
  ///
  /// [AlignKind.distributeX] / [AlignKind.distributeY] 是等距分布，要求至少
  /// 三个元素才有意义（两个元素的「等距」就是现在这样）。
  void alignSelection(AlignKind kind) {
    final selected = selectedElements;
    if (selected.length < 2) return;
    Rect bounds = selected.first.worldBounds;
    for (var i = 1; i < selected.length; i++) {
      bounds = bounds.expandToInclude(selected[i].worldBounds);
    }
    _record();
    final next = List<WbElement>.of(_elements);

    switch (kind) {
      case AlignKind.left:
        for (final e in selected) {
          _replaceIn(next, e.translated(Offset(bounds.left - e.worldBounds.left, 0)));
        }
      case AlignKind.centerX:
        for (final e in selected) {
          _replaceIn(
            next,
            e.translated(Offset(bounds.center.dx - e.worldBounds.center.dx, 0)),
          );
        }
      case AlignKind.right:
        for (final e in selected) {
          _replaceIn(next, e.translated(Offset(bounds.right - e.worldBounds.right, 0)));
        }
      case AlignKind.top:
        for (final e in selected) {
          _replaceIn(next, e.translated(Offset(0, bounds.top - e.worldBounds.top)));
        }
      case AlignKind.centerY:
        for (final e in selected) {
          _replaceIn(
            next,
            e.translated(Offset(0, bounds.center.dy - e.worldBounds.center.dy)),
          );
        }
      case AlignKind.bottom:
        for (final e in selected) {
          _replaceIn(next, e.translated(Offset(0, bounds.bottom - e.worldBounds.bottom)));
        }
      case AlignKind.distributeX:
        _distribute(next, selected, horizontal: true);
      case AlignKind.distributeY:
        _distribute(next, selected, horizontal: false);
    }
    _elements = next;
    _dirty = true;
    notifyListeners();
  }

  void _distribute(List<WbElement> next, List<WbElement> selected, {required bool horizontal}) {
    if (selected.length < 3) return;
    final sorted = List<WbElement>.of(selected)
      ..sort((a, b) => horizontal
          ? a.worldBounds.left.compareTo(b.worldBounds.left)
          : a.worldBounds.top.compareTo(b.worldBounds.top));
    final total = sorted.fold<double>(
      0,
      (sum, e) => sum + (horizontal ? e.worldBounds.width : e.worldBounds.height),
    );
    final span = horizontal
        ? sorted.last.worldBounds.right - sorted.first.worldBounds.left
        : sorted.last.worldBounds.bottom - sorted.first.worldBounds.top;
    final gap = (span - total) / (sorted.length - 1);
    var cursor = horizontal ? sorted.first.worldBounds.left : sorted.first.worldBounds.top;
    for (final e in sorted) {
      final delta = horizontal
          ? Offset(cursor - e.worldBounds.left, 0)
          : Offset(0, cursor - e.worldBounds.top);
      final moved = e.translated(delta);
      _replaceIn(next, moved);
      cursor += (horizontal ? moved.worldBounds.width : moved.worldBounds.height) + gap;
    }
  }

  void _replaceIn(List<WbElement> list, WbElement element) {
    final index = list.indexWhere((e) => e.id == element.id);
    if (index >= 0) list[index] = element;
  }

  // ── 样式 ───────────────────────────────────────────────────────────────────

  /// 改样式：有选中就改选中，没选中就改「下一次新建」的默认值。
  void applyStyle({
    Color? stroke,
    Color? fill,
    bool clearFill = false,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    double? fontSize,
    double? cornerRadius,
    Color? noteColor,
    double? roughness,
    bool record = true,
  }) {
    final nextStyle = _style.copyWith(
      stroke: stroke,
      fill: fill,
      clearFill: clearFill,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      fontSize: fontSize,
      cornerRadius: cornerRadius,
      noteColor: noteColor,
      roughness: roughness,
    );
    _style = nextStyle;

    if (_selection.isEmpty) {
      notifyListeners();
      return;
    }

    if (record) _record();
    _elements = _elements.map((e) {
      if (!_selection.contains(e.id)) return e;
      return switch (e) {
        StrokeElement s => s.copyWith(
            color: stroke ?? s.color,
            strokeWidth: strokeWidth ?? s.strokeWidth,
          ),
        ShapeElement s => s.copyWith(
            stroke: stroke ?? s.stroke,
            fill: fill ?? s.fill,
            clearFill: clearFill,
            strokeWidth: strokeWidth ?? s.strokeWidth,
            strokeStyle: strokeStyle ?? s.strokeStyle,
            cornerRadius: cornerRadius ?? s.cornerRadius,
            roughness: roughness ?? s.roughness,
            // 从「几何」切到手绘时补一个种子：不补的话所有形状都用 0 号
            // 噪声，抖动完全一样，一排矩形看起来像复制粘贴的。
            seed: roughness != null && roughness > 0 && s.seed == 0
                ? _nextSeed()
                : null,
          ),
        ArrowElement a => a.copyWith(
            stroke: stroke ?? a.stroke,
            strokeWidth: strokeWidth ?? a.strokeWidth,
            strokeStyle: strokeStyle ?? a.strokeStyle,
          ),
        TextElement t => normalizeText(t.copyWith(
            color: stroke ?? t.color,
            fontSize: fontSize ?? t.fontSize,
          )),
        NoteElement n => n.copyWith(
            fill: fill ?? noteColor ?? n.fill,
            fontSize: fontSize ?? n.fontSize,
          ),
        ImageElement i => i,
      };
    }).toList(growable: false);
    _dirty = true;
    notifyListeners();
  }

  void toggleBold() {
    final target = singleSelected;
    if (target is! TextElement) return;
    _record();
    replaceElement(target.copyWith(bold: !target.bold));
  }

  void toggleItalic() {
    final target = singleSelected;
    if (target is! TextElement) return;
    _record();
    replaceElement(target.copyWith(italic: !target.italic));
  }

  // ── 元素工厂 ───────────────────────────────────────────────────────────────

  Offset _snap(Offset point) {
    if (!_snapToGrid) return point;
    return Offset(
      (point.dx / _gridSize).round() * _gridSize,
      (point.dy / _gridSize).round() * _gridSize,
    );
  }

  WbElement createShape(ToolKind tool, Offset start, Offset end, {bool constrain = false}) {
    var a = _snap(start);
    var b = _snap(end);
    if (constrain) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final side = math.max(dx.abs(), dy.abs());
      b = a + Offset(dx.isNegative ? -side : side, dy.isNegative ? -side : side);
    }
    final rect = ensureMinSize(normalizedRect(a, b), minSize: 2);

    switch (tool) {
      case ToolKind.arrow:
      case ToolKind.line:
        final frame = ensureMinSize(rectFromPoints(a, b), minSize: 1);
        return ArrowElement(
          id: newId('el'),
          frame: frame,
          start: a - frame.topLeft,
          end: b - frame.topLeft,
          stroke: _style.stroke,
          strokeWidth: _style.strokeWidth,
          endHead: tool == ToolKind.arrow,
          strokeStyle: _style.strokeStyle,
          opacity: 1,
        );
      default:
        final shape = switch (tool) {
          ToolKind.ellipse => ShapeKind.ellipse,
          ToolKind.diamond => ShapeKind.diamond,
          _ => ShapeKind.rectangle,
        };
        return ShapeElement(
          id: newId('el'),
          frame: rect,
          shape: shape,
          stroke: _style.stroke,
          fill: _style.fill,
          strokeWidth: _style.strokeWidth,
          strokeStyle: _style.strokeStyle,
          cornerRadius: _style.cornerRadius,
          roughness: _style.roughness,
          // 种子跟着形状走：同一个形状无论重绘多少次，抖动都长一个样。
          seed: _style.roughness > 0 ? _nextSeed() : 0,
        );
    }
  }

  int _seedCounter = 0;

  /// 简单的递增种子，不用随机数：随机数会让「撤销后重做」得到的形状和
  /// 原来长得不一样，虽然功能上没错，但看着像丢了一次编辑。
  int _nextSeed() => (_seedCounter += 7919) & 0x7fffffff;

  StrokeElement createStroke(List<Offset> worldPoints, {List<double>? pressures}) {
    final points = worldPoints.map(_snap).toList(growable: false);
    Rect bounds = Rect.fromCircle(center: points.first, radius: 0.5);
    for (final p in points) {
      bounds = bounds.expandToInclude(Rect.fromCircle(center: p, radius: 0.5));
    }
    final pad = _style.strokeWidth / 2 + 0.5;
    final frame = bounds.inflate(pad);

    // 压力数组长度必须和点一一对应，否则宁可不存。设备没提供压感时上游
    // 传 null，这里就退回等宽描边。
    //
    // 再加一道「全零」检查：有些平台会稳定上报 pressure = 0，长度对得上但
    // 数值没有意义。存下来只会得到一条全程最细的线。
    final usable = pressures != null &&
        pressures.length == points.length &&
        pressures.any((p) => p > 0.01);
    return StrokeElement(
      id: newId('el'),
      frame: frame,
      points: points.map((p) => p - frame.topLeft).toList(growable: false),
      color: _style.stroke,
      strokeWidth: _style.strokeWidth,
      pressures: usable ? List<double>.unmodifiable(pressures) : const <double>[],
    );
  }

  TextElement createText(Offset at, {String text = ''}) {
    final style = buildTextStyle(
      fontSize: _style.fontSize,
      color: _style.stroke,
      lineHeight: 1.35,
    );
    final size = measureTextBlock(text.isEmpty ? ' ' : text, style, maxWidth: 320);
    final frame = Rect.fromLTWH(
      _snap(at).dx,
      _snap(at).dy,
      // 空文本框也要有 320 的编辑宽度。按空串量出来只有 40，输入第一句话
      // 就会在光标旁边一个字一个字折行，看起来像出了 bug。
      math.max(320, size.width + 4),
      math.max(_style.fontSize * 1.4, size.height),
    );
    return TextElement(
      id: newId('el'),
      frame: frame,
      text: text,
      color: _style.stroke,
      fontSize: _style.fontSize,
    );
  }

  NoteElement createNote(Offset at) {
    final topLeft = _snap(at);
    return NoteElement(
      id: newId('el'),
      frame: Rect.fromLTWH(topLeft.dx, topLeft.dy, 200, 200),
      text: '',
      fill: _style.noteColor,
      fontSize: 18,
    );
  }

  /// 文本编辑结束后按内容重新算尺寸。
  WbElement normalizeText(TextElement element) {
    if (element.text.trim().isEmpty) return element;
    final style = buildTextStyle(
      fontSize: element.fontSize,
      color: element.color,
      bold: element.bold,
      italic: element.italic,
      lineHeight: element.lineHeight,
    );
    // 自动宽度的文本框按内容撑开，上限 600 —— 再宽就该手动拖了。
    final natural = measureTextBlock(element.text, style, maxWidth: 600, align: element.align);
    final width = element.autoWidth
        ? math.max(40.0, math.min(natural.width + 8, 600.0))
        : math.max(40.0, element.frame.width);
    final size = measureTextBlock(element.text, style, maxWidth: width, align: element.align);
    return element.copyWith(
      frame: Rect.fromLTWH(
        element.frame.left,
        element.frame.top,
        width,
        math.max(element.fontSize * 1.4, size.height),
      ),
    );
  }

  // ── 文档 ───────────────────────────────────────────────────────────────────

  void loadDocument({
    required String name,
    required List<WbElement> elements,
    String? filePath,
    Offset? pan,
    double? zoom,
    Color? canvasColor,
  }) {
    _elements = List<WbElement>.unmodifiable(elements);
    _selection = <String>{};
    _name = name;
    _filePath = filePath;
    _dirty = false;
    _canvasColor = (canvasColor ?? kCanvasPaper).withValues(alpha: 1);
    // 打开一份深色文档后，默认笔色必须跟着翻面，否则第一次落笔什么都看不见。
    _style = _style.copyWith(stroke: readableInk(_style.stroke, _canvasColor));
    history.clear();
    if (pan != null && zoom != null) viewport.restore(pan, zoom);
    notifyListeners();
  }

  void newDocument({Color? canvasColor}) {
    loadDocument(
      name: '未命名白板',
      elements: const <WbElement>[],
      canvasColor: canvasColor,
    );
  }

  @override
  void dispose() {
    viewport.removeListener(notifyListeners);
    viewport.dispose();
    pointerWorld.dispose();
    super.dispose();
  }
}

enum AlignKind { left, centerX, right, top, centerY, bottom, distributeX, distributeY }

extension AlignKindLabel on AlignKind {
  String get label => switch (this) {
        AlignKind.left => '左对齐',
        AlignKind.centerX => '水平居中',
        AlignKind.right => '右对齐',
        AlignKind.top => '顶对齐',
        AlignKind.centerY => '垂直居中',
        AlignKind.bottom => '底对齐',
        AlignKind.distributeX => '水平等距',
        AlignKind.distributeY => '垂直等距',
      };
}
