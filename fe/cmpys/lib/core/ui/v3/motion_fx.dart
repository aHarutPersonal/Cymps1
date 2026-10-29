import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PlaceholderAlignment;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

// `BlurWords`, `Tilt`, `Reveal` and `Flame` from `v3/core.jsx`.

// ─────────────────────────────────────────────────────────────────────────────
// BlurWords
// ─────────────────────────────────────────────────────────────────────────────

/// `BlurWords` from `v3/core.jsx`: a headline that resolves word by word.
///
/// While [show] is true each word goes from opacity 0, `blur(10px)` and
/// 12 px down to sharp and in place over [duration] (.8 s on `--out`),
/// word `i` starting at [delay] + `i` × [step]. Hiding plays it back.
///
/// It lays out as one paragraph: the words wrap, align ([textAlign]) and
/// scale with the text size like a [Text] in [style] (merged over the
/// ambient [DefaultTextStyle]). Screen readers get one label, the whole
/// [text]; the words themselves are hidden from them.
///
/// With reduced motion the whole text fades in as one (no blur, no offset,
/// no stagger).
class V3BlurWords extends StatefulWidget {
  const V3BlurWords({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.delay = Duration.zero,
    this.step = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 800),
    this.show = true,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration delay;
  final Duration step;
  final Duration duration;
  final bool show;

  /// The reduced-motion fade.
  static const Duration reducedFade = Duration(milliseconds: 300);

  @override
  State<V3BlurWords> createState() => _V3BlurWordsState();
}

class _V3BlurWordsState extends State<V3BlurWords>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  bool? _motion;

  List<String> get _words => widget.text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);

  Duration get _total {
    final words = _words.length;
    if (_motion == false) return V3BlurWords.reducedFade;
    return widget.delay +
        widget.step * math.max(0, words - 1) +
        widget.duration;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = MotionConfig.enabled(context);
    if (motion == _motion) return;
    final first = _motion == null;
    _motion = motion;
    _controller.duration = _total;
    if (!first && widget.show) {
      // Switching modes mid-way: land on the shown state.
      _controller.value = 1;
    } else {
      _run();
    }
  }

  @override
  void didUpdateWidget(V3BlurWords oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _total;
    if (oldWidget.show != widget.show) _run();
  }

  void _run() {
    if (widget.show) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Word [i]'s eased progress at the controller's current time.
  double _progress(int i) {
    final total = _controller.duration!.inMicroseconds;
    if (total == 0) return _controller.value;
    final elapsed = _controller.value * total;
    final start = (widget.delay + widget.step * i).inMicroseconds;
    final t = ((elapsed - start) / widget.duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    return AppMotion.out.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    if (_motion == false) {
      return FadeTransition(
        opacity: _controller,
        child: Text(widget.text, style: style, textAlign: widget.textAlign),
      );
    }
    final words = _words;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < words.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              // The span already scales the word with the text size.
              child: MediaQuery.withNoTextScaling(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) =>
                      _Word(progress: _progress(i), child: child!),
                  child: Text(words[i], style: style),
                ),
              ),
            ),
          ],
        ],
      ),
      textAlign: widget.textAlign,
      semanticsLabel: widget.text,
    );
  }
}

