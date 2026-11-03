import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';

import '../model/canvas_style.dart';
import '../model/element.dart';
import '../model/geometry.dart';
import '../model/snap_guides.dart';
import '../state/editor_controller.dart';
import '../state/viewport.dart';
import '../render/painting.dart';
import 'theme.dart';

/// 选择框上的控制点索引。
/// 0..3 是四角（左上、右上、右下、左下），4..7 是四边中点（上、右、下、左）。
const double _handleRadius = 5.5;
const double _rotateHandleDistance = 26;

/// 对齐参考线的颜色。洋红：画布上的笔色通常是黑、蓝、绿、黄，只有它会
/// 被一眼认成「辅助」而不是内容。
const Color _kGuideColor = Color(0xFFFF3B6B);

enum _DragMode { none, pan, move, resize, rotate, marquee, create, draw, erase, pinch }

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.controller,
    required this.onEditText,
    required this.onNotice,
    this.ignorePointers = false,
    this.onOutsidePointer,
  });

  final EditorController controller;
  final void Function(WbElement element) onEditText;
  final void Function(String message) onNotice;

  /// 文本浮层打开期间为 true：此时画布不处理指针，否则「点空白处结束编辑」
  /// 会顺手在原地又新建一个文本框。
  final bool ignorePointers;

  /// 浮层打开时画布上的点击。用来提交当前编辑。
  final VoidCallback? onOutsidePointer;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

class CanvasViewState extends State<CanvasView> {
  EditorController get _controller => widget.controller;

  final Map<int, Offset> _pointers = <int, Offset>{};
  _DragMode _mode = _DragMode.none;

  // 画笔
  List<Offset> _drawPoints = <Offset>[];
  List<double> _drawPressures = <double>[];
  /// 速度模拟的平滑值。原始压力逐帧跳变会让笔画边缘变成锯齿。
  double _smoothedPressure = 1;
  Duration _lastSampleTime = Duration.zero;
  Offset _lastSampleWorld = Offset.zero;

  // 拖拽创建形状时的预览
  WbElement? _preview;

  // 框选
  Rect? _marquee;

  // 变换基线：手势开始时的完整元素列表与选中快照
  List<WbElement> _baseline = const <WbElement>[];
  Map<String, WbElement> _startById = <String, WbElement>{};
  Rect _startBounds = Rect.zero;
  /// 移动开始时的整体包围盒。吸附要基于「起点 + 原始位移」算，不能基于
  /// 上一帧的结果 —— 否则吸住之后再拖会带着误差滚动。
  Rect _moveStartBounds = Rect.zero;
  Offset _startWorld = Offset.zero;
  int? _handle;
  double _startRotation = 0;
  double _startAngle = 0;
  Offset _rotateCenter = Offset.zero;

  // 双指
  double _pinchStartDistance = 1;
  double _pinchStartZoom = 1;
  Offset _pinchAnchorWorld = Offset.zero;

  // 双击检测
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;

  Viewport get _viewport => _controller.viewport;

  bool get _spacePressed =>
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  bool get _shiftPressed => HardwareKeyboard.instance.isShiftPressed;

  Offset _toWorld(Offset local) => _viewport.toWorld(local);

