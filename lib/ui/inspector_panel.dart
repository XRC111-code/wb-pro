import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/element.dart';
import '../state/editor_controller.dart';
import 'theme.dart';
import 'widgets.dart';

Color? strokeColorOf(WbElement element) => switch (element) {
      StrokeElement e => e.color,
      ShapeElement e => e.stroke,
      ArrowElement e => e.stroke,
      TextElement e => e.color,
      NoteElement e => e.textColor,
      ImageElement _ => null,
    };

Color? fillColorOf(WbElement element) => switch (element) {
      ShapeElement e => e.fill,
      NoteElement e => e.fill,
      _ => null,
    };

double? strokeWidthOf(WbElement element) => switch (element) {
      StrokeElement e => e.strokeWidth,
      ShapeElement e => e.strokeWidth,
      ArrowElement e => e.strokeWidth,
      _ => null,
    };

StrokeStyle? strokeStyleOf(WbElement element) => switch (element) {
      ShapeElement e => e.strokeStyle,
      ArrowElement e => e.strokeStyle,
      _ => null,
    };

double? fontSizeOf(WbElement element) => switch (element) {
      TextElement e => e.fontSize,
      NoteElement e => e.fontSize,
      _ => null,
    };

double? cornerRadiusOf(WbElement element) => switch (element) {
      ShapeElement e when e.shape == ShapeKind.rectangle => e.cornerRadius,
      _ => null,
    };

/// 取第一个非空属性作为面板显示值。多选时元素属性可能各不相同，
/// 显示「第一个」比显示「混合」更可用 —— 用户改一下就会全部统一。
T? _firstOf<T>(List<WbElement> elements, T? Function(WbElement) read) {
  for (final element in elements) {
    final value = read(element);
    if (value != null) return value;
  }
  return null;
}

