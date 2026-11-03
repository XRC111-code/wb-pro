import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../state/editor_controller.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

/// 顶部两角：左边文档名，右边一组动作。
///
/// 没有顶栏条。一条 52px 高的实色横条会横贯整个画布上沿，看起来像给窗口
/// 戴了个帽子；改成两块各自独立的小浮层之后，画布从第一条像素就是画布。
class TopBar extends StatefulWidget {
  const TopBar({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
  });

  final EditorController controller;
  final WbActions actions;
  final bool compact;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  /// 菜单由 Material 的 [MenuAnchor] 承载：它自带键盘导航、屏幕内翻转和
  /// 级联子菜单。`PopupMenuButton` 在 768 高的窗口里放不下二十多项，
  /// 最后几项会直接落在屏幕外点不到。
  final MenuController _menu = MenuController();

  EditorController get controller => widget.controller;
  WbActions get actions => widget.actions;
  bool get compact => widget.compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          children: <Widget>[
            // 不要用 Flexible：它和后面的 Spacer 都是 flex:1，会平分剩余空间，
            // 结果动作栏被顶到画布中间。
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _titleBar(context),
            ),
            const Spacer(),
            const SizedBox(width: 8),
            _actionBar(context),
          ],
        );
      },
    );
  }

  Widget _titleBar(BuildContext context) {
    final dirty = controller.dirty;
    return WbFloatingBar(
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
      // 高度和右边的动作栏对齐：两块浮层同高，顶边才在一条线上。
      child: SizedBox(
        height: 36,
        child: MiuixPressable(
          onPressed: actions.renameDocument,
          borderRadius: BorderRadius.circular(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  controller.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: WbTheme.onChrome(context),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              // 未保存是一个实心点，已保存是一个极淡的勾。两个都用彩色会抢戏，
              // 但完全没有标记的话，用户不知道关窗口会不会丢东西。
              if (dirty)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: WbTheme.activeColor(context),
                    shape: BoxShape.circle,
                  ),
                )
              else
                Icon(
                  Icons.check,
                  size: 12,
                  color: WbTheme.onChrome(context, alpha: 0.30),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    return WbFloatingBar(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WbIconButton(
            icon: Icons.undo,
            tooltip: '撤销  Ctrl+Z',
            onPressed: controller.canUndo ? actions.undo : null,
          ),
          WbIconButton(
            icon: Icons.redo,
            tooltip: '重做  Ctrl+Shift+Z',
            onPressed: controller.canRedo ? actions.redo : null,
          ),
          if (!compact) ...<Widget>[
            _separator(context),
            WbIconButton(
              icon: Icons.save_outlined,
              tooltip: '保存  Ctrl+S',
              onPressed: actions.save,
              active: controller.dirty,
            ),
            WbIconButton(
              icon: Icons.ios_share,
              tooltip: '导出 / 导入',
              onPressed: () => _showExportSheet(context),
            ),
          ],
          _separator(context),
          _buildMenu(context),
        ],
      ),
    );
  }

  Widget _separator(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: WbTheme.chromeHairline(context),
      );

  Widget _buildMenu(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      style: _menuStyle(context),
      // 和按钮下沿留 6px：菜单紧贴按钮时，第一项看起来像是按钮的一部分。
      alignmentOffset: const Offset(0, 6),
      menuChildren: _menuChildren(context),
      builder: (context, menuController, child) => WbIconButton(
        icon: Icons.menu,
        // 这里故意不挂 tooltip：点开菜单后鼠标正好停在这个按钮上，气泡会
        // 在 420ms 后弹出来压住菜单第一项。菜单图标本身不需要解释。
        tooltip: '',
        onPressed: () =>
            menuController.isOpen ? menuController.close() : menuController.open(),
      ),
    );
  }

  MenuStyle _menuStyle(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(WbTheme.panelColor(context)),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(10),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(238, 0)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      side: WidgetStatePropertyAll(BorderSide(
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.06),
      )),
    );
  }

  ButtonStyle _itemStyle(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      padding:
          const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      foregroundColor:
          WidgetStatePropertyAll(Theme.of(context).colorScheme.onSurface),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05);
        }
        return Colors.transparent;
      }),
    );
  }

  /// 一项菜单。动作执行完立刻收起菜单 —— 菜单里点「导出 PNG」之后菜单还
  /// 浮在文件对话框上面，是最容易漏掉的一步。
  Widget _menuButton(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
    String? shortcut,
    bool enabled = true,
    bool danger = false,
  }) {
    final subtle = WbTheme.subtleText(context);
    final color = !enabled
        ? subtle.withValues(alpha: 0.4)
        : (danger
            ? const Color(0xFFE03131)
            : Theme.of(context).colorScheme.onSurface);
    return MenuItemButton(
      onPressed: enabled
          ? () {
              _menu.close();
              _handleMenu(context, value);
            }
          : null,
      style: _itemStyle(context),
      leadingIcon: MiuixIcon(icon: icon, size: 16, tint: color),
      trailingIcon: shortcut == null
          ? null
          : Text(shortcut, style: TextStyle(fontSize: 11, color: subtle)),
      child: Text(label, style: TextStyle(fontSize: 13, color: color)),
    );
  }

  Widget _menuDivider(BuildContext context) => Divider(
        height: 9,
        thickness: 1,
        indent: 8,
        endIndent: 8,
        color: WbTheme.hairline(context),
      );

  void _handleMenu(BuildContext context, String value) {
    switch (value) {
      case 'new':
        actions.newDocument();
      case 'open':
        actions.openDocument();
      case 'save':
        actions.save();
      case 'saveAs':
        actions.saveAs();
      case 'png':
        actions.exportPng();
      case 'svg':
        actions.exportSvg();
      case 'image':
        actions.importImage();
      case 'rename':
        actions.renameDocument();
      case 'clear':
        actions.clearCanvas();
      case 'undo':
        actions.undo();
      case 'redo':
        actions.redo();
      case 'cut':
        actions.cutSelection();
      case 'copy':
        actions.copySelection();
      case 'paste':
        actions.paste();
      case 'duplicate':
        actions.duplicateSelection();
      case 'delete':
        actions.deleteSelection();
      case 'selectAll':
        actions.selectAll();
      case 'grid':
        actions.toggleGrid();
      case 'snap':
        actions.toggleSnap();
      case 'guides':
        actions.toggleGuides();
      case 'canvas':
        actions.chooseCanvasColor();
      case 'inspector':
        actions.toggleInspector();
      case 'layers':
        actions.toggleLayers();
      case 'theme':
        actions.toggleTheme();
      case 'shortcuts':
        actions.showShortcuts();
      case 'about':
        actions.showAbout();
    }
  }

  /// 菜单结构按「文件 / 编辑 / 视图与帮助」分三段。
  ///
  /// 视图相关的七项收进子菜单：主菜单二十多项在 768 高的窗口里会溢出，
  /// 最后几项落在屏幕外，鼠标够不到、键盘也得按好几次才滚动过去。
  List<Widget> _menuChildren(BuildContext context) {
    final hasSelection = controller.selection.isNotEmpty;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final subtle = WbTheme.subtleText(context);

    return <Widget>[
      _menuButton(context, value: 'new', icon: Icons.note_add_outlined, label: '新建', shortcut: 'Ctrl+N'),
      _menuButton(context, value: 'open', icon: Icons.folder_open_outlined, label: '打开…', shortcut: 'Ctrl+O'),
      _menuButton(context, value: 'save', icon: Icons.save_outlined, label: '保存', shortcut: 'Ctrl+S'),
      _menuButton(context, value: 'saveAs', icon: Icons.save_as_outlined, label: '另存为…', shortcut: 'Ctrl+Shift+S'),
      _menuDivider(context),
      _menuButton(context, value: 'png', icon: Icons.image_outlined, label: '导出 PNG…', shortcut: 'Ctrl+E'),
      _menuButton(context, value: 'svg', icon: Icons.timeline, label: '导出 SVG…'),
      _menuButton(context, value: 'image', icon: Icons.add_photo_alternate_outlined, label: '插入图片…'),
      _menuDivider(context),
      _menuButton(context, value: 'undo', icon: Icons.undo, label: '撤销', shortcut: 'Ctrl+Z', enabled: controller.canUndo),
      _menuButton(context, value: 'redo', icon: Icons.redo, label: '重做', shortcut: 'Ctrl+Shift+Z', enabled: controller.canRedo),
      _menuButton(context, value: 'cut', icon: Icons.content_cut, label: '剪切', shortcut: 'Ctrl+X', enabled: hasSelection),
      _menuButton(context, value: 'copy', icon: Icons.content_copy, label: '复制', shortcut: 'Ctrl+C', enabled: hasSelection),
      _menuButton(context, value: 'paste', icon: Icons.content_paste, label: '粘贴', shortcut: 'Ctrl+V'),
      _menuButton(context, value: 'duplicate', icon: Icons.copy_all_outlined, label: '创建副本', shortcut: 'Ctrl+D', enabled: hasSelection),
      _menuButton(context, value: 'delete', icon: Icons.delete_outline, label: '删除', shortcut: 'Del', enabled: hasSelection, danger: true),
      _menuButton(context, value: 'selectAll', icon: Icons.select_all, label: '全选', shortcut: 'Ctrl+A'),
      _menuDivider(context),
      SubmenuButton(
        style: _itemStyle(context),
        menuStyle: _menuStyle(context),
        leadingIcon: MiuixIcon(
          icon: Icons.tune,
          size: 16,
          tint: Theme.of(context).colorScheme.onSurface,
        ),
        trailingIcon: Icon(Icons.chevron_right, size: 15, color: subtle),
        menuChildren: <Widget>[
          _menuButton(
            context,
            value: 'grid',
            icon: Icons.grid_on,
            label: controller.showGrid ? '隐藏网格' : '显示网格',
            shortcut: 'Ctrl+G',
          ),
          _menuButton(
            context,
            value: 'snap',
            icon: Icons.straighten,
            label: controller.snapToGrid ? '关闭吸附' : '吸附到网格',
            shortcut: 'Ctrl+Shift+G',
          ),
          _menuButton(
            context,
            value: 'guides',
            icon: Icons.align_horizontal_left,
            label: controller.smartGuides ? '关闭智能参考线' : '开启智能参考线',
          ),
          _menuButton(
            context,
            value: 'canvas',
            icon: Icons.palette_outlined,
            label: '画布底色…',
          ),
          _menuButton(
            context,
            value: 'inspector',
            icon: Icons.view_sidebar_outlined,
            label: '属性面板',
            shortcut: 'Ctrl+Alt+P',
          ),
          _menuButton(
            context,
            value: 'layers',
            icon: Icons.layers_outlined,
            label: '图层面板',
            shortcut: 'Ctrl+Shift+L',
          ),
          _menuDivider(context),
          // 放大 / 缩小 / 实际大小 / 适应内容 不放进菜单：右下角一直摆着这几个
          // 按钮，菜单再列一遍只会把它顶到屏幕外面去。
          _menuButton(
            context,
            value: 'theme',
            icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            label: dark ? '浅色主题' : '深色主题',
          ),
          _menuButton(context, value: 'shortcuts', icon: Icons.keyboard_outlined, label: '快捷键', shortcut: '?'),
          _menuButton(context, value: 'about', icon: Icons.info_outline, label: '关于 wb-pro'),
        ],
        child: const Text('视图与帮助', style: TextStyle(fontSize: 13)),
      ),
    ];
  }

  /// 窄屏没有顶栏导出按钮，用一个底部弹层代替。
  void _showExportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('导出 PNG'),
              subtitle: const Text('按内容范围渲染，2 倍像素密度'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.exportPng();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('导出 SVG'),
              subtitle: const Text('矢量格式，可在 Figma / Illustrator 里编辑'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.exportSvg();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('插入图片'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.importImage();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
