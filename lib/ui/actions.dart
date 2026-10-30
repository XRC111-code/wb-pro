import 'package:flutter/material.dart';

/// 主页面暴露给顶栏/菜单的动作集合。
///
/// 打包成一个对象而不是在 `TopBar` 上挂十几个回调参数：顶栏、菜单、快捷键、
/// 空状态页都要触发同一批动作，参数列表一旦超过六个就开始出现「传错位置」
/// 这种低级错误。
class WbActions {
  const WbActions({
    required this.newDocument,
    required this.openDocument,
    required this.save,
    required this.saveAs,
    required this.exportPng,
    required this.exportSvg,
    required this.importImage,
    required this.renameDocument,
    required this.showShortcuts,
    required this.showAbout,
    required this.toggleTheme,
    required this.toggleInspector,
    required this.clearCanvas,
    required this.copySelection,
    required this.cutSelection,
    required this.paste,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.selectAll,
    required this.undo,
    required this.redo,
    required this.zoomIn,
    required this.zoomOut,
    required this.zoomReset,
    required this.zoomToFit,
    required this.toggleGrid,
    required this.toggleSnap,
  });

  final VoidCallback newDocument;
  final VoidCallback openDocument;
  final VoidCallback save;
  final VoidCallback saveAs;
  final VoidCallback exportPng;
  final VoidCallback exportSvg;
  final VoidCallback importImage;
  final VoidCallback renameDocument;
  final VoidCallback showShortcuts;
  final VoidCallback showAbout;
  final VoidCallback toggleTheme;
  final VoidCallback toggleInspector;
  final VoidCallback clearCanvas;
  final VoidCallback copySelection;
  final VoidCallback cutSelection;
  final VoidCallback paste;
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;
  final VoidCallback selectAll;
  final VoidCallback undo;
  final VoidCallback redo;
  final VoidCallback zoomIn;
  final VoidCallback zoomOut;
  final VoidCallback zoomReset;
  final VoidCallback zoomToFit;
  final VoidCallback toggleGrid;
  final VoidCallback toggleSnap;
}
