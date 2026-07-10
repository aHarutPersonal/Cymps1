// CMPYS shared design-system primitives.
//
// One file deliberately — small, cohesive, and easier to read in context than a
// dozen 30-line files. Each primitive mirrors a widget from the original React
// prototype (`ui.jsx`) and is the canonical CMPYS component:
//
//   • CmpysKicker        — small uppercase mono label
//   • CmpysMonogram      — circular initials avatar
//   • CmpysButton        — pill button with variants
//   • CmpysChip          — pill toggle
//   • CmpysCard          — white rounded card
//   • CmpysRing          — circular progress
//   • CmpysBar           — linear progress
//   • CmpysSegBar        — segmented progress (2026 look)
//   • CmpysTypingDots    — animated 3-dot indicator
//   • CmpysThinkFeed     — typewriter "thinking" stream
//   • CmpysSheet         — bottom sheet helper
//   • CmpysToast         — floating toast
//   • CmpysMentorAvatar  — uses assets/images/mentors/{slug}.png with fallback

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kicker
// ─────────────────────────────────────────────────────────────────────────────

class CmpysKicker extends StatelessWidget {
  const CmpysKicker(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.kicker.copyWith(color: color ?? AppColors.ink3),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Monogram (initials avatar)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysMonogram extends StatelessWidget {
  const CmpysMonogram({
    super.key,
    required this.initials,
    this.size = 44,
    this.color = AppColors.green,
    this.tint = AppColors.greenSoft,
    this.ring = false,
  });

  final String initials;
  final double size;
  final Color color;
  final Color tint;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        boxShadow: ring
            ? [
                BoxShadow(
                  color: color,
                  blurRadius: 0,
                  spreadRadius: 3.5,
                ),
                const BoxShadow(
                  color: AppColors.card,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: AppTypography.h3.fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mentor portrait (uses real asset, falls back to monogram + tint)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysMentorAvatar extends StatelessWidget {
  const CmpysMentorAvatar({
    super.key,
    required this.slug,
    required this.initials,
    this.color = AppColors.green,
    this.tint = AppColors.greenSoft,
    this.size = 48,
    this.border,
  });

  final String slug;
  final String initials;
  final Color color;
  final Color tint;
  final double size;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Image.asset(
        'assets/images/mentors/$slug.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            initials,
            style: TextStyle(
              fontFamily: AppTypography.h3.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.36,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

enum CmpysBtnVariant { primary, ochre, dark, outline, soft, ghost, danger }

enum CmpysBtnSize { sm, md, lg }

class CmpysButton extends StatefulWidget {
  const CmpysButton({
    super.key,
    required this.child,
    required this.onTap,
    this.variant = CmpysBtnVariant.primary,
    this.size = CmpysBtnSize.md,
    this.full = false,
    this.leadingIcon,
    this.trailingIcon,
    this.disabled = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final CmpysBtnVariant variant;
  final CmpysBtnSize size;
  final bool full;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool disabled;

  @override
  State<CmpysButton> createState() => _CmpysButtonState();
}

class _CmpysButtonState extends State<CmpysButton> {
  bool _pressed = false;

  ({double height, double fontSize, double padH}) get _dims {
    switch (widget.size) {
      case CmpysBtnSize.sm:
        return (height: 42, fontSize: 14, padH: 18);
      case CmpysBtnSize.md:
        return (height: 52, fontSize: 16, padH: 22);
      case CmpysBtnSize.lg:
        return (height: 58, fontSize: 17, padH: 26);
    }
  }

  ({Color bg, Color fg, BoxBorder? border}) get _palette {
    switch (widget.variant) {
      case CmpysBtnVariant.primary:
        return (
          bg: AppColors.green,
          fg: Colors.white,
          border: Border.all(color: AppColors.green2, width: 1),
        );
      case CmpysBtnVariant.ochre:
        return (
          bg: AppColors.ochre,
          fg: Colors.white,
          border: Border.all(color: AppColors.ochre2, width: 1),
        );
      case CmpysBtnVariant.dark:
        return (
          bg: AppColors.blkInk,
          fg: Colors.white,
          border: Border.all(color: Colors.black, width: 1),
        );
      case CmpysBtnVariant.outline:
        return (
          bg: Colors.transparent,
          fg: AppColors.ink,
          border: Border.all(color: AppColors.hair2, width: 1.5),
        );
      case CmpysBtnVariant.soft:
        return (
          bg: AppColors.greenSoft,
          fg: AppColors.green2,
          border: null,
        );
      case CmpysBtnVariant.ghost:
        return (
          bg: Colors.transparent,
          fg: AppColors.ink2,
          border: null,
        );
      case CmpysBtnVariant.danger:
        return (
          bg: Colors.transparent,
          fg: AppColors.danger,
          border: Border.all(color: const Color(0xFFE3C9C3), width: 1.5),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dims;
    final p = _palette;
    final enabled = !widget.disabled && widget.onTap != null;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 110),
          scale: _pressed ? 0.975 : 1.0,
          child: Container(
            height: d.height,
            padding: EdgeInsets.symmetric(horizontal: d.padH),
            width: widget.full ? double.infinity : null,
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: AppRadii.button,
              border: p.border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.leadingIcon != null) ...[
                  Icon(widget.leadingIcon, size: d.fontSize + 3, color: p.fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: DefaultTextStyle(
                    style: AppTypography.button.copyWith(
                      color: p.fg,
                      fontSize: d.fontSize,
                    ),
                    overflow: TextOverflow.ellipsis,
                    child: widget.child,
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(widget.trailingIcon, size: d.fontSize + 3, color: p.fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip (pill toggle)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysChipPill extends StatelessWidget {
  const CmpysChipPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.color = AppColors.green,
    this.tint = AppColors.greenSoft,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: active ? tint : Colors.transparent,
          borderRadius: AppRadii.brFull,
          border: Border.all(
            color: active ? color : AppColors.hair2,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodyMedium.copyWith(
            color: active ? color : AppColors.ink2,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card (white rounded surface)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysCardSurface extends StatelessWidget {
  const CmpysCardSurface({
    super.key,
    required this.child,
    this.pad = const EdgeInsets.all(18),
    this.color = AppColors.card,
    this.border = true,
    this.raised = false,
    this.onTap,
    this.radius,
  });

  final Widget child;
  final EdgeInsets pad;
  final Color color;
  final bool border;
  final bool raised;
  final VoidCallback? onTap;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: pad,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius ?? AppRadii.card,
        border: border ? Border.all(color: AppColors.hair, width: 1) : null,
        boxShadow: raised ? AppShadows.md : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: card,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress ring
// ─────────────────────────────────────────────────────────────────────────────

class CmpysRing extends StatelessWidget {
  const CmpysRing({
    super.key,
    required this.value,
    this.size = 64,
    this.stroke = 6,
    this.color = AppColors.green,
    this.track = AppColors.hair,
    this.child,
  });

  final double value; // 0–100
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            curve: AppCurves.easeOut,
            tween: Tween(begin: 0, end: value.clamp(0, 100) / 100),
            builder: (_, v, _) => CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                value: v,
                color: color,
                track: track,
                stroke: stroke,
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (value <= 0) return;
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -90 * 3.1415926 / 180,
      value * 2 * 3.1415926,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

// ─────────────────────────────────────────────────────────────────────────────
// Linear bar
// ─────────────────────────────────────────────────────────────────────────────

class CmpysBar extends StatelessWidget {
  const CmpysBar({
    super.key,
    required this.value,
    this.color = AppColors.green,
    this.track = AppColors.hair,
    this.height = 7,
  });

  final double value; // 0–100
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pct = (value.clamp(0, 100)) / 100;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(height),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 800),
          curve: AppCurves.easeOut,
          tween: Tween(begin: 0, end: pct),
          builder: (_, v, _) => FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented bar (2026)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysSegBar extends StatelessWidget {
  const CmpysSegBar({
    super.key,
    required this.total,
    required this.done,
    this.color = AppColors.green,
    this.track = AppColors.hair,
    this.height = 8,
    this.gap = 4,
  });

  final int total;
  final int done;
  final Color color;
  final Color track;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: List.generate(total, (i) {
          final filled = i < done;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : gap),
              decoration: BoxDecoration(
                color: filled ? color : track,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing dots
// ─────────────────────────────────────────────────────────────────────────────

class CmpysTypingDots extends StatefulWidget {
  const CmpysTypingDots({super.key, this.color = AppColors.ink3, this.size = 7});
  final Color color;
  final double size;

  @override
  State<CmpysTypingDots> createState() => _CmpysTypingDotsState();
}

class _CmpysTypingDotsState extends State<CmpysTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Per-dot blink: opacity 0.2 ↔ 1.0 with 0.18s stagger.
            final t = ((_c.value + i * 0.18) % 1.0);
            // 0.2 at t=0|1, 1.0 at t=0.5
            final o = (t < 0.5)
                ? 0.2 + (t * 2) * 0.8
                : 0.2 + ((1 - t) * 2) * 0.8;
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
              child: Opacity(
                opacity: o,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Think feed (typewriter-style thought stream)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysThinkFeed extends StatefulWidget {
  const CmpysThinkFeed({
    super.key,
    required this.lines,
    this.intervalMs = 850,
    this.color = const Color(0xE0FFFFFF),
    this.dimColor,
    this.accent = const Color(0xFFFFD166),
    this.italic = true,
    this.onDone,
  });

  final List<String> lines;
  final int intervalMs;
  final Color color;
  final Color? dimColor;
  final Color accent;
  final bool italic;
  final VoidCallback? onDone;

  @override
  State<CmpysThinkFeed> createState() => _CmpysThinkFeedState();
}

class _CmpysThinkFeedState extends State<CmpysThinkFeed> {
  int _shown = 1;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: widget.intervalMs), () {
      if (!mounted) return;
      if (_shown >= widget.lines.length) {
        widget.onDone?.call();
        return;
      }
      setState(() => _shown++);
      _schedule();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.dimColor ?? widget.color.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_shown, (i) {
        final last = i == _shown - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: i == _shown - 1 ? 0 : 10),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 350),
            curve: AppCurves.easeOut,
            builder: (_, t, child) {
              return Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
              );
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 9),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: last ? widget.accent : dim,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.lines[i],
                    style: AppTypography.body.copyWith(
                      fontSize: 13.5,
                      height: 1.5,
                      color: last ? widget.color : dim,
                      fontStyle:
                          widget.italic ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toast (lightweight, can be shown via showCmpysToast)
// ─────────────────────────────────────────────────────────────────────────────

void showCmpysToast(
  BuildContext context,
  String message, {
  IconData? icon,
  Color tone = const Color(0xFF9FD0B6),
  Duration duration = const Duration(milliseconds: 2100),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastWidget(
      message: message,
      icon: icon,
      tone: tone,
      onClose: () => entry.remove(),
      duration: duration,
    ),
  );
  overlay.insert(entry);
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onClose,
    this.icon,
  });
  final String message;
  final IconData? icon;
  final Color tone;
  final Duration duration;
  final VoidCallback onClose;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
    Future.delayed(widget.duration, () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onClose();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: keyboardInset > 0 ? keyboardInset + 16 : 108 + bottomInset,
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Opacity(
              opacity: _c.value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - _c.value)),
                child: child,
              ),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 17, color: widget.tone),
                    const SizedBox(width: 9),
                  ],
                  Text(
                    widget.message,
                    style: AppTypography.body.copyWith(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet helper
// ─────────────────────────────────────────────────────────────────────────────

Future<T?> showCmpysSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    barrierColor: const Color(0x6B16161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14, top: 4),
                    decoration: BoxDecoration(
                      color: AppColors.hair2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (title != null) ...[
                  Text(title, style: AppTypography.h3),
                  const SizedBox(height: 12),
                ],
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}
