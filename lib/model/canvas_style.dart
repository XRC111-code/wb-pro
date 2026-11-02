import 'dart:math' as math;
import 'dart:ui';

/// 画布底色与「什么颜色能在上面看清」。
///
/// 底色属于文档，不属于主题：同一份白板在深色和浅色界面里打开必须是同一个
/// 样子，否则发给别人看时就成了另一张图。主题只管外围的 chrome。
///
/// 颜色是绝对值的另一面是：画布变深之后，之前画的深色线条真的会消失。所以
/// 这里同时提供基于对比度的判断，让「默认笔色」在换底色时跟着翻面。

/// 旧文档没有 canvas 字段时的回落值，也是「纸白」预设。
const Color kCanvasPaper = Color(0xFFFAFAFA);

/// 深色画布的默认值（新建文档、深色主题下使用）。
const Color kCanvasInk = Color(0xFF131518);

/// 可选画布底色。
///
/// 只给四个：浅纸、暖纸、石板、墨黑。白板的底色是背景，不是调色盘 —— 选项
/// 一多，用户就会开始纠结用哪个灰，而不是画内容。
class CanvasPreset {
  const CanvasPreset(this.name, this.color, this.hint);

  final String name;
  final Color color;

  /// 一句话说明，显示在色卡下面。空字符串不显示。
  final String hint;

  bool matches(Color other) => color.toARGB32() == other.toARGB32();
}

const List<CanvasPreset> kCanvasPresets = <CanvasPreset>[
  CanvasPreset('纸白', kCanvasPaper, '默认'),
  CanvasPreset('暖纸', Color(0xFFF0E9DA), '护眼'),
  CanvasPreset('石板', Color(0xFF2B3036), '柔和'),
  CanvasPreset('墨黑', kCanvasInk, '高对比'),
];

/// 判断画布是不是深色。
///
/// 阈值取 0.42 而不是 0.5：`computeLuminance` 走的是 sRGB 线性化，中灰
/// (#808080) 的亮度只有 0.216，用 0.5 会把一半的中性灰误判成浅色。
bool isDarkCanvas(Color canvas) => canvas.computeLuminance() < 0.42;

/// 画布上的「墨色」——空状态提示、默认笔色都取它。
Color inkOnCanvas(Color canvas) =>
    isDarkCanvas(canvas) ? const Color(0xFFE7E9EC) : const Color(0xFF1F2933);

/// 网格点。深色画布上用白点，否则一层黑点会被底吃掉。
Color gridOnCanvas(Color canvas) => isDarkCanvas(canvas)
    ? const Color(0x14FFFFFF)
    : const Color(0x14000000);

/// 选中框垫底的那道线。浅色画布垫白，深色画布垫黑——两边都是「比底色更极端」，
/// 绿线才能从任意背景里立出来。
Color haloOnCanvas(Color canvas) =>
    isDarkCanvas(canvas) ? const Color(0xFF08090B) : const Color(0xFFFFFFFF);

/// WCAG 对比度（1–21）。用来判断某个笔色在这块底上还能不能看见。
///
/// 不追求 4.5:1 那种正文级标准：白板线条粗、面积大，2.0 左右就够辨认。用
/// 正文标准会导致「浅灰笔在米色纸上」被误判为不可见，然后被强行改成黑色。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 低于这个对比度就认为「落笔等于没画」。
const double kMinInkContrast = 2.0;

/// 这个笔色放在这块画布上是否还能看清。
bool isVisibleOn(Color ink, Color canvas) =>
    contrastRatio(ink, canvas) >= kMinInkContrast;

/// 给一块画布挑一个能看清的笔色：原来的还能用就保留，否则换成墨色。
Color readableInk(Color ink, Color canvas) =>
    isVisibleOn(ink, canvas) ? ink : inkOnCanvas(canvas);
