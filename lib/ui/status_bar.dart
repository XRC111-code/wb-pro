import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../state/editor_controller.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

/// 底部状态栏：元素数、光标坐标、缩放。
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
    final subtle = WbTheme.subtleText(context);
    return SizedBox(
      height: WbTheme.statusBarHeight,
      child: MiuixSurface(
        color: WbTheme.panelColor(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(height: 1, color: WbTheme.hairline(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Row(
            children: <Widget>[
              _text(
                context,
                '${controller.elements.length} 个元素',
                color: subtle,
              ),
              if (controller.selection.isNotEmpty) ...<Widget>[
                const SizedBox(width: 10),
                _text(
                  context,
                  '已选 ${controller.selection.length}',
                  color: WbTheme.activeColor(context),
                ),
              ],
              if (!compact) ...<Widget>[
                const SizedBox(width: 14),
                _dot(context),
                const SizedBox(width: 14),
                ValueListenableBuilder<Offset?>(
                  valueListenable: controller.pointerWorld,
                  builder: (context, world, __) => SizedBox(
                    width: 128,
                    child: _text(
                      context,
                      world == null
                          ? '—'
                          : 'x ${world.dx.toStringAsFixed(0)}  y ${world.dy.toStringAsFixed(0)}',
                      color: subtle,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              WbIconButton(
                icon: controller.showGrid ? Icons.grid_on : Icons.grid_off,
                tooltip: controller.showGrid ? '隐藏网格  Ctrl+G' : '显示网格  Ctrl+G',
                size: 24,
                iconSize: 14,
                active: controller.showGrid,
                onPressed: actions.toggleGrid,
              ),
              WbIconButton(
                icon: Icons.straighten,
                tooltip: controller.snapToGrid ? '关闭吸附  Ctrl+Shift+G' : '吸附到网格  Ctrl+Shift+G',
                size: 24,
                iconSize: 14,
                active: controller.snapToGrid,
                onPressed: actions.toggleSnap,
              ),
              const SizedBox(width: 2),
              WbIconButton(
                icon: Icons.remove,
                tooltip: '缩小  Ctrl+-',
                size: 24,
                iconSize: 14,
                onPressed: actions.zoomOut,
              ),
              MiuixPressable(
                onPressed: actions.zoomReset,
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 50,
                  height: 20,
                  child: Center(
                    child: MiuixText(
                      '${(controller.viewport.zoom * 100).round()}%',
                      style: const TextStyle(fontSize: 11),
                      color: subtle,
                    ),
                  ),
                ),
              ),
              WbIconButton(
                icon: Icons.add,
                tooltip: '放大  Ctrl+=',
                size: 24,
                iconSize: 14,
                onPressed: actions.zoomIn,
              ),
              WbIconButton(
                icon: Icons.crop_free,
                tooltip: '适应内容  Shift+1',
                size: 24,
                iconSize: 14,
                onPressed: actions.zoomToFit,
              ),
            ],
          );
                },
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _text(BuildContext context, String value, {required Color color}) {
    return MiuixText(
      value,
      style: const TextStyle(fontSize: 11),
      color: color,
    );
  }

  Widget _dot(BuildContext context) => Container(
        width: 1,
        height: 12,
        color: WbTheme.hairline(context),
      );
}
