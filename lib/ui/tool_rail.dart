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
  ToolDescriptor(
      kind: ToolKind.select,
      icon: Icons.near_me_outlined,
      label: '选择',
      shortcut: 'V'),
  ToolDescriptor(
      kind: ToolKind.hand,
      icon: Icons.pan_tool_outlined,
      label: '抓手',
      shortcut: 'H'),
  ToolDescriptor(
      kind: ToolKind.pen,
      icon: Icons.gesture,
      label: '笔',
      shortcut: 'P',
      group: 1),
  ToolDescriptor(
      kind: ToolKind.eraser,
      icon: Icons.auto_fix_normal_outlined,
      label: '橡皮',
      shortcut: 'E',
      group: 1),
  ToolDescriptor(
      kind: ToolKind.rectangle,
      icon: Icons.crop_square,
      label: '矩形',
      shortcut: 'R',
      group: 2),
  ToolDescriptor(
      kind: ToolKind.ellipse,
      icon: Icons.circle_outlined,
      label: '椭圆',
      shortcut: 'O',
      group: 2),
  ToolDescriptor(
      kind: ToolKind.diamond,
      icon: Icons.change_history,
      label: '菱形',
      shortcut: 'D',
      group: 2),
  ToolDescriptor(
      kind: ToolKind.arrow,
      icon: Icons.arrow_right_alt,
      label: '箭头',
      shortcut: 'A',
      group: 2),
  ToolDescriptor(
      kind: ToolKind.line,
      icon: Icons.horizontal_rule,
      label: '直线',
      shortcut: 'L',
      group: 2),
  ToolDescriptor(
      kind: ToolKind.text,
      icon: Icons.title,
      label: '文本',
      shortcut: 'T',
      group: 3),
  ToolDescriptor(
      kind: ToolKind.note,
      icon: Icons.sticky_note_2_outlined,
      label: '便签',
      shortcut: 'N',
      group: 3),
];

/// 底部工具条：深色外壳 + 白色卡片组。
///
/// 布局照「快捷白板」：左边一组「菜单 / 保存」，中间一组绘图工具，右边一组
/// 「更多」。中间那组用 [Expanded] 居中，两侧各占自然宽度，窄屏时中间那组
/// 优先收缩而不是把两侧挤出去。
///
/// 和旧版的差别：以前是一条居中的浮条、只有图标；现在有深色外壳托底、
/// 卡片带文字标签。外壳是**界面**的颜色，不参与文档底色（见 canvas_style）。
class ToolRail extends StatefulWidget {
  const ToolRail({
    super.key,
    required this.controller,
    required this.onImportImage,
    this.onOpenInspector,
    this.inspectorOpen = false,
    this.onUndo,
    this.onClear,
    this.onMenu,
    this.onSave,
    this.onMore,
  });

  final EditorController controller;
  final VoidCallback onImportImage;

  /// 非空时在末尾追加「样式」按钮。
  final VoidCallback? onOpenInspector;
  final bool inspectorOpen;

  /// 撤销 / 清屏 / 菜单 / 保存 / 更多。为 null 时该卡片不出现。
  final VoidCallback? onUndo;
  final VoidCallback? onClear;
  final VoidCallback? onMenu;
  final VoidCallback? onSave;
  final VoidCallback? onMore;

  @override
  State<ToolRail> createState() => _ToolRailState();
}

class _ToolRailState extends State<ToolRail> {
  EditorController get controller => widget.controller;

  void _setTool(ToolKind kind) => controller.setTool(kind);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: WbTheme.inset,
            vertical: 10,
          ),
          color: WbTheme.shell,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _leftGroup(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _centerGroup(),
                  ),
                ),
              ),
              _rightGroup(),
            ],
          ),
        );
      },
    );
  }

  /// 左侧：菜单、保存。
  Widget _leftGroup() {
    final cards = <Widget>[
      if (widget.onMenu != null)
        WbToolCard(
          icon: Icons.menu,
          label: '菜单',
          selected: false,
          tooltip: '菜单',
          onTap: widget.onMenu,
        ),
      if (widget.onSave != null)
        WbToolCard(
          icon: Icons.save_outlined,
          label: '保存',
          selected: false,
          tooltip: '保存  Ctrl+S',
          onTap: widget.onSave,
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return WbToolCardGroup(children: cards);
  }

  /// 中间：当前选中的工具所在的那一组。
  ///
  /// 分组切换会改变底栏宽度，视觉上像底栏在「跳」。所以这里不按频率分组，
  /// 而是**始终展示全部工具**、超出才横向滚动——位置稳定比省宽更重要，
  /// 用户对「笔在第 3 格」是有肌肉记忆的。
  Widget _centerGroup() {
    final cards = <Widget>[
      for (final tool in kTools)
        WbToolCard(
          icon: tool.icon,
          label: tool.label,
          selected: controller.tool == tool.kind,
          tooltip: '${tool.label}  ${tool.shortcut}',
          onTap: () => _setTool(tool.kind),
        ),
    ];
    cards.add(WbToolCard(
      icon: Icons.image_outlined,
      label: '图片',
      selected: false,
      tooltip: '插入图片',
      onTap: widget.onImportImage,
    ));
    if (widget.onOpenInspector != null) {
      cards.add(WbToolCard(
        icon: Icons.tune,
        label: '样式',
        selected: widget.inspectorOpen,
        tooltip: '样式  Ctrl+Alt+P',
        onTap: widget.onOpenInspector,
      ));
    }
    return WbToolCardGroup(children: cards);
  }

  /// 右侧：撤销、清屏、更多。
  Widget _rightGroup() {
    final cards = <Widget>[
      if (widget.onUndo != null)
        WbToolCard(
          icon: Icons.undo,
          label: '撤销',
          selected: false,
          enabled: controller.canUndo,
          tooltip: '撤销  Ctrl+Z',
          onTap: widget.onUndo,
        ),
      if (widget.onClear != null)
        WbToolCard(
          icon: Icons.delete_outline,
          label: '清屏',
          selected: false,
          tooltip: '清空画布',
          onTap: widget.onClear,
        ),
      if (widget.onMore != null)
        WbToolCard(
          icon: Icons.more_horiz,
          label: '更多',
          selected: false,
          tooltip: '更多操作',
          onTap: widget.onMore,
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return WbToolCardGroup(children: cards);
  }
}
