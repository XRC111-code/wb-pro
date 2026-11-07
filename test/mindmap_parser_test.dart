import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/io/mindmap_parser.dart';
import 'package:wb_pro/model/mindmap.dart';

/// 造一个最小 zip：只含 stored（不压缩）条目。
///
/// 手写 zip 而不是引 archive 包 —— 测试的目的就是验证我们自己的 zip
/// 读取器，用同一个第三方库生成再读回来，等于自己验自己。
Uint8List _buildZip(Map<String, List<int>> entries, {bool deflate = false}) {
  final localParts = <int>[];
  final centralParts = <int>[];
  final offsets = <int>[];

  void u16(List<int> out, int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
  }

  void u32(List<int> out, int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 24) & 0xFF);
  }

  for (final entry in entries.entries) {
    final name = utf8.encode(entry.key);
    final raw = Uint8List.fromList(entry.value);
    final data = deflate ? _deflateRaw(raw) : raw;
    final method = deflate ? 8 : 0;
    final crc = _crc32(raw);

    offsets.add(localParts.length);

    // 本地文件头
    u32(localParts, 0x04034B50);
    u16(localParts, 20);
    u16(localParts, 0);
    u16(localParts, method);
    u16(localParts, 0);
    u16(localParts, 0);
    u32(localParts, crc);
    u32(localParts, data.length);
    u32(localParts, raw.length);
    u16(localParts, name.length);
    u16(localParts, 0);
    localParts.addAll(name);
    localParts.addAll(data);

    // 中央目录
    u32(centralParts, 0x02014B50);
    u16(centralParts, 20);
    u16(centralParts, 20);
    u16(centralParts, 0);
    u16(centralParts, method);
    u16(centralParts, 0);
    u16(centralParts, 0);
    u32(centralParts, crc);
    u32(centralParts, data.length);
    u32(centralParts, raw.length);
    u16(centralParts, name.length);
    u16(centralParts, 0);
    u16(centralParts, 0);
    u16(centralParts, 0);
    u16(centralParts, 0);
    u32(centralParts, 0);
    u32(centralParts, offsets.last);
    centralParts.addAll(name);
  }

  final out = <int>[];
  out.addAll(localParts);
  final centralStart = out.length;
  out.addAll(centralParts);

  // EOCD
  u32(out, 0x06054B50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, centralParts.length);
  u32(out, centralStart);
  u16(out, 0);

  return Uint8List.fromList(out);
}

/// 裸 deflate 压缩（不带 zlib 头）。
Uint8List _deflateRaw(Uint8List data) {
  final encoded = const ZLibEncoder(raw: true).convert(data);
  return Uint8List.fromList(encoded);
}

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (~crc) & 0xFFFFFFFF;
}