  /// 采样当前的落笔压力。
  ///
  /// 优先用设备上报的：数位笔和压感屏的 `pressure` 是真实值。判断依据是
  /// **设备类型**而不是「min/max 有没有范围」—— GTK 上鼠标事件的范围就是
  /// 0..1，`pressure` 恒为 0，只看范围会把每支鼠标都当成压感笔，画出来的
  /// 线全是「最轻的一档」。触屏设备很多也报 0，所以要求值真的大于 0。
  ///
  /// 其余情况退回**按速度模拟** —— 快速划过变细、收笔放慢变粗，这是所有
  /// 手写笔刷的通用做法，比一根粗细不变的电线好看得多。
  double _pressureOf(PointerEvent event, Offset world, {bool first = false}) {
    final spread = event.pressureMax - event.pressureMin;
    final kind = event.kind;
    final stylus = kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
    if (stylus && spread > 0.001) {
      return ((event.pressure - event.pressureMin) / spread).clamp(0.0, 1.0);
    }
    if (kind == PointerDeviceKind.touch && spread > 0.001 && event.pressure > 0) {
      return ((event.pressure - event.pressureMin) / spread).clamp(0.0, 1.0);
    }
    if (first) return 0.85;
    final dt = (event.timeStamp - _lastSampleTime).inMicroseconds / 1e6;
    if (dt <= 0) return _smoothedPressure;
    final speed = (world - _lastSampleWorld).distance / dt;
    // 700 单位/秒时大约降到一半粗细；再快也不会细于 0.3。
    final target = (1 / (1 + speed / 700)).clamp(0.3, 1.0);
    // 低通：不平滑的话，采样抖动会让边缘出现细密的锯齿。
    _smoothedPressure = _smoothedPressure * 0.72 + target * 0.28;
    return _smoothedPressure;
  }

  List<WbElement> _withSelectionShifted(Offset delta) {
    return _baseline
        .map((e) => _startById.containsKey(e.id)
            ? _startById[e.id]!.translated(delta)
            : e)
        .toList(growable: false);
  }

  // ── 指针事件 ───────────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (widget.ignorePointers) {
      widget.onOutsidePointer?.call();
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    _controller.setPointerWorld(_toWorld(event.localPosition));
    if (_pointers.length >= 2) {
      _beginPinch();
      return;
    }

    final world = _toWorld(event.localPosition);
    _startWorld = world;

    // 中键 / 空格 / 抓手：平移
    final middleButton = event.buttons & kMiddleMouseButton != 0;
    if (middleButton || _controller.tool == ToolKind.hand || _spacePressed) {
      _mode = _DragMode.pan;
      return;
    }

