import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../state/editor_controller.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

/// 顶部两角：左边文档名，右边一组就地动作。
///
/// 没有顶栏条。一条 52px 高的实色横条会横贯整个画布上沿，看起来像给窗口
/// 戴了个帽子；改成两块各自独立的小浮层之后，画布从第一条像素就是画布。
///
/// ⚠️ 这里**不再有菜单**。完整菜单已下沉到底栏的「菜单」卡片（见
/// `tool_rail.dart` 与 `home_page.dart` 的 `_MainMenuSheet`）——那是「快捷白板」
/// 的结构：所有入口从底部起，顶栏只留状态。两处都放菜单会出现两个入口，
/// 且顶栏那个用 MenuAnchor 从顶部弹、底栏那个从底部弹，方向相反很割裂。
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
                    fontFamily: WbTheme.fontFamily,
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
          // 导出/导入之外，只在顶栏留一个「关于」入口：它是唯一不影响
          // 画布内容、又需要随时能点到的动作。
          WbIconButton(
            icon: Icons.info_outline,
            tooltip: '关于 wb-pro',
            onPressed: actions.showAbout,
          ),
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
