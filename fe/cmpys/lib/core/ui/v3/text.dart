import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stream
// ─────────────────────────────────────────────────────────────────────────────

/// `Stream` from `v3/core.jsx`: reveals [text] word by word, two tokens (a
/// word and the whitespace after it) every [speed], with a blinking caret,
/// then calls [onDone] once. [start] false holds it at nothing.
///
/// Screen readers get the full [text]. With reduced motion the full text
/// shows at once and [onDone] still fires (after the first frame).
class V3Stream extends StatefulWidget {
  const V3Stream({
    super.key,
    required this.text,
    this.speed = const Duration(milliseconds: 28),
    this.onDone,
    this.caret = true,
    this.start = true,
    this.style,
  });

  final String text;

  /// Delay per two-token step (the design's `speed`, in ms there).
  final Duration speed;
  final VoidCallback? onDone;
  final bool caret;
  final bool start;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// `text.split(/(\s+)/)`: words and the whitespace runs between them.
  @visibleForTesting
  static List<String> tokenize(String text) {
    final tokens = <String>[];
    var last = 0;
    for (final match in RegExp(r'\s+').allMatches(text)) {
      tokens
        ..add(text.substring(last, match.start))
        ..add(match.group(0)!);
      last = match.end;
    }
    tokens.add(text.substring(last));
    return tokens;
  }

  @override
  State<V3Stream> createState() => _V3StreamState();
}

class _V3StreamState extends State<V3Stream> {
  late List<String> _tokens = V3Stream.tokenize(widget.text);
  int _shown = 0;
  Timer? _timer;
  bool _doneFired = false;
  bool _motion = true;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionConfig.enabled(context);
    if (!_initialised) {
      _initialised = true;
      _resume();
    } else if (!_motion) {
      _resume();
    }
  }

  @override
  void didUpdateWidget(V3Stream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _tokens = V3Stream.tokenize(widget.text);
      _doneFired = false;
    }
    if (oldWidget.text != widget.text || oldWidget.start != widget.start) {
      _resume();
    }
  }

  void _resume() {
    _timer?.cancel();
    _timer = null;
    if (!widget.start) return;
    if (!_motion) {
      _shown = _tokens.length;
      _finishIfDone();
      return;
    }
    if (_shown >= _tokens.length) {
      _finishIfDone();
    } else {
      _timer = Timer(widget.speed, _tick);
    }
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _shown += 2);
    if (_shown >= _tokens.length) {
      _timer = null;
      _finishIfDone();
    } else {
      _timer = Timer(widget.speed, _tick);
    }
  }

  /// Fires [V3Stream.onDone] once, always after the current frame: callers
  /// (chat) setState in it, and this can be reached from didUpdateWidget,
  /// i.e. during build.
  void _finishIfDone() {
    if (_doneFired || _shown < _tokens.length) return;
    _doneFired = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final visible = _tokens.take(_shown).join();
    final showCaret = widget.caret && _motion && _shown < _tokens.length;
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: visible,
          children: [
            if (showCaret)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _V3Caret(
                  height: style.fontSize ?? 14,
                  color: style.color ?? AppColors.ink,
                ),
              ),
          ],
        ),
        style: widget.style,
      ),
    );
  }
}

/// 2 pt × 1 em caret, 2 pt after the text and 2 pt below the baseline,
/// blinking on `caret .8s steps(1)`.
class _V3Caret extends StatefulWidget {
  const _V3Caret({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  State<_V3Caret> createState() => _V3CaretState();
}

class _V3CaretState extends State<_V3Caret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Transform.translate(
        offset: const Offset(0, 2),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Opacity(
            opacity: _controller.value < 0.5 ? 1 : 0,
            child: SizedBox(
              width: 2,
              height: widget.height,
              child: ColoredBox(color: widget.color),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing
// ─────────────────────────────────────────────────────────────────────────────

/// `Typing` from `v3/core.jsx`: three 7 pt dots blinking (opacity .25 ↔ 1,
/// 1.1 s, staggered .15 s). With reduced motion they hold still, graded so
/// they still read as typing.
class V3Typing extends StatefulWidget {
  const V3Typing({super.key, this.color = AppColors.ink3, this.semanticLabel});

  final Color color;

  /// Optional spoken label (the design has none).
  final String? semanticLabel;

  @override
  State<V3Typing> createState() => _V3TypingState();
}

class _V3TypingState extends State<V3Typing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  static const _stagger = 150 / 1100;
  static const _still = [1.0, 0.62, 0.25];

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

  // `blink`: 0%,100% { .25 } 50% { 1 }, each leg on CSS `ease`.
  static double _blink(double t) {
    final phase = t % 1;
    if (phase < 0.5) return 0.25 + 0.75 * Curves.ease.transform(phase * 2);
    return 1 - 0.75 * Curves.ease.transform((phase - 0.5) * 2);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    Widget dot(double opacity) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color.withValues(alpha: widget.color.a * opacity),
      ),
    );
    final dots = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            dot(
              motion ? _blink(_controller.value - i * _stagger + 1) : _still[i],
            ),
          ],
        ],
      ),
    );
    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel == null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: dots,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skel
// ─────────────────────────────────────────────────────────────────────────────

/// `Skel` from `v3/core.jsx`: a shimmer placeholder bar (`.skel`, or
/// `.skel-d` when [dark]). The highlight sweeps on `shimmer 1.6s ease
/// infinite` over a 300% tile, as the CSS background does. [width] null
/// fills the available width. Reduced motion shows the plain base colour.
class V3Skel extends StatefulWidget {
  const V3Skel({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.dark = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool dark;

  @override
  State<V3Skel> createState() => _V3SkelState();
}

class _V3SkelState extends State<V3Skel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
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
    final base = widget.dark ? const Color(0x0FFFFFFF) : AppColors.paper2;
    final highlight = widget.dark
        ? const Color(0x24FFFFFF)
        : const Color(0xFFF7F3EC);
    final radius = BorderRadius.circular(widget.radius);
    if (!MotionConfig.enabled(context)) {
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width ?? double.infinity,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: radius,
          // 90deg gradient, 300% wide, repeating, stops 25 / 40 / 60%.
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: const Alignment(5, 0),
            tileMode: TileMode.repeated,
            colors: [base, highlight, base],
            stops: const [0.25, 0.40, 0.60],
            transform: _ShimmerShift(Curves.ease.transform(_controller.value)),
          ),
        ),
      ),
    );
  }
}

/// `background-position: -200% 0 → 200% 0` with `background-size: 300%`
/// moves the tile from +4w to -4w.
class _ShimmerShift extends GradientTransform {
  const _ShimmerShift(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final w = bounds.width;
    return Matrix4.translationValues(4 * w - 8 * w * t, 0, 0);
  }
}
