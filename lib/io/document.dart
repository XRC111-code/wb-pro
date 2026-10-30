import 'dart:convert';
import 'dart:ui';

import '../model/element.dart';

/// 文档格式错误（文件不是 wb-pro、JSON 语法错、根节点类型不对）。
///
/// 和「某个元素读不出来」区分开：后者降级跳过并记 warning，前者必须让用户
/// 看到「这个文件打不开」。
class DocumentException implements Exception {
  const DocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解码结果。除了文档本身还带回降级信息，UI 可以据此提示
/// 「有 3 个元素来自更新的版本，已跳过」。
class DocumentDecodeResult {
  const DocumentDecodeResult(this.document, this.warnings);

  final WbDocument document;
  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// 一份白板文档。
///
/// 落盘格式刻意保持「一个 JSON 对象 + elements 数组」，元素内部结构由
/// `WbElement.toJson` 决定。这样新增元素类型时不需要动文档层。
class WbDocument {
  const WbDocument({
    required this.name,
    required this.elements,
    this.pan = Offset.zero,
    this.zoom = 1,
    this.createdAt,
    this.modifiedAt,
  });

  /// 文件头里的格式标识。读到别的值直接拒绝，避免把同名 JSON 当成白板。
  static const String formatId = 'wb-pro';
  static const int formatVersion = 1;
  static const String extension = 'wbpro';
  static const String suggestedExtension = '.wbpro';

  final String name;
  final List<WbElement> elements;
  final Offset pan;
  final double zoom;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'format': formatId,
        'version': formatVersion,
        'name': name,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'modifiedAt': (modifiedAt ?? DateTime.now()).toIso8601String(),
        'viewport': <String, Object?>{
          'panX': pan.dx,
          'panY': pan.dy,
          'zoom': zoom,
        },
        'elements': elements.map((e) => e.toJson()).toList(growable: false),
      };

  /// 紧凑编码。带缩进会让内嵌图片的 base64 把文件撑大一倍，而 .wbpro
  /// 本身不是给人手改的格式（要可读性请导出 SVG/PNG）。
  String encode() => jsonEncode(toJson());

  static DocumentDecodeResult decode(String source) {
    final warnings = <String>[];
    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (error) {
      throw DocumentException('不是有效的 JSON：${error.message}');
    }
    if (raw is! Map) {
      throw const DocumentException('文档根节点不是一个对象');
    }
    final map = Map<String, Object?>.from(raw);

    final format = map['format'];
    if (format is String && format != formatId) {
      throw DocumentException('不是 wb-pro 文档（format = "$format"）');
    }

    final declaredVersion = map['version'];
    if (declaredVersion is num && declaredVersion > formatVersion) {
      warnings.add('文档由更新版本的 wb-pro 创建（v${declaredVersion.toInt()}），'
          '部分内容可能无法显示。');
    }

    final elements = <WbElement>[];
    var skipped = 0;
    final rawElements = map['elements'];
    if (rawElements is List) {
      for (final item in rawElements) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        try {
          elements.add(WbElement.fromJson(Map<String, Object?>.from(item)));
        } catch (_) {
          // 单个元素坏掉不该让整份文档打不开 —— 白板里丢一个箭头远好过
          // 用户看到「文件已损坏」然后丢掉全部内容。
          skipped++;
        }
      }
    } else if (rawElements != null) {
      warnings.add('elements 字段不是数组，已忽略。');
    }
    if (skipped > 0) {
      warnings.add('有 $skipped 个元素无法识别，已跳过（可能来自更新的版本或已损坏）。');
    }

    final viewport = map['viewport'];
    var pan = Offset.zero;
    var zoom = 1.0;
    if (viewport is Map) {
      final v = Map<String, Object?>.from(viewport);
      pan = Offset(_double(v['panX']), _double(v['panY']));
      final rawZoom = _double(v['zoom'], 1);
      if (rawZoom.isFinite && rawZoom > 0) {
        zoom = rawZoom.clamp(0.05, 8).toDouble();
      }
    }

    final name = map['name'];
    return DocumentDecodeResult(
      WbDocument(
        name: name is String && name.trim().isNotEmpty ? name.trim() : '未命名白板',
        elements: List<WbElement>.unmodifiable(elements),
        pan: pan,
        zoom: zoom,
        createdAt: _parseDate(map['createdAt']),
        modifiedAt: _parseDate(map['modifiedAt']),
      ),
      warnings,
    );
  }

  static double _double(Object? value, [double fallback = 0]) =>
      value is num && value.isFinite ? value.toDouble() : fallback;

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
