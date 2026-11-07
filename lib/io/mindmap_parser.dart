import 'dart:convert';
import 'dart:io' show RawZLibFilter;
import 'dart:typed_data';

import '../model/mindmap.dart';

/// 支持的思维导图文件格式。
enum MindMapFormat {
  xmind('XMind'),
  freemind('FreeMind'),
  opml('OPML');

  const MindMapFormat(this.label);

  final String label;

  /// 按扩展名判断格式。不认识返回 null（调用方据此提示用户）。
  static MindMapFormat? fromFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'xmind':
        return MindMapFormat.xmind;
      case 'mm':
        return MindMapFormat.freemind;
      case 'opml':
        return MindMapFormat.opml;
      default:
        return null;
    }
  }
}

/// 解析失败时抛的异常，带一句能直接给用户看的话。
class MindMapParseException implements Exception {
  const MindMapParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 思维导图解析器：把 .xmind / .mm / .opml 变成 [MindMapNode] 树。
///
/// ── 与 doodlio 的差别 ──────────────────────────────────────────────────────
/// 那边把导入结果转成 **Markdown**（因为它有 Markdown 演示面板），导进来
/// 是一段文本。wb-pro 要的是**可编辑的画布对象**，所以这里直接产出节点树，
/// 不再经过 Markdown 这个中间形态 —— 走一趟文本再解析回树，只会丢信息
/// （层级、备注格式全被压平），还多两层出错的机会。
///
/// 全部是纯函数，不碰文件系统：调用方负责读字节，这里只负责解析。
class MindMapParser {
  const MindMapParser();

  /// 统一入口：按 [format] 分派。
  MindMapNode parse(Uint8List bytes, MindMapFormat format) {
    switch (format) {
      case MindMapFormat.xmind:
        return parseXMind(bytes);
      case MindMapFormat.freemind:
        return parseFreeMind(_decodeText(bytes));
      case MindMapFormat.opml:
        return parseOpml(_decodeText(bytes));
    }
  }

  /// 按文件名自动判格式并解析。
  MindMapNode parseFile(Uint8List bytes, String fileName) {
    final format = MindMapFormat.fromFileName(fileName);
    if (format == null) {
      throw MindMapParseException(
        '不认识的思维导图格式：$fileName。支持 .xmind / .mm / .opml。',
      );
    }
    return parse(bytes, format);
  }

