import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../reading/lesson_fences.dart';
import '../../motion/motion_config.dart';
import 'in_view.dart';

/// `FormulaStack` from v3/tutorial.jsx: the formula's terms stacked under its
/// title, each with a signed badge. The rows slide in one after another the
/// first time the stack scrolls into view (reduced motion: shown at once).
class FormulaStack extends StatelessWidget {
  const FormulaStack({
    super.key,
    required this.block,
    this.theme = ReaderTheme.light,
  });

  final FormulaBlock block;
  final ReaderTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: [
        block.title,
        for (final term in block.terms) '${term.sign} ${term.label}',
      ].join('. '),
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.hair),
          ),
          child: LessonInView(
            builder: (context, visible) =>
                _Rows(block: block, theme: theme, visible: visible),
          ),
        ),
      ),
    );
  }
}

class _Rows extends StatefulWidget {
  const _Rows({
    required this.block,
    required this.theme,
    required this.visible,
  });

  final FormulaBlock block;
  final ReaderTheme theme;
  final bool visible;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> with SingleTickerProviderStateMixin {
  static const _row = 550;
  static const _stagger = 120;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: _row + _stagger * (widget.block.terms.length - 1),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.value = 1;
  }

  @override
  void didUpdateWidget(_Rows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  (Color, Color) _badge(String sign) => switch (sign) {
    '+' => (AppColors.sageSoft, AppColors.sage2),
    '−' => (AppColors.dangerSoft, AppColors.danger),
    _ => (AppColors.goldSoft, AppColors.gold2),
  };

  @override
  Widget build(BuildContext context) {
    final animate = MotionConfig.enabled(context);
    final total = _controller.duration!.inMilliseconds;
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            widget.block.title,
            style: AppTypography.sans(
              12,
              FontWeight.w600,
            ).copyWith(color: theme.fg2),
          ),
        ),
        for (var i = 0; i < widget.block.terms.length; i++)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final start = i * _stagger / total;
              final t = !animate
                  ? 1.0
                  : AppMotion.out.transform(
                      Interval(
                        start,
                        (start + _row / total).clamp(0.0, 1.0),
                      ).transform(_controller.value),
                    );
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(-14 * (1 - t), 0),
                  child: child,
                ),
              );
            },
            child: _term(i, theme),
          ),
      ],
    );
  }

  Widget _term(int i, ReaderTheme theme) {
    final term = widget.block.terms[i];
    final sign = i == 0 ? '=' : term.sign;
    final (background, foreground) = _badge(sign);
    return CustomPaint(
      painter: i == 0 ? null : _DashedTop(theme.hair),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                sign,
                style: AppTypography.sans(
                  16,
                  FontWeight.w700,
                ).copyWith(color: foreground, height: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                term.label,
                style: AppTypography.sans(
                  15,
                  FontWeight.w500,
                ).copyWith(color: theme.fg, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CSS `border-top: 1px dashed`.
class _DashedTop extends CustomPainter {
  const _DashedTop(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, .5), Offset(x + 3, .5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedTop oldDelegate) => oldDelegate.color != color;
}
