import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../state/editor_controller.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

/// 底部两角的状态：左边元素数，右边缩放。
///
/// 不是一条横贯底部的状态栏，而是两块各自贴着角落的小浮层。中间那块空出来
/// 的地方留给工具条——三块并排，谁也不压谁。
class StatusBar extends StatelessWidget {
  const StatusBar({
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
      builder: (context, _) => Row(
        children: <Widget>[
          _stats(context),
          const Spacer(),
          _zoom(context),
        ],
      ),
    );
  }

  Widget _stats(BuildContext context) {
    final subtle = WbTheme.onChrome(context, alpha: 0.55);
    final selected = controller.selection.length;
    return WbFloatingBar(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      radius: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${controller.elements.length} 个元素',
            style: TextStyle(fontSize: 11.5, color: subtle),
          ),
          if (selected > 0) ...<Widget>[
            const SizedBox(width: 7),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: subtle.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '已选 $selected',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: WbTheme.activeColor(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _zoom(BuildContext context) {
    final subtle = WbTheme.onChrome(context, alpha: 0.55);
    return WbFloatingBar(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      radius: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WbIconButton(
            icon: Icons.remove,
            tooltip: '缩小  Ctrl+-',
            size: 26,
            iconSize: 15,
            onPressed: actions.zoomOut,
          ),
          MiuixPressable(
            onPressed: actions.zoomReset,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 46,
              height: 24,
              child: Center(
                child: MiuixText(
                  '${(controller.viewport.zoom * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w500),
                  color: subtle,
                ),
              ),
            ),
          ),
          WbIconButton(
            icon: Icons.add,
            tooltip: '放大  Ctrl+=',
            size: 26,
            iconSize: 15,
            onPressed: actions.zoomIn,
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: WbTheme.chromeHairline(context),
          ),
          WbIconButton(
            icon: Icons.crop_free,
            tooltip: '适应内容  Shift+1',
            size: 26,
            iconSize: 15,
            onPressed: actions.zoomToFit,
          ),
        ],
      ),
    );
  }
}
