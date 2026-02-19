import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Linear progress bar component.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.progress,
    this.height = 8,
    this.backgroundColor,
    this.progressColor,
    this.borderRadius,
    this.showPercentage = false,
    this.label,
    this.animated = true,
  });

  /// Progress value from 0.0 to 1.0
  final double progress;
  final double height;
  final Color? backgroundColor;
  final Color? progressColor;
  final BorderRadius? borderRadius;
  final bool showPercentage;
  final String? label;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final radius = borderRadius ?? BorderRadius.circular(height / 2);

    Widget progressBar = Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface2,
        borderRadius: radius,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: animated ? AppDurations.normal : Duration.zero,
                curve: Curves.easeOut,
                width: constraints.maxWidth * clampedProgress,
                height: height,
                decoration: BoxDecoration(
                  color: progressColor ?? AppColors.accent,
                  borderRadius: radius,
                ),
              ),
            ],
          );
        },
      ),
    );

    if (label != null || showPercentage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (label != null)
                Text(
                  label!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              if (showPercentage)
                Text(
                  '${(clampedProgress * 100).round()}%',
                  style: AppTypography.captionMedium.copyWith(
                    color: progressColor ?? AppColors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          progressBar,
        ],
      );
    }

    return progressBar;
  }
}

/// Segmented progress bar.
class SegmentedProgressBar extends StatelessWidget {
  const SegmentedProgressBar({
    super.key,
    required this.totalSegments,
    required this.completedSegments,
    this.height = 4,
    this.gap = 4,
    this.activeColor,
    this.inactiveColor,
  });

  final int totalSegments;
  final int completedSegments;
  final double height;
  final double gap;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSegments, (index) {
        final isCompleted = index < completedSegments;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: index < totalSegments - 1 ? gap : 0,
            ),
            height: height,
            decoration: BoxDecoration(
              color: isCompleted
                  ? (activeColor ?? AppColors.accent)
                  : (inactiveColor ?? AppColors.surface2),
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        );
      }),
    );
  }
}

/// Labeled progress with categories.
class CategoryProgressBar extends StatelessWidget {
  const CategoryProgressBar({
    super.key,
    required this.label,
    required this.progress,
    this.color,
    this.trailing,
  });

  final String label;
  final double progress;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.bodyMedium),
            trailing ??
                Text(
                  '${(progress * 100).round()}%',
                  style: AppTypography.bodyMedium.copyWith(
                    color: progressColor,
                  ),
                ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        ProgressBar(
          progress: progress,
          progressColor: progressColor,
          height: 6,
        ),
      ],
    );
  }
}
