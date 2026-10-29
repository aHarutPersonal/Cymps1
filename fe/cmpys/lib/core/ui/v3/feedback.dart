import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'icons.dart';
import 'motion.dart';

const Color _white = Color(0xFFFFFFFF);

// ─────────────────────────────────────────────────────────────────────────────
// CheckDot
// ─────────────────────────────────────────────────────────────────────────────

/// `CheckDot` from `v3/core.jsx`: a completion circle. Not done it is a
/// 2 pt hair2 ring; done it fills [color] and draws a white check (.4 s on
/// `--out`). On the transition to done it also plays a [V3Burst]; it never
/// bursts when it first builds already done or when un-marked.
///
/// The disc is [size] (30 in the design); the hit box is at least 44 pt.
class V3CheckDot extends StatefulWidget {
  const V3CheckDot({
    super.key,
    required this.done,
    this.onPressed,
    this.size = 30,
    this.color = AppColors.sage2,
    this.semanticLabel,
  });

  final bool done;
  final VoidCallback? onPressed;
  final double size;
  final Color color;

  /// Defaults to the design's `Mark done` / `Mark not done`.
  final String? semanticLabel;

  @override
  State<V3CheckDot> createState() => _V3CheckDotState();
}

class _V3CheckDotState extends State<V3CheckDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;
  int _burst = 0;
  bool _bursting = false;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // The design's check animates whenever it mounts (`draw .4s both`).
    if (widget.done) _draw.forward();
  }

  @override
  void didUpdateWidget(V3CheckDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.done && widget.done) {
      _draw.forward(from: 0);
      _burst++;
      _bursting = true;
    } else if (oldWidget.done && !widget.done) {
      _bursting = false;
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final done = widget.done;
    final size = widget.size;
    return V3Pressable(
      onTap: widget.onPressed,
      checked: done,
      semanticLabel:
          widget.semanticLabel ?? (done ? 'Mark not done' : 'Mark done'),
      focusRadius: BorderRadius.circular(size / 2),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: motion
                  ? const Duration(milliseconds: 300)
                  : Duration.zero,
              curve: AppMotion.out,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? widget.color : widget.color.withValues(alpha: 0),
                // The fill covers the whole disc, so a clear 2 pt border
                // reads as "no border" without a hairline at width 0.
                border: Border.all(
                  color: done
                      ? AppColors.hair2.withValues(alpha: 0)
                      : AppColors.hair2,
                  width: 2,
                ),
              ),
            ),
            if (done)
              AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => CustomPaint(
                  size: Size.square(size * 0.55),
                  painter: _CheckPainter(
                    motion ? AppMotion.out.transform(_draw.value) : 1,
                  ),
                ),
              ),
            if (done && _bursting)
              Positioned.fill(
                child: V3Burst(
                  key: ValueKey<int>(_burst),
                  color: widget.color,
                  onEnd: () {
                    if (mounted) setState(() => _bursting = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The design's check (`M20 6 9 17l-5-5`, stroke 3) drawn with
/// `stroke-dasharray: 24` from offset 24 to 0, so it draws from the top-right.
class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.progress);

  final double progress;

  static final Path _path = Path()
    ..moveTo(20, 6)
    ..lineTo(9, 17)
    ..lineTo(4, 12);
  static final PathMetric _metric = _path.computeMetrics().single;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = math.min(_metric.length, 24 * progress);
    if (visible <= 0) return;
    canvas.scale(size.width / 24);
    canvas.drawPath(
      _metric.extractPath(0, visible),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _white,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Burst
// ─────────────────────────────────────────────────────────────────────────────

/// `Burst` from `v3/core.jsx`: a halo ring (scale .7 → 2.2, fading) plus
/// [count] particles flying [radius] pt outward in ember / gold / iris / sage,
/// .6 s on `--out`. Plays once when built, then calls [onEnd].
///
/// It paints around the centre of the box it is given: fill a parent with
/// `Positioned.fill`, or drop it in a zero-size box at the burst point. With
/// reduced motion it paints nothing and ends at once.
class V3Burst extends StatefulWidget {
  const V3Burst({
    super.key,
    this.color = AppColors.ember,
    this.count = 10,
    this.radius = 26,
    this.onEnd,
  });

  /// Halo colour (the design's `c`).
  final Color color;

  /// Particle count (the design's `n`).
  final int count;

  /// Particle travel (the design's `r`).
  final double radius;
  final VoidCallback? onEnd;

  @override
  State<V3Burst> createState() => _V3BurstState();
}

class _V3BurstState extends State<V3Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenCompleteOrCancel(_end);
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) {
      if (!_ended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _end();
        });
      }
      return const SizedBox.shrink();
    }
    // The painter listens to the controller: frames repaint this layer only,
    // with no per-frame rebuild.
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BurstPainter(
            progress: _controller,
            color: widget.color,
            count: widget.count,
            radius: widget.radius,
          ),
        ),
      ),
    );
  }
}