/// One word at [progress] 0 (hidden: transparent, blurred 10, 12 px down)
/// to 1 (shown).
class _Word extends StatelessWidget {
  const _Word({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final hidden = 1 - p;
    final sigma = 10 * hidden;
    return Opacity(
      opacity: p.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 12 * hidden),
        child: ImageFiltered(
          enabled: sigma > 0.01,
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tilt
// ─────────────────────────────────────────────────────────────────────────────

/// `Tilt` from `v3/core.jsx`, for a finger: while a finger is down on the
/// child it leans toward it, up to [max] degrees (the finger's position
/// `x, y` in −.5….5 of the box gives `rotateX(-y·max) rotateY(x·max)` under
/// a 900 px perspective), following over 120 ms linearly. On release it
/// springs back over .7 s (`--spring`). With [glare], a soft white light
/// (`rgba(255,255,255,.55)` → transparent at 55%, soft-light) sits under the
/// finger, fading in and out over .4 s.
///
/// It only listens to pointers (no gesture recogniser), so taps, buttons
/// and scrolling inside and around it work as before; a scroll that starts
/// on it lets the card spring back.
///
/// With reduced motion it is inert: the child, untouched.
class V3Tilt extends StatefulWidget {
  const V3Tilt({
    super.key,
    required this.child,
    this.max = 7,
    this.glare = true,
    this.radius = 30,
  });

  /// Key on the tilting [Transform], for tests.
  static const transformKey = ValueKey<String>('v3-tilt-transform');

  final Widget child;

  /// Largest lean, in degrees.
  final double max;
  final bool glare;

  /// Corner radius the glare is clipped to (the card's own radius).
  final double radius;

  @override
  State<V3Tilt> createState() => _V3TiltState();
}

class _V3TiltState extends State<V3Tilt> with TickerProviderStateMixin {
  late final AnimationController _lean;
  late final AnimationController _glare;

  @override
  void initState() {
    super.initState();
    _lean = AnimationController(vsync: this);
    _glare = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  /// Lean is interpolated from [_from] to [_to] along [_curve].
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  Curve _curve = Curves.linear;

  /// The finger's position as fractions of the box (0…1), for the glare.
  Offset _light = const Offset(0.5, 0.5);
  int? _pointer;
  ScrollPosition? _scroll;

  Offset get _current =>
      Offset.lerp(_from, _to, _curve.transform(_lean.value))!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _scroll)) {
      _scroll?.isScrollingNotifier.removeListener(_onScrolling);
      _scroll = position;
      _scroll?.isScrollingNotifier.addListener(_onScrolling);
    }
    if (!MotionConfig.enabled(context)) _reset();
  }

  @override
  void dispose() {
    _scroll?.isScrollingNotifier.removeListener(_onScrolling);
    _lean.dispose();
    _glare.dispose();
    super.dispose();
  }

  void _onScrolling() {
    if (_scroll?.isScrollingNotifier.value ?? false) _release();
  }

  void _reset() {
    _pointer = null;
    _from = _to = Offset.zero;
    _lean.value = 0;
    _glare.value = 0;
  }

  void _moveTo(Offset target, Duration duration, Curve curve) {
    _from = _current;
    _to = target;
    _curve = curve;
    _lean
      ..duration = duration
      ..forward(from: 0);
  }

  void _follow(PointerEvent event) {
    if (!MotionConfig.enabled(context)) return;
    if (_pointer != null && _pointer != event.pointer) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    _pointer = event.pointer;
    final size = box.size;
    final x = (event.localPosition.dx / size.width).clamp(0.0, 1.0);
    final y = (event.localPosition.dy / size.height).clamp(0.0, 1.0);
    _light = Offset(x, y);
    _moveTo(
      Offset(x - 0.5, y - 0.5),
      const Duration(milliseconds: 120),
      Curves.linear,
    );
    if (widget.glare) _glare.forward();
  }

  void _release([PointerEvent? event]) {
    if (event != null && event.pointer != _pointer) return;
    if (_pointer == null) return;
    _pointer = null;
    _moveTo(Offset.zero, const Duration(milliseconds: 700), AppMotion.spring);
    _glare.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    return Listener(
      // Sees every finger on the card (gaps included) while still letting
      // the child and anything behind it be hit; a Listener never joins
      // the gesture arena, so it can't steal a tap or a scroll.
      behavior: HitTestBehavior.translucent,
      onPointerDown: motion ? _follow : null,
      onPointerMove: motion ? _follow : null,
      onPointerUp: motion ? _release : null,
      onPointerCancel: motion ? _release : null,
      child: AnimatedBuilder(
        animation: _lean,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (widget.glare && motion)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.radius),
                    child: AnimatedBuilder(
                      // The light follows the finger (the lean animates on
                      // every move) and fades with the glare.
                      animation: Listenable.merge([_glare, _lean]),
                      builder: (context, _) => _glare.value == 0
                          ? const SizedBox.shrink()
                          : CustomPaint(
                              painter: _GlarePainter(
                                at: _light,
                                opacity: _glare.value,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        builder: (context, child) {
          final lean = motion ? _current : Offset.zero;
          final rad = widget.max * math.pi / 180;
          // CSS `perspective(900px)` brings +z toward the viewer; Flutter's
          // w = 1 + m32·z, so the CSS look needs m32 = −1/900.
          final matrix = lean == Offset.zero
              ? Matrix4.identity()
              : (Matrix4.identity()
                  ..setEntry(3, 2, -1 / 900)
                  ..rotateX(-lean.dy * rad)
                  ..rotateY(lean.dx * rad));
          return Transform(
            key: V3Tilt.transformKey,
            alignment: Alignment.center,
            transform: matrix,
            child: child,
          );
        },
      ),
    );
  }
}

class _GlarePainter extends CustomPainter {
  const _GlarePainter({required this.at, required this.opacity});

  /// The light's centre as fractions of the box.
  final Offset at;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(at.dx * size.width, at.dy * size.height);
    // CSS `circle` defaults to `farthest-corner`.
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    final radius = math.max(1.0, reach * 0.55);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.softLight
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, 0.55 * opacity),
            const Color(0x00FFFFFF),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GlarePainter old) =>
      old.at != at || old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reveal
// ─────────────────────────────────────────────────────────────────────────────

/// `Reveal` from `v3/core.jsx`: a [color] circle grows from the tap point
/// [at] (global coordinates) until it covers the screen (radius 1100 px, or
/// the farthest screen corner if that is further) over .55 s on
/// `cubic-bezier(.7,0,.3,1)`. At 480 ms [onCovered] runs, which is where
/// the caller opens the destination (a go_router push, say) under the ink;
/// at 560 ms the ink fades out over .5 s, and at 1.1 s it is removed.
///
/// The ink sits in the root [Overlay], above every route, and never takes
/// pointer events (the prototype's `pointer-events: none`), so nothing is
/// blocked during or after it. The returned future completes when it is
/// gone.
///
/// With reduced motion it is a plain colour fade: in over 200 ms, then
/// [onCovered], then out over 250 ms.
Future<void> showInkReveal(
  BuildContext context, {
  required Offset at,
  required Color color,
  required VoidCallback onCovered,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    onCovered();
    return Future<void>.value();
  }
  final motion = MotionConfig.enabled(context);
  final done = Completer<void>();
  final fading = ValueNotifier<bool>(false);
  final entry = OverlayEntry(
    builder: (context) =>
        _InkReveal(at: at, color: color, motion: motion, fading: fading),
  );
  overlay.insert(entry);

  // The timeline counts from the tap.
  final covered = motion ? 480 : 200;
  final fade = motion ? 560 : 280;
  final remove = motion ? 1100 : 530;
  Timer(Duration(milliseconds: covered), onCovered);
  Timer(Duration(milliseconds: fade), () => fading.value = true);
  Timer(Duration(milliseconds: remove), () {
    if (entry.mounted) entry.remove();
    entry.dispose();
    // After the entry's last frame has let go of it.
    SchedulerBinding.instance.addPostFrameCallback((_) => fading.dispose());
    SchedulerBinding.instance.ensureVisualUpdate();
    done.complete();
  });
  return done.future;
}

/// The reveal's grow curve, `cubic-bezier(.7,0,.3,1)`.
const Cubic _revealCurve = Cubic(0.7, 0, 0.3, 1);

class _InkReveal extends StatefulWidget {
  const _InkReveal({
    required this.at,
    required this.color,
    required this.motion,
    required this.fading,
  });

  final Offset at;
  final Color color;
  final bool motion;

  /// Turns true when the ink starts fading out.
  final ValueListenable<bool> fading;

  @override
  State<_InkReveal> createState() => _InkRevealState();
}

class _InkRevealState extends State<_InkReveal> with TickerProviderStateMixin {
  late final AnimationController _grow;
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _grow = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.motion ? 550 : 200),
    );
    _fade = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.motion ? 500 : 250),
    );
    if (widget.motion) {
      // Started on the next frame (the prototype waits two frames so the
      // transition has a start state).
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _grow.forward();
      });
    } else {
      _grow.forward();
    }
    widget.fading.addListener(_onFading);
  }

  void _onFading() {
    if (widget.fading.value) _fade.forward();
  }

  @override
  void dispose() {
    widget.fading.removeListener(_onFading);
    _grow.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: Listenable.merge([_grow, _fade]),
          builder: (context, _) {
            // `opacity .5s ease`.
            final opacity = 1 - Curves.ease.transform(_fade.value);
            if (!widget.motion) {
              return Opacity(
                opacity: (_grow.value * opacity).clamp(0.0, 1.0),
                child: ColoredBox(color: widget.color),
              );
            }
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: CustomPaint(
                size: Size.infinite,
                painter: _InkPainter(
                  // The root overlay fills the screen: global is local.
                  at: widget.at,
                  progress: _revealCurve.transform(_grow.value),
                  color: widget.color,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  const _InkPainter({
    required this.at,
    required this.progress,
    required this.color,
  });

  final Offset at;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final farthest = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - at).distance).reduce(math.max);
    final radius = math.max(1100.0, farthest) * progress;
    canvas.drawCircle(at, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      old.at != at || old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Flame
// ─────────────────────────────────────────────────────────────────────────────

/// `Flame` from `v3/core.jsx`: the two-path streak flame at [size] (the
/// paths are drawn on a 24-unit box).
///
/// When [lit], the outer flame flickers (`flick 1.6s ease-in-out infinite`,
/// origin 50% 90%), the inner one too (`flick 1.1s ease-in-out .2s
/// infinite`, origin 50% 95%), and three 3 px embers rise from the top
/// (`ember 1.8s ease-out ${i*.6}s infinite`, at (i−1)·4 px from the centre).
/// Unlit, or with reduced motion, it is the same flame, static, with no
/// embers.
///
/// Decorative: hidden from screen readers unless [semanticLabel] is given.
class V3Flame extends StatefulWidget {
  const V3Flame({
    super.key,
    this.size = 22,
    this.lit = true,
    this.semanticLabel,
  });

  /// Key on the ember particles' painter (absent when static), for tests.
  static const embersKey = ValueKey<String>('v3-flame-embers');

  final double size;
  final bool lit;
  final String? semanticLabel;

  @override
  State<V3Flame> createState() => _V3FlameState();
}

// `oklch(0.86 0.13 80)` and `oklch(0.8 0.15 60)` in sRGB.
const Color _flameCore = Color(0xFFFEC766);
const Color _emberDot = Color(0xFFFFA44E);

class _V3FlameState extends State<V3Flame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<Duration> _clock = ValueNotifier(Duration.zero);

  bool get _animated => widget.lit && MotionConfig.enabled(context);

  void _tick(Duration elapsed) => _clock.value = elapsed;

  void _syncTicker() {
    if (_animated) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      _clock.value = Duration.zero;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(V3Flame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animated = _animated;
    Widget flame = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _FlamePainter(clock: _clock, animated: animated),
        foregroundPainter: animated ? _EmberPainter(clock: _clock) : null,
      ),
    );
    if (animated) {
      // Tags the subtree that paints the embers (painters aren't findable).
      flame = KeyedSubtree(key: V3Flame.embersKey, child: flame);
    }
    if (widget.semanticLabel == null) return ExcludeSemantics(child: flame);
    return Semantics(label: widget.semanticLabel, image: true, child: flame);
  }
}

/// Seconds as a double.
double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// `flick`: `0%,100% scale(1,1) skewX(0); 25% scale(.96,1.06) skewX(-2deg);
/// 50% scale(1.03,.95) skewX(2deg); 75% scale(.98,1.04) skewX(-1deg)`,
/// each leg eased (CSS `ease-in-out`). Returns (sx, sy, skew degrees).
(double, double, double) _flick(double phase) {
  const frames = <(double, double, double)>[
    (1, 1, 0),
    (0.96, 1.06, -2),
    (1.03, 0.95, 2),
    (0.98, 1.04, -1),
    (1, 1, 0),
  ];
  final p = phase.clamp(0.0, 1.0) * 4;
  final i = math.min(p.floor(), 3);
  final t = Curves.easeInOut.transform(p - i);
  final a = frames[i];
  final b = frames[i + 1];
  double mix(double x, double y) => x + (y - x) * t;
  return (mix(a.$1, b.$1), mix(a.$2, b.$2), mix(a.$3, b.$3));
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.clock, required this.animated})
    : super(repaint: clock);

  final ValueListenable<Duration> clock;
  final bool animated;

  // `M12 22c4 0 7-3 7-7 0-4-3-6-4-9-1 2-2 3-4 3 0-2-1-4-2-6-1 4-4 7-4 12
  // 0 4 3 7 7 7z`
  static final Path _outer = Path()
    ..moveTo(12, 22)
    ..relativeCubicTo(4, 0, 7, -3, 7, -7)
    ..relativeCubicTo(0, -4, -3, -6, -4, -9)
    ..relativeCubicTo(-1, 2, -2, 3, -4, 3)
    ..relativeCubicTo(0, -2, -1, -4, -2, -6)
    ..relativeCubicTo(-1, 4, -4, 7, -4, 12)
    ..relativeCubicTo(0, 4, 3, 7, 7, 7)
    ..close();

  // `M12 21c2.2 0 3.8-1.6 3.8-3.8 0-2.2-1.6-3.3-2.2-5-.6 1.1-1.2 1.6-2.2
  // 1.6 0-1.1-.5-2.2-1.1-3.3-.6 2.2-2.1 3.8-2.1 6.7C8.2 19.4 9.8 21 12 21z`
  static final Path _inner = Path()
    ..moveTo(12, 21)
    ..relativeCubicTo(2.2, 0, 3.8, -1.6, 3.8, -3.8)
    ..relativeCubicTo(0, -2.2, -1.6, -3.3, -2.2, -5)
    ..relativeCubicTo(-0.6, 1.1, -1.2, 1.6, -2.2, 1.6)
    ..relativeCubicTo(0, -1.1, -0.5, -2.2, -1.1, -3.3)
    ..relativeCubicTo(-0.6, 2.2, -2.1, 3.8, -2.1, 6.7)
    ..cubicTo(8.2, 19.4, 9.8, 21, 12, 21)
    ..close();

  void _drawFlicked(
    Canvas canvas,
    Path path,
    Color color,
    Offset origin,
    double phase,
  ) {
    canvas.save();
    if (animated) {
      final (sx, sy, skew) = _flick(phase);
      canvas
        ..translate(origin.dx, origin.dy)
        // CSS `scale() skewX()`: the skew applies to the point first.
        ..scale(sx, sy)
        ..skew(math.tan(skew * math.pi / 180), 0)
        ..translate(-origin.dx, -origin.dy);
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = _seconds(clock.value);
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    _drawFlicked(
      canvas,
      _outer,
      AppColors.ember,
      const Offset(12, 24 * 0.9),
      (s % 1.6) / 1.6,
    );
    final inner = s - 0.2;
    _drawFlicked(
      canvas,
      _inner,
      _flameCore,
      const Offset(12, 24 * 0.95),
      inner <= 0 ? 0 : (inner % 1.1) / 1.1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) =>
      old.animated != animated || old.clock != clock;
}

/// `ember`: `0% translateY(0) opacity 0; 20% opacity 1; 100% translateY(-16px)
/// translateX(3px) opacity 0` over 1.8 s, `ease-out`, particle `i` from
/// `i × .6 s`. A particle waits unseen until its first start (the prototype
/// shows a still dot during the delay; that is dropped).
class _EmberPainter extends CustomPainter {
  _EmberPainter({required this.clock}) : super(repaint: clock);

  final ValueListenable<Duration> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _seconds(clock.value);
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final local = s - i * 0.6;
      if (local < 0) continue;
      final phase = (local % 1.8) / 1.8;
      final move = Curves.easeOut.transform(phase);
      final double opacity = phase < 0.2
          ? Curves.easeOut.transform(phase / 0.2)
          : 1 - Curves.easeOut.transform((phase - 0.2) / 0.8);
      if (opacity <= 0) continue;
      paint.color = _emberDot.withValues(alpha: opacity.clamp(0.0, 1.0));
      final center = Offset(
        size.width / 2 + (i - 1) * 4 + 3 * move,
        1.5 - 16 * move,
      );
      canvas.drawCircle(center, 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) => old.clock != clock;
}
