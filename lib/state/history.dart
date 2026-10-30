import 'package:flutter/foundation.dart';

import '../model/element.dart';

/// 一次可撤销的状态。
///
/// 只存元素列表的**引用**和选中集：元素本身不可变，编辑时整条列表换成新的
/// （结构共享），因此快照几乎不占内存。对比「每次操作深拷贝整棵场景」的
/// 做法，100 步历史在这个方案里是几百 KB 而不是几百 MB。
@immutable
class EditorSnapshot {
  const EditorSnapshot({required this.elements, required this.selection});

  final List<WbElement> elements;
  final Set<String> selection;

  static bool sameElements(List<WbElement> a, List<WbElement> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  bool sameAs(EditorSnapshot other) =>
      sameElements(elements, other.elements) && setEquals(selection, other.selection);
}

/// 撤销/重做栈。
///
/// 语义是「记录变更前的状态」：编辑前把当前状态压入 past，撤销时把它取回来。
/// 这样每个操作只需要在开始处记一次，不用关心自己改了什么。
class History {
  History({this.limit = 100});

  final int limit;
  final List<EditorSnapshot> _past = <EditorSnapshot>[];
  final List<EditorSnapshot> _future = <EditorSnapshot>[];

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  int get undoDepth => _past.length;
  int get redoDepth => _future.length;

  /// 记录一次变更前的状态。
  ///
  /// 与栈顶完全相同时直接丢弃：拖动后回到原位、连续两次同样的样式设置
  /// 都会产生这种「无效历史」，留着只会让用户按两次撤销才退一步。
  void record(EditorSnapshot snapshot) {
    if (_past.isNotEmpty && _past.last.sameAs(snapshot)) return;
    _past.add(snapshot);
    if (_past.length > limit) _past.removeAt(0);
    _future.clear();
  }

  EditorSnapshot? undo(EditorSnapshot current) {
    if (_past.isEmpty) return null;
    _future.add(current);
    return _past.removeLast();
  }

  EditorSnapshot? redo(EditorSnapshot current) {
    if (_future.isEmpty) return null;
    _past.add(current);
    return _future.removeLast();
  }

  void clear() {
    _past.clear();
    _future.clear();
  }
}
