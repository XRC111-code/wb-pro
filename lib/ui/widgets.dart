import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'theme.dart';

/// 统一的悬浮提示。
///
/// miuix 的 tooltip 走 Overlay，会自己处理越界翻转；Material 的 Tooltip 在
/// 屏幕边缘经常被裁掉一半。
Widget _tip({required String message, required Widget child}) {
  if (message.isEmpty) return child;
  return MiuixTooltipBox(
    positioning: MiuixTooltipAnchorPosition.below,
    tooltip: (context, scope) => MiuixPlainTooltip(
      scope: scope,
      child: Text(message),
    ),
    child: child,
  );
}

/// 浮在画布上的一小块：圆角、底色、极淡描边、轻阴影。
///
/// 整个界面没有顶栏条和状态栏条，所有 chrome 都是这个形状的浮层。参数少是
/// 故意的——一旦允许每个地方自己调圆角和阴影，界面就会散。
class WbFloatingBar extends StatelessWidget {
  const WbFloatingBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
    this.radius = WbTheme.radius,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: WbTheme.chromeDecoration(context, radius: radius),
      padding: padding,
      child: child,
    );
  }
}

/// 工具栏 / 顶栏上的图标按钮。
///
/// 常态完全透明，悬停才浮出一层淡底。浮动控件上如果每个按钮都画个方块，
/// 一条工具条会变成九宫格。
class WbIconButton extends StatelessWidget {
  const WbIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = 30,
    this.iconSize = 17,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = WbTheme.activeColor(context);
    final enabled = onPressed != null;
    final foreground = color ??
        (enabled
            ? (active ? accent : WbTheme.onChrome(context, alpha: 0.90))
            : WbTheme.onChrome(context, alpha: 0.28));
    return _tip(
      message: tooltip,
      child: MiuixIconButton(
        onPressed: onPressed,
        enabled: enabled,
        backgroundColor: active ? accent.withValues(alpha: 0.14) : null,
        cornerRadius: WbTheme.radiusSmall,
        minWidth: size,
        minHeight: size,
        child: MiuixIcon(icon: icon, size: iconSize, tint: foreground),
      ),
    );
  }
}

/// 快捷白板式工具卡片：图标在上、文字在下，整块可点。
///
/// 以前工具条是纯图标的，但工具一多就必须靠悬停才知道是什么；带一行短标签
/// 让「笔 / 橡皮 / 选择」一眼可辨，代价是每格宽到 60px。
///
/// 选中态是整块实底强调色（图标和文字一起变白），不是描边高亮——底部工具条
/// 有深色外壳托着，实底块比一圈细描边在余光里更容易定位。
class WbToolCard extends StatelessWidget {
  const WbToolCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.tooltip = '',
    this.iconSize = 18,
    this.minWidth = 60,
  });

  final IconData icon;

  /// 卡片下方的短标签（2~3 个字）。
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// 不可用时整块降透明度，但仍占位——工具条的位置不该随状态跳动。
  final bool enabled;

  /// 悬停提示。默认与标签相同，需要补充快捷键时传更长的文案。
  final String tooltip;
  final double iconSize;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final accent = WbTheme.activeColor(context);
    final fg = !enabled
        ? WbTheme.onCard.withValues(alpha: 0.32)
        : (selected ? WbTheme.onCardActive : WbTheme.onCard);

    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(WbTheme.cardRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: iconSize, color: fg),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: WbTheme.fontFamily,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w400,
              color: fg,
            ),
          ),
        ],
      ),
    );

    // 禁用时不挂 onPressed，而不是传 null：MiuixPressable 的 onPressed 是否
    // 可空取决于版本，这里绕开这个约定——禁用本来就不该有按压反馈。
    final interactive = enabled && onTap != null
        ? MiuixPressable(
            onPressed: onTap!,
            borderRadius: BorderRadius.circular(WbTheme.cardRadius),
            child: face,
          )
        : face;

    return _tip(message: tooltip.isEmpty ? label : tooltip, child: interactive);
  }
}

/// 一整组工具卡片：白色圆角条，内部按卡片逐个分隔。
///
/// 卡片之间那条 1px 竖线是这组控件能被读成「一个整体」的关键——没有它，
/// 一排白底方块会有各自独立的错觉。
class WbToolCardGroup extends StatelessWidget {
  const WbToolCardGroup({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: Colors.black.withValues(alpha: 0.08),
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: WbTheme.cardGroupDecoration(),
      padding: padding,
      height: WbTheme.cardBarHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WbTheme.cardRadius),
        child: Row(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// 属性面板里的分区标题。
class WbSection extends StatelessWidget {
  const WbSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: WbTheme.subtleText(context),
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

/// 一组可选的色块。
class WbColorGrid extends StatelessWidget {
  const WbColorGrid({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
    this.allowNone = false,
    this.noneLabel = '无',
    this.dotSize = 22,
  });

  final List<Color> colors;
  final Color? selected;
  final ValueChanged<Color?> onSelected;
  final bool allowNone;
  final String noneLabel;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final accent = WbTheme.activeColor(context);
    final count = colors.length + (allowNone ? 1 : 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 固定列数而不是让 Wrap 自由折行：12 个色板在 240 宽的面板里会折成
        // 7+5，第二行孤零零挂五个，看着像忘了摆整齐。列数按色板总数挑能整除的。
        final columns = _columnsFor(count);
        const gap = 4.0;
        final slot = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final dot = (slot - 6).clamp(14.0, dotSize).toDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            if (allowNone)
              _Dot(
                size: dot,
                slot: slot,
                color: null,
                label: noneLabel,
                selected: selected == null,
                accent: accent,
                onTap: () => onSelected(null),
              ),
            for (final color in colors)
              _Dot(
                size: dot,
                slot: slot,
                color: color,
                selected: selected != null &&
                    selected!.toARGB32() == color.toARGB32(),
                accent: accent,
                onTap: () => onSelected(color),
              ),
          ],
        );
      },
    );
  }