    switch (_controller.tool) {
      case ToolKind.pen:
        _controller.beginGesture();
        _mode = _DragMode.draw;
        _drawPoints = <Offset>[world];
        _smoothedPressure = 1;
        _drawPressures = <double>[
          _pressureOf(event, world, first: true),
        ];
        _lastSampleTime = event.timeStamp;
        _lastSampleWorld = world;
        _preview = _controller.createStroke(_drawPoints, pressures: _drawPressures);
        setState(() {});
        return;
      case ToolKind.eraser:
        _controller.beginGesture();
        _mode = _DragMode.erase;
        _eraseAt(world);
        return;
      case ToolKind.text:
        final element = _controller.createText(_snap(world));
        _controller.addElement(element);
        widget.onEditText(element);
        _mode = _DragMode.none;
        return;
      case ToolKind.note:
        final note = _controller.createNote(_snap(world));
        _controller.addElement(note);
        widget.onEditText(note);
        _mode = _DragMode.none;
        return;
      case ToolKind.rectangle:
      case ToolKind.ellipse:
      case ToolKind.diamond:
      case ToolKind.arrow:
      case ToolKind.line:
        _controller.beginGesture();
        _mode = _DragMode.create;
        _preview = _controller.createShape(_controller.tool, world, world);
        setState(() {});
        return;
      case ToolKind.hand:
        // 抓手在更上面已经处理过，这里补一个分支只是为了 switch 穷尽。
        _mode = _DragMode.pan;
        return;
      case ToolKind.select:
        _beginSelect(world, event.localPosition);
        return;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (widget.ignorePointers) {
      widget.onOutsidePointer?.call();
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    _controller.setPointerWorld(_toWorld(event.localPosition));

    if (_mode == _DragMode.pinch) {
      _updatePinch();
      return;
    }
    if (_pointers.length >= 2) {
      _beginPinch();
      return;
    }

    final world = _toWorld(event.localPosition);
    switch (_mode) {
      case _DragMode.pan:
        _viewport.panByScreen(event.delta);
      case _DragMode.draw:
        final last = _drawPoints.isEmpty ? null : _drawPoints.last;
        // 采样去重：指针静止时仍会持续上报，全部收下会让点数暴涨，
        // 撤销一步要重绘几千个点。
        if (last == null || (world - last).distance > 1.2 / _viewport.zoom) {
          _drawPoints = <Offset>[..._drawPoints, world];
          _drawPressures = <double>[..._drawPressures, _pressureOf(event, world)];
          _lastSampleTime = event.timeStamp;
          _lastSampleWorld = world;
          _preview = _controller.createStroke(
            _drawPoints,
            pressures: _drawPressures,
          );
          setState(() {});
        }
      case _DragMode.erase:
        _eraseAt(world);
      case _DragMode.move:
        final raw = world - _startWorld;
        final snap = _controller.snapSelection(_moveStartBounds.shift(raw));
        _controller.updateLive(_withSelectionShifted(raw + snap.delta));
      case _DragMode.resize:
        _resizeTo(world);
      case _DragMode.rotate:
        _rotateTo(world);
      case _DragMode.create:
        _preview = _controller.createShape(
          _controller.tool,
          _startWorld,
          world,
          constrain: _shiftPressed,
        );
        setState(() {});
      case _DragMode.marquee:
        setState(() {
          _marquee = Rect.fromPoints(
            _viewport.toScreen(_startWorld),
            _viewport.toScreen(world),
          );
        });
      case _DragMode.none:
      case _DragMode.pinch:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_mode == _DragMode.pinch) {
      if (_pointers.isEmpty) _mode = _DragMode.none;
      return;
    }

    switch (_mode) {
      case _DragMode.draw:
        final points = _drawPoints;
        final pressures = _drawPressures;
        _drawPoints = <Offset>[];
        _drawPressures = <double>[];
        _preview = null;
        if (points.isNotEmpty) {
          final stroke = _controller.createStroke(points, pressures: pressures);
          _controller.addElement(stroke, select: false, record: false);
        }
        _controller.endGesture();
      case _DragMode.erase:
        _controller.endGesture();
      case _DragMode.move:
      case _DragMode.resize:
      case _DragMode.rotate:
        _controller.endGesture();
      case _DragMode.create:
        if (_preview != null) {
          final created = _preview!;
          _preview = null;
          _controller.addElement(created, record: false);
          _controller.endGesture();
          // 不自动切回选择工具：连着画三个矩形是白板里最常见的操作，
          // 每画一个都要重新点一次工具会很烦。按 Esc / V 切回选择。
          _controller.selectOnly(created.id);
        }
      case _DragMode.marquee:
        _applyMarquee();
      case _DragMode.pan:
      case _DragMode.none:
      case _DragMode.pinch:
        break;
    }
    _mode = _DragMode.none;
    _handle = null;
    _controller.clearGuides();
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_mode == _DragMode.draw ||
        _mode == _DragMode.move ||
        _mode == _DragMode.resize ||
        _mode == _DragMode.rotate ||
        _mode == _DragMode.erase) {
      _controller.cancelGesture();
    }
    _mode = _DragMode.none;
    _preview = null;
    _drawPoints = <Offset>[];
    _drawPressures = <double>[];
    _controller.clearGuides();
    setState(() {});
  }

  // ── 选择 / 变换 ────────────────────────────────────────────────────────────

