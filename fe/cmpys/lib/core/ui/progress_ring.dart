import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Circular progress ring component.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 8,
    this.backgroundColor,
    this.progressColor,
    this.showPercentage = true,
    this.centerWidget,
    this.animated = true,
  });

  /// Progress value from 0.0 to 1.0
  final double progress;
  final double size;
  final double strokeWidth;
  final Color? backgroundColor;
  final Color? progressColor;
  final bool showPercentage;
  final Widget? centerWidget;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: 1.0,
              strokeWidth: strokeWidth,
              color: backgroundColor ?? AppColors.surfaceHighlight,
            ),
          ),
          // Progress ring
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: clampedProgress),
            duration: animated ? AppDurations.slow : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return CustomPaint(
                size: Size(size, size),
                painter: _RingPainter(
                  progress: value,
                  strokeWidth: strokeWidth,
                  color: progressColor ?? AppColors.accent,
                ),
              );
            },
          ),
          // Center content
          centerWidget ??
              (showPercentage
                  ? Text(
                      '${(clampedProgress * 100).round()}%',
                      style: AppTypography.h3.copyWith(
                        color: progressColor ?? AppColors.accent,
                      ),
                    )
                  : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
  });

  final double progress;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Compact progress ring with label.
class LabeledProgressRing extends StatelessWidget {
  const LabeledProgressRing({
    super.key,
    required this.label,
    required this.progress,
    this.size = 64,
    this.color,
  });

  final String label;
  final double progress;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProgressRing(
          progress: progress,
          size: size,
          strokeWidth: 6,
          progressColor: color,
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          label,
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Multi-ring progress indicator (for overall + categories).
class MultiProgressRing extends StatelessWidget {
  const MultiProgressRing({
    super.key,
    required this.mainProgress,
    required this.categoryProgresses,
    this.size = 120,
    this.mainColor,
  });

  final double mainProgress;
  final List<(double progress, Color color)> categoryProgresses;
  final double size;
  final Color? mainColor;

  @override
  Widget build(BuildContext context) {
    final ringCount = categoryProgresses.length + 1;
    final strokeWidth = size / (ringCount * 4 + 2);
    final gap = strokeWidth * 0.5;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main progress ring (outermost)
          ProgressRing(
            progress: mainProgress,
            size: size,
            strokeWidth: strokeWidth,
            progressColor: mainColor ?? AppColors.accent,
            showPercentage: false,
          ),
          // Category rings
          ...categoryProgresses.asMap().entries.map((entry) {
            final index = entry.key;
            final (progress, color) = entry.value;
            final ringSize = size - ((index + 1) * (strokeWidth + gap) * 2);

            return ProgressRing(
              progress: progress,
              size: ringSize,
              strokeWidth: strokeWidth * 0.8,
              progressColor: color,
              showPercentage: false,
            );
          }),
          // Center percentage
          Text(
            '${(mainProgress * 100).round()}%',
            style: AppTypography.h2.copyWith(
              color: mainColor ?? AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
