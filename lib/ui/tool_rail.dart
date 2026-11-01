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
      label: '画笔',
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

/// 底部居中的一条工具条。
///
/// 桌面端也不放左侧竖排：竖排会吃掉 52px 的画布宽度，而它只是一排图标。
/// 横条压在画布下沿，鼠标移动距离更短，窄屏也不用来回换布局。
class ToolRail extends StatefulWidget {
  const ToolRail({
    super.key,
    required this.controller,
    required this.onImportImage,
    this.onOpenInspector,
    this.inspectorOpen = false,
  });

  final EditorController controller;
  final VoidCallback onImportImage;

  /// 非空时在末尾追加「样式」按钮。
  final VoidCallback? onOpenInspector;
  final bool inspectorOpen;

  @override
  State<ToolRail> createState() => _ToolRailState();
}

class _ToolRailState extends State<ToolRail> {
  final ScrollController _scroll = ScrollController();

  bool _atStart = true;

  /// 先假设「右边还有东西」，布局完再校正。反过来会让首帧直接走「两端都
  /// 贴边」的捷径，之后再想变成渐隐就得等一次完整重建。
  bool _atEnd = false;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncEdges);
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncEdges);
    _scroll.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final atStart = position.pixels <= 2;
    final atEnd = position.pixels >= position.maxScrollExtent - 2;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  /// 首帧拿不到 maxScrollExtent，布局完再量一次。
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _syncEdges();
    });
  }

  List<Widget> _items(BuildContext context) {
    final children = <Widget>[];
    var lastGroup = -1;
    for (final tool in kTools) {
      if (lastGroup != -1 && tool.group != lastGroup) {
        children.add(_separator(context));
      }
      lastGroup = tool.group;
      children.add(
        WbToolButton(
          icon: tool.icon,
          label: '${tool.label}  ${tool.shortcut}',
          selected: widget.controller.tool == tool.kind,
          onTap: () => widget.controller.setTool(tool.kind),
        ),
      );
    }
    children.add(_separator(context));
    children.add(
      WbToolButton(
        icon: Icons.image_outlined,
        label: '插入图片',
        selected: false,
        onTap: widget.onImportImage,
      ),
    );
    if (widget.onOpenInspector != null) {
      children.add(
        WbToolButton(
          icon: Icons.tune,
          label: '样式  Ctrl+Alt+P',
          selected: widget.inspectorOpen,
          onTap: widget.onOpenInspector!,
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSync();
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return WbFloatingBar(
          child: ConstrainedBox(
            // 内容超出就横向滚动，此时两端渐隐提示还有没看全的工具。
            constraints: const BoxConstraints(maxWidth: 620),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thickness: 2,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: _fadeEdges(
                  context,
                  Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _items(context)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 两端按滚动位置渐隐：贴边的一端不再淡出，否则首尾图标会一直发灰。
  ///
  /// 内容没溢出时 `_atStart && _atEnd` 成立，直接原样返回——不能按「初值
  /// 是 true」来判，那样在布局完成前会跳过渐隐，第一帧闪一下。
  Widget _fadeEdges(BuildContext context, Widget child) {
    if (!_scroll.hasClients || (_atStart && _atEnd)) return child;
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final clear = Colors.white.withValues(alpha: 0);
        return LinearGradient(
          colors: <Color>[
            _atStart ? Colors.white : clear,
            Colors.white,
            Colors.white,
            _atEnd ? Colors.white : clear,
          ],
          stops: const <double>[0, 0.05, 0.95, 1],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }

  Widget _separator(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        color: WbTheme.chromeHairline(context),
      );
}
