import 'dart:ui';

/// 统一的颜色序列化入口。
///
/// Flutter 3.27 起 `Color.value` 被弃用，`toARGB32()` 才是稳定 API；
/// 直接写 `.value` 会在 analyze 里报 deprecated，且未来会移除。
int argbOf(Color color) => color.toARGB32();

/// 从 0xAARRGGBB 还原。
///
/// 不用 `Color(int)` 构造：它接受的是「ARGB 顺序的 int」但语义上容易和
/// `Color.fromARGB` 混，这里显式拆通道，读代码的人不用猜。
Color colorOf(int argb) => Color.fromARGB(
      (argb >> 24) & 0xFF,
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
    );

/// 带透明度的同一个颜色（不改原对象的 alpha）。
Color withOpacityValue(Color color, double opacity) =>
    color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0));