  static String _decodeText(Uint8List bytes) {
    // XML 可能是 UTF-8 带 BOM，也可能是 GBK（老的 FreeMind 在中文 Windows
    // 上存的）。BOM 好办，GBK 不引库解不了 —— 直接按 UTF-8 解，坏字符
    // 留给上层显示，比抛异常吞掉整份文件好。
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ── XMind ────────────────────────────────────────────────────────────────
  //
  // .xmind 就是一个 zip。XMind 8+ 用 content.json（数组，每个元素是一张
  // 画布），更早的用 metadata.json。zip 读取由 [MiniZip] 负责，只支持
  // stored / deflate 两种压缩方式（XMind 实际只用这两种）。
  MindMapNode parseXMind(Uint8List bytes) {
    final entries = MiniZip.read(bytes);
    final content = entries['content.json'];
    if (content != null) {
      final data = jsonDecode(utf8.decode(content, allowMalformed: true));
      final sheets = data is List ? data : <Object?>[data];
      if (sheets.isNotEmpty && sheets.first is Map) {
        final sheet = (sheets.first as Map).cast<String, Object?>();
        final rootTopic = sheet['rootTopic'];
        if (rootTopic is Map) {
          return _xmindTopic(rootTopic.cast<String, Object?>(), 'n0');
        }
      }
    }
    // 老格式：拿不到树，至少把标题读出来，别让用户看到空白。
    final meta = entries['metadata.json'];
    if (meta != null) {
      try {
        final m = jsonDecode(utf8.decode(meta, allowMalformed: true));
        if (m is Map && m['title'] is String) {
          return MindMapNode(
            id: 'n0',
            title: m['title'] as String,
            children: const <MindMapNode>[],
          );
        }
      } catch (_) {/* 忽略，走下面的统一报错 */}
    }
    throw const MindMapParseException(
      '这份 .xmind 里没有 content.json，可能是很旧的格式，暂时读不了。',
    );
  }

  MindMapNode _xmindTopic(Map<String, Object?> topic, String id) {
    final title = topic['title'] is String ? topic['title'] as String : '';
    String note = '';
    final notes = topic['notes'];
    if (notes is Map) {
      final plain = notes['plain'];
      if (plain is Map && plain['content'] is String) {
        note = plain['content'] as String;
      }
    }

    final children = <MindMapNode>[];
    final rawChildren = topic['children'];
    if (rawChildren is Map) {
      // XMind 8+ 把子主题放在 children.attached
      final attached = rawChildren['attached'] ?? rawChildren['topics'];
      if (attached is List) {
        for (var i = 0; i < attached.length; i++) {
          if (attached[i] is Map) {
            children.add(_xmindTopic(
              (attached[i] as Map).cast<String, Object?>(),
              '$id-$i',
            ));
          }
        }
      }
    }

    return MindMapNode(id: id, title: title, note: note, children: children);
  }

  // ── FreeMind (.mm) ───────────────────────────────────────────────────────
  MindMapNode parseFreeMind(String xml) {
    final root = _parseXml(xml);
    final map = _firstElement(root, 'map');
    final node = map == null ? null : _firstElement(map, 'node');
    if (node == null) {
      throw const MindMapParseException('这份 .mm 里没有 <map><node> 结构。');
    }
    return _freeMindNode(node, 'n0');
  }

  MindMapNode _freeMindNode(_XmlNode el, String id) {
    final title = el.attributes['TEXT'] ?? el.attributes['text'] ?? '';
    var note = '';
    for (final child in el.children) {
      if (child.name == 'richcontent' &&
          (child.attributes['TYPE'] == 'NOTE' ||
              child.attributes['type'] == 'NOTE')) {
        // FreeMind 的 NOTE 通常包成
        //   <richcontent TYPE="NOTE"><html><body><p>正文</p></body></html></richcontent>
        // 正文在**后代**元素的 text 里，直接读 child.text 只会拿到空白。
        note = _collectText(child).trim();
        break;
      }
    }

    final children = <MindMapNode>[];
    var index = 0;
    for (final child in el.children) {
      if (child.name == 'node') {
        children.add(_freeMindNode(child, '$id-$index'));
        index++;
      }
    }
    return MindMapNode(id: id, title: title, note: note, children: children);
  }

  // ── OPML ─────────────────────────────────────────────────────────────────
  MindMapNode parseOpml(String xml) {
    final root = _parseXml(xml);
    final head = _firstElement(root, 'head');
    final titleEl = head == null ? null : _firstElement(head, 'title');
    final title = (titleEl?.text.trim().isNotEmpty ?? false)
        ? titleEl!.text.trim()
        : 'OPML';

    final body = _firstElement(root, 'body');
    final children = <MindMapNode>[];
    if (body != null) {
      var index = 0;
      for (final outline in body.children) {
        if (outline.name == 'outline') {
          children.add(_opmlOutline(outline, 'n0-$index'));
          index++;
        }
      }
    }
    return MindMapNode(id: 'n0', title: title, children: children);
  }

  MindMapNode _opmlOutline(_XmlNode el, String id) {
    final title = el.attributes['text'] ?? el.attributes['title'] ?? '';
    final note = el.attributes['_note'] ?? '';
    final children = <MindMapNode>[];
    var index = 0;
    for (final child in el.children) {
      if (child.name == 'outline') {
        children.add(_opmlOutline(child, '$id-$index'));
        index++;
      }
    }
    return MindMapNode(
      id: id,
      title: title,
      note: note,
      children: children,
    );
  }

  // ── 极简 XML ─────────────────────────────────────────────────────────────
  //
  // 不引 xml 包：wb-pro 现在是零第三方依赖（除了 UI 相关的 miuix / file
  // selector）。思维导图的 XML 结构非常规整（只有嵌套元素 + 属性），
  // 写一个够用的解析器比多一个依赖划算。
  //
  // 不支持的：命名空间前缀会被当普通名字、CDATA 会被当文本、注释会跳过。
  // 这三种在 .mm / .opml 里基本不出现；真遇到宁可少解析，也不抛异常吞文件。
  static _XmlNode _parseXml(String xml) {
    final root = _XmlNode('#document', <String, String>{});
    final stack = <_XmlNode>[root];
    var i = 0;

    while (i < xml.length) {
      final lt = xml.indexOf('<', i);
      if (lt < 0) break;

      if (xml.startsWith('<!--', lt)) {
        final end = xml.indexOf('-->', lt + 4);
        i = end < 0 ? xml.length : end + 3;
        continue;
      }
      if (xml.startsWith('<?', lt) || xml.startsWith('<!', lt)) {
        final end = xml.indexOf('>', lt);
        i = end < 0 ? xml.length : end + 1;
        continue;
      }

      final gt = _tagEnd(xml, lt);
      if (gt < 0) break;
      final body = xml.substring(lt + 1, gt);

      if (body.startsWith('/')) {
        if (stack.length > 1) stack.removeLast();
        i = gt + 1;
        continue;
      }

      final selfClosing = body.endsWith('/');
      final inner = selfClosing ? body.substring(0, body.length - 1) : body;
      final node = _parseTag(inner);
      stack.last.children.add(node);
      i = gt + 1;

      if (selfClosing) continue;

      // 收集文本直到下一个标签。
      final nextLt = xml.indexOf('<', i);
      final textEnd = nextLt < 0 ? xml.length : nextLt;
      if (textEnd > i) {
        node.text = node.text + xml.substring(i, textEnd);
      }
      stack.add(node);
    }
    return root;
  }

  /// 找标签的结束 `>`，跳过引号里的 `>`（属性值里可能有）。
  static int _tagEnd(String xml, int lt) {
    var quote = 0;
    for (var i = lt + 1; i < xml.length; i++) {
      final ch = xml.codeUnitAt(i);
      if (quote != 0) {
        if (ch == quote) quote = 0;
        continue;
      }
      if (ch == 0x22 || ch == 0x27) {
        quote = ch;
        continue;
      }
      if (ch == 0x3E) return i;
    }
    return -1;
  }

  static _XmlNode _parseTag(String inner) {
    final trimmed = inner.trim();
    var nameEnd = 0;
    while (nameEnd < trimmed.length &&
        !_isSpace(trimmed.codeUnitAt(nameEnd))) {
      nameEnd++;
    }
    final name = trimmed.substring(0, nameEnd);
    final node = _XmlNode(name, <String, String>{});

    var i = nameEnd;
    while (i < trimmed.length) {
      while (i < trimmed.length && _isSpace(trimmed.codeUnitAt(i))) {
        i++;
      }
      if (i >= trimmed.length) break;

      final keyStart = i;
      while (i < trimmed.length) {
        final ch = trimmed.codeUnitAt(i);
        if (ch == 0x3D || _isSpace(ch)) break;
        i++;
      }
      final key = trimmed.substring(keyStart, i);
      while (i < trimmed.length && _isSpace(trimmed.codeUnitAt(i))) {
        i++;
      }
      if (i < trimmed.length && trimmed.codeUnitAt(i) == 0x3D) {
        i++;
        while (i < trimmed.length && _isSpace(trimmed.codeUnitAt(i))) {
          i++;
        }
        if (i < trimmed.length &&
            (trimmed.codeUnitAt(i) == 0x22 || trimmed.codeUnitAt(i) == 0x27)) {
          final quote = trimmed.codeUnitAt(i);
          i++;
          final valStart = i;
          while (i < trimmed.length && trimmed.codeUnitAt(i) != quote) {
            i++;
          }
          final raw = trimmed.substring(valStart, i);
          node.attributes[key] = _unescape(raw);
          i++;
        }
      } else if (key.isNotEmpty) {
        node.attributes[key] = '';
      }
    }
    return node;
  }

  static bool _isSpace(int ch) =>
      ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D;

  static String _unescape(String raw) {
    if (!raw.contains('&')) return raw;
    return raw
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#10;', '\n')
        .replaceAll('&amp;', '&');
  }

  static _XmlNode? _firstElement(_XmlNode node, String name) {
    for (final child in node.children) {
      if (child.name == name) return child;
    }
    return null;
  }

  /// 收集一个元素及其所有后代里的文本，按出现顺序拼接。
  ///
  /// 用于 FreeMind 的 `<richcontent TYPE="NOTE"><html><body><p>…</p>…`：
  /// 正文埋在后代里，只读直接子节点的 text 会得到空串。
  static String _collectText(_XmlNode node) {
    final buffer = StringBuffer();
    void walk(_XmlNode n) {
      if (n.text.isNotEmpty) buffer.write(n.text);
      for (final child in n.children) {
        walk(child);
      }
    }

    walk(node);
    return buffer.toString();
  }
}

class _XmlNode {
  _XmlNode(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<_XmlNode> children = <_XmlNode>[];
  String text = '';
}

/// 极简 zip 读取器 —— 只做「按文件名取出条目」。
///
/// XMind 的包只用 deflate 或 stored 两种压缩方式，没有加密、没有 zip64
/// （实测 XMind 8 / XMind 2020+ 都是普通 zip）。这里只实现这两种。
///
/// 不引 `archive` 包的理由同上：为了读一个 content.json 多一个依赖不值得。
class MiniZip {
  const MiniZip._();

