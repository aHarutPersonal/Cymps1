import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/design_tokens.dart';

/// A reusable Stack widget that creates the product-deck ambient glass backdrop.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.primaryGlowColor,
    this.secondaryGlowColor,
    this.useSafeArea = true,
  });

  /// The main content of the screen to be displayed over the background.
  final Widget child;

  /// The primary accent color for the ambient glow. If null, uses AppColors.crimson.
  final Color? primaryGlowColor;

  /// The secondary accent color for the ambient glow. If null, uses a muted variant.
  final Color? secondaryGlowColor;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final color1 =
        primaryGlowColor ?? AppColors.brandAccent.withValues(alpha: 0.22);
    final color2 = secondaryGlowColor ?? AppColors.mint.withValues(alpha: 0.16);

    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.bg,
            gradient: RadialGradient(
              center: const Alignment(-0.75, -0.85),
              radius: 1.4,
              colors: [
                color1,
                AppColors.peach.withValues(alpha: 0.08),
                AppColors.bg,
              ],
              stops: const [0.0, 0.34, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.95, -0.85),
              radius: 1.35,
              colors: [color2, Colors.transparent],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.42),
                Colors.transparent,
                Colors.white.withValues(alpha: 0.28),
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        Positioned.fill(child: CustomPaint(painter: _SubtleGridPainter())),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: const SizedBox.expand(),
          ),
        ),
        if (useSafeArea) SafeArea(child: child) else child,
      ],
    );
  }
}

class _SubtleGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.charcoal.withValues(alpha: 0.035)
      ..strokeWidth = 0.7;
    const step = 64.0;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
