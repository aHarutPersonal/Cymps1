import 'dart:ui';
import 'package:flutter/material.dart';

/// A reusable glassmorphic card replicating the premium UI design.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24.0),
    this.borderRadius = 32.0,
    this.blurSigma = 18.0,
    this.onTap,
  });

  /// The widget below this widget in the tree.
  final Widget child;

  /// External padding inside the card.
  final EdgeInsetsGeometry padding;

  /// Corner radius for the card, matching the reference large rounded corners.
  final double borderRadius;

  /// The intensity of the blur effect (15-20 recommended).
  final double blurSigma;

  /// Optional tap handler
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            // Highly transparent fill
            color: Colors.white.withValues(alpha: 0.03),
            // Subtle thin white border
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      );
    }

    return content;
  }
}
