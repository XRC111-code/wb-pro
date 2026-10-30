import 'package:flutter/material.dart';

import '../state/editor_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// 一个工具在工具栏里的描述。
class ToolDescriptor {
  const ToolDescriptor({
    required this.kind,
    required this.icon,
    required this.label,
    required this.shortcut,
    this.group = 0,
  });

  final ToolKind kind;
  final IconData icon;
  final String label;

  /// 单键快捷键，显示在 tooltip 里。
  final String shortcut;

  /// 分隔线分组：同一组内不画线。
  final int group;
}

const List<ToolDescriptor> kTools = <ToolDescriptor>[
  ToolDescriptor(kind: ToolKind.select, icon: Icons.near_me_outlined, label: '选择', shortcut: 'V'),
  ToolDescriptor(kind: ToolKind.hand, icon: Icons.pan_tool_outlined, label: '抓手', shortcut: 'H'),
  ToolDescriptor(kind: ToolKind.pen, icon: Icons.gesture, label: '画笔', shortcut: 'P', group: 1),
  ToolDescriptor(kind: ToolKind.eraser, icon: Icons.auto_fix_normal_outlined, label: '橡皮', shortcut: 'E', group: 1),
  ToolDescriptor(kind: ToolKind.rectangle, icon: Icons.crop_square, label: '矩形', shortcut: 'R', group: 2),
  ToolDescriptor(kind: ToolKind.ellipse, icon: Icons.circle_outlined, label: '椭圆', shortcut: 'O', group: 2),
  ToolDescriptor(kind: ToolKind.diamond, icon: Icons.change_history, label: '菱形', shortcut: 'D', group: 2),
  ToolDescriptor(kind: ToolKind.arrow, icon: Icons.arrow_right_alt, label: '箭头', shortcut: 'A', group: 2),
  ToolDescriptor(kind: ToolKind.line, icon: Icons.horizontal_rule, label: '直线', shortcut: 'L', group: 2),
  ToolDescriptor(kind: ToolKind.text, icon: Icons.title, label: '文本', shortcut: 'T', group: 3),
  ToolDescriptor(kind: ToolKind.note, icon: Icons.sticky_note_2_outlined, label: '便签', shortcut: 'N', group: 3),
];

/// 左侧竖排工具栏（移动端会横过来放到底部）。
class ToolRail extends StatelessWidget {
  const ToolRail({
    super.key,
    required this.controller,
    required this.onImportImage,
    this.onOpenInspector,
    this.horizontal = false,
  });

  final EditorController controller;
  final VoidCallback onImportImage;

  /// 非空时在末尾追加一个「样式」按钮（移动端没有常驻的属性面板）。
  final VoidCallback? onOpenInspector;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final children = <Widget>[];
        var lastGroup = -1;
        for (final tool in kTools) {
          if (lastGroup != -1 && tool.group != lastGroup) {
            children.add(_gap(context, horizontal));
          }
          lastGroup = tool.group;
          children.add(
            WbToolButton(
              icon: tool.icon,
              label: '${tool.label}  ${tool.shortcut}',
              selected: controller.tool == tool.kind,
              onTap: () => controller.setTool(tool.kind),
            ),
          );
        }
        children.add(_gap(context, horizontal));
        children.add(
          WbToolButton(
            icon: Icons.image_outlined,
            label: '插入图片',
            selected: false,
            onTap: onImportImage,
          ),
        );
        if (onOpenInspector != null) {
          children.add(_gap(context, horizontal));
          children.add(
            WbToolButton(
              icon: Icons.tune,
              label: '样式',
              selected: false,
              onTap: onOpenInspector!,
            ),
          );
        }

        if (horizontal) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: children),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: children),
        );
      },
    );
  }

  Widget _gap(BuildContext context, bool horizontal) => horizontal
      ? Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: WbTheme.hairline(context),
        )
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: 26,
            child: Divider(color: WbTheme.hairline(context), height: 1),
          ),
        );
}