const List<Color> _burstColors = [
  AppColors.ember,
  AppColors.gold,
  AppColors.iris,
  AppColors.sage,
];

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.progress,
    required this.color,
    required this.count,
    required this.radius,
  }) : super(repaint: progress);

  /// Linear 0–1 driver; eased on `--out` when painting.
  final Animation<double> progress;
  final Color color;
  final int count;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final t = AppMotion.out.transform(progress.value);
    final center = size.center(Offset.zero);
    // Halo: `inset: -2`, border 2, scale .7 → 2.2, opacity .6 → 0.
    final scale = 0.7 + 1.5 * t;
    final halo = (Offset.zero & size).inflate(2);
    final haloRadius = math.min(99.0, halo.shortestSide / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(halo.deflate(1), Radius.circular(haloRadius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: color.a * 0.6 * (1 - t)),
    );
    canvas.restore();

    // Particles: 5 pt dots, translate to (cos, sin) · r, scale 1 → .3.
    final dot = 2.5 * (1 - 0.7 * t);
    for (var i = 0; i < count; i++) {
      final a = i / count * math.pi * 2;
      final c = _burstColors[i % _burstColors.length];
      canvas.drawCircle(
        center + Offset(math.cos(a) * radius, math.sin(a) * radius) * t,
        dot,
        Paint()..color = c.withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.count != count ||
      old.radius != radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// Confetti
// ─────────────────────────────────────────────────────────────────────────────

/// `Confetti` from `v3/core.jsx`: [count] (46) pieces in ember / gold / iris
/// / sage / white falling from the top edge, each 1.8 s on
/// `cubic-bezier(.2,.6,.4,1)` after a 0–400 ms delay. Fills and clips to its
/// (bounded) box, typically `Positioned.fill`. Pass [seed] for a repeatable
/// layout. With reduced motion it paints nothing.
class V3Confetti extends StatefulWidget {
  const V3Confetti({super.key, this.count = 46, this.seed});

  final int count;
  final int? seed;

  @override
  State<V3Confetti> createState() => _V3ConfettiState();
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.x,
    required this.delayMs,
    required this.dx,
    required this.dy,
    required this.color,
    required this.width,
    required this.round,
  });

  final double x; // 0–100 %
  final double delayMs;
  final double dx;
  final double dy;
  final Color color;
  final double width;
  final bool round;
}

const List<Color> _confettiColors = [
  AppColors.ember,
  AppColors.gold,
  AppColors.iris,
  AppColors.sage,
  _white,
];

class _V3ConfettiState extends State<V3Confetti>
    with SingleTickerProviderStateMixin {
  static const _fallMs = 1800.0;
  static const _maxDelayMs = 400.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_fallMs + _maxDelayMs).round()),
    )..forward();
  }

  late final List<_ConfettiPiece> _pieces = () {
    final random = math.Random(widget.seed);
    return [
      for (var i = 0; i < widget.count; i++)
        _ConfettiPiece(
          x: random.nextDouble() * 100,
          delayMs: random.nextDouble() * _maxDelayMs,
          dx: (random.nextDouble() - 0.5) * 160,
          dy: 300 + random.nextDouble() * 420,
          color: _confettiColors[i % _confettiColors.length],
          width: 5 + random.nextDouble() * 6,
          round: random.nextDouble() > 0.5,
        ),
    ];
  }();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return const SizedBox.expand();
    // The painter listens to the controller: frames repaint this layer only,
    // with no per-frame rebuild.
    return IgnorePointer(
      child: ClipRect(
        child: SizedBox.expand(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ConfettiPainter(
                _pieces,
                _controller,
                _fallMs + _maxDelayMs,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress, this.totalMs)
    : super(repaint: progress);

  final List<_ConfettiPiece> pieces;

  /// Linear 0–1 over [totalMs] (longest delay + the 1.8 s fall).
  final Animation<double> progress;
  final double totalMs;

  static const Curve _curve = Cubic(0.2, 0.6, 0.4, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final elapsedMs = progress.value * totalMs;
    for (final p in pieces) {
      final linear = ((elapsedMs - p.delayMs) / 1800).clamp(0.0, 1.0);
      final t = _curve.transform(linear);
      final opacity = 1 - t;
      if (opacity <= 0) continue;
      final height = p.round ? p.width : p.width * 2.2;
      final scale = 1 - 0.7 * t;
      final center =
          Offset(p.x / 100 * size.width + p.width / 2, -10 + height / 2) +
          Offset(p.dx, p.dy) * t;
      final rect = Rect.fromCenter(
        center: center,
        width: p.width * scale,
        height: height * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular((p.round ? 9 : 2) * scale),
        ),
        Paint()..color = p.color.withValues(alpha: p.color.a * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress ||
      old.pieces != pieces ||
      old.totalMs != totalMs;
}

// ─────────────────────────────────────────────────────────────────────────────
// Toast
// ─────────────────────────────────────────────────────────────────────────────

/// Toast icon disc colour: sage for success, gold for a warning.
enum V3ToastTone { success, warn }

/// The `Toast` pill from `v3/core.jsx` (static): a dark 94% ink capsule with
/// a 22 pt sage / gold disc holding a 13 pt white icon, then 13.5 pt w500
/// text. [showV3Toast] positions and animates it.
class V3Toast extends StatelessWidget {
  const V3Toast({
    super.key,
    required this.text,
    this.icon = V3Icons.check,
    this.tone = V3ToastTone.success,
  });

  /// Key on the pill (tests and layout probes).
  static const pillKey = ValueKey<String>('v3-toast-pill');

  final String text;
  final V3Icons icon;
  final V3ToastTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: pillKey,
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xF017151A),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, 12),
            blurRadius: 30,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone == V3ToastTone.warn ? AppColors.gold : AppColors.sage,
            ),
            child: V3Icon(icon, size: 13, strokeWidth: 2.6, color: _white),
          ),
          const SizedBox(width: 9),
          // A full style (not merged onto the ambient one): toasts live in
          // the root overlay, outside any Material text theme.
          Flexible(
            child: DefaultTextStyle(
              style: AppTypography.sans(
                13.5,
                FontWeight.w500,
              ).copyWith(color: _white, decoration: TextDecoration.none),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows [text] as the app's top toast (58 pt from the top, below the status
/// bar), springing in, auto-hiding after 2.2 s. A toast that is already up
/// is replaced in place and its timer restarts, as the design's single
/// `toast` state does.
void showV3Toast(
  BuildContext context,
  String text, {
  V3Icons icon = V3Icons.check,
  V3ToastTone tone = V3ToastTone.success,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  (_toastHosts[overlay] ??= _ToastHost(
    overlay,
  )).show(_ToastData(text, icon, tone));
}

/// Hides the current toast (if any) under [context]'s root overlay.
void hideV3Toast(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastHosts[overlay]?.hide();
}

final Expando<_ToastHost> _toastHosts = Expando<_ToastHost>('v3 toast');

@immutable
class _ToastData {
  const _ToastData(this.text, this.icon, this.tone);

  final String text;
  final V3Icons icon;
  final V3ToastTone tone;
}

class _ToastHost {
  _ToastHost(this.overlay);

  static const _visibleFor = Duration(milliseconds: 2200);

  final OverlayState overlay;
  final ValueNotifier<_ToastData?> data = ValueNotifier<_ToastData?>(null);
  OverlayEntry? _entry;
  Timer? _timer;

  void show(_ToastData next) {
    // Key on the reference, not `mounted`: a just-inserted entry is not
    // mounted until the next build, and a second insert would duplicate it.
    if (_entry == null) {
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _ToastLayer(host: this, entry: entry),
      );
      _entry = entry;
      overlay.insert(entry);
    }
    data.value = next;
    _timer?.cancel();
    _timer = Timer(_visibleFor, hide);
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    data.value = null;
  }

  /// Whether [entry] is the live toast entry (not one already retired).
  bool owns(OverlayEntry entry) => identical(_entry, entry);

  /// Called by [entry]'s layer once its exit animation has finished.
  void removeIfHidden(OverlayEntry entry) {
    if (data.value != null || !owns(entry)) return;
    _entry = null;
    entry.remove();
  }

  /// Called when [entry]'s layer is disposed. Only the live entry's layer
  /// may clear host state: a retired layer disposing a frame late must not
  /// cancel the timer of a toast shown after it.
  void detach(OverlayEntry entry) {
    if (!owns(entry)) return;
    _timer?.cancel();
    _timer = null;
    _entry = null;
    data.value = null;
  }
}

class _ToastLayer extends StatefulWidget {
  const _ToastLayer({required this.host, required this.entry});

  final _ToastHost host;
  final OverlayEntry entry;

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _move;
  late final CurvedAnimation _fade;
  _ToastData? _shown;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // transform .5s --spring; opacity .3s ease (CSS default timing).
    _move = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.spring,
      reverseCurve: const FlippedCurve(AppMotion.spring),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.6, curve: Curves.ease),
      reverseCurve: const FlippedCurve(Interval(0, 0.6, curve: Curves.ease)),
    );
    widget.host.data.addListener(_sync);
  }

  void _sync() {
    // A retired layer (its entry already removed) ignores later toasts.
    if (!widget.host.owns(widget.entry)) return;
    final next = widget.host.data.value;
    if (next != null) {
      if (_started) {
        setState(() => _shown = next);
      } else {
        _shown = next;
      }
      if (!_controller.isCompleted) _controller.forward();
    } else {
      _controller.reverse().whenCompleteOrCancel(() {
        if (mounted && _controller.isDismissed) {
          widget.host.removeIfHidden(widget.entry);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MotionConfig.enabled(context)
        ? const Duration(milliseconds: 500)
        : Duration.zero;
    if (!_started) {
      _sync();
      _started = true;
    }
  }

  @override
  void dispose() {
    widget.host.data.removeListener(_sync);
    widget.host.detach(widget.entry);
    _move.dispose();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final top = math.max(58.0, MediaQuery.paddingOf(context).top + 4);
    return Positioned(
      left: 16,
      right: 16,
      top: top,
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            container: true,
            liveRegion: true,
            label: shown.text,
            excludeSemantics: true,
            child: AnimatedBuilder(
              animation: _controller,
              child: V3Toast(
                text: shown.text,
                icon: shown.icon,
                tone: shown.tone,
              ),
              builder: (context, child) {
                final v = _move.value;
                return Opacity(
                  opacity: _fade.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -70 * (1 - v)),
                    child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
