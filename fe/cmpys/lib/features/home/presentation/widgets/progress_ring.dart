import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

/// Executive progress ring for Hub screen.
/// Matches HTML: emerald ring stroke w/ glow, light weight center number.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.percent,
    required this.label,
    required this.subLabel,
    this.size = 80,
    this.thickness = 4,
    this.color = AppColors.coral,
  });

  final double percent; // 0.0 to 1.0
  final String label;
  final String subLabel;
  final double size;
  final double thickness;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Ring
          CustomPaint(
            painter: _RingPainter(
              percent: 1.0,
              color: AppColors.cardTextSecondary.withValues(alpha: 0.15),
              thickness: thickness,
            ),
          ),
          // Progress Ring
          CustomPaint(
            painter: _RingPainter(
              percent: percent,
              color: color,
              thickness: thickness,
              isGlow: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percent,
    required this.color,
    required this.thickness,
    this.isGlow = false,
  });

  final double percent;
  final Color color;
  final double thickness;
  final bool isGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - thickness) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (isGlow) {
      // Add subtle glow effect
      paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);
    }

    final sweepAngle = 2 * pi * percent;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return percent != oldDelegate.percent ||
        color != oldDelegate.color ||
        thickness != oldDelegate.thickness;
  }
}
