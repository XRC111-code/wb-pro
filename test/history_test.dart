import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/model/element.dart';
import 'package:wb_pro/state/history.dart';

WbElement _rect(String id, {double x = 0}) => ShapeElement(
      id: id,
      frame: Rect.fromLTWH(x, 0, 10, 10),
      shape: ShapeKind.rectangle,
      stroke: const Color(0xFF000000),
      strokeWidth: 1,
    );

EditorSnapshot _snapshot(List<WbElement> elements, [Set<String>? selection]) =>
    EditorSnapshot(elements: elements, selection: selection ?? <String>{});

void main() {
  group('EditorSnapshot', () {
    test('同一个列表实例视为相同', () {
      final elements = <WbElement>[_rect('a')];
      expect(
        EditorSnapshot.sameElements(elements, elements),
        isTrue,
      );
    });

    test('长度不同即不同', () {
      expect(
        EditorSnapshot.sameElements(<WbElement>[_rect('a')], <WbElement>[]),
        isFalse,
      );
    });

    test('同内容但不同实例视为不同', () {
      // 元素是不可变对象，编辑时整条列表换新，因此「引用不同」就等于「改过」。
      expect(
        EditorSnapshot.sameElements(<WbElement>[_rect('a')], <WbElement>[_rect('a')]),
        isFalse,
      );
    });

    test('selection 用值比较', () {
      final elements = <WbElement>[_rect('a')];
      final a = _snapshot(elements, <String>{'x'});
      final b = _snapshot(elements, <String>{'x'});
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(_snapshot(elements)), isFalse);
    });
  });

  group('History', () {
    test('初始状态两个方向都不可用', () {
      final history = History();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('撤销返回上一次记录的状态', () {
      final history = History();
      final first = _snapshot(<WbElement>[_rect('a')]);
      history.record(first);

      final restored = history.undo(_snapshot(<WbElement>[_rect('a'), _rect('b')]));
      expect(identical(restored, first), isTrue);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);
    });

    test('重做把当前状态推回 past', () {
      final history = History();
      history.record(_snapshot(<WbElement>[]));
      final current = _snapshot(<WbElement>[_rect('a')]);
      history.undo(current);

      final redone = history.redo(_snapshot(<WbElement>[]));
      expect(identical(redone, current), isTrue);
      expect(history.canRedo, isFalse);
    });

    test('重复记录相同状态会被丢弃', () {
      final history = History();
      final snapshot = _snapshot(<WbElement>[_rect('a')]);
      history.record(snapshot);
      history.record(snapshot);
      expect(history.undoDepth, 1);
    });

    test('新操作清空重做栈', () {
      final history = History();
      history.record(_snapshot(<WbElement>[]));
      history.undo(_snapshot(<WbElement>[_rect('a')]));
      expect(history.canRedo, isTrue);

      history.record(_snapshot(<WbElement>[_rect('b')]));
      expect(history.canRedo, isFalse);
    });

    test('超出上限时丢弃最旧的记录', () {
      final history = History(limit: 3);
      for (var i = 0; i < 6; i++) {
        history.record(_snapshot(<WbElement>[_rect('e$i', x: i.toDouble())]));
      }
      expect(history.undoDepth, 3);
      // 最早的三条已经被挤掉，撤销三次后仍然可撤销为 false。
      history.undo(_snapshot(<WbElement>[]));
      history.undo(_snapshot(<WbElement>[]));
      history.undo(_snapshot(<WbElement>[]));
      expect(history.canUndo, isFalse);
    });

    test('clear 之后两个方向都不可用', () {
      final history = History();
      history.record(_snapshot(<WbElement>[]));
      history.undo(_snapshot(<WbElement>[_rect('a')]));
      history.clear();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('空栈上撤销返回 null', () {
      expect(History().undo(_snapshot(<WbElement>[])), isNull);
      expect(History().redo(_snapshot(<WbElement>[])), isNull);
    });
  });
}
