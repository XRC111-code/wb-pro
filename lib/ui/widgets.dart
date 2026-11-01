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

/// 工具栏 / 顶栏上的图标按钮。
class WbIconButton extends StatelessWidget {
  const WbIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = 34,
    this.iconSize = 18,
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
        (!enabled
            ? MiuixTheme.of(context).colors.disabledOnSurface
            : active
                ? accent
                : MiuixTheme.of(context).colors.onSurfaceSecondary);
    return _tip(
      message: tooltip,
      child: MiuixIconButton(
        onPressed: onPressed,
        enabled: enabled,
        backgroundColor: active ? accent.withValues(alpha: 0.12) : null,
        cornerRadius: WbTheme.radiusSmall,
        minWidth: size,
        minHeight: size,
        child: MiuixIcon(icon: icon, size: iconSize, tint: foreground),
      ),
    );
  }
}

/// 左侧工具栏里的工具按钮。比顶栏按钮大一圈，选中时是实心强调色。
class WbToolButton extends StatelessWidget {
  const WbToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = WbTheme.activeColor(context);
    return _tip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: MiuixIconButton(
          onPressed: onTap,
          backgroundColor: selected ? accent : null,
          cornerRadius: 12,
          minWidth: 40,
          minHeight: 38,
          child: MiuixIcon(
            icon: icon,
            size: 19,
            tint: selected
                ? Colors.white
                : MiuixTheme.of(context).colors.onSurfaceSecondary,
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              MiuixSmallTitle(
                title,
                textColor: WbTheme.subtleText(context),
                insideMargin: const EdgeInsets.symmetric(vertical: 6),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
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
        final slot =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
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
                selected:
                    selected != null && selected!.toARGB32() == color.toARGB32(),
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
        height: 32,
        cornerRadius: 9,
        itemSpacing: 3,
        minWidth: 0,
        maxWidth: double.infinity,
        colors: MiuixTabRowColors(
          backgroundColor: dark ? const Color(0xFF262A31) : const Color(0xFFEFF1F4),
          contentColor: WbTheme.subtleText(context),
          selectedBackgroundColor: dark ? const Color(0xFF3A3F47) : Colors.white,
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
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF262A31) : const Color(0xFFEFF1F4),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: MiuixPressable(
                onPressed: () => onChanged(options[i].value),
                borderRadius: BorderRadius.circular(7),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? (dark ? const Color(0xFF3A3F47) : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
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
          SizedBox(
            width: 42,
            child: Text(label, style: labelStyle),
          ),
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

/// 浮在画布上的圆角面板。
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
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WbTheme.radius),
        child: MiuixSurface(
          cornerRadius: WbTheme.radius,
          shadowElevation: 10,
          child: Padding(padding: padding, child: child),
        ),
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
      size: 30,
      iconSize: 16,
    );
  }
}