  static int _columnsFor(int count) {
    if (count <= 6) return count;
    for (final candidate in <int>[6, 5, 4]) {
      if (count % candidate == 0) return candidate;
    }
    return 6;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.slot,
    required this.color,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.label,
  });

  final double size;
  final double slot;
  final Color? color;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final border = WbTheme.hairline(context);
    return _tip(
      message: label ?? '',
      child: MiuixPressable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(slot / 2),
        child: SizedBox(
          width: slot,
          height: slot,
          child: Center(
            child: Container(
              width: size + 6,
              height: size + 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : Colors.transparent,
                  width: 1.8,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color ?? Colors.transparent,
                  border: Border.all(
                    color: color == null
                        ? border
                        : Colors.black.withValues(alpha: 0.10),
                  ),
                ),
                child: color == null
                    ? Icon(
                        Icons.block,
                        size: size * 0.66,
                        color: WbTheme.subtleText(context),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WbSegmentedOption<T> {
  const WbSegmentedOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 横向分段控件（线型、对齐这类 3~4 选 1 的场景）。
///
/// 用 miuix 的 TabRow：选中块会在两项之间滑动，比 Material 的
/// SegmentedButton 更接近手机系统的观感。图标选项退回自绘——TabRow 只吃文字。
class WbSegmented<T> extends StatelessWidget {
  const WbSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<WbSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.value == value);
    if (options.every((o) => o.icon == null)) {
      final dark = MiuixTheme.of(context).brightness == Brightness.dark;
      final accent = WbTheme.activeColor(context);
      return MiuixTabRow(
        tabs: <String>[for (final o in options) o.label],
        selectedTabIndex: index < 0 ? 0 : index,
        onTabSelected: (i) => onChanged(options[i].value),
        height: 30,
        cornerRadius: 8,
        itemSpacing: 3,
        minWidth: 0,
        maxWidth: double.infinity,
        colors: MiuixTabRowColors(
          backgroundColor:
              dark ? const Color(0xFF2C2E34) : const Color(0xFFF0F1F4),
          contentColor: WbTheme.subtleText(context),
          selectedBackgroundColor:
              dark ? const Color(0xFF3C3F46) : Colors.white,
          selectedContentColor: accent,
        ),
      );
    }
    return _iconSegmented(context, index);
  }

  Widget _iconSegmented(BuildContext context, int index) {
    final accent = WbTheme.activeColor(context);
    final dark = MiuixTheme.of(context).brightness == Brightness.dark;
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2C2E34) : const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: MiuixPressable(
                onPressed: () => onChanged(options[i].value),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? (dark ? const Color(0xFF3C3F46) : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: MiuixIcon(
                    icon: options[i].icon!,
                    size: 16,
                    tint: i == index ? accent : WbTheme.subtleText(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 带标签和数值的滑块。
class WbSliderRow extends StatelessWidget {
  const WbSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.formatter,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String Function(double)? formatter;

  /// 拖动开始/结束。用来把「一次拖动」压成一条历史记录，否则滑块每移动
  /// 一像素就写一次撤销栈。
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontFamily: WbTheme.fontFamily,
      fontSize: 12,
      color: WbTheme.subtleText(context),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          SizedBox(width: 42, child: Text(label, style: labelStyle)),
          Expanded(
            // miuix 的滑块没有 onChangeStart，用 Listener 在按下时补一个；
            // 结束信号它自带（onValueChangeFinished）。
            child: Listener(
              onPointerDown: (_) => onChangeStart?.call(value),
              child: MiuixSlider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                onValueChanged: onChanged,
                onValueChangeFinished: onChangeEnd == null
                    ? null
                    : () => onChangeEnd!(value.clamp(min, max).toDouble()),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              formatter?.call(value) ?? value.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: labelStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// 浮在画布上的圆角面板（属性面板）。
class WbPanel extends StatelessWidget {
  const WbPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.width,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: WbTheme.chromeDecoration(context),
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WbTheme.radius),
        child: child,
      ),
    );
  }
}

/// 面板里的小按钮（层级、对齐这类图标组）。
class WbMiniButton extends StatelessWidget {
  const WbMiniButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return WbIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      active: active,
      size: 26,
      iconSize: 15,
    );
  }
}
