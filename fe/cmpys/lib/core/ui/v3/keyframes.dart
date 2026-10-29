import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

// Small keyframe pieces from `CMPYS v3.html` that more than one screen uses:
// `breathe`, `halo`, `shock`, `flyL` / `flyR`. (`rise` and `pop` are
// [V3Rise] and [V3Pop] in `motion.dart`.) Each one follows the owner's
// reduced-motion rule: no loops, fades only.

/// Runs [start] after [delay], or at once for a zero delay. Returns the
/// timer to cancel, if any.
Timer? _after(Duration delay, VoidCallback start) {
  if (delay <= Duration.zero) {
    start();
    return null;
  }
  return Timer(delay, start);
}

// ─────────────────────────────────────────────────────────────────────────────
// breathe
// ─────────────────────────────────────────────────────────────────────────────

/// `breathe` (`0%,100% {scale 1; opacity .55} 50% {scale 1.08; opacity
/// .9}`), looping every [period] on CSS `ease-in-out`, after [delay].
///
/// With reduced motion it holds still at the resting values (scale 1,
/// opacity .55): no loop.
class V3Breathe extends StatefulWidget {
  const V3Breathe({
    super.key,
    required this.child,
    this.period = const Duration(seconds: 5),
    this.delay = Duration.zero,
    this.restOpacity = 0.55,
    this.peakOpacity = 0.9,
    this.peakScale = 1.08,
  });

  final Widget child;

  /// One full breath (in and out), the CSS animation duration.
  final Duration period;
  final Duration delay;
  final double restOpacity;
  final double peakOpacity;
  final double peakScale;

  @override
  State<V3Breathe> createState() => _V3BreatheState();
}

class _V3BreatheState extends State<V3Breathe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _motion = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period ~/ 2,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = MotionConfig.enabled(context);
    if (motion == _motion && (_controller.isAnimating || _timer != null)) {
      return;
    }
    _motion = motion;
    _timer?.cancel();
    _timer = null;
    if (motion) {
      _timer = _after(widget.delay, () {
        _timer = null;
        if (mounted) _controller.repeat(reverse: true);
      });
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didUpdateWidget(V3Breathe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period ~/ 2;
      if (_controller.isAnimating) _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity:
              widget.restOpacity +
              (widget.peakOpacity - widget.restOpacity) * t,
          child: Transform.scale(
            scale: 1 + (widget.peakScale - 1) * t,
            child: child,
          ),
        );
      },
    );
  }
}

/// The design's breathing radial glow: a [size] pt disc of
/// `radial-gradient(circle, color, transparent 65%)` centred horizontally
/// at [centerY] (a fraction of the height), breathing every [period]
/// ([V3Breathe]). It fills its parent and ignores pointers.
///
/// Used behind the celebration (520 pt at 42%, 5 s) and the "Week unlocked"
/// moment (520 pt at 40%, 4 s). Static with reduced motion.
class V3BreathingGlow extends StatelessWidget {
  const V3BreathingGlow({
    super.key,
    required this.color,
    this.size = 520,
    this.centerY = 0.42,
    this.period = const Duration(seconds: 5),
  });

  final Color color;
  final double size;

  /// Vertical centre of the disc as a fraction of the parent's height.
  final double centerY;
  final Duration period;

