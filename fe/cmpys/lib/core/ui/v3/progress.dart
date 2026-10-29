import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

/// Drives a value from where it is to a new target after a delay, on
/// `--out` (Ring and Bar both `setTimeout` then CSS-transition).
class _DelayedValue {
  _DelayedValue(TickerProvider vsync, Duration duration)
    : controller = AnimationController(vsync: vsync, duration: duration);

  final AnimationController controller;
  double _from = 0;
  double _to = 0;
  Timer? _timer;

  double get value {
    final t = AppMotion.out.transform(controller.value);
    return _from * (1 - t) + _to * t;
  }

  void animateTo(double target, Duration wait) {
    _timer?.cancel();
    _timer = Timer(wait, () {
      _from = value;
      _to = target;
      controller.forward(from: 0);
    });
  }

  void dispose() {
    _timer?.cancel();
    controller.dispose();
  }
}

/// `Ring` from `v3/core.jsx`: a circular progress ring that sweeps from 0
/// to [value] (0–1) over 1.2 s on `--out`, starting 60 ms + [delay] after it
/// builds or [value] changes. [child] sits in the centre. Reduced motion
/// draws [value] at once.
class V3Ring extends StatefulWidget {
  const V3Ring({
    super.key,
    this.value = 0,
    this.size = 44,
    this.strokeWidth = 4,
    this.color = AppColors.ember,
    this.track = AppColors.hair,
    this.delay = Duration.zero,
    this.child,
  });

  /// Progress, 0–1 (the design's `p`).
  final double value;
  final double size;

  /// Ring thickness (the design's `sw`).
  final double strokeWidth;
  final Color color;
  final Color track;
  final Duration delay;
  final Widget? child;

  @override
  State<V3Ring> createState() => _V3RingState();
}

class _V3RingState extends State<V3Ring> with SingleTickerProviderStateMixin {
  late final _DelayedValue _value = _DelayedValue(
    this,
    const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _value.animateTo(widget.value, _wait);
  }

  Duration get _wait => const Duration(milliseconds: 60) + widget.delay;

  @override
  void didUpdateWidget(V3Ring oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value.animateTo(widget.value, _wait);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _value.controller,
        child: widget.child == null ? null : Center(child: widget.child),
        builder: (context, child) => CustomPaint(
          painter: _RingPainter(
            progress: motion ? _value.value : widget.value,
            strokeWidth: widget.strokeWidth,
            color: widget.color,
            track: widget.track,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.track,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawCircle(center, radius, paint);
    final sweep = progress.clamp(0.0, 1.0) * 2 * math.pi;
    if (sweep <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      paint
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.track != track;
}

/// `Bar` from `v3/core.jsx`: a rounded linear progress bar that grows from 0
/// to [value] (0–1) over 1.1 s on `--out`, starting 80 ms + [delay] after it
/// builds or [value] changes. Fills the available width. Reduced motion
/// draws [value] at once.
class V3Bar extends StatefulWidget {
  const V3Bar({
    super.key,
    required this.value,
    this.color = AppColors.ember,
    this.height = 6,
    this.track = AppColors.hair,
    this.delay = Duration.zero,
  });

  /// Progress, 0–1 (the design's `p`).
  final double value;
  final Color color;

  /// Thickness (the design's `h`).
  final double height;
  final Color track;
  final Duration delay;

  @override
  State<V3Bar> createState() => _V3BarState();
}

class _V3BarState extends State<V3Bar> with SingleTickerProviderStateMixin {
  late final _DelayedValue _value = _DelayedValue(
    this,
    const Duration(milliseconds: 1100),
  );

  Duration get _wait => const Duration(milliseconds: 80) + widget.delay;

  @override
  void initState() {
    super.initState();
    _value.animateTo(widget.value, _wait);
  }

  @override
  void didUpdateWidget(V3Bar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value.animateTo(widget.value, _wait);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final radius = BorderRadius.circular(9);
    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: widget.track, borderRadius: radius),
      child: AnimatedBuilder(
        animation: _value.controller,
        builder: (context, _) => FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: (motion ? _value.value : widget.value).clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );
  }
}

/// `CountUp` from `v3/core.jsx`: counts from 0 to [to] over [duration] on an
/// ease-out cubic, after [delay], in tabular figures. Restarts from 0 when
/// [to] changes. Screen readers get the final value. Reduced motion shows
/// [to] at once.
class V3CountUp extends StatefulWidget {
  const V3CountUp({
    super.key,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.delay = Duration.zero,
    this.format,
    this.style,
  });

  final num to;
  final Duration duration;
  final Duration delay;

  /// Formats the running value (default: rounded integer).
  final String Function(double value)? format;
  final TextStyle? style;

  @override
  State<V3CountUp> createState() => _V3CountUpState();
}

class _V3CountUpState extends State<V3CountUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _controller
      ..duration = widget.duration
      ..value = 0;
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () => _controller.forward(from: 0));
    }
  }

  @override
  void didUpdateWidget(V3CountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.to != widget.to) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _format(double value) =>
      widget.format?.call(value) ?? value.round().toString();

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final style = (widget.style ?? const TextStyle()).merge(AppTypography.tnum);
    return Semantics(
      label: _format(widget.to.toDouble()),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final k = _controller.value;
          final eased = 1 - math.pow(1 - k, 3).toDouble();
          final value = motion ? widget.to * eased : widget.to.toDouble();
          return Text(_format(value), style: style);
        },
      ),
    );
  }
}
