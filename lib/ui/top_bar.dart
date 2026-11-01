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
class TopBar extends StatelessWidget {
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
          _menu(context),
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

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '菜单',
      icon: MiuixIcon(
        icon: Icons.menu,
        size: 18,
        tint: WbTheme.onChrome(context, alpha: 0.82),
      ),
      constraints: const BoxConstraints(minWidth: 246),
      position: PopupMenuPosition.under,
      onSelected: (value) => _handleMenu(context, value),
      itemBuilder: (context) => _menuItems(context),
    );
  }

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
      case 'inspector':
        actions.toggleInspector();
      case 'zoomIn':
        actions.zoomIn();
      case 'zoomOut':
        actions.zoomOut();
      case 'zoomReset':
        actions.zoomReset();
      case 'fit':
        actions.zoomToFit();
      case 'theme':
        actions.toggleTheme();
      case 'shortcuts':
        actions.showShortcuts();
      case 'about':
        actions.showAbout();
    }
  }

  List<PopupMenuEntry<String>> _menuItems(BuildContext context) {
    final subtle = WbTheme.subtleText(context);
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      String? shortcut,
      bool enabled = true,
      bool danger = false,
    }) {
      final color = enabled
          ? (danger
              ? const Color(0xFFE03131)
              : Theme.of(context).colorScheme.onSurface)
          : subtle.withValues(alpha: 0.4);
      return PopupMenuItem<String>(
        value: value,
        height: 38,
        enabled: enabled,
        child: Row(
          children: <Widget>[
            MiuixIcon(icon: icon, size: 16, tint: color),
            const SizedBox(width: 10),
            Expanded(
              child: MiuixText(label,
                  style: const TextStyle(fontSize: 13), color: color),
            ),
            if (shortcut != null)
              MiuixText(
                shortcut,
                style: const TextStyle(fontSize: 11),
                color: subtle,
              ),
          ],
        ),
      );
    }

    final hasSelection = controller.selection.isNotEmpty;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return <PopupMenuEntry<String>>[
      item('new', Icons.note_add_outlined, '新建', shortcut: 'Ctrl+N'),
      item('open', Icons.folder_open_outlined, '打开…', shortcut: 'Ctrl+O'),
      item('save', Icons.save_outlined, '保存', shortcut: 'Ctrl+S'),
      item('saveAs', Icons.save_as_outlined, '另存为…', shortcut: 'Ctrl+Shift+S'),
      const PopupMenuDivider(),
      item('png', Icons.image_outlined, '导出 PNG…', shortcut: 'Ctrl+E'),
      item('svg', Icons.timeline, '导出 SVG…'),
      item('image', Icons.add_photo_alternate_outlined, '插入图片…'),
      const PopupMenuDivider(),
      item('undo', Icons.undo, '撤销',
          shortcut: 'Ctrl+Z', enabled: controller.canUndo),
      item('redo', Icons.redo, '重做',
          shortcut: 'Ctrl+Shift+Z', enabled: controller.canRedo),
      item('cut', Icons.content_cut, '剪切',
          shortcut: 'Ctrl+X', enabled: hasSelection),
      item('copy', Icons.content_copy, '复制',
          shortcut: 'Ctrl+C', enabled: hasSelection),
      item('paste', Icons.content_paste, '粘贴', shortcut: 'Ctrl+V'),
      item('duplicate', Icons.copy_all_outlined, '创建副本',
          shortcut: 'Ctrl+D', enabled: hasSelection),
      item('delete', Icons.delete_outline, '删除',
          shortcut: 'Del', enabled: hasSelection, danger: true),
      item('selectAll', Icons.select_all, '全选', shortcut: 'Ctrl+A'),
      const PopupMenuDivider(),
      item('grid', Icons.grid_on, controller.showGrid ? '隐藏网格' : '显示网格',
          shortcut: 'Ctrl+G'),
      item('snap', Icons.straighten, controller.snapToGrid ? '关闭吸附' : '吸附到网格',
          shortcut: 'Ctrl+Shift+G'),
      item('inspector', Icons.tune, '属性面板', shortcut: 'Ctrl+Alt+P'),
      // 放大 / 缩小 / 实际大小 / 适应内容 不放进菜单：右下角一直摆着这几个
      // 按钮，菜单再列一遍只会把它顶到屏幕外面去。
      const PopupMenuDivider(),
      item('theme', dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          dark ? '浅色主题' : '深色主题'),
      item('shortcuts', Icons.keyboard_outlined, '快捷键', shortcut: '?'),
      item('about', Icons.info_outline, '关于 wb-pro'),
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
