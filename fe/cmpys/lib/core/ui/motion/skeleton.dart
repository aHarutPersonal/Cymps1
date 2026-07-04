import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import 'motion_config.dart';

/// Shimmer placeholder primitives for screen-level loading states.
///
/// Grey blocks matching the existing loading-card look (paper2), with a
/// soft white sweep looping while motion is enabled. Compose them to
/// mirror the real layout they replace.
class CmpysSkeleton extends StatelessWidget {
  const CmpysSkeleton.block({
    super.key,
    this.height = 96,
    this.width = double.infinity,
    this.radius = AppRadii.lg,
  });

  const CmpysSkeleton.line({
    super.key,
    this.width = 140,
    this.height = 14,
    this.radius = AppRadii.br8,
  });

  const CmpysSkeleton.circle({super.key, double size = 40})
      : width = size,
        height = size,
        radius = AppRadii.brFull;

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.paper2, borderRadius: radius),
    );
    if (!MotionConfig.enabled(context)) return block;
    return block
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: const Duration(milliseconds: 1200),
          color: Colors.white.withValues(alpha: 0.6),
        );
  }
}
