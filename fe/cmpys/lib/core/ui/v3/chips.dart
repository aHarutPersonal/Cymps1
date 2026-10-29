import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'icons.dart';
import 'motion.dart';

const Color _white = Color(0xFFFFFFFF);

/// `Chip` from `v3/core.jsx`: a 38 pt pill toggle. When [on] it fills ink
/// (white when [dark]) and pops in a check; otherwise it shows the optional
/// [icon]. The selected state reaches semantics; the hit box is 44 pt tall.
///
/// Large text: the label stops growing at 2× and the pill grows from its
/// 38 pt minimum instead of clipping. In a bounded parent (a [Wrap]) a label
/// wider than the room ellipsizes; in an unbounded one (a horizontal
/// scroller) the chip is as wide as its label.
class V3Chip extends StatelessWidget {
  const V3Chip({
    super.key,
    required this.child,
    required this.onPressed,
    this.on = false,
    this.icon,
    this.dark = false,
  });

  /// Usually a [Text]; it inherits the chip's 14 pt w500 style.
  final Widget child;
  final VoidCallback? onPressed;
  final bool on;
  final V3Icons? icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final duration = motion ? const Duration(milliseconds: 250) : Duration.zero;
    final Color background;
    final Color foreground;
    final Color border;
    if (on) {
      background = dark ? _white : AppColors.ink;
      foreground = dark ? AppColors.ink : _white;
      border = const Color(0x00000000);
    } else {
      background = dark ? const Color(0x14FFFFFF) : AppColors.card;
      foreground = dark ? _white : AppColors.ink;
      border = dark ? const Color(0x24FFFFFF) : AppColors.hair;
    }

    final leading = on
        ? const V3Pop(child: V3Icon(V3Icons.check, size: 14, strokeWidth: 2.6))
        : icon == null
        ? null
        : V3Icon(icon!, size: 15);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2,
      child: V3Pressable(
        onTap: onPressed,
        selected: on,
        child: AnimatedContainer(
          duration: duration,
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: IconTheme(
            data: IconThemeData(color: foreground),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 6)],
                // Loose: it ellipsizes under a bounded width and lays out
                // at its own width under an unbounded one (no flex error).
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    style: AppTypography.sans(
                      14,
                      FontWeight.w500,
                    ).copyWith(color: foreground),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `Tag` from `v3/core.jsx`: a 24 pt label pill (11.5 pt w600) with an
/// optional 12 pt [icon]. Not interactive. [height], [horizontalPadding] and
/// [fontSize] are the design's `style` overrides (the mentor preview's domain
/// tags use 30 / 12 / 12.5).
class V3Tag extends StatelessWidget {
  const V3Tag({
    super.key,
    required this.child,
    this.color = AppColors.ink2,
    this.background = AppColors.paper2,
    this.icon,
    this.height = 24,
    this.horizontalPadding = 9,
    this.fontSize = 11.5,
  });

  /// Usually a [Text].
  final Widget child;

  /// Text and icon colour (the design's `c`).
  final Color color;

  /// Fill (the design's `bg`).
  final Color background;
  final V3Icons? icon;
  final double height;
  final double horizontalPadding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // A fixed-height pill: like the tab bar and top bar, its label stops
    // growing at 1.3× so large text can't push it past its row.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _pill(),
    );
  }

  Widget _pill() {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            V3Icon(icon!, size: 12, strokeWidth: 2.2, color: color),
            const SizedBox(width: 5),
          ],
          DefaultTextStyle(
            style: AppTypography.sans(
              fontSize,
              FontWeight.w600,
            ).copyWith(color: color, letterSpacing: 0.01 * fontSize),
            maxLines: 1,
            softWrap: false,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// One option of a [V3Seg].
@immutable
class V3SegItem<T> {
  const V3SegItem(this.value, this.label);

  final T value;
  final String label;
}

/// `Seg` from `v3/core.jsx`: a segmented control whose thumb slides to the
/// selected item on `--spring` (.45 s). It fills the available width (give
/// it a bounded width). Segments expose their selected state to semantics.
///
/// The track is the design's 42 pt (34 pt cells + 4 pt padding); the control
/// is laid out 44 pt tall so every segment meets the minimum tap target.
class V3Seg<T> extends StatelessWidget {
  const V3Seg({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.dark = false,
  });

  /// Key on the sliding thumb (tests and layout probes).
  static const thumbKey = ValueKey<String>('v3-seg-thumb');

  final List<V3SegItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // A fixed-height track: its labels stop growing at 2× (they clip from
    // about 2.35×).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2,
      child: Builder(builder: _track),
    );
  }

  Widget _track(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final index = math.max(0, items.indexWhere((item) => item.value == value));
    return SizedBox(
      height: kV3TapTarget,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = (constraints.maxWidth - 8) / items.length;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 1,
                bottom: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark ? const Color(0x14FFFFFF) : AppColors.paper2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: motion
                    ? const Duration(milliseconds: 450)
                    : Duration.zero,
                curve: AppMotion.spring,
                left: 4 + index * cell,
                top: 5,
                width: cell,
                height: 34,
                child: DecoratedBox(
                  key: thumbKey,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0x29FFFFFF) : AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: dark
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x14000000),
                              offset: Offset(0, 1),
                              blurRadius: 3,
                            ),
                          ],
                  ),
                ),
              ),
              Positioned.fill(
                left: 4,
                right: 4,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: V3Pressable(
                          pressedScale: 1,
                          minTapTarget: 0,
                          selected: i == index,
                          focusRadius: BorderRadius.circular(999),
                          onTap: () => onChanged(items[i].value),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: motion
                                  ? const Duration(milliseconds: 300)
                                  : Duration.zero,
                              style: AppTypography.sans(13.5, FontWeight.w600)
                                  .copyWith(
                                    color: i == index
                                        ? (dark ? _white : AppColors.ink)
                                        : (dark
                                              ? AppColors.nink3
                                              : AppColors.ink3),
                                  ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              child: Text(items[i].label),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