  void _beginSelect(Offset world, Offset local) {
    final single = _controller.singleSelected;
    final bounds = single?.frame ?? _controller.selectionBounds;
    if (bounds != null) {
      final handle = _hitHandle(local, bounds);
      if (handle != null) {
        _handle = handle;
        _startBounds = bounds;
        _baseline = _controller.elements;
        _startById = {for (final e in _controller.selectedElements) e.id: e};
        if (handle == 8) {
          final single = _controller.singleSelected;
          _rotateCenter = bounds.center;
          _startRotation = single?.rotation ?? 0;
          _startAngle = math.atan2(world.dy - bounds.center.dy, world.dx - bounds.center.dx);
          _mode = _DragMode.rotate;
        } else {
          _mode = _DragMode.resize;
        }
        _controller.beginGesture();
        return;
      }
    }

    // 容差按屏幕像素折算：放大到 400% 时 4 个世界单位只有 1 像素，
    // 线条会变得「点不中」。
    final hit = _controller.hitTest(world, tolerance: 4 / _viewport.zoom + 1);
    if (hit != null) {
      if (_shiftPressed) {
        _controller.toggleSelection(hit.id);
      } else if (!_controller.selection.contains(hit.id)) {
        _controller.selectOnly(hit.id);
      }
      final now = DateTime.now();
      final isDoubleTap = _lastTapAt != null &&
          now.difference(_lastTapAt!) < const Duration(milliseconds: 350) &&
          _lastTapPosition != null &&
          (_lastTapPosition! - local).distance < 8;
      _lastTapAt = now;
      _lastTapPosition = local;

      if (isDoubleTap && (hit is TextElement || hit is NoteElement)) {
        widget.onEditText(hit);
        _mode = _DragMode.none;
        return;
      }

      _baseline = _controller.elements;
      _startById = {for (final e in _controller.selectedElements) e.id: e};
      if (_startById.isEmpty) {
        _mode = _DragMode.none;
        return;
      }
      _moveStartBounds = _controller.selectionBounds ?? Rect.zero;
      _controller.beginGesture();
      _mode = _DragMode.move;
      return;
    }

    _lastTapAt = null;
    if (!_shiftPressed) _controller.clearSelection();
    _mode = _DragMode.marquee;
    _marquee = Rect.fromPoints(_viewport.toScreen(world), _viewport.toScreen(world));
    setState(() {});
  }

  /// 返回命中的控制点索引，8 表示旋转手柄。
  int? _hitHandle(Offset local, Rect bounds) {
    final rotation = _controller.singleSelected?.rotation ?? 0;
    final screenBounds = _viewport.rectToScreen(bounds);
    final handles = _handleScreenPositions(screenBounds, rotation);
    for (var i = 0; i < handles.length; i++) {
      if ((handles[i] - local).distance <= _handleRadius + 5) return i;
    }
    // 旋转手柄：单选时在上方中点之外。
    if (_controller.singleSelected != null) {
      final top = handles[4];
      final direction = Offset(math.sin(rotation), -math.cos(rotation));
      final rotateAt = top + direction * _rotateHandleDistance;
      if ((rotateAt - local).distance <= _handleRadius + 6) return 8;
    }
    return null;
  }

  List<Offset> _handleScreenPositions(Rect screenBounds, double rotation) {
    final center = screenBounds.center;
    final halfW = screenBounds.width / 2;
    final halfH = screenBounds.height / 2;
    final local = <Offset>[
      Offset(-halfW, -halfH),
      Offset(halfW, -halfH),
      Offset(halfW, halfH),
      Offset(-halfW, halfH),
      Offset(0, -halfH),
      Offset(halfW, 0),
      Offset(0, halfH),
      Offset(-halfW, 0),
    ];
    return local
        .map((p) => center + Offset(
              p.dx * math.cos(rotation) - p.dy * math.sin(rotation),
              p.dx * math.sin(rotation) + p.dy * math.cos(rotation),
            ))
        .toList(growable: false);
  }

