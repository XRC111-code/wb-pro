import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/mindmap.dart';

MindMapNode _node(String id, String title, [List<MindMapNode> children = const []]) {
  return MindMapNode(id: id, title: title, children: children);
}

void main() {
  group('MindMapNode 树操作', () {
    final tree = _node('r', '根', <MindMapNode>[
      _node('a', '甲', <MindMapNode>[_node('a1', '甲1')]),
      _node('b', '乙'),
    ]);

    test('先序遍历带深度与父节点', () {
      final seen = <String>[];
      final depths = <String, int>{};
      tree.forEach((node, depth, parent) {
        seen.add(node.id);
        depths[node.id] = depth;
        if (node.id == 'a1') expect(parent?.id, 'a');
      });
      expect(seen, <String>['r', 'a', 'a1', 'b']);
      expect(depths['r'], 0);
      expect(depths['a'], 1);
      expect(depths['a1'], 2);
    });

    test('find 能命中任意层级，找不到返回 null', () {
      expect(tree.find('a1')?.title, '甲1');
      expect(tree.find('nope'), isNull);
    });

    test('replace 是不可变更新，原树不受影响', () {
      final next = tree.replace('b', (old) => old.copyWith(title: '乙改'));
      expect(next.find('b')?.title, '乙改');
      expect(tree.find('b')?.title, '乙'); // 原树不动
    });

    test('replace 改了深层节点，沿途父节点是新实例', () {
      final next = tree.replace('a1', (old) => old.copyWith(title: '甲1改'));
      expect(next.find('a1')?.title, '甲1改');
      expect(identical(next, tree), isFalse);
      expect(identical(next.find('b'), tree.find('b')), isTrue,
          reason: '没改的分支应当结构共享');
    });

    test('replace 找不到 id 时原样返回', () {
      expect(identical(tree.replace('nope', (o) => o), tree), isTrue);
    });

    test('remove 删掉整棵子树', () {
      final next = tree.remove('a');
      expect(next.find('a'), isNull);
      expect(next.find('a1'), isNull, reason: '后代要一起消失');
      expect(next.find('b'), isNotNull);
    });

    test('remove 不存在的 id 是空操作', () {
      expect(identical(tree.remove('nope'), tree), isTrue);
    });

    test('JSON 往返保持结构与 id', () {
      final back = MindMapNode.fromJson(tree.toJson());
      expect(back.allIds(), tree.allIds());
      expect(back.find('a1')?.title, '甲1');
    });

    test('JSON 缺字段时给安全默认值', () {
      final back = MindMapNode.fromJson(<String, Object?>{});
      expect(back.id, 'n0');
      expect(back.title, '');
      expect(back.children, isEmpty);
    });
  });

  group('MindMapLayoutEngine 向右布局', () {
    const engine = MindMapLayoutEngine();

    test('单节点落在起点', () {
      final layout = engine.layout(<MindMapNode>[_node('r', '根')]);
      final box = layout.boxOf('r')!;
      expect(box.rect.left, engine.origin.dx);
      expect(layout.boxes, hasLength(1));
    });

    test('子节点在父节点右侧，且垂直居中于父节点', () {
      final layout = engine.layout(<MindMapNode>[
        _node('r', '根', <MindMapNode>[_node('a', '甲')])
      ]);
      final root = layout.boxOf('r')!;
      final child = layout.boxOf('a')!;
      expect(child.rect.left, greaterThan(root.rect.right));
      expect(child.center.dy, closeTo(root.center.dy, 0.01));
      expect(child.depth, 1);
    });

    test('同一父节点的多个子节点不重叠', () {
      final layout = engine.layout(<MindMapNode>[
        _node('r', '根', <MindMapNode>[
          _node('a', '甲'),
          _node('b', '乙'),
          _node('c', '丙'),
        ])
      ]);
      final boxes = <double>[
        layout.boxOf('a')!.rect.top,
        layout.boxOf('b')!.rect.top,
        layout.boxOf('c')!.rect.top,
      ];
      expect(boxes[0], lessThan(boxes[1]));
      expect(boxes[1], lessThan(boxes[2]));
      // 相邻两个之间至少有 nodeGap 的空隙
      final a = layout.boxOf('a')!.rect;
      final b = layout.boxOf('b')!.rect;
      expect(b.top - a.bottom, greaterThanOrEqualTo(engine.nodeGap - 0.01));
    });

    test('折叠的节点，后代不参与布局', () {
      final layout = engine.layout(<MindMapNode>[
        _node('r', '根', <MindMapNode>[
          _node('a', '甲', <MindMapNode>[_node('a1', '甲1')]).copyWith(collapsed: true),
        ])
      ]);
      expect(layout.boxOf('a'), isNotNull);
      expect(layout.boxOf('a1'), isNull, reason: '折叠后后代不该有位置');
    });

    test('多棵树在垂直方向依次排开，不重叠', () {
      final layout = engine.layout(<MindMapNode>[
        _node('r1', '第一棵', <MindMapNode>[_node('a', '甲')]),
        _node('r2', '第二棵', <MindMapNode>[_node('b', '乙')]),
      ]);
      final t1 = layout.boxOf('r1')!.rect;
      final t2 = layout.boxOf('r2')!.rect;
      expect(t2.top, greaterThan(t1.bottom));
    });

    test('深子树的总高度把父节点也撑开（子节点不压到父节点）', () {
      // 一个父节点带 5 个带孙子的子节点，父节点应当垂直居中于整棵子树。
      final layout = engine.layout(<MindMapNode>[
        _node('r', '根', <MindMapNode>[
          for (var i = 0; i < 5; i++)
            _node('c$i', '子$i', <MindMapNode>[_node('g$i', '孙$i')])
        ])
      ]);
      final root = layout.boxOf('r')!;
      final first = layout.boxOf('c0')!.rect;
      final last = layout.boxOf('c4')!.rect;
      expect(root.center.dy, greaterThan(first.center.dy));
      expect(root.center.dy, lessThan(last.center.dy));
    });

    test('edges 给出一对一的父子连线，折叠掉的子节点无连线', () {
      final layout = engine.layout(<MindMapNode>[
        _node('r', '根', <MindMapNode>[
          _node('a', '甲'),
          _node('b', '乙', <MindMapNode>[_node('b1', '乙1')]).copyWith(collapsed: true),
        ])
      ]);
      final edges = layout.edges();
      // r-a 与 r-b 两条；b 被折叠，b-b1 不产生
      expect(edges, hasLength(2));
      for (final (from, to) in edges) {
        expect(to.dx, greaterThan(from.dx), reason: '向右布局里连线应当朝右');
      }
    });

    test('bounds 覆盖所有节点', () {
      final layout = engine.layout(<MindMapNode>[
        _node('r', '根', <MindMapNode>[_node('a', '甲')])
      ]);
      final bounds = layout.bounds;
      for (final box in layout.boxes) {
        expect(bounds.contains(box.rect.topLeft), isTrue);
        expect(bounds.contains(box.rect.bottomRight - const Offset(1, 1)), isTrue);
      }
    });
  });

  group('MindMapLayoutEngine 向下布局', () {
    const engine = MindMapLayoutEngine();

    test('子节点在父节点下方并水平居中', () {
      final layout = engine.layout(
        <MindMapNode>[_node('r', '根', <MindMapNode>[_node('a', '甲')])],
        direction: MindMapDirection.down,
      );
      final root = layout.boxOf('r')!;
      final child = layout.boxOf('a')!;
      expect(child.rect.top, greaterThan(root.rect.bottom));
      expect(child.center.dx, closeTo(root.center.dx, 0.01));
    });

    test('兄弟节点水平排开不重叠', () {
      final layout = engine.layout(
        <MindMapNode>[
          _node('r', '根', <MindMapNode>[_node('a', '甲'), _node('b', '乙')])
        ],
        direction: MindMapDirection.down,
      );
      final a = layout.boxOf('a')!.rect;
      final b = layout.boxOf('b')!.rect;
      expect(a.right, lessThanOrEqualTo(b.left + 0.01));
    });
  });

  group('MindMapLayoutEngine 径向布局', () {
    const engine = MindMapLayoutEngine();

    test('子节点绕根分布，到根的距离相等', () {
      final layout = engine.layout(
        <MindMapNode>[
          _node('r', '根', <MindMapNode>[
            _node('a', '甲'),
            _node('b', '乙'),
            _node('c', '丙'),
            _node('d', '丁'),
          ])
        ],
        direction: MindMapDirection.radial,
      );
      final root = layout.boxOf('r')!.center;
      final distances = <double>[
        for (final id in <String>['a', 'b', 'c', 'd'])
          (layout.boxOf(id)!.center - root).distance,
      ];
      for (final d in distances) {
        expect(d, closeTo(distances.first, 0.01));
      }
    });

    test('空树返回空布局', () {
      final layout = engine.layout(<MindMapNode>[]);
      expect(layout.isEmpty, isTrue);
      expect(layout.bounds, Rect.zero);
    });
  });

  group('节点尺寸估算', () {
    const engine = MindMapLayoutEngine();

    test('汉字按全角算，比拉丁字符宽', () {
      final cn = MindMapLayoutEngine.estimateLineWidth('思维导图', 14);
      final en = MindMapLayoutEngine.estimateLineWidth('abcd', 14);
      expect(cn, greaterThan(en));
      expect(cn, closeTo(14 * 4, 0.01));
      expect(en, closeTo(14 * 0.6 * 4, 0.01));
    });

    test('多行标题高度按行数增加', () {
      final one = engine.nodeSize(_node('a', '一行'), 14);
      final two = engine.nodeSize(_node('b', '一行\n两行'), 14);
      expect(two.height, greaterThan(one.height));
    });

    test('空标题也占一个最小尺寸', () {
      final size = engine.nodeSize(_node('a', ''), 14);
      expect(size.width, greaterThanOrEqualTo(engine.minWidth));
      expect(size.height, greaterThan(0));
    });

    test('传入 measure 时以它为准', () {
      final size = engine.nodeSize(
        _node('a', '很长的标题'),
        14,
        measure: (String line, double fontSize) => 500.0,
      );
      // 500 + 左右内边距
      expect(size.width, closeTo(500 + engine.paddingX * 2, 0.01));
    });
  });
}