  /// 返回 文件名 → 内容。读不出来的条目会被跳过。
  static Map<String, Uint8List> read(Uint8List bytes) {
    final result = <String, Uint8List>{};
    final eocd = _findEndOfCentralDirectory(bytes);
    if (eocd < 0) {
      throw const MindMapParseException(
        '这不是一个有效的 .xmind 文件（找不到 zip 目录）。',
      );
    }

    final entryCount = _u16(bytes, eocd + 10);
    var offset = _u32(bytes, eocd + 16);
    final decoder = _RawInflater();

    for (var i = 0; i < entryCount; i++) {
      if (offset + 46 > bytes.length) break;
      if (_u32(bytes, offset) != 0x02014B50) break; // 中央目录签名

      final method = _u16(bytes, offset + 10);
      final compressedSize = _u32(bytes, offset + 20);
      final nameLen = _u16(bytes, offset + 28);
      final extraLen = _u16(bytes, offset + 30);
      final commentLen = _u16(bytes, offset + 32);
      final localOffset = _u32(bytes, offset + 42);

      final name = utf8.decode(
        bytes.sublist(offset + 46, offset + 46 + nameLen),
        allowMalformed: true,
      );

      // 本地头里的名字/extra 长度可能与中央目录不同，必须重新读。
      if (localOffset + 30 <= bytes.length &&
          _u32(bytes, localOffset) == 0x04034B50) {
        final localNameLen = _u16(bytes, localOffset + 26);
        final localExtraLen = _u16(bytes, localOffset + 28);
        final dataStart = localOffset + 30 + localNameLen + localExtraLen;
        final dataEnd = dataStart + compressedSize;

        if (dataEnd <= bytes.length) {
          final raw = bytes.sublist(dataStart, dataEnd);
          try {
            if (method == 0) {
              result[name] = raw;
            } else if (method == 8) {
              result[name] = decoder.inflate(raw);
            }
          } catch (_) {
            // 解不开就跳过这个条目，其余照常。
          }
        }
      }

      offset += 46 + nameLen + extraLen + commentLen;
    }
    return result;
  }

