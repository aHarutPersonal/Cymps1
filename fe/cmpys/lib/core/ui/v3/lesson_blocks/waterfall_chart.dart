import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../reading/lesson_fences.dart';
import '../../motion/motion_config.dart';
import 'in_view.dart';

/// `Waterfall` from v3/tutorial.jsx, plus the `bars` chart type.
///
/// A waterfall's first row is the base (iris), the signed deltas step up
/// (sage) or down (danger), and the `=` total row stands on the axis (ember).
/// Bars all stand on the axis (iris, danger when negative). The bars grow
/// and their values fade in the first time the chart scrolls into view
/// (reduced motion: shown at once).
class WaterfallChart extends StatelessWidget {
  const WaterfallChart({
    super.key,
    required this.block,
    this.theme = ReaderTheme.light,
  });

  final ChartBlock block;
  final ReaderTheme theme;

  static const double _height = 150;

  List<_Bar> _bars() {
    if (block.type == ChartType.bars) {
      return [
        for (final row in block.rows)
          _Bar(
            label: row.label,
            from: math.min(0, row.value),
            size: row.value.abs(),
            value: row.text,
            color: row.value < 0 ? AppColors.danger : AppColors.iris,
          ),
      ];
    }
    final bars = <_Bar>[];
    var run = 0.0;
    for (var i = 0; i < block.rows.length; i++) {
      final row = block.rows[i];
      if (row.total) {
        bars.add(
          _Bar(
            label: row.label,
            from: math.min(0, row.value),
            size: row.value.abs(),
            value: row.text,
            color: AppColors.ember,
          ),
        );
        continue;
      }
      final from = run;
      run += row.value;
      final base = i == 0;
      final up = row.value >= 0;
      bars.add(
        _Bar(
          label: row.label,
          from: math.min(from, run),
          size: row.value.abs(),
          value: base ? row.text : '${up ? '+' : '−'}${row.number.magnitude}',
          color: base
              ? AppColors.iris
              : up
              ? AppColors.sage
              : AppColors.danger,
          opacity: base ? 1 : .85,
        ),
      );
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars();
    return Semantics(
      container: true,
      label: [
        block.title,
        if (block.unit != null) block.unit!,
        for (final bar in bars) '${bar.label} ${bar.value}',
      ].join('. '),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      block.title,
                      style: AppTypography.sans(
                        12,
                        FontWeight.w600,
                      ).copyWith(color: theme.fg2),
                    ),
                  ),
                  if (block.unit != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        block.unit!,
                        style: AppTypography.sans(
                          11,
                        ).copyWith(color: theme.fg2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              LessonInView(
                threshold: .5,
                builder: (context, visible) =>
                    _Plot(bars: bars, theme: theme, visible: visible),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar {
  const _Bar({
    required this.label,
    required this.from,
    required this.size,
    required this.value,
    required this.color,
    this.opacity = 1,
  });

  final String label;
  final double from;
  final double size;
  final String value;
  final Color color;
  final double opacity;
}

class _Plot extends StatefulWidget {
  const _Plot({required this.bars, required this.theme, required this.visible});

  final List<_Bar> bars;
  final ReaderTheme theme;
  final bool visible;

  @override
  State<_Plot> createState() => _PlotState();
}

class _PlotState extends State<_Plot> with SingleTickerProviderStateMixin {
  static const _grow = 700;
  static const _stagger = 180;
  static const _fade = 400;
  static const _fadeDelay = 400;

  late final int _total =
      math.max(_grow, _fadeDelay + _fade) + _stagger * (widget.bars.length - 1);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _total),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.value = 1;
  }

  @override
  void didUpdateWidget(_Plot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _phase(int startMs, int lengthMs, Curve curve) {
    final start = startMs / _total;
    final end = math.min(1.0, (startMs + lengthMs) / _total);
    return curve.transform(Interval(start, end).transform(_controller.value));
  }

  @override
  Widget build(BuildContext context) {
    final animate = MotionConfig.enabled(context);
    final bars = widget.bars;
    final low = bars.map((bar) => bar.from).fold<double>(0, math.min);
    final high = bars
        .map((bar) => bar.from + bar.size)
        .fold<double>(0, math.max);
    final range = high - low <= 0 ? 1.0 : high - low;
    double y(double value) => (value - low) / range * WaterfallChart._height;
    final gap = bars.length > 5 ? 6.0 : 10.0;
    final theme = widget.theme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < bars.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: WaterfallChart._height + 24,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -4,
                          right: -4,
                          bottom: y(bars[i].from + bars[i].size) + 4,
                          child: Opacity(
                            opacity: animate
                                ? _phase(
                                    _fadeDelay + i * _stagger,
                                    _fade,
                                    Curves.linear,
                                  )
                                : 1,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                bars[i].value,
                                textAlign: TextAlign.center,
                                style: AppTypography.sans(11.5, FontWeight.w700)
                                    .merge(AppTypography.tnum)
                                    .copyWith(color: theme.fg),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: y(bars[i].from),
                          height: math.max(
                            1.5,
                            bars[i].size / range * WaterfallChart._height,
                          ),
                          child: Transform(
                            alignment: Alignment.bottomCenter,
                            transform: Matrix4.diagonal3Values(
                              1,
                              animate
                                  ? _phase(i * _stagger, _grow, AppMotion.out)
                                  : 1,
                              1,
                            ),
                            child: Opacity(
                              opacity: bars[i].opacity,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: bars[i].color,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bars[i].label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      10.5,
                      FontWeight.w600,
                    ).copyWith(color: theme.fg2, height: 1.2),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