  void _resizeTo(Offset world) {
    final handle = _handle;
    if (handle == null || _startBounds.isEmpty) return;

    final rotation = _controller.singleSelected?.rotation ?? 0;
    // 把指针转回「未旋转」的坐标系，这样后面的边调整和普通矩形完全一致。
    final anchorCenter = _startBounds.center;
    final localPointer = rotation == 0
        ? world
        : rotatePoint(world, anchorCenter, -rotation);

    var left = _startBounds.left;
    var top = _startBounds.top;
    var right = _startBounds.right;
    var bottom = _startBounds.bottom;

    switch (handle) {
      case 0:
        left = localPointer.dx;
        top = localPointer.dy;
      case 1:
        right = localPointer.dx;
        top = localPointer.dy;
      case 2:
        right = localPointer.dx;
        bottom = localPointer.dy;
      case 3:
        left = localPointer.dx;
        bottom = localPointer.dy;
      case 4:
        top = localPointer.dy;
      case 5:
        right = localPointer.dx;
      case 6:
        bottom = localPointer.dy;
      case 7:
        left = localPointer.dx;
    }

    if (left > right) {
      final tmp = left;
      left = right;
      right = tmp;
    }
    if (top > bottom) {
      final tmp = top;
      top = bottom;
      bottom = tmp;
    }
    if (right - left < 2) right = left + 2;
    if (bottom - top < 2) bottom = top + 2;

    var next = Rect.fromLTRB(left, top, right, bottom);

    // 缩放的吸附只作用于被拖动的那几条边：拖右边时把右边缘往目标的竖线上
    // 推，左边（锚点）必须钉死。如果把整个框平移，用户会觉得「拖一点，对
    // 面那条边也跑了」。旋转过的框不吸附 —— 世界坐标里的「右边」在局部
    // 坐标里不是一个方向，代价大于收益。
    if (rotation == 0) {
      final edges = <SnapEdge>{
        if (handle == 0 || handle == 3 || handle == 7) SnapEdge.left,
        if (handle == 1 || handle == 2 || handle == 5) SnapEdge.right,
        if (handle == 0 || handle == 1 || handle == 4) SnapEdge.top,
        if (handle == 2 || handle == 3 || handle == 6) SnapEdge.bottom,
      };
      final snap = _controller.snapSelection(next, edges: edges);
      if (snap.delta != Offset.zero) {
        final snapped = Rect.fromLTRB(
          edges.contains(SnapEdge.left) ? next.left + snap.delta.dx : next.left,
          edges.contains(SnapEdge.top) ? next.top + snap.delta.dy : next.top,
          edges.contains(SnapEdge.right) ? next.right + snap.delta.dx : next.right,
          edges.contains(SnapEdge.bottom) ? next.bottom + snap.delta.dy : next.bottom,
        );
        // 吸附不该把框压成负数宽度；真到了这一步说明两个目标线离得太近，
        // 放弃吸附比画出一个翻转的框好。
        if (snapped.width >= 2 && snapped.height >= 2) next = snapped;
      }
    }

    // 旋转元素：新框的中心变了，绕新中心旋转会把锚点甩出去。按对角锚点
    // 反算一次平移，用户的感受才是「拖哪个角，对角就钉在原地」。
    if (rotation != 0) {
      final anchorIndex = _oppositeCorner(handle);
      final oldAnchor = _cornerOf(_startBounds, anchorIndex);
      final newAnchor = _cornerOf(next, anchorIndex);
      final worldOld = rotatePoint(oldAnchor, _startBounds.center, rotation);
      final worldNew = rotatePoint(newAnchor, next.center, rotation);
      next = next.shift(worldOld - worldNew);
    }

    if (_startById.length == 1) {
      final element = _startById.values.first;
      final updated = element.resized(next);
      _controller.updateLive(
        _baseline.map((e) => e.id == element.id ? updated : e).toList(growable: false),
      );
    } else {
      _resizeGroup(next);
    }
  }

  void _resizeGroup(Rect next) {
    final old = _startBounds;
    if (old.width <= 0 || old.height <= 0) return;
    final sx = next.width / old.width;
    final sy = next.height / old.height;
    final updated = <WbElement>[];
    for (final element in _baseline) {
      final start = _startById[element.id];
      if (start == null) {
        updated.add(element);
        continue;
      }
      final startBounds = start.worldBounds;
      final center = Offset(
        next.left + (startBounds.center.dx - old.left) * sx,
        next.top + (startBounds.center.dy - old.top) * sy,
      );
      final resized = start.resized(Rect.fromLTWH(
        start.frame.left,
        start.frame.top,
        math.max(start.frame.width * sx, 2),
        math.max(start.frame.height * sy, 2),
      ));
      updated.add(resized.copyWith(
        frame: Rect.fromCenter(
          center: center,
          width: math.max(resized.frame.width, 2),
          height: math.max(resized.frame.height, 2),
        ),
      ));
    }
    _controller.updateLive(updated);
  }