  @override
  Widget build(BuildContext context) {
    // `radial-gradient(circle, c, transparent 65%)` on a square: the circle
    // reaches the farthest corner, so 65% of that is 0.65 · √2 / 2 of the box.
    final disc = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.65 * math.sqrt2 / 2,
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned(
            left: constraints.maxWidth / 2 - size / 2,
            top: constraints.maxHeight * centerY - size / 2,
            width: size,
            height: size,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: V3Breathe(
                  period: period,
                  child: SizedBox.expand(child: disc),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// halo
// ─────────────────────────────────────────────────────────────────────────────

/// `halo` (`0% {scale .7; opacity .6} 100% {scale 2.2; opacity 0}`) on a
/// ring the size of its parent: a [strokeWidth] border in [color] that grows
/// and fades every [period] on `--out`, starting after [delay].
///
/// The celebration's white ring is `halo 1.6s --out .4s infinite`; the
/// mentor lab's three rings are `halo 2.4s --out ${i*.8}s infinite`.
/// With reduced motion it draws nothing (no loops).
class V3HaloRing extends StatefulWidget {
  const V3HaloRing({
    super.key,
    this.color = const Color(0xFFFFFFFF),
    this.strokeWidth = 2,
    this.period = const Duration(milliseconds: 1600),
    this.delay = Duration.zero,
  });

  final Color color;
  final double strokeWidth;
  final Duration period;
  final Duration delay;

  @override
  State<V3HaloRing> createState() => _V3HaloRingState();
}

class _V3HaloRingState extends State<V3HaloRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    _timer = _after(widget.delay, () {
      _timer = null;
      if (!mounted) return;
      _controller.repeat();
      setState(() => _started = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started || !MotionConfig.enabled(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RingPainter(
            _controller,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
            fromScale: 0.7,
            toScale: 2.2,
            fromOpacity: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Paints a ring the size of the box, scaled and faded by [progress]
/// (eased on `--out`).
class _RingPainter extends CustomPainter {
  _RingPainter(
    this.progress, {
    required this.color,
    required this.strokeWidth,
    required this.fromScale,
    required this.toScale,
    required this.fromOpacity,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;
  final double fromScale;
  final double toScale;
  final double fromOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final t = AppMotion.out.transform(progress.value.clamp(0.0, 1.0));
    final alpha = color.a * fromOpacity * (1 - t);
    if (alpha <= 0) return;
    final center = size.center(Offset.zero);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(fromScale + (toScale - fromScale) * t);
    // A CSS border sits inside the box: the stroke centre is at
    // radius − width / 2.
    canvas.drawCircle(
      Offset.zero,
      size.shortestSide / 2 - strokeWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: alpha),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

// ─────────────────────────────────────────────────────────────────────────────
// shock
// ─────────────────────────────────────────────────────────────────────────────

/// `shock` (`0% {scale .4; opacity .8} 100% {scale 2.6; opacity 0}`) once,
/// on `--out`, after [delay]: a ring the size of its parent (Compare's
/// ripples from the age badge are `2px solid var(--ember)`, `shock .9s .85s`
/// and `shock 1.1s 1s`). It plays one shot and then draws nothing.
/// With reduced motion it draws nothing.
class V3Shock extends StatefulWidget {
  const V3Shock({
    super.key,
    this.color = AppColors.ember,
    this.strokeWidth = 2,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
  });

  final Color color;
  final double strokeWidth;
  final Duration duration;
  final Duration delay;

  @override
  State<V3Shock> createState() => _V3ShockState();
}

class _V3ShockState extends State<V3Shock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _timer = _after(widget.delay, () {
      _timer = null;
      if (!mounted) return;
      setState(() => _started = true);
      _controller.forward().whenCompleteOrCancel(() {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started ||
        _controller.isCompleted ||
        !MotionConfig.enabled(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _RingPainter(
          _controller,
          color: widget.color,
          strokeWidth: widget.strokeWidth,
          fromScale: 0.4,
          toScale: 2.6,
          fromOpacity: 0.8,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// flyL / flyR
// ─────────────────────────────────────────────────────────────────────────────

/// Which way [V3Fly] comes in from.
enum V3FlyFrom { left, right }

/// `flyL` / `flyR` once, on `--spring` (each keyframe leg eased, as CSS
/// does), after [delay]:
///
/// - left: `0% translateX(-90px) rotate(-12deg) opacity 0; 70%
///   translateX(6px) rotate(2deg) opacity 1; 100% none`;
/// - right: the mirror image.
///
/// Hidden until the delay elapses (`both`). With reduced motion it is a
/// plain fade over the same duration.
class V3Fly extends StatefulWidget {
  const V3Fly({
    super.key,
    required this.child,
    required this.from,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
  });

  final Widget child;
  final V3FlyFrom from;
  final Duration duration;
  final Duration delay;

  @override
  State<V3Fly> createState() => _V3FlyState();
}

class _V3FlyState extends State<V3Fly> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  static Animatable<double> _legs(
    double a,
    double b,
    double c,
  ) => TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: a, end: b).chain(CurveTween(curve: AppMotion.spring)),
      weight: 70,
    ),
    TweenSequenceItem(
      tween: Tween(begin: b, end: c).chain(CurveTween(curve: AppMotion.spring)),
      weight: 30,
    ),
  ]);

  static final Animatable<double> _dx = _legs(-90, 6, 0);
  static final Animatable<double> _turn = _legs(-12, 2, 0);
  static final Animatable<double> _opacity = _legs(0, 1, 1);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _timer = _after(widget.delay, () {
      _timer = null;
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final sign = widget.from == V3FlyFrom.left ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (!motion) {
          return Opacity(opacity: _controller.value, child: child);
        }
        final degrees = sign * _turn.evaluate(_controller);
        return Opacity(
          opacity: _opacity.evaluate(_controller).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(sign * _dx.evaluate(_controller), 0),
            child: Transform.rotate(
              angle: degrees * math.pi / 180,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
