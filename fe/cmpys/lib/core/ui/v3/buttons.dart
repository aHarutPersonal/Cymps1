import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'icons.dart';
import 'motion.dart';

/// `Btn` kinds from `v3/core.jsx`.
enum V3ButtonKind { primary, dark, light, soft, glass, ghost, line, iris, sage }

/// `Btn` sizes: [lg] 54 pt, [md] 44 pt, [sm] 36 pt tall.
enum V3Size {
  lg(54),
  md(44),
  sm(36);

  const V3Size(this.height);

  /// Visual height of the pill.
  final double height;
}

class _ButtonPalette {
  const _ButtonPalette(
    this.background,
    this.foreground, {
    this.border,
    this.shadow,
  });

  final Color background;
  final Color foreground;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;
}

const Color _white = Color(0xFFFFFFFF);

_ButtonPalette _palette(V3ButtonKind kind) => switch (kind) {
  // 0 8px 22px -8px oklch(0.6 0.17 42 / .7)
  V3ButtonKind.primary => const _ButtonPalette(
    AppColors.ember,
    _white,
    shadow: [
      BoxShadow(
        color: Color(0xB3D05418),
        offset: Offset(0, 8),
        blurRadius: 22,
        spreadRadius: -8,
      ),
    ],
  ),
  V3ButtonKind.dark => const _ButtonPalette(AppColors.ink, _white),
  V3ButtonKind.light => const _ButtonPalette(_white, AppColors.ink),
  V3ButtonKind.soft => const _ButtonPalette(AppColors.paper2, AppColors.ink),
  // rgba(255,255,255,.12) with a 1px rgba(255,255,255,.16) border.
  V3ButtonKind.glass => _ButtonPalette(
    const Color(0x1FFFFFFF),
    _white,
    border: Border.all(color: const Color(0x29FFFFFF)),
  ),
  V3ButtonKind.ghost => const _ButtonPalette(Color(0x00000000), AppColors.ink2),
  V3ButtonKind.line => _ButtonPalette(
    const Color(0x00000000),
    AppColors.ink,
    border: Border.all(color: AppColors.hair2, width: 1.5),
  ),
  V3ButtonKind.iris => const _ButtonPalette(AppColors.iris, _white),
  V3ButtonKind.sage => const _ButtonPalette(AppColors.sage2, _white),
};

/// `Btn` from `v3/core.jsx`: a pill button in one of nine [kind]s and three
/// [size]s, with optional leading [icon] / trailing [iconRight].
///
/// [disabled] (or a null [onPressed]) fades it to .38, drops the shadow and
/// ignores taps; [loading] swaps the content for a [V3Spinner] and ignores
/// taps. [full] stretches it to the available width. The hit box is at least
/// 44 pt tall even for [V3Size.sm].
class V3Button extends StatelessWidget {
  const V3Button({
    super.key,
    this.kind = V3ButtonKind.primary,
    this.size = V3Size.lg,
    this.icon,
    this.iconRight,
    this.child,
    required this.onPressed,
    this.disabled = false,
    this.loading = false,
    this.full = false,
    this.semanticLabel,
  });

  final V3ButtonKind kind;
  final V3Size size;
  final V3Icons? icon;
  final V3Icons? iconRight;

  /// Usually a [Text]; it inherits the button's 15.5 / 13.5 pt w600 style.
  final Widget? child;
  final VoidCallback? onPressed;
  final bool disabled;
  final bool loading;
  final bool full;

  /// Overrides the label read by screen readers (defaults to [child]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(kind);
    final inactive = disabled || onPressed == null;
    final small = size == V3Size.sm;
    final fontSize = small ? 13.5 : 15.5;
    final iconSize = small ? 16.0 : 18.0;
    final motion = MotionConfig.enabled(context);

