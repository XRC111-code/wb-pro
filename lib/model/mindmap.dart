import 'dart:math' as math;
import 'dart:ui';

/// 思维导图的布局方向。
///
/// 与 doodlio 一致三种：向右展开、向下展开、径向。向右是最常用的
/// （左右结构的脑图），向下适合放进窄窗口，径向适合做「发散图」。
enum MindMapDirection {
  right('向右'),
  down('向下'),
  radial('径向');

  const MindMapDirection(this.label);

  final String label;
}

/// 一个思维导图节点。
///
/// ── 为什么用独立模型而不是复用 [WbElement] ──────────────────────────────────
/// 白板的元素是**扁平的、彼此独立**的：六个元素互不相干，移动谁就改谁的框。
/// 思维导图是**一棵树**：改父节点的字号会让整棵子树重新排布，删节点要级联，
/// 折叠一个分支要让所有后代消失。把这些语义塞进扁平数组，撤销栈会先坏掉
/// —— 一次自动布局到底是「一步」还是「N 步」，两种答案在数组模型里都别扭。
///
/// 所以这里是**独立子系统**：文档里存这棵树，渲染时投影成元素。
/// 投影是纯函数（[MindMapTree.project]），不改文档。
class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.title,
    this.note = '',
    this.children = const <MindMapNode>[],
    this.collapsed = false,
  });

  final String id;

  /// 节点正文。允许换行，渲染时按行拆开。
  final String title;

  /// 备注。显示在标题下方的小字，与 doodlio 的 note 对应。
  final String note;

  final List<MindMapNode> children;

  /// 折叠：自身仍显示，后代不参与布局与渲染。
  final bool collapsed;

  bool get hasChildren => children.isNotEmpty;

  MindMapNode copyWith({
    String? id,
    String? title,
    String? note,
    List<MindMapNode>? children,
    bool? collapsed,
  }) {
    return MindMapNode(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      children: children ?? this.children,
      collapsed: collapsed ?? this.collapsed,
    );
  }

  /// 深度优先遍历。`depth` 从 0（根）开始。
  void forEach(void Function(MindMapNode node, int depth, MindMapNode? parent) visit,
      [MindMapNode? parent, int depth = 0]) {
    visit(this, depth, parent);
    for (final child in children) {
      child.forEach(visit, this, depth + 1);
    }
  }

  /// 在树里按 id 找节点。
  MindMapNode? find(String nodeId) {
    if (id == nodeId) return this;
    for (final child in children) {
      final hit = child.find(nodeId);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 返回替换了 [nodeId] 这棵子树的新树（不可变更新）。
  ///
  /// 找不到就原样返回自己 —— 调用方多半是「改一个已经被删掉的节点」，
  /// 那是空操作而不是错误。
  MindMapNode replace(String nodeId, MindMapNode Function(MindMapNode old) update) {
    if (id == nodeId) return update(this);
    var changed = false;
    final next = <MindMapNode>[];
    for (final child in children) {
      final replaced = child.replace(nodeId, update);
      if (!identical(replaced, child)) changed = true;
      next.add(replaced);
    }
    return changed ? copyWith(children: next) : this;
  }

  /// 删除 [nodeId] 及其整棵子树。
  MindMapNode remove(String nodeId) {
    final next = <MindMapNode>[];
    var changed = false;
    for (final child in children) {
      if (child.id == nodeId) {
        changed = true;
        continue;
      }
      final trimmed = child.remove(nodeId);
      if (!identical(trimmed, child)) changed = true;
      next.add(trimmed);
    }
    return changed ? copyWith(children: next) : this;
  }

  /// 所有节点的 id（含自身），按先序。
  List<String> allIds() {
    final ids = <String>[];
    forEach((node, _, __) => ids.add(node.id));
    return ids;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        if (note.isNotEmpty) 'note': note,
        if (collapsed) 'collapsed': true,
        if (children.isNotEmpty)
          'children': <Object?>[for (final c in children) c.toJson()],
      };

  static MindMapNode fromJson(Map<String, Object?> json, {String fallbackId = 'n0'}) {
    final rawChildren = json['children'];
    final children = <MindMapNode>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        if (item is Map) {
          children.add(MindMapNode.fromJson(
            item.cast<String, Object?>(),
            fallbackId: '$fallbackId-x${children.length}',
          ));
        }
      }
    }
    return MindMapNode(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : fallbackId,
      title: json['title'] is String ? json['title'] as String : '',
      note: json['note'] is String ? json['note'] as String : '',
      collapsed: json['collapsed'] == true,
      children: children,
    );
  }
}

