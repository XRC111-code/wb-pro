import 'package:flutter/material.dart';

import 'theme.dart';

class _Shortcut {
  const _Shortcut(this.keys, this.description);

  final String keys;
  final String description;
}

class _Group {
  const _Group(this.title, this.items);

  final String title;
  final List<_Shortcut> items;
}

const List<_Group> _shortcuts = <_Group>[
  _Group('工具', <_Shortcut>[
    _Shortcut('V', '选择'),
    _Shortcut('H', '抓手（也可按住空格）'),
    _Shortcut('P', '画笔'),
    _Shortcut('E', '橡皮'),
    _Shortcut('R / O / D', '矩形 / 椭圆 / 菱形'),
    _Shortcut('A / L', '箭头 / 直线'),
    _Shortcut('T / N', '文本 / 便签'),
  ]),
  _Group('编辑', <_Shortcut>[
    _Shortcut('Ctrl+Z', '撤销'),
    _Shortcut('Ctrl+Shift+Z / Ctrl+Y', '重做'),
    _Shortcut('Ctrl+C / X / V', '复制 / 剪切 / 粘贴'),
    _Shortcut('Ctrl+D', '创建副本'),
    _Shortcut('Ctrl+A', '全选'),
    _Shortcut('Delete', '删除选中'),
    _Shortcut('方向键', '微移 1px（Shift 为 10px）'),
    _Shortcut('Ctrl+] / [', '上移 / 下移一层'),
    _Shortcut('Ctrl+Shift+] / [', '置顶 / 置底'),
  ]),
  _Group('文件', <_Shortcut>[
    _Shortcut('Ctrl+N', '新建'),
    _Shortcut('Ctrl+O', '打开'),
    _Shortcut('Ctrl+S', '保存'),
    _Shortcut('Ctrl+Shift+S', '另存为'),
    _Shortcut('Ctrl+E', '导出 PNG'),
  ]),
  _Group('视图', <_Shortcut>[
    _Shortcut('滚轮 / 双指', '平移'),
    _Shortcut('Ctrl+滚轮', '以光标为中心缩放'),
    _Shortcut('Ctrl+= / Ctrl+-', '放大 / 缩小'),
    _Shortcut('Ctrl+0', '实际大小（100%）'),
    _Shortcut('Shift+1', '适应内容'),
    _Shortcut('Ctrl+G', '显示/隐藏网格'),
    _Shortcut('Ctrl+Shift+G', '吸附到网格'),
    _Shortcut('空格拖动 / 中键拖动', '平移画布'),
    _Shortcut('Shift 拖拽', '绘制正方形 / 等比箭头'),
    _Shortcut('Shift 旋转', '按 15° 步进'),
  ]),
];

Future<void> showShortcutsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('快捷键'),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 28,
            runSpacing: 18,
            children: <Widget>[
              for (final group in _shortcuts)
                SizedBox(
                  width: 270,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: WbTheme.subtleText(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final item in group.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(
                                width: 140,
                                child: Text(
                                  item.keys,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFeatures: <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: WbTheme.subtleText(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

Future<void> showAboutWbPro(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF4C8DFF), Color(0xFF2F5BFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.gesture, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('wb-pro'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '跨平台无限画布白板 · 1.0.0',
              style: TextStyle(fontSize: 13, color: WbTheme.subtleText(context)),
            ),
            const SizedBox(height: 14),
            const Text(
              '手绘、形状、箭头、文本、便签与图片，全部落在同一块无限画布上。'
              '文档保存为自包含的 .wbpro（图片内嵌），也可以导出 PNG 与可编辑的 SVG。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 14),
            const Text(
              'Flutter 构建，同一套代码运行在 Windows、macOS、Linux 与 Android 上。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 18),
            Text(
              'github.com/XRC111-code/wb-pro',
              style: TextStyle(fontSize: 12, color: WbTheme.activeColor(context)),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