  void _rotateTo(Offset world) {
    final single = _controller.singleSelected;
    if (single == null) return;
    final angle = math.atan2(
      world.dy - _rotateCenter.dy,
      world.dx - _rotateCenter.dx,
    );
    var next = _startRotation + (angle - _startAngle);
    if (_shiftPressed) {
      const step = math.pi / 12; // 15°
      next = (next / step).round() * step;
    }
    _controller.updateLive(
      _baseline
          .map((e) => e.id == single.id ? e.copyWith(rotation: next) : e)
          .toList(growable: false),
    );
  }

  int _oppositeCorner(int handle) => switch (handle) {
        0 => 2,
        1 => 3,
        2 => 0,
        3 => 1,
        4 => 6,
        5 => 7,
        6 => 4,
        7 => 5,
        _ => 2,
      };

  Offset _cornerOf(Rect rect, int index) => switch (index) {
        0 => rect.topLeft,
        1 => rect.topRight,
        2 => rect.bottomRight,
        3 => rect.bottomLeft,
        4 => Offset(rect.center.dx, rect.top),
        5 => Offset(rect.right, rect.center.dy),
        6 => Offset(rect.center.dx, rect.bottom),
        _ => Offset(rect.left, rect.center.dy),
      };

  void _applyMarquee() {
    final rect = _marquee;
    _marquee = null;
    if (rect == null) return;
    final world = _viewport.rectToWorld(rect);
    if (world.width < 2 && world.height < 2) return;
    final hits = _controller.hitTestRect(world);
    _controller.selectMany(hits.map((e) => e.id));
  }

  // ── 橡皮 / 双指 ────────────────────────────────────────────────────────────

  void _eraseAt(Offset world) {
    final hit = _controller.hitTest(
      world,
      tolerance: 2 / _viewport.zoom + 1,
      loose: false,
    );
    if (hit == null) return;
    _controller.updateLive(
      _controller.elements.where((e) => e.id != hit.id).toList(growable: false),
    );
    ImageRegistry.evict(hit.id);
  }

  void _beginPinch() {
    if (_pointers.length < 2) return;
    if (_mode != _DragMode.pinch) {
      // 从画笔/拖拽切到双指时，先把已经开始的操作收尾，避免留下半条线。
      if (_mode == _DragMode.draw) {
        _drawPoints = <Offset>[];
        _preview = null;
        _controller.cancelGesture();
      }
      _mode = _DragMode.pinch;
      final points = _pointers.values.take(2).toList(growable: false);
      final center = (points[0] + points[1]) / 2;
      _pinchStartDistance = math.max((points[0] - points[1]).distance, 1);
      _pinchStartZoom = _viewport.zoom;
      _pinchAnchorWorld = _viewport.toWorld(center);
    }
  }

  void _updatePinch() {
    if (_pointers.length < 2) return;
    final points = _pointers.values.take(2).toList(growable: false);
    final distance = math.max((points[0] - points[1]).distance, 1);
    final center = (points[0] + points[1]) / 2;
    final nextZoom = (_pinchStartZoom * (distance / _pinchStartDistance))
        .clamp(Viewport.minZoom, Viewport.maxZoom)
        .toDouble();
    // 手算 pan 而不是调 setZoom：setZoom 每次从「当前」状态推进，连续调用会
    // 把缩放因子叠乘，双指一抖画面就飞出去了。
    _viewport.restore(_pinchAnchorWorld - center / nextZoom, nextZoom);
  }

  // ── 滚轮 / 触控板 ──────────────────────────────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (widget.ignorePointers) return;
    if (event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    final zoomModifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (zoomModifier) {
      final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      _viewport.zoomAt(event.localPosition, factor);
    } else if (keyboard.isShiftPressed) {
      _viewport.panByScreen(Offset(event.scrollDelta.dy, 0));
    } else {
      _viewport.panByScreen(-event.scrollDelta);
    }
  }