void main() {
  const parser = MindMapParser();

  group('格式识别', () {
    test('按扩展名认格式，大小写不敏感', () {
      expect(MindMapFormat.fromFileName('a.xmind'), MindMapFormat.xmind);
      expect(MindMapFormat.fromFileName('a.XMIND'), MindMapFormat.xmind);
      expect(MindMapFormat.fromFileName('a.mm'), MindMapFormat.freemind);
      expect(MindMapFormat.fromFileName('b.OPML'), MindMapFormat.opml);
    });

    test('不认识的扩展名返回 null', () {
      expect(MindMapFormat.fromFileName('a.png'), isNull);
      expect(MindMapFormat.fromFileName('noext'), isNull);
    });

    test('不认识的文件抛带用户可读信息的异常', () {
      expect(
        () => parser.parseFile(Uint8List(0), 'a.png'),
        throwsA(isA<MindMapParseException>().having(
          (e) => e.message,
          'message',
          contains('不认识的思维导图格式'),
        )),
      );
    });
  });

  group('XMind 解析', () {
    test('content.json 里的树能完整还原（stored）', () {
      final content = jsonEncode(<Object?>[
        <String, Object?>{
          'rootTopic': <String, Object?>{
            'title': '根主题',
            'children': <String, Object?>{
              'attached': <Object?>[
                <String, Object?>{
                  'title': '分支一',
                  'notes': <String, Object?>{
                    'plain': <String, Object?>{'content': '这是备注'}
                  },
                  'children': <String, Object?>{
                    'attached': <Object?>[
                      <String, Object?>{'title': '孙节点'},
                    ],
                  },
                },
                <String, Object?>{'title': '分支二'},
              ],
            },
          },
        },
      ]);
      final zip = _buildZip(<String, List<int>>{
        'content.json': utf8.encode(content),
      });

      final tree = parser.parseXMind(zip);
      expect(tree.title, '根主题');
      expect(tree.children, hasLength(2));
      expect(tree.children[0].title, '分支一');
      expect(tree.children[0].note, '这是备注');
      expect(tree.children[0].children.first.title, '孙节点');
      expect(tree.children[1].title, '分支二');
    });

    test('content.json 为 deflate 压缩时也能读', () {
      final content = jsonEncode(<Object?>[
        <String, Object?>{
          'rootTopic': <String, Object?>{
            'title': '压缩的根',
            'children': <String, Object?>{
              'attached': <Object?>[
                <String, Object?>{'title': '子'}
              ],
            },
          },
        },
      ]);
      final zip = _buildZip(
        <String, List<int>>{'content.json': utf8.encode(content)},
        deflate: true,
      );

      final tree = parser.parseXMind(zip);
      expect(tree.title, '压缩的根');
      expect(tree.children.single.title, '子');
    });

    test('content.json 是单个对象（非数组）也能读', () {
      final content = jsonEncode(<String, Object?>{
        'rootTopic': <String, Object?>{'title': '单个 sheet'},
      });
      final zip = _buildZip(<String, List<int>>{
        'content.json': utf8.encode(content),
      });
      expect(parser.parseXMind(zip).title, '单个 sheet');
    });

    test('只有 metadata.json 时退回读标题', () {
      final zip = _buildZip(<String, List<int>>{
        'metadata.json': utf8.encode(jsonEncode(<String, Object?>{'title': '老格式'})),
      });
      final tree = parser.parseXMind(zip);
      expect(tree.title, '老格式');
      expect(tree.children, isEmpty);
    });

    test('两个都没有时抛可读异常', () {
      final zip = _buildZip(<String, List<int>>{
        'other.txt': utf8.encode('nothing'),
      });
      expect(
        () => parser.parseXMind(zip),
        throwsA(isA<MindMapParseException>()),
      );
    });

    test('不是 zip 时抛可读异常', () {
      expect(
        () => parser.parseXMind(Uint8List.fromList(<int>[1, 2, 3, 4, 5])),
        throwsA(isA<MindMapParseException>().having(
          (e) => e.message,
          'message',
          contains('不是'),
        )),
      );
    });
  });

  group('FreeMind 解析', () {
    test('嵌套 node 的 TEXT 还原成树', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<map version="1.0.1">
  <node TEXT="中心主题">
    <node TEXT="分支甲">
      <node TEXT="叶子"/>
    </node>
    <node TEXT="分支乙">
      <richcontent TYPE="NOTE">一段备注</richcontent>
    </node>
  </node>
</map>''';
      final tree = parser.parseFreeMind(xml);
      expect(tree.title, '中心主题');
      expect(tree.children.map((n) => n.title), <String>['分支甲', '分支乙']);
      expect(tree.children.first.children.single.title, '叶子');
      expect(tree.children[1].note, '一段备注');
    });

    test('富文本 NOTE（正文埋在后代 p 里）也能取到', () {
      // FreeMind 实际存的就是这个形状，只读直接子节点的 text 会拿到空串。
      const xml = '''
<map><node TEXT="根">
  <node TEXT="带备注">
    <richcontent TYPE="NOTE"><html><body><p>第一段</p><p>第二段</p></body></html></richcontent>
  </node>
</node></map>''';
      final tree = parser.parseFreeMind(xml);
      expect(tree.children.single.note, contains('第一段'));
      expect(tree.children.single.note, contains('第二段'));
    });

    test('属性值里的 &amp; 等实体被还原', () {
      const xml = '''
<map><node TEXT="A &amp; B &lt;test&gt;">
  <node TEXT="child"/>
</node></map>''';
      final tree = parser.parseFreeMind(xml);
      expect(tree.title, 'A & B <test>');
    });

    test('小写 text 属性也认（有些工具这样写）', () {
      const xml = '<map><node text="小写"><node TEXT="子"/></node></map>';
      expect(parser.parseFreeMind(xml).title, '小写');
    });

    test('没有 map/node 结构时抛异常', () {
      expect(
        () => parser.parseFreeMind('<html><body/></html>'),
        throwsA(isA<MindMapParseException>()),
      );
    });

    test('属性值里带 > 不会把标签截断', () {
      const xml = '<map><node TEXT="a &gt; b"><node TEXT="子"/></node></map>';
      final tree = parser.parseFreeMind(xml);
      expect(tree.title, 'a > b');
      expect(tree.children.single.title, '子');
    });
  });

  group('OPML 解析', () {
    test('head/title 作为根，body 下的 outline 作为子节点', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head><title>我的大纲</title></head>
  <body>
    <outline text="第一章">
      <outline text="1.1 小节"/>
      <outline text="1.2 小节"/>
    </outline>
    <outline text="第二章"/>
  </body>
</opml>''';
      final tree = parser.parseOpml(xml);
      expect(tree.title, '我的大纲');
      expect(tree.children.map((n) => n.title), <String>['第一章', '第二章']);
      expect(tree.children.first.children.map((n) => n.title),
          <String>['1.1 小节', '1.2 小节']);
    });

    test('title 属性也能当正文（有些工具这么写）', () {
      const xml = '<opml><head><title>T</title></head>'
          '<body><outline title="用 title 属性"/></body></opml>';
      expect(parser.parseOpml(xml).children.single.title, '用 title 属性');
    });

    test('_note 属性作为备注', () {
      const xml = '<opml><head><title>T</title></head>'
          '<body><outline text="条目" _note="说明"/></body></opml>';
      expect(parser.parseOpml(xml).children.single.note, '说明');
    });

    test('没有 head/title 时用 OPML 兜底', () {
      const xml = '<opml><body><outline text="只有条目"/></body></opml>';
      expect(parser.parseOpml(xml).title, 'OPML');
    });
  });

  group('parseFile 统一入口', () {
    test('按文件名分派到对应解析器', () {
      const xml = '<map><node TEXT="来自 mm"/></map>';
      final tree = parser.parseFile(
        Uint8List.fromList(utf8.encode(xml)),
        'a.mm',
      );
      expect(tree.title, '来自 mm');
    });

    test('UTF-8 BOM 不影响解析', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('<map><node TEXT="有BOM"/></map>')];
      final tree = parser.parseFile(Uint8List.fromList(bytes), 'a.mm');
      expect(tree.title, '有BOM');
    });
  });

  group('解析结果可直接用于布局', () {
    test('解析出的树交给布局引擎能产出节点', () {
      const xml = '''
<map><node TEXT="根">
  <node TEXT="甲"><node TEXT="甲1"/></node>
  <node TEXT="乙"/>
</node></map>''';
      final tree = parser.parseFreeMind(xml);
      const engine = MindMapLayoutEngine();
      final layout = engine.layout(<MindMapNode>[tree]);
      expect(layout.boxes, hasLength(4));
      expect(layout.boxOf(tree.id)?.depth, 0);
    });
  });
}