  static int _findEndOfCentralDirectory(Uint8List bytes) {
    // EOCD 在文件尾，最多带 64KB 注释。
    final min = bytes.length - 65557;
    for (var i = bytes.length - 22; i >= (min < 0 ? 0 : min); i--) {
      if (_u32(bytes, i) == 0x06054B50) return i;
    }
    return -1;
  }

  static int _u16(Uint8List b, int o) => o + 2 <= b.length ? b[o] | (b[o + 1] << 8) : 0;

  static int _u32(Uint8List b, int o) => o + 4 <= b.length
      ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
      : 0;
}

/// 原始 deflate（无 zlib 头）解压。
///
/// zip 条目里的 deflate 流是**裸的**：既没有两字节 zlib 头，也没有尾部的
/// Adler-32 校验。`ZLibDecoder` 期待完整 zlib 流，直接喂裸流会抛
/// `FormatException`；而 `RawZLibFilter.inflateFilter(raw: true)` 正是为
/// 这种情况准备的，用它即可。
class _RawInflater {
  Uint8List inflate(Uint8List raw) {
    final filter = RawZLibFilter.inflateFilter(raw: true);
    final out = <int>[];
    filter.process(raw, 0, raw.length);
    // 循环取尽：processed() 每次只吐一块，大文件不是一次就能拿完的。
    // 第一次 flush 把剩余数据推出来，之后返回空表示结束。
    while (true) {
      final chunk = filter.processed(flush: true);
      if (chunk == null || chunk.isEmpty) break;
      out.addAll(chunk);
    }
    return Uint8List.fromList(out);
  }
}
