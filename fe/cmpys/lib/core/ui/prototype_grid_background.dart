import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Light prototype canvas with the subtle mint grid used across the HTML mocks.
class PrototypeGridBackground extends StatelessWidget {
  const PrototypeGridBackground({
    super.key,
    required this.child,
    this.gridSize = 24,
    this.color = AppColors.bg,
  });

  final Widget child;
  final double gridSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: CustomPaint(
        painter: _PrototypeGridPainter(gridSize: gridSize),
        child: child,
      ),
    );
  }
}

class _PrototypeGridPainter extends CustomPainter {
  const _PrototypeGridPainter({required this.gridSize});

  final double gridSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mint.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PrototypeGridPainter oldDelegate) {
    return oldDelegate.gridSize != gridSize;
  }
}