    final Widget content;
    if (loading) {
      content = V3Spinner(color: palette.foreground);
    } else {
      final parts = <Widget>[
        if (icon != null) V3Icon(icon!, size: iconSize),
        if (child != null)
          Flexible(
            child: DefaultTextStyle(
              style: AppTypography.sans(fontSize, FontWeight.w600).copyWith(
                color: palette.foreground,
                letterSpacing: -0.005 * fontSize,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              child: child!,
            ),
          ),
        if (iconRight != null) V3Icon(iconRight!, size: iconSize),
      ];
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            parts[i],
          ],
        ],
      );
    }

    final pill = AnimatedOpacity(
      opacity: disabled || onPressed == null ? 0.38 : 1,
      duration: motion ? const Duration(milliseconds: 250) : Duration.zero,
      child: AnimatedContainer(
        duration: motion ? const Duration(milliseconds: 250) : Duration.zero,
        height: size.height,
        width: full ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: small ? 14 : 22),
        alignment: full ? Alignment.center : null,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(999),
          border: palette.border,
          boxShadow: inactive ? null : palette.shadow,
        ),
        child: IconTheme(
          data: IconThemeData(color: palette.foreground, size: iconSize),
          child: Center(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );

    // A fixed-height pill: its label stops growing at 2× (it clips from
    // about 2.35×), like the tags and the tab bar.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2,
      child: V3Pressable(
        onTap: inactive || loading ? null : onPressed,
        semanticLabel: semanticLabel,
        child: pill,
      ),
    );
  }
}

/// `IconBtn` from `v3/core.jsx`: a round icon button of [size] (34–48 in the
/// design) with a card or dark-glass fill, a hairline border and an optional
/// ember [badge] dot. The icon is 46% of [size].
///
/// [label] is required: it is the button's only accessible name. The disc
/// stays at [size]; the hit box is at least 44 pt.
class V3IconButton extends StatelessWidget {
  const V3IconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.dark = false,
    this.size = 40,
    this.badge = false,
    this.color,
  });

  /// Key on the visible disc (tests and layout probes).
  static const discKey = ValueKey<String>('v3-icon-button-disc');

  final V3Icons icon;
  final String label;
  final VoidCallback? onPressed;
  final bool dark;
  final double size;
  final bool badge;

  /// Icon colour (the design's `c`); defaults to ink, or white when [dark].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      key: discKey,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0x1AFFFFFF) : AppColors.card,
        border: Border.all(
          color: dark ? const Color(0x1FFFFFFF) : AppColors.hair,
        ),
      ),
      child: V3Icon(
        icon,
        size: size * 0.46,
        color: color ?? (dark ? _white : AppColors.ink),
      ),
    );
    return V3Pressable(
      onTap: onPressed,
      semanticLabel: label,
      focusRadius: BorderRadius.circular(size / 2),
      child: badge
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                disc,
                // `top: 7, right: 8` inside the 1px border.
                Positioned(
                  top: 8,
                  right: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.ember,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 2),
                    ),
                  ),
                ),
              ],
            )
          : disc,
    );
  }
}

/// `Spinner` from `v3/core.jsx`: a 25% track with a quarter arc turning every
/// .8 s. [color] defaults to the ambient [IconTheme] colour. Holds still with
/// reduced motion.
class V3Spinner extends StatefulWidget {
  const V3Spinner({
    super.key,
    this.color,
    this.size = 18,
    this.semanticLabel = 'Loading',
  });

  final Color? color;
  final double size;
  final String? semanticLabel;

  @override
  State<V3Spinner> createState() => _V3SpinnerState();
}

class _V3SpinnerState extends State<V3Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionConfig.enabled(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? IconTheme.of(context).color ?? AppColors.ink;
    return Semantics(
      label: widget.semanticLabel,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SpinnerPainter(color),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    const rect = Rect.fromLTWH(3, 3, 18, 18);
    canvas.drawCircle(
      const Offset(12, 12),
      9,
      paint..color = color.withValues(alpha: color.a * 0.25),
    );
    // `M21 12a9 9 0 0 0-9-9`: 3 o'clock back to 12 o'clock.
    canvas.drawArc(
      rect,
      0,
      -math.pi / 2,
      false,
      paint
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => oldDelegate.color != color;
}