/// 节点排版后的位置（世界坐标，左上角）。
///
/// 只带几何，不带样式：布局是纯计算，样式由投影阶段决定。这样布局算法
/// 能脱离渲染单独测试。
class MindMapNodeBox {
  const MindMapNodeBox({
    required this.node,
    required this.rect,
    required this.depth,
    required this.branch,
  });

  final MindMapNode node;
  final Rect rect;
  final int depth;

  /// 一级分支的序号，用来给同一条分支着色。
  final int branch;

  Offset get center => rect.center;
}

/// 思维导图的一棵（或多棵）树的布局结果。
class MindMapLayout {
  const MindMapLayout({
    required this.boxes,
    required this.direction,
  });

  final List<MindMapNodeBox> boxes;
  final MindMapDirection direction;

  bool get isEmpty => boxes.isEmpty;

  /// 所有节点的包围盒（含连线外扩），用于「适应内容」。
  Rect get bounds {
    if (boxes.isEmpty) return Rect.zero;
    var rect = boxes.first.rect;
    for (final box in boxes.skip(1)) {
      rect = rect.expandToInclude(box.rect);
    }
    return rect;
  }

  MindMapNodeBox? boxOf(String nodeId) {
    for (final box in boxes) {
      if (box.node.id == nodeId) return box;
    }
    return null;
  }

  /// 父子连线：父节点右侧中点到子节点左侧中点。
  ///
  /// 只产出相连的一对，具体画贝塞尔还是直线由渲染层决定 —— 布局层不该
  /// 知道画笔长什么样。
  List<(Offset from, Offset to)> edges() {
    final byId = <String, MindMapNodeBox>{for (final b in boxes) b.node.id: b};
    final result = <(Offset, Offset)>[];
    for (final box in boxes) {
      for (final child in box.node.children) {
        final childBox = byId[child.id];
        if (childBox == null) continue; // 被折叠掉了
        final from = switch (direction) {
          MindMapDirection.down => Offset(box.rect.center.dx, box.rect.bottom),
          _ => Offset(box.rect.right, box.rect.center.dy),
        };
        final to = switch (direction) {
          MindMapDirection.down => Offset(childBox.rect.center.dx, childBox.rect.top),
          _ => Offset(childBox.rect.left, childBox.rect.center.dy),
        };
        result.add((from, to));
      }
    }
    return result;
  }
}

/// 思维导图布局算法。
///
/// 移植自 doodlio 的 `mindmapLayout.ts`，但把「估算节点尺寸」改成可注入：
/// 那边用 `fontSize * 0.6` 猜字符宽度，中文全是全角，猜出来会窄一大截，
/// 长标题就互相压字。这里允许调用方传入真实的测量函数（wb-pro 有
/// `text_metrics.dart`），测不到时才退回估算。
class MindMapLayoutEngine {
  const MindMapLayoutEngine({
    this.levelGap = 200,
    this.nodeGap = 16,
    this.paddingX = 16,
    this.paddingY = 10,
    this.minWidth = 60,
    this.origin = const Offset(60, 100),
  });

  /// 层与层之间的间距。
  final double levelGap;

  /// 兄弟节点之间的间距。
  final double nodeGap;

  final double paddingX;
  final double paddingY;
  final double minWidth;

  /// 第一棵树的起点。
  final Offset origin;

  /// 估算节点尺寸。传入 [measure] 时用它，否则按字符数估。
  Size nodeSize(
    MindMapNode node,
    double fontSize, {
    Size Function(String line, double fontSize)? measure,
  }) {
    final lines = node.title.isEmpty ? <String>[' '] : node.title.split('\n');
    final lineHeight = fontSize * 1.3;
    var maxWidth = 0.0;
    for (final line in lines) {
      final w = measure?.call(line, fontSize) ?? estimateLineWidth(line, fontSize);
      if (w > maxWidth) maxWidth = w;
    }
    return Size(
      math.max(minWidth, maxWidth + paddingX * 2),
      lines.length * lineHeight + paddingY * 2,
    );
  }

