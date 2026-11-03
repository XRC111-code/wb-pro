import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_pro/io/export_svg.dart';
import 'package:wb_pro/model/element.dart';

const Color _black = Color(0xFF1F2933);

void main() {
  // TextPainter 需要绑定；这里只测纯字符串输出，不需要真实渲染。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('整体结构', () {
    test('空内容仍然输出合法的正尺寸画布', () {
      final svg = exportSvg(const <WbElement>[]);
      expect(svg.startsWith('<?xml'), isTrue);
      expect(svg, contains('<svg '));
      expect(svg, contains('viewBox='));
      expect(svg, contains('</svg>'));
      // width="0" 在多数渲染器里直接报错。
      expect(svg.contains('width="0"'), isFalse);
      expect(svg.contains('height="0"'), isFalse);
    });

    test('导出区域覆盖全部内容并留出边距', () {
      const area = Rect.fromLTWH(-100, -50, 300, 200);
      final padded = exportAreaFor(<WbElement>[
        ShapeElement(
          id: 'a',
          frame: area,
          shape: ShapeKind.rectangle,
          stroke: _black,
          strokeWidth: 2,
        ),
      ], padding: 20);
      expect(padded.left, lessThan(area.left));
      expect(padded.right, greaterThan(area.right));
      expect(padded.top, lessThan(area.top));
      expect(padded.bottom, greaterThan(area.bottom));
    });

    test('可选背景色', () {
      final without = exportSvg(
        const <WbElement>[],
        options: const SvgExportOptions(background: null),
      );
      expect(without.contains('fill="#ffffff"'), isFalse);

      final withBackground = exportSvg(const <WbElement>[]);
      expect(withBackground.toLowerCase().contains('fill="#ffffff"'), isTrue);
    });
  });

  group('元素输出', () {
    test('矩形输出 rect 与描边属性', () {
      final svg = exportSvg(<WbElement>[
        ShapeElement(
          id: 'r',
          frame: const Rect.fromLTWH(10, 20, 100, 50),
          shape: ShapeKind.rectangle,
          stroke: const Color(0xFFE03131),
          strokeWidth: 3,
          fill: const Color(0xFFFFE08A),
          cornerRadius: 8,
        ),
      ]);
      expect(svg, contains('<rect '));
      expect(svg, contains('fill="#ffe08a"'));
      expect(svg, contains('stroke="#e03131"'));
      expect(svg, contains('width="100"'));
      expect(svg, contains('rx="8"'));
    });

    test('椭圆输出 ellipse', () {
      final svg = exportSvg(<WbElement>[
        ShapeElement(
          id: 'e',
          frame: const Rect.fromLTWH(0, 0, 80, 40),
          shape: ShapeKind.ellipse,
          stroke: _black,
          strokeWidth: 2,
        ),
      ]);
      expect(svg, contains('<ellipse '));
      expect(svg, contains('rx="40"'));
      expect(svg, contains('ry="20"'));
    });

    test('菱形输出 polygon', () {
      final svg = exportSvg(<WbElement>[
        ShapeElement(
          id: 'd',
          frame: const Rect.fromLTWH(0, 0, 100, 100),
          shape: ShapeKind.diamond,
          stroke: _black,
          strokeWidth: 2,
        ),
      ]);
      expect(svg, contains('<polygon '));
      expect(svg, contains('50,0'));
    });

    test('虚线输出 dasharray', () {
      final svg = exportSvg(<WbElement>[
        ShapeElement(
          id: 'r',
          frame: const Rect.fromLTWH(0, 0, 10, 10),
          shape: ShapeKind.rectangle,
          stroke: _black,
          strokeWidth: 2,
          strokeStyle: StrokeStyle.dashed,
        ),
      ]);
      expect(svg, contains('stroke-dasharray'));
    });

    test('旋转元素包在 transform 里', () {
      final svg = exportSvg(<WbElement>[
        ShapeElement(
          id: 'r',
          frame: const Rect.fromLTWH(0, 0, 100, 50),
          shape: ShapeKind.rectangle,
          stroke: _black,
          strokeWidth: 2,
          rotation: math.pi / 2,
        ),
      ]);
      expect(svg, contains('rotate(90 50 25)'));
    });

    test('透明度小于 1 时输出 opacity', () {
      final svg = exportSvg(<WbElement>[
        ShapeElement(
          id: 'r',
          frame: const Rect.fromLTWH(0, 0, 10, 10),
          shape: ShapeKind.rectangle,
          stroke: _black,
          strokeWidth: 2,
          opacity: 0.4,
        ),
      ]);
      expect(svg, contains('opacity="0.4"'));
    });

    test('箭头按端点数输出 polyline', () {
      final single = exportSvg(<WbElement>[
        ArrowElement(
          id: 'a',
          frame: const Rect.fromLTWH(0, 0, 100, 0),
          start: Offset.zero,
          end: const Offset(100, 0),
          stroke: _black,
          strokeWidth: 2,
        ),
      ]);
      expect(RegExp('<polygon ').allMatches(single).length, 1);

      final both = exportSvg(<WbElement>[
        ArrowElement(
          id: 'a',
          frame: const Rect.fromLTWH(0, 0, 100, 0),
          start: Offset.zero,
          end: const Offset(100, 0),
          stroke: _black,
          strokeWidth: 2,
          startHead: true,
          endHead: true,
        ),
      ]);
      expect(RegExp('<polygon ').allMatches(both).length, 2);
    });

    test('笔迹输出平滑路径', () {
      final svg = exportSvg(<WbElement>[
        StrokeElement(
          id: 's',
          frame: const Rect.fromLTWH(0, 0, 100, 100),
          points: const <Offset>[
            Offset(0, 0),
            Offset(20, 30),
            Offset(60, 40),
            Offset(100, 100),
          ],
          color: _black,
          strokeWidth: 3,
        ),
      ]);
      expect(svg, contains('<path d="M 0 0'));
      expect(svg, contains(' Q '));
      expect(svg, contains('stroke-linecap="round"'));
    });

    test('图片内嵌为 data URI', () {
      final svg = exportSvg(<WbElement>[
        ImageElement(
          id: 'i',
          frame: const Rect.fromLTWH(0, 0, 10, 10),
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          mimeType: 'image/png',
        ),
      ]);
      expect(svg, contains('data:image/png;base64,'));
      expect(svg, contains('<image '));
    });

    test('空图片不产生垃圾标签', () {
      final svg = exportSvg(<WbElement>[
        ImageElement(
          id: 'i',
          frame: const Rect.fromLTWH(0, 0, 10, 10),
          bytes: Uint8List(0),
          mimeType: 'image/png',
        ),
      ]);
      expect(svg.contains('<image '), isFalse);
    });
  });

  group('文本', () {
    test('特殊字符被转义', () {
      final svg = exportSvg(<WbElement>[
        TextElement(
          id: 't',
          frame: const Rect.fromLTWH(0, 0, 400, 40),
          text: 'a & b < c > d "e"',
          color: _black,
          fontSize: 16,
        ),
      ]);
      expect(svg, contains('a &amp; b &lt; c &gt; d &quot;e&quot;'));
      expect(svg.contains('< c'), isFalse);
    });

    test('多行文本拆成 tspan', () {
      final svg = exportSvg(<WbElement>[
        TextElement(
          id: 't',
          frame: const Rect.fromLTWH(0, 0, 200, 100),
          text: '第一行\n第二行',
          color: _black,
          fontSize: 16,
        ),
      ]);
      expect(RegExp('<tspan').allMatches(svg).length, greaterThanOrEqualTo(2));
      expect(svg, contains('第一行'));
      expect(svg, contains('第二行'));
    });

    test('居中文本使用 text-anchor=middle', () {
      final svg = exportSvg(<WbElement>[
        TextElement(
          id: 't',
          frame: const Rect.fromLTWH(0, 0, 200, 40),
          text: '居中',
          color: _black,
          fontSize: 16,
          align: TextAlign.center,
        ),
      ]);
      expect(svg, contains('text-anchor="middle"'));
    });

    test('加粗与斜体写入字体属性', () {
      final svg = exportSvg(<WbElement>[
        TextElement(
          id: 't',
          frame: const Rect.fromLTWH(0, 0, 200, 40),
          text: 'Bold',
          color: _black,
          fontSize: 16,
          bold: true,
          italic: true,
        ),
      ]);
      expect(svg, contains('font-weight="700"'));
      expect(svg, contains('font-style="italic"'));
    });

    test('便签同时输出底色与文字', () {
      final svg = exportSvg(<WbElement>[
        NoteElement(
          id: 'n',
          frame: const Rect.fromLTWH(0, 0, 200, 200),
          text: '记得开会',
          fill: const Color(0xFFFFE08A),
        ),
      ]);
      expect(svg, contains('fill="#ffe08a"'));
      expect(svg, contains('记得开会'));
    });
  });

  group('压感笔迹', () {
    StrokeElement ink({List<double> pressures = const <double>[]}) => StrokeElement(
          id: 'k1',
          frame: const Rect.fromLTWH(0, 0, 60, 10),
          points: const <Offset>[
            Offset(0, 0),
            Offset(20, 5),
            Offset(40, 0),
            Offset(60, 5),
          ],
          color: _black,
          strokeWidth: 8,
          pressures: pressures,
        );

    test('有压力时输出填充轮廓和两个圆盖', () {
      final svg = exportSvg(<WbElement>[ink(pressures: const <double>[1, 0.5, 0.8, 0.3])]);
      expect(svg, contains('<path d="M'));
      expect(svg, contains('<circle'));
      expect(svg.contains('stroke-width="8"'), isFalse);
    });

    test('没有压力时保持等宽描边', () {
      final svg = exportSvg(<WbElement>[ink()]);
      expect(svg, contains('stroke-width="8"'));
      expect(svg, contains('fill="none"'));
    });
  });

  group('手绘风格', () {
    ShapeElement rough({double roughness = 1, int seed = 5}) => ShapeElement(
          id: 'r1',
          frame: const Rect.fromLTWH(0, 0, 160, 90),
          shape: ShapeKind.rectangle,
          stroke: _black,
          strokeWidth: 2,
          fill: const Color(0xFFFFFFFF),
          roughness: roughness,
          seed: seed,
        );

    test('手绘形状输出抖动路径而不是 rect', () {
      final svg = exportSvg(<WbElement>[rough()]);
      expect(svg, contains('<path'));
      // 填充仍然用几何形状，描边才是抖的
      expect(svg, contains('<rect'));
      expect(svg.contains('Q '), isTrue);
    });

    test('几何形状不输出 Q 命令', () {
      final svg = exportSvg(<WbElement>[rough(roughness: 0)]);
      expect(svg.contains('Q '), isFalse);
      expect(svg, contains('<rect'));
    });

    test('同一个形状两次导出完全一致', () {
      final a = exportSvg(<WbElement>[rough(seed: 11)]);
      final b = exportSvg(<WbElement>[rough(seed: 11)]);
      expect(a, b);
    });

    test('不同种子导出不同的抖动', () {
      final a = exportSvg(<WbElement>[rough(seed: 1)]);
      final b = exportSvg(<WbElement>[rough(seed: 2)]);
      expect(a, isNot(b));
    });
  });

  group('网格', () {
    test('开启后输出点阵', () {
      final svg = exportSvg(
        const <WbElement>[],
        options: const SvgExportOptions(includeGrid: true, gridSize: 100),
      );
      expect(svg, contains('<circle'));
    });

    test('关闭时不输出点阵', () {
      final svg = exportSvg(const <WbElement>[]);
      expect(svg.contains('<circle'), isFalse);
    });
  });
}
