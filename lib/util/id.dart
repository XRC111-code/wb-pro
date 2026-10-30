import 'dart:math' as math;

/// 生成元素 id。
///
/// 时间戳保证同一进程内单调，随机后缀处理「同一毫秒内新建多个元素」以及
/// 「从别的窗口粘贴过来的 id 碰巧相同」。用固定长度而不是自增整数：粘贴、
/// 撤销、合并文档时 id 必须全局唯一，自增计数器在跨文档场景下必然撞。
String newId(String prefix) {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = math.Random().nextInt(0x7FFFFFFF).toRadixString(36);
  return '$prefix-$stamp-$salt';
}
