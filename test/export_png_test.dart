import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/io/export_png.dart';
import 'package:wb_pro/model/element.dart';

const List<int> _pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

int _uint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

WbElement _rect(double width, double height) => ShapeElement(
      id: 'r',
      frame: Rect.fromLTWH(0, 0, width, height),
      shape: ShapeKind.rectangle,
      stroke: const Color(0xFF1F2933),
      strokeWidth: 2,
      fill: const Color(0xFFFFE08A),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PNG 导出', () {
    test('输出合法的 PNG 文件头', () async {
      final bytes = await exportPng(<WbElement>[_rect(100, 50)]);
      expect(bytes.length, greaterThan(64));
      expect(bytes.sublist(0, 8), _pngMagic);
    });

    test('尺寸等于内容范围加边距', () async {
      final bytes = await exportPng(
        <WbElement>[_rect(100, 50)],
        options: const PngExportOptions(pixelRatio: 1, padding: 32),
      );
      // exportAreaFor 会额外留 8px 给线宽与阴影。
      expect(_uint32(bytes, 16), 180);
      expect(_uint32(bytes, 20), 130);
    });

    test('pixelRatio 按倍数放大像素尺寸', () async {
      final bytes = await exportPng(
        <WbElement>[_rect(100, 50)],
        options: const PngExportOptions(pixelRatio: 2, padding: 32),
      );
      expect(_uint32(bytes, 16), 360);
      expect(_uint32(bytes, 20), 260);
    });

    test('空场景也能导出（默认 800×600 画布）', () async {
      final bytes = await exportPng(
        const <WbElement>[],
        options: const PngExportOptions(pixelRatio: 1, padding: 32),
      );
      expect(bytes.sublist(0, 8), _pngMagic);
      expect(_uint32(bytes, 16), 864);
      expect(_uint32(bytes, 20), 664);
    });

    test('透明背景不报错', () async {
      final bytes = await exportPng(
        <WbElement>[_rect(40, 40)],
        options: const PngExportOptions(background: null, pixelRatio: 1),
      );
      expect(bytes.sublist(0, 8), _pngMagic);
    });

    test('超大内容自动降低像素比而不是崩溃', () async {
      final bytes = await exportPng(
        <WbElement>[_rect(20000, 12000)],
        options: const PngExportOptions(pixelRatio: 2, padding: 8),
      );
      expect(bytes.sublist(0, 8), _pngMagic);
      expect(_uint32(bytes, 16), lessThanOrEqualTo(8192));
      expect(_uint32(bytes, 20), lessThanOrEqualTo(8192));
    });
  });
}
