import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/io/document.dart';
import 'package:wb_pro/model/canvas_style.dart';
import 'package:wb_pro/model/element.dart';

const Color _black = Color(0xFF1F2933);

WbElement _shape(String id, {double x = 0}) => ShapeElement(
      id: id,
      frame: Rect.fromLTWH(x, 0, 20, 20),
      shape: ShapeKind.rectangle,
      stroke: _black,
      strokeWidth: 2,
    );

void main() {
  group('编码与解码', () {
    test('往返后文档内容一致', () {
      final document = WbDocument(
        name: '设计草图',
        elements: <WbElement>[_shape('a'), _shape('b', x: 100)],
        pan: const Offset(-40, 12),
        zoom: 1.75,
      );
      final result = WbDocument.decode(document.encode());

      expect(result.document.name, '设计草图');
      expect(result.document.elements.length, 2);
      expect(result.document.elements[1].frame.left, 100);
      expect(result.document.pan, const Offset(-40, 12));
      expect(result.document.zoom, 1.75);
      expect(result.warnings, isEmpty);
    });

    test('空文档也能往返', () {
      const document = WbDocument(name: '空白', elements: <WbElement>[]);
      final result = WbDocument.decode(document.encode());
      expect(result.document.elements, isEmpty);
      expect(result.document.name, '空白');
    });

    test('隐藏与锁定随文档保存', () {
      final hidden = _shape('h').copyWith(visible: false);
      final locked = _shape('l', x: 100).copyWith(locked: true);
      final document = WbDocument(name: 'x', elements: <WbElement>[hidden, locked]);
      final result = WbDocument.decode(document.encode());

      expect(result.document.elements[0].visible, isFalse);
      expect(result.document.elements[0].locked, isFalse);
      expect(result.document.elements[1].locked, isTrue);
      expect(result.document.elements[1].visible, isTrue);
    });

    test('旧文档没有可见字段时默认显示', () {
      final json = const WbDocument(name: 'x', elements: <WbElement>[]).toJson();
      json['elements'] = <Object?>[
        <String, Object?>{
          'type': 'shape',
          'id': 'a',
          'x': 0,
          'y': 0,
          'w': 100,
          'h': 60,
          'shape': 'rectangle',
        },
      ];
      final result = WbDocument.decode(jsonEncode(json));
      expect(result.document.elements.single.visible, isTrue);
      expect(result.document.elements.single.locked, isFalse);
    });

    test('编码结果带格式标识与版本', () {
      final json = const WbDocument(name: 'x', elements: <WbElement>[]).toJson();
      expect(json['format'], WbDocument.formatId);
      expect(json['version'], WbDocument.formatVersion);
      expect(json['createdAt'], isA<String>());
    });
  });

  group('画布底色', () {
    test('深色画布往返后仍是同一个颜色', () {
      const document = WbDocument(
        name: '夜景',
        elements: <WbElement>[],
        canvasColor: kCanvasInk,
      );
      final result = WbDocument.decode(document.encode());
      expect(result.document.canvasColor.toARGB32(), kCanvasInk.toARGB32());
      expect(result.warnings, isEmpty);
    });

    test('旧文档没有 canvas 字段时回落纸白', () {
      final result = WbDocument.decode('{"format":"wb-pro","version":1,"elements":[]}');
      expect(result.document.canvasColor.toARGB32(), kCanvasPaper.toARGB32());
      // 缺字段属于正常情况，不该弹「部分内容无法显示」。
      expect(result.hasWarnings, isFalse);
    });

    test('颜色类型不对或越界时回落，不报警告', () {
      for (final raw in <String>[
        '{"canvas":{"color":"#fff"},"elements":[]}',
        '{"canvas":{"color":-1},"elements":[]}',
        '{"canvas":{"color":99999999999},"elements":[]}',
        '{"canvas":"dark","elements":[]}',
      ]) {
        final result = WbDocument.decode(raw);
        expect(result.document.canvasColor.toARGB32(), kCanvasPaper.toARGB32());
        expect(result.hasWarnings, isFalse);
      }
    });

    test('半透明底色被还原成不透明', () {
      // 0x80FFFFFF：白色但 alpha 只有一半。半透明画布会让同一份文档在
      // 深浅色界面里长得不一样，读入时就归一。
      final result = WbDocument.decode('{"canvas":{"color":2164260863},"elements":[]}');
      expect(result.document.canvasColor.a, 1.0);
      expect(result.document.canvasColor.toARGB32(), 0xFFFFFFFF);
    });

    test('编码里带版本 2', () {
      final json = const WbDocument(name: 'x', elements: <WbElement>[]).toJson();
      expect(json['version'], 2);
      expect((json['canvas'] as Map)['color'], kCanvasPaper.toARGB32());
    });
  });

  group('拒绝非法文件', () {
    test('非 JSON 抛 DocumentException', () {
      expect(
        () => WbDocument.decode('这不是 json'),
        throwsA(isA<DocumentException>()),
      );
    });

    test('根节点不是对象时拒绝', () {
      expect(
        () => WbDocument.decode('[1, 2, 3]'),
        throwsA(isA<DocumentException>()),
      );
    });

    test('format 不匹配时拒绝', () {
      expect(
        () => WbDocument.decode('{"format":"other-app","elements":[]}'),
        throwsA(isA<DocumentException>()),
      );
    });

    test('没有 format 字段时按 wb-pro 接受（兼容早期手写文件）', () {
      final result = WbDocument.decode('{"elements":[]}');
      expect(result.document.elements, isEmpty);
    });
  });

  group('降级与警告', () {
    test('未知元素被跳过并给出数量', () {
      final result = WbDocument.decode('''
      {
        "format": "wb-pro",
        "version": 1,
        "elements": [
          {"type": "shape", "id": "ok", "x": 0, "y": 0, "w": 10, "h": 10},
          {"type": "hologram", "id": "bad"}
        ]
      }
      ''');
      expect(result.document.elements.length, 1);
      expect(result.hasWarnings, isTrue);
      expect(result.warnings.join(), contains('1 个元素'));
    });

    test('elements 不是数组时保留空画布', () {
      final result = WbDocument.decode('{"elements":"oops"}');
      expect(result.document.elements, isEmpty);
      expect(result.hasWarnings, isTrue);
    });

    test('更高版本给出提示但不拒绝', () {
      final result = WbDocument.decode('{"format":"wb-pro","version":99,"elements":[]}');
      expect(result.document.elements, isEmpty);
      expect(result.warnings.join(), contains('更新版本'));
    });

    test('缺失名称时用默认名', () {
      expect(WbDocument.decode('{"elements":[]}').document.name, '未命名白板');
      expect(WbDocument.decode('{"name":"   ","elements":[]}').document.name, '未命名白板');
    });
  });

  group('视口容错', () {
    test('越界缩放被夹回合法范围', () {
      final result = WbDocument.decode('{"elements":[],"viewport":{"zoom":9999}}');
      expect(result.document.zoom, 8);
    });

    test('非法缩放回落到 1', () {
      final result = WbDocument.decode('{"elements":[],"viewport":{"zoom":-3}}');
      expect(result.document.zoom, 1);
    });

    test('缺少视口时用默认值', () {
      final result = WbDocument.decode('{"elements":[]}');
      expect(result.document.pan, Offset.zero);
      expect(result.document.zoom, 1);
    });
  });
}
