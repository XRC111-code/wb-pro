import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/element.dart';
import '../render/painting.dart';
import 'export_svg.dart' show exportAreaFor;

/// PNG 导出参数。
class PngExportOptions {
  const PngExportOptions({
    this.padding = 32,
    this.pixelRatio = 2,
    this.background = const Color(0xFFFFFFFF),
  });

  final double padding;

  /// 每个逻辑像素对应的物理像素。2 在 Retina/高分屏上清晰，文件也不至于太大。
  final double pixelRatio;

  /// null 表示透明背景。
  final Color? background;
}

/// 把场景渲染成 PNG 字节。
///
/// 走 `PictureRecorder` 而不是截屏：截屏受当前缩放影响、会把选择框一起拍进去，
/// 而且在高缩放时分辨率反而不够。
Future<Uint8List> exportPng(
  List<WbElement> elements, {
  PngExportOptions options = const PngExportOptions(),
}) async {
  await ImageRegistry.preload(elements.whereType<ImageElement>());

  final area = exportAreaFor(elements, padding: options.padding);

  // 超大画布（几万元素摊开）直接按 2x 会撞到 GPU 的纹理上限，这里按最长边
  // 收敛比例；宁可糊一点，也不能抛异常导致整个导出失败。
  const maxSide = 8192.0;
  var ratio = options.pixelRatio;
  final longSide = math.max(area.width, area.height);
  if (longSide > 0 && longSide * ratio > maxSide) {
    ratio = maxSide / longSide;
  }
  ratio = ratio.clamp(0.02, 8.0).toDouble();

  final width = math.max(1, (area.width * ratio).round());
  final height = math.max(1, (area.height * ratio).round());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  canvas.scale(ratio);
  canvas.translate(-area.left, -area.top);

  final background = options.background;
  if (background != null) {
    canvas.drawRect(area, Paint()..color = background);
  }
  paintScene(canvas, elements, area);

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG 编码失败：设备未返回图像数据');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