/// 右侧属性面板。
///
/// 面板永远显示同样的分区顺序，只把不适用的分区灰掉而不是藏起来：频繁改选
/// 时如果整块面板上下跳动，用户会找不到刚才那个滑块。
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({
    super.key,
    required this.controller,
    this.onClose,
    this.embedded = false,
  });

  final EditorController controller;
  final VoidCallback? onClose;

  /// 在底部弹层里时去掉自带的宽度和阴影。
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.selectedElements;
        final single = controller.singleSelected;
        final hasSelection = selected.isNotEmpty;
        final style = controller.style;

        bool anyOf(bool Function(WbElement) test) =>
            !hasSelection || selected.any(test);

        final showStroke = anyOf(
          (e) =>
              e is StrokeElement ||
              e is ShapeElement ||
              e is ArrowElement ||
              e is TextElement,
        );
        final showFill = anyOf((e) => e is ShapeElement);
        final showNote = hasSelection && anyOf((e) => e is NoteElement);
        final showWidth = anyOf(
          (e) => e is StrokeElement || e is ShapeElement || e is ArrowElement,
        );
        final showLineStyle = anyOf((e) => e is ShapeElement || e is ArrowElement);
        final showRadius = anyOf((e) => e is ShapeElement);
        final showFont = anyOf((e) => e is TextElement || e is NoteElement);

        final strokeColor = _firstOf(selected, strokeColorOf) ?? style.stroke;
        final fillColor = _firstOf(selected, fillColorOf) ?? style.fill;
        final strokeWidth = _firstOf(selected, strokeWidthOf) ?? style.strokeWidth;
        final lineStyle = _firstOf(selected, strokeStyleOf) ?? style.strokeStyle;
        final fontSize = _firstOf(selected, fontSizeOf) ?? style.fontSize;
        final cornerRadius = _firstOf(selected, cornerRadiusOf) ?? style.cornerRadius;
        final noteColor = _firstOf(selected, fillColorOf) ?? style.noteColor;
        final opacity = hasSelection ? selected.first.opacity : 1.0;

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(context, selected.length, hasSelection),
            _section(
              context,
              enabled: showStroke,
              title: '描边',
              child: WbColorGrid(
                colors: kStrokePalette,
                selected: strokeColor,
                onSelected: (color) {
                  if (color != null) controller.applyStyle(stroke: color);
                },
              ),
            ),
            _section(
              context,
              enabled: showFill,
              title: '填充',
              child: WbColorGrid(
                colors: kFillPalette,
                selected: fillColor,
                allowNone: true,
                noneLabel: '无填充',
                onSelected: (color) {
                  if (color == null) {
                    controller.applyStyle(clearFill: true);
                  } else {
                    controller.applyStyle(fill: color);
                  }
                },
              ),
            ),
            if (showNote)
              _section(
                context,
                enabled: true,
                title: '便签颜色',
                child: WbColorGrid(
                  colors: kNotePalette,
                  selected: noteColor,
                  onSelected: (color) {
                    if (color != null) controller.applyStyle(noteColor: color);
                  },
                ),
              ),
            _section(
              context,
              enabled: showWidth,
              title: '线宽',
              child: WbSliderRow(
                label: '粗细',
                value: strokeWidth,
                min: 1,
                max: 20,
                divisions: 19,
                formatter: (v) => v.toStringAsFixed(0),
                onChangeStart: (_) => controller.beginGesture(),
                onChangeEnd: (_) => controller.endGesture(),
                onChanged: (value) =>
                    controller.applyStyle(strokeWidth: value, record: false),
              ),
            ),
            _section(
              context,
              enabled: showLineStyle,
              title: '线型',
              child: WbSegmented<StrokeStyle>(
                value: lineStyle,
                onChanged: (value) => controller.applyStyle(strokeStyle: value),
                options: const <WbSegmentedOption<StrokeStyle>>[
                  WbSegmentedOption(StrokeStyle.solid, '实线'),
                  WbSegmentedOption(StrokeStyle.dashed, '虚线'),
                  WbSegmentedOption(StrokeStyle.dotted, '点线'),
                ],
              ),
            ),
            _section(
              context,
              enabled: showRadius,
              title: '圆角',
              child: WbSliderRow(
                label: '半径',
                value: cornerRadius,
                min: 0,
                max: 48,
                divisions: 24,
                formatter: (v) => v.toStringAsFixed(0),
                onChangeStart: (_) => controller.beginGesture(),
                onChangeEnd: (_) => controller.endGesture(),
                onChanged: (value) =>
                    controller.applyStyle(cornerRadius: value, record: false),
              ),
            ),
            _section(
              context,
              enabled: showFont,
              title: '字号',
              child: WbSliderRow(
                label: '大小',
                value: fontSize,
                min: 10,
                max: 96,
                divisions: 43,
                formatter: (v) => v.toStringAsFixed(0),
                onChangeStart: (_) => controller.beginGesture(),
                onChangeEnd: (_) => controller.endGesture(),
                onChanged: (value) =>
                    controller.applyStyle(fontSize: value, record: false),
              ),
            ),
            if (single is TextElement) _textStyleSection(context, single),
            if (hasSelection)
              _section(
                context,
                enabled: true,
                title: '不透明度',
                child: WbSliderRow(
                  label: '透明',
                  value: opacity * 100,
                  min: 5,
                  max: 100,
                  divisions: 19,
                  formatter: (v) => '${v.toStringAsFixed(0)}%',
                  onChangeStart: (_) => controller.beginGesture(),
                  onChangeEnd: (_) => controller.endGesture(),
                  onChanged: (value) => controller.setSelectionOpacity(
                    value / 100,
                    record: false,
                  ),
                ),
              ),
            if (single != null)
              _section(
                context,
                enabled: true,
                title: '旋转',
                child: WbSliderRow(
                  label: '角度',
                  value: single.rotation * 180 / math.pi,
                  min: -180,
                  max: 180,
                  divisions: 24,
                  formatter: (v) => '${v.toStringAsFixed(0)}°',
                  onChangeStart: (_) => controller.beginGesture(),
                  onChangeEnd: (_) => controller.endGesture(),
                  onChanged: (value) => controller.updateElement(
                    single.copyWith(rotation: value * math.pi / 180),
                    record: false,
                  ),
                ),
              ),
            if (hasSelection) _layerSection(context),
            if (selected.length >= 2) _alignSection(context),
            const SizedBox(height: 14),
          ],
        );

        if (embedded) {
          return SingleChildScrollView(child: body);
        }
        return SizedBox(
          width: WbTheme.inspectorWidth,
          child: WbPanel(
            child: Scrollbar(
              child: SingleChildScrollView(child: body),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, int count, bool hasSelection) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: <Widget>[
          Text(
            hasSelection ? '样式' : '默认样式',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          if (hasSelection)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: WbTheme.activeColor(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: WbTheme.activeColor(context),
                ),
              ),
            ),
          const Spacer(),
          if (onClose != null)
            WbIconButton(
              icon: Icons.close,
              tooltip: '收起',
              size: 28,
              iconSize: 16,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required bool enabled,
    required String title,
    required Widget child,
  }) {
    // 不适用的分区直接不渲染，而不是灰掉。
    //
    // 面板现在是浮层，高度有限：一个灰掉的「字号」要占掉七十多像素，正好把
    // 下面的对齐按钮挤出可视区。以前是常驻侧栏，高度管够，灰掉能保持布局
    // 稳定；现在稳定让位给「能不能一眼看全」。
    if (!enabled) return const SizedBox.shrink();
    return WbSection(title: title, child: child);
  }

  Widget _textStyleSection(BuildContext context, TextElement element) {
    return WbSection(
      title: '文本',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _toggle(
                context,
                icon: Icons.format_bold,
                active: element.bold,
                tooltip: '粗体',
                onTap: controller.toggleBold,
              ),
              const SizedBox(width: 4),
              _toggle(
                context,
                icon: Icons.format_italic,
                active: element.italic,
                tooltip: '斜体',
                onTap: controller.toggleItalic,
              ),
            ],
          ),
          const SizedBox(height: 8),
          WbSegmented<TextAlign>(
            value: element.align,
            onChanged: (value) => controller.updateElement(
              element.copyWith(align: value),
            ),
            options: const <WbSegmentedOption<TextAlign>>[
              WbSegmentedOption(TextAlign.left, '左'),
              WbSegmentedOption(TextAlign.center, '中'),
              WbSegmentedOption(TextAlign.right, '右'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    BuildContext context, {
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return WbIconButton(
      icon: icon,
      tooltip: tooltip,
      active: active,
      size: 32,
      iconSize: 17,
      onPressed: onTap,
    );
  }

  Widget _layerSection(BuildContext context) {
    return WbSection(
      title: '图层',
      child: Row(
        children: <Widget>[
          WbMiniButton(
            icon: Icons.flip_to_front,
            tooltip: '置顶  Ctrl+Shift+]',
            onPressed: controller.bringToFront,
          ),
          WbMiniButton(
            icon: Icons.arrow_upward,
            tooltip: '上移一层  Ctrl+]',
            onPressed: controller.bringForward,
          ),
          WbMiniButton(
            icon: Icons.arrow_downward,
            tooltip: '下移一层  Ctrl+[',
            onPressed: controller.sendBackward,
          ),
          WbMiniButton(
            icon: Icons.flip_to_back,
            tooltip: '置底  Ctrl+Shift+[',
            onPressed: controller.sendToBack,
          ),
        ],
      ),
    );
  }

  Widget _alignSection(BuildContext context) {
    return WbSection(
      title: '对齐',
      child: Wrap(
        spacing: 1,
        runSpacing: 1,
        children: <Widget>[
          WbMiniButton(
            icon: Icons.align_horizontal_left,
            tooltip: '左对齐',
            onPressed: () => controller.alignSelection(AlignKind.left),
          ),
          WbMiniButton(
            icon: Icons.align_horizontal_center,
            tooltip: '水平居中',
            onPressed: () => controller.alignSelection(AlignKind.centerX),
          ),
          WbMiniButton(
            icon: Icons.align_horizontal_right,
            tooltip: '右对齐',
            onPressed: () => controller.alignSelection(AlignKind.right),
          ),
          WbMiniButton(
            icon: Icons.align_vertical_top,
            tooltip: '顶对齐',
            onPressed: () => controller.alignSelection(AlignKind.top),
          ),
          WbMiniButton(
            icon: Icons.align_vertical_center,
            tooltip: '垂直居中',
            onPressed: () => controller.alignSelection(AlignKind.centerY),
          ),
          WbMiniButton(
            icon: Icons.align_vertical_bottom,
            tooltip: '底对齐',
            onPressed: () => controller.alignSelection(AlignKind.bottom),
          ),
          WbMiniButton(
            icon: Icons.horizontal_distribute,
            tooltip: '水平等距（至少 3 个）',
            onPressed: () => controller.alignSelection(AlignKind.distributeX),
          ),
          WbMiniButton(
            icon: Icons.vertical_distribute,
            tooltip: '垂直等距（至少 3 个）',
            onPressed: () => controller.alignSelection(AlignKind.distributeY),
          ),
        ],
      ),
    );
  }
}
