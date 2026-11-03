import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../model/element.dart';
import '../state/editor_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// 左侧图层列表。
///
/// 只做三件事：看清「画面里有什么」、单独关掉某几样、钉住不该动的东西。
/// 层级调整留给菜单里的「置于顶层 / 底层」—— 在一个 220px 宽的浮层里做
/// 拖拽排序，命中区只有二十几像素，比按钮难用得多。
///
/// 列表是**倒序**的：最晚画的元素在最上面，和画布上的堆叠顺序一致。正序
/// 列表会让用户点第一行却选中了被压在最后面的东西。
class LayerPanel extends StatelessWidget {
  const LayerPanel({
    super.key,
    required this.controller,
    this.onClose,
  });

  final EditorController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final elements = controller.elements;
        final ordered = elements.reversed.toList(growable: false);
        return WbFloatingBar(
          child: SizedBox(
            width: 218,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(context, elements.length),
                if (elements.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
                    child: Text(
                      '还没有元素',
                      style: TextStyle(
                        fontSize: 12,
                        color: WbTheme.subtleText(context),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: ordered.length,
                      itemBuilder: (context, index) => _row(
                        context,
                        ordered[index],
                        elements.length - 1 - index,
                      ),
                    ),
                  ),
                if (controller.selection.isNotEmpty) _footer(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(
        children: <Widget>[
          Text(
            '图层',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: WbTheme.onChrome(context, alpha: 0.88),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 11, color: WbTheme.subtleText(context)),
          ),
          const Spacer(),
          if (onClose != null)
            WbIconButton(
              icon: Icons.close,
              tooltip: '收起图层面板',
              onPressed: onClose,
              size: 24,
              iconSize: 14,
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WbElement element, int index) {
    final selected = controller.selection.contains(element.id);
    final accent = WbTheme.activeColor(context);
    final dimmed = !element.visible;
    final ink = dimmed
        ? WbTheme.onChrome(context, alpha: 0.32)
        : WbTheme.onChrome(context, alpha: 0.88);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MiuixPressable(
        onPressed: () => controller.selectOnly(element.id),
        borderRadius: BorderRadius.circular(WbTheme.radiusSmall),
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 6, right: 2),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(WbTheme.radiusSmall),
          ),
          child: Row(
            children: <Widget>[
              MiuixIcon(icon: _iconOf(element), size: 14, tint: ink),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _labelOf(element),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: ink,
                    decoration: dimmed ? TextDecoration.lineThrough : null,
                    decorationColor: ink,
                  ),
                ),
              ),
              if (element.locked)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: MiuixIcon(
                    icon: Icons.lock_outline,
                    size: 13,
                    tint: WbTheme.onChrome(context, alpha: 0.55),
                  ),
                ),
              WbIconButton(
                icon: element.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                tooltip: element.visible ? '隐藏' : '显示',
                onPressed: () =>
                    controller.setElementVisible(element.id, !element.visible),
                size: 24,
                iconSize: 14,
                color: element.visible ? null : WbTheme.subtleText(context),
              ),
              WbIconButton(
                icon: element.locked ? Icons.lock : Icons.lock_open_outlined,
                tooltip: element.locked ? '解锁' : '锁定',
                onPressed: () =>
                    controller.setElementLocked(element.id, !element.locked),
                size: 24,
                iconSize: 14,
                active: element.locked,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: WbTheme.onChrome(context, alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          TextButton.icon(
            onPressed: controller.bringToFront,
            icon: const Icon(Icons.flip_to_front, size: 14),
            label: const Text('置顶', style: TextStyle(fontSize: 11.5)),
            style: _buttonStyle(context),
          ),
          TextButton.icon(
            onPressed: controller.sendToBack,
            icon: const Icon(Icons.flip_to_back, size: 14),
            label: const Text('置底', style: TextStyle(fontSize: 11.5)),
            style: _buttonStyle(context),
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle(BuildContext context) => TextButton.styleFrom(
        foregroundColor: WbTheme.onChrome(context, alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

IconData _iconOf(WbElement element) => switch (element) {
      StrokeElement _ => Icons.gesture,
      ShapeElement e => switch (e.shape) {
          ShapeKind.rectangle => Icons.crop_square,
          ShapeKind.ellipse => Icons.circle_outlined,
          ShapeKind.diamond => Icons.change_history,
        },
      ArrowElement e => e.endHead ? Icons.arrow_forward : Icons.horizontal_rule,
      TextElement _ => Icons.text_fields,
      NoteElement _ => Icons.sticky_note_2_outlined,
      ImageElement _ => Icons.image_outlined,
    };

/// 列表里显示的名字。文本和便签取内容前缀：一堆「文本」在列表里没法区分。
String _labelOf(WbElement element) {
  String clip(String value) {
    final one = value.replaceAll('\n', ' ').trim();
    if (one.isEmpty) return '空';
    return one.length <= 14 ? one : '${one.substring(0, 14)}…';
  }

  return switch (element) {
    StrokeElement _ => '手绘',
    ShapeElement e => switch (e.shape) {
        ShapeKind.rectangle => '矩形',
        ShapeKind.ellipse => '椭圆',
        ShapeKind.diamond => '菱形',
      },
    ArrowElement e => e.endHead ? '箭头' : '直线',
    TextElement e => clip(e.text),
    NoteElement e => '便签 · ${clip(e.text)}',
    ImageElement e => e.label.isEmpty ? '图片' : e.label,
  };
}