  /// 无测量函数时的字符宽度估算。
  ///
  /// 中日韩字符按 1.0 em，其余按 0.6 em —— 只按 0.6 会把「思维导图」这种
  /// 四个汉字的标题算成 2.4em 宽，实际需要 4em，节点框会明显偏窄。
  static double estimateLineWidth(String line, double fontSize) {
    var width = 0.0;
    for (final rune in line.runes) {
      width += _isWide(rune) ? fontSize : fontSize * 0.6;
    }
    return width;
  }

  static bool _isWide(int rune) {
    // CJK 统一表意文字、扩展 A、假名、谚文、全角标点。
    return (rune >= 0x1100 && rune <= 0x115F) ||
        (rune >= 0x2E80 && rune <= 0xA4CF) ||
        (rune >= 0xAC00 && rune <= 0xD7A3) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0xFE30 && rune <= 0xFE6F) ||
        (rune >= 0xFF00 && rune <= 0xFF60) ||
        (rune >= 0xFFE0 && rune <= 0xFFE6);
  }

  /// 对一棵树做布局（也接受多棵：`roots` 会依次向下排开）。
  MindMapLayout layout(
    List<MindMapNode> roots, {
    MindMapDirection direction = MindMapDirection.right,
    double fontSize = 14,
    Size Function(String line, double fontSize)? measure,
  }) {
    if (roots.isEmpty) {
      return MindMapLayout(boxes: <MindMapNodeBox>[], direction: direction);
    }

    Size sizeOf(MindMapNode node) => nodeSize(node, fontSize, measure: measure);

    // 折叠裁剪：折叠节点的后代完全不参与布局。
    List<MindMapNode> effectiveChildren(MindMapNode node) =>
        node.collapsed ? const <MindMapNode>[] : node.children;

    final boxes = <MindMapNodeBox>[];

    // ── 向右（默认）────────────────────────────────────────────────────────
    if (direction == MindMapDirection.right) {
      final heightCache = <String, double>{};

      double subtreeHeight(MindMapNode node) {
        final cached = heightCache[node.id];
        if (cached != null) return cached;
        final self = sizeOf(node).height;
        final children = effectiveChildren(node);
        if (children.isEmpty) {
          heightCache[node.id] = self;
          return self;
        }
        var total = 0.0;
        for (final child in children) {
          total += subtreeHeight(child);
        }
        total += (children.length - 1) * nodeGap;
        final result = math.max(self, total);
        heightCache[node.id] = result;
        return result;
      }

      void place(MindMapNode node, double x, double centerY, int depth, int branch) {
        final size = sizeOf(node);
        boxes.add(MindMapNodeBox(
          node: node,
          rect: Rect.fromLTWH(x, centerY - size.height / 2, size.width, size.height),
          depth: depth,
          branch: branch,
        ));

        final children = effectiveChildren(node);
        if (children.isEmpty) return;

        final childX = x + size.width + levelGap;
        var total = 0.0;
        for (final child in children) {
          total += subtreeHeight(child);
        }
        total += (children.length - 1) * nodeGap;

        var cursor = centerY - total / 2;
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          final childTreeHeight = subtreeHeight(child);
          final childCenterY = cursor + childTreeHeight / 2;
          place(child, childX, childCenterY, depth + 1, depth == 0 ? i : branch);
          cursor += childTreeHeight + nodeGap;
        }
      }

      var startY = origin.dy;
      for (final root in roots) {
        final treeHeight = subtreeHeight(root);
        place(root, origin.dx, startY + treeHeight / 2, 0, 0);
        startY += treeHeight + nodeGap * 3;
      }
      return MindMapLayout(boxes: boxes, direction: direction);
    }

    // ── 向下 ───────────────────────────────────────────────────────────────
    if (direction == MindMapDirection.down) {
      final widthCache = <String, double>{};

      double subtreeWidth(MindMapNode node) {
        final cached = widthCache[node.id];
        if (cached != null) return cached;
        final self = sizeOf(node).width;
        final children = effectiveChildren(node);
        if (children.isEmpty) {
          widthCache[node.id] = self;
          return self;
        }
        var total = 0.0;
        for (final child in children) {
          total += subtreeWidth(child);
        }
        total += (children.length - 1) * nodeGap;
        final result = math.max(self, total);
        widthCache[node.id] = result;
        return result;
      }

      void placeDown(MindMapNode node, double centerX, double y, int depth, int branch) {
        final size = sizeOf(node);
        boxes.add(MindMapNodeBox(
          node: node,
          rect: Rect.fromLTWH(centerX - size.width / 2, y, size.width, size.height),
          depth: depth,
          branch: branch,
        ));

        final children = effectiveChildren(node);
        if (children.isEmpty) return;

        final childY = y + size.height + levelGap * 0.5;
        var total = 0.0;
        for (final child in children) {
          total += subtreeWidth(child);
        }
        total += (children.length - 1) * nodeGap;

        var cursor = centerX - total / 2;
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          final childTreeWidth = subtreeWidth(child);
          final childCenterX = cursor + childTreeWidth / 2;
          placeDown(child, childCenterX, childY, depth + 1, depth == 0 ? i : branch);
          cursor += childTreeWidth + nodeGap;
        }
      }

      var startX = origin.dx;
      for (final root in roots) {
        final treeWidth = subtreeWidth(root);
        placeDown(root, startX + treeWidth / 2, origin.dy, 0, 0);
        startX += treeWidth + nodeGap * 3;
      }
      return MindMapLayout(boxes: boxes, direction: direction);
    }

    // ── 径向 ───────────────────────────────────────────────────────────────
    void placeRadialSub(
      MindMapNode node,
      double x,
      double y,
      double parentAngle,
      double sectorAngle,
      int depth,
      int branch,
    ) {
      final children = effectiveChildren(node);
      if (children.isEmpty) return;

      final startAngle = parentAngle - sectorAngle / 2;
      final step = sectorAngle / math.max(children.length - 1, 1);
      final radius = levelGap * (0.7 + 0.15 * depth);

      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        final angle = children.length == 1 ? parentAngle : startAngle + step * i;
        final size = sizeOf(child);
        // 径向布局里节点以中心定位，换成左上角。
        final center = Offset(x + math.cos(angle) * radius, y + math.sin(angle) * radius);
        boxes.add(MindMapNodeBox(
          node: child,
          rect: Rect.fromCenter(
              center: center, width: size.width, height: size.height),
          depth: depth + 1,
          branch: depth == 0 ? i : branch,
        ));
        placeRadialSub(
          child,
          center.dx,
          center.dy,
          angle,
          sectorAngle / math.max(children.length, 1),
          depth + 1,
          depth == 0 ? i : branch,
        );
      }
    }

    void placeRadialRoot(MindMapNode root, double cx, double cy) {
      final size = sizeOf(root);
      boxes.add(MindMapNodeBox(
        node: root,
        rect: Rect.fromCenter(center: Offset(cx, cy), width: size.width, height: size.height),
        depth: 0,
        branch: 0,
      ));

      final children = effectiveChildren(root);
      if (children.isEmpty) return;

      final angleStep = 2 * math.pi / children.length;
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        final angle = angleStep * i - math.pi / 2;
        final childSize = sizeOf(child);
        final center = Offset(
          cx + math.cos(angle) * levelGap,
          cy + math.sin(angle) * levelGap,
        );
        boxes.add(MindMapNodeBox(
          node: child,
          rect: Rect.fromCenter(
              center: center, width: childSize.width, height: childSize.height),
          depth: 1,
          branch: i,
        ));
        placeRadialSub(child, center.dx, center.dy, angle, angleStep * 0.8, 2, i);
      }
    }

    var offsetX = origin.dx + 240;
    for (final root in roots) {
      placeRadialRoot(root, offsetX, origin.dy + 200);
      offsetX += 600;
    }
    return MindMapLayout(boxes: boxes, direction: direction);
  }
}