  double _lastPanZoomScale = 1;

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _lastPanZoomScale = 1;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.panDelta != Offset.zero) {
      _viewport.panByScreen(event.panDelta);
    }
    if (event.scale != _lastPanZoomScale) {
      final factor = event.scale / _lastPanZoomScale;
      _lastPanZoomScale = event.scale;
      _viewport.zoomAt(event.localPosition, factor);
    }
  }

  // ── 其他 ───────────────────────────────────────────────────────────────────

  Offset _snap(Offset world) {
    if (!_controller.snapToGrid) return world;
    final grid = _controller.gridSize;
    return Offset(
      (world.dx / grid).round() * grid,
      (world.dy / grid).round() * grid,
    );
  }

  MouseCursor get _cursor {
    if (_spacePressed || _controller.tool == ToolKind.hand) {
      return _mode == _DragMode.pan
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab;
    }
    return switch (_controller.tool) {
      ToolKind.select => SystemMouseCursors.basic,
      ToolKind.pen || ToolKind.eraser => SystemMouseCursors.precise,
      _ => SystemMouseCursors.precise,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (!size.isEmpty && size != _controller.viewport.size) {
          // 只在尺寸真的变了才注册：无条件注册会让「帧结束→setSize→通知→
          // 重建→再注册」形成永不停歇的帧循环，空转 CPU。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _controller.viewport.setSize(size);
          });
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          child: MouseRegion(
            cursor: _cursor,
            onHover: (event) => _controller.setPointerWorld(
              _viewport.toWorld(event.localPosition),
            ),
            child: ClipRect(
              child: CustomPaint(
                painter: ScenePainter(
                  controller: _controller,
                  preview: _preview,
                  marquee: _marquee,
                  // 底色来自文档，不是主题：同一份 .wbpro 换台机器、换个系统
                  // 主题，看到的必须是同一张图。
                  background: _controller.canvasColor,
                  gridColor: gridOnCanvas(_controller.canvasColor),
                  selectionColor: WbTheme.accent,
                  onImageReady: () {
                    if (mounted) setState(() {});
                  },
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 场景绘制器。
///
/// 分两遍画：世界坐标下的元素（随缩放），屏幕坐标下的选择框与控制点（不随
/// 缩放）。控制点如果跟着缩放，放大到 400% 时会变成西瓜那么大。
class ScenePainter extends CustomPainter {
  ScenePainter({
    required this.controller,
    required this.background,
    required this.gridColor,
    required this.selectionColor,
    this.preview,
    this.marquee,
    this.onImageReady,
  }) : super(repaint: controller);

  final EditorController controller;
  final Color background;
  final Color gridColor;
  final Color selectionColor;
  final WbElement? preview;
  final Rect? marquee;
  final VoidCallback? onImageReady;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = controller.viewport;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    if (controller.showGrid) {
      canvas.save();
      canvas.scale(viewport.zoom);
      canvas.translate(-viewport.pan.dx, -viewport.pan.dy);
      paintGrid(
        canvas,
        viewport.visibleWorld,
        viewport.zoom,
        spacing: controller.gridSize,
        color: gridColor,
      );
      canvas.restore();
    }

    canvas.save();
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.pan.dx, -viewport.pan.dy);
    for (final element in controller.elements) {
      if (element is ImageElement && element.visible) {
        ImageRegistry.ensure(element, onImageReady ?? () {});
      }
    }
    paintScene(canvas, controller.elements, viewport.visibleWorld);
    final ghost = preview;
    if (ghost != null) {
      paintElement(canvas, ghost);
    }
    canvas.restore();

    _paintSelection(canvas, viewport);
    // 参考线画在选中框之上：吸附发生时，被对齐的那条边往往正好被选中框
    // 压着，画在下面等于没画。
    _paintGuides(canvas, viewport);
    _paintMarquee(canvas);
  }

  /// 对齐参考线。画在屏幕坐标里：1 物理像素的细线，不跟着缩放变粗。
  void _paintGuides(Canvas canvas, Viewport viewport) {
    final guides = controller.activeGuides;
    if (guides.isEmpty) return;
    final paint = Paint()
      ..color = _kGuideColor
      ..strokeWidth = 1.4
      ..isAntiAlias = true;
    for (final guide in guides) {
      final a = guide.vertical
          ? Offset(guide.position, guide.from)
          : Offset(guide.from, guide.position);
      final b = guide.vertical
          ? Offset(guide.position, guide.to)
          : Offset(guide.to, guide.position);
      canvas.drawLine(viewport.toScreen(a), viewport.toScreen(b), paint);
    }
  }

  void _paintSelection(Canvas canvas, Viewport viewport) {
    final selection = controller.selection;
    if (selection.isEmpty) return;
    final selected = controller.selectedElements;
    if (selected.isEmpty) return;

    // 每个选中元素都描一圈细线，多选时能看清具体选了哪些。
    if (selected.length > 1) {
      final thin = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = selectionColor.withValues(alpha: 0.55);
      for (final element in selected) {
        final corners = cornersOf(element.frame, element.rotation);
        final path = Path()..addPolygon(
            corners.map(viewport.toScreen).toList(growable: false),
            true,
          );
        canvas.drawPath(path, thin);
      }
    }

    final single = controller.singleSelected;
    final bounds = single?.frame ?? controller.selectionBounds;
    if (bounds == null) return;
    final rotation = single?.rotation ?? 0;
    final screen = viewport.rectToScreen(bounds);
    final center = screen.center;
    final corners = <Offset>[
      Offset(-screen.width / 2, -screen.height / 2),
      Offset(screen.width / 2, -screen.height / 2),
      Offset(screen.width / 2, screen.height / 2),
      Offset(-screen.width / 2, screen.height / 2),
    ]
        .map((p) => center +
            Offset(
              p.dx * math.cos(rotation) - p.dy * math.sin(rotation),
              p.dx * math.sin(rotation) + p.dy * math.cos(rotation),
            ))
        .toList(growable: false);

    // 框线先垫一道「比底色更极端」的线，再压彩色。白板上任何颜色都可能
    // 出现，选中一个深色形状时单根细线会陷进去；浅底垫白、深底垫黑之后，
    // 绿线在两种底色上都立得住。
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = haloOnCanvas(background);
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = selectionColor;
    final framePath = Path()..addPolygon(corners, true);
    canvas.drawPath(framePath, haloPaint);
    canvas.drawPath(framePath, framePaint);

    final handles = <Offset>[
      corners[0],
      corners[1],
      corners[2],
      corners[3],
      (corners[0] + corners[1]) / 2,
      (corners[1] + corners[2]) / 2,
      (corners[2] + corners[3]) / 2,
      (corners[3] + corners[0]) / 2,
    ];

    if (controller.singleSelected != null) {
      final top = handles[4];
      final direction = Offset(math.sin(rotation), -math.cos(rotation));
      final rotateAt = top + direction * _rotateHandleDistance;
      canvas.drawLine(top, rotateAt, framePaint);
      canvas.drawCircle(rotateAt, _handleRadius, Paint()..color = Colors.white);
      canvas.drawCircle(
        rotateAt,
        _handleRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = selectionColor,
      );
    }

    for (final handle in handles) {
      canvas.drawCircle(handle, _handleRadius, Paint()..color = Colors.white);
      canvas.drawCircle(
        handle,
        _handleRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = selectionColor,
      );
    }
  }

  void _paintMarquee(Canvas canvas) {
    final rect = marquee;
    if (rect == null) return;
    canvas.drawRect(
      rect,
      Paint()..color = selectionColor.withValues(alpha: 0.08),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = selectionColor.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(ScenePainter oldDelegate) =>
      oldDelegate.preview != preview ||
      oldDelegate.marquee != marquee ||
      oldDelegate.background != background ||
      oldDelegate.controller != controller;
}
