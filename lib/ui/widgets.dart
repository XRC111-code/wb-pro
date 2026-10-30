import 'package:flutter/material.dart';

import 'theme.dart';

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
            ? WbTheme.subtleText(context).withValues(alpha: 0.35)
            : active
                ? accent
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.78));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(WbTheme.radiusSmall),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: foreground),
          ),
        ),
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
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 38,
              child: Icon(
                icon,
                size: 19,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.76),
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: WbTheme.subtleText(context),
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
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
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: <Widget>[
        if (allowNone)
          _Dot(
            size: dotSize,
            color: null,
            label: noneLabel,
            selected: selected == null,
            accent: accent,
            onTap: () => onSelected(null),
          ),
        for (final color in colors)
          _Dot(
            size: dotSize,
            color: color,
            selected: selected != null && selected!.toARGB32() == color.toARGB32(),
            accent: accent,
            onTap: () => onSelected(color),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.color,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.label,
  });

  final double size;
  final Color? color;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final border = WbTheme.hairline(context);
    return Tooltip(
      message: label ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size + 6,
          height: size + 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.6,
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
                color: color == null ? border : Colors.black.withValues(alpha: 0.10),
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
    );
  }
}

class WbSegmentedOption<T> {
  const WbSegmentedOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 横向分段控件（线型、字号档位这类 3~4 选 1 的场景）。
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
    final accent = WbTheme.activeColor(context);
    final surface = WbTheme.panelColor(context);
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: <Widget>[
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option.value == value ? surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: option.value == value
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: option.icon == null
                      ? Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: option.value == value ? FontWeight.w600 : FontWeight.w400,
                            color: option.value == value
                                ? accent
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7),
                          ),
                        )
                      : Icon(
                          option.icon,
                          size: 16,
                          color: option.value == value ? accent : WbTheme.subtleText(context),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: WbTheme.subtleText(context)),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                activeTrackColor: WbTheme.activeColor(context),
                inactiveTrackColor: WbTheme.hairline(context),
                thumbColor: WbTheme.activeColor(context),
                overlayColor: WbTheme.activeColor(context).withValues(alpha: 0.12),
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                onChangeStart: onChangeStart,
                onChangeEnd: onChangeEnd,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              formatter?.call(value) ?? value.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: WbTheme.subtleText(context)),
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
    return Container(
      width: width,
      padding: padding,
      decoration: WbTheme.panelDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: child,
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
