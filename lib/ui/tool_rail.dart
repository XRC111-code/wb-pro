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
///
/// 两处窄屏细节值得说明：工具一多就必然要滚动，而「能滚」这件事在触屏上
/// 完全没有提示，用户会以为只有眼前这几个工具。所以两端做了随滚动位置变化
/// 的渐隐，看到边缘被削掉一半的图标就知道还能滑。「样式」按钮则固定在最右，
/// 不参与滚动 —— 否则手机上想改颜色得先滑到底，路径太长。
class ToolRail extends StatefulWidget {
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
  State<ToolRail> createState() => _ToolRailState();
}

class _ToolRailState extends State<ToolRail> {
  final ScrollController _scroll = ScrollController();

  bool _atStart = true;

  /// 先假设「右边还有东西」，布局完再校正。
  ///
  /// 反过来（初始 true、量完再改）会让首帧直接走「两端都贴边」的捷径，
  /// 之后再想变成渐隐就得等一次完整重建；而首帧本来就在窗口还没显示时，
  /// 提前画一帧渐隐用户看不见，代价为零。
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
        children.add(_gap(context));
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
    children.add(_gap(context));
    children.add(
      WbToolButton(
        icon: Icons.image_outlined,
        label: '插入图片',
        selected: false,
        onTap: widget.onImportImage,
      ),
    );
    return children;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return widget.horizontal ? _horizontal(context) : _vertical(context);
      },
    );
  }

  Widget _horizontal(BuildContext context) {
    _scheduleSync();
    return Row(
      children: <Widget>[
        Expanded(
          // 常驻的细滚动条 + 两端渐隐，两个信号叠着用：滚动条说明「这里能滑」，
          // 渐隐说明「现在滑到哪一端」。只靠渐隐不够，内容边界正好落在按钮间隙时
          // 会被削得看不出来。
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            thickness: 2,
            radius: const Radius.circular(2),
            child: _fadeEdges(
              context,
              SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
                child: Row(children: _items(context)),
              ),
            ),
          ),
        ),
        if (widget.onOpenInspector != null) ...<Widget>[
          Container(width: 1, height: 26, color: WbTheme.hairline(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
            child: WbToolButton(
              icon: Icons.tune,
              label: '样式',
              selected: false,
              onTap: widget.onOpenInspector!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _vertical(BuildContext context) {
    _scheduleSync();
    final children = _items(context);
    if (widget.onOpenInspector != null) {
      children.add(_gap(context));
      children.add(
        WbToolButton(
          icon: Icons.tune,
          label: '样式',
          selected: false,
          onTap: widget.onOpenInspector!,
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      thickness: 2,
      radius: const Radius.circular(2),
      child: _fadeEdges(
        context,
        SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: children),
        ),
      ),
    );
  }

  /// 两端按滚动位置渐隐：贴边的一端不再淡出，否则首尾图标会一直发灰。
  Widget _fadeEdges(BuildContext context, Widget child) {
    // 还没 attach 到滚动视图时宽度未知，先按原样画，等量完再决定。
    if (!_scroll.hasClients || (_atStart && _atEnd)) return child;
    final horizontal = widget.horizontal;
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final clear = Colors.white.withValues(alpha: 0);
        return LinearGradient(
          begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
          end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
          colors: <Color>[
            _atStart ? Colors.white : clear,
            Colors.white,
            Colors.white,
            _atEnd ? Colors.white : clear,
          ],
          stops: const <double>[0, 0.06, 0.94, 1],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }

  Widget _gap(BuildContext context) => widget.horizontal
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
