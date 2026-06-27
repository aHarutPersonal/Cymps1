// CMPYS bottom-nav icons — recreated as exact traces of the design's SVG paths
// (from ui.jsx's Icon set) so they match the reference pixel-for-pixel rather
// than approximating with a generic icon font.
//
// All paths are authored in the design's 24×24 viewBox and scaled to `size`.
// They are stroked (outline) with round caps/joins — matching the design's
// line-icon treatment.

import 'package:flutter/material.dart';

enum CmpysNavGlyph { today, plan, chat, compare, you }

class CmpysNavIcon extends StatelessWidget {
  const CmpysNavIcon(
    this.glyph, {
    super.key,
    this.size = 23,
    this.color = const Color(0xFF16161C),
    this.strokeWidth = 1.9,
  });

  final CmpysNavGlyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _NavIconPainter(
          glyph: glyph,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _NavIconPainter extends CustomPainter {
  _NavIconPainter({
    required this.glyph,
    required this.color,
    required this.strokeWidth,
  });

  final CmpysNavGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0; // design viewBox is 24×24
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset p(double x, double y) => Offset(x * s, y * s);
    double r(double v) => v * s;

    switch (glyph) {
      case CmpysNavGlyph.today:
        // Roof: M4 11.5 12 5l8 6.5
        final roof = Path()
          ..moveTo(p(4, 11.5).dx, p(4, 11.5).dy)
          ..lineTo(p(12, 5).dx, p(12, 5).dy)
          ..lineTo(p(20, 11.5).dx, p(20, 11.5).dy);
        // Body: M6 10v9h12v-9
        final body = Path()
          ..moveTo(p(6, 10).dx, p(6, 10).dy)
          ..lineTo(p(6, 19).dx, p(6, 19).dy)
          ..lineTo(p(18, 19).dx, p(18, 19).dy)
          ..lineTo(p(18, 10).dx, p(18, 10).dy);
        // Door: M10 19v-5h4v5
        final door = Path()
          ..moveTo(p(10, 19).dx, p(10, 19).dy)
          ..lineTo(p(10, 14).dx, p(10, 14).dy)
          ..lineTo(p(14, 14).dx, p(14, 14).dy)
          ..lineTo(p(14, 19).dx, p(14, 19).dy);
        canvas.drawPath(roof, paint);
        canvas.drawPath(body, paint);
        canvas.drawPath(door, paint);
        break;

      case CmpysNavGlyph.plan:
        // Three lines: M5 5h14M5 12h14M5 19h9  (+ a bullet dot on the first)
        canvas.drawLine(p(5, 5), p(19, 5), paint);
        canvas.drawLine(p(5, 12), p(19, 12), paint);
        canvas.drawLine(p(5, 19), p(14, 19), paint);
        canvas.drawCircle(
            p(3.2, 5), r(0.9), Paint()..color = color);
        canvas.drawCircle(
            p(3.2, 12), r(0.9), Paint()..color = color);
        canvas.drawCircle(
            p(3.2, 19), r(0.9), Paint()..color = color);
        break;

      case CmpysNavGlyph.chat:
        // Rounded speech bubble with a tail at the bottom-left.
        final rad = Radius.circular(r(1));
        final bubble = Path()
          ..moveTo(p(5, 5).dx, p(5, 5).dy)
          ..lineTo(p(19, 5).dx, p(19, 5).dy)
          ..arcToPoint(p(20, 6), radius: rad, clockwise: true)
          ..lineTo(p(20, 15).dx, p(20, 15).dy)
          ..arcToPoint(p(19, 16), radius: rad, clockwise: true)
          ..lineTo(p(9, 16).dx, p(9, 16).dy)
          ..lineTo(p(5, 19).dx, p(5, 19).dy)
          ..lineTo(p(5, 16).dx, p(5, 16).dy)
          ..arcToPoint(p(4, 15), radius: rad, clockwise: true)
          ..lineTo(p(4, 6).dx, p(4, 6).dy)
          ..arcToPoint(p(5, 5), radius: rad, clockwise: true)
          ..close();
        canvas.drawPath(bubble, paint);
        break;

      case CmpysNavGlyph.compare:
        // Balance scale: beam, two pans, crossbar, feet.
        canvas.drawLine(p(12, 4), p(12, 20), paint);
        final leftPan = Path()
          ..moveTo(p(5, 8).dx, p(5, 8).dy)
          ..lineTo(p(2.5, 13).dx, p(2.5, 13).dy)
          ..lineTo(p(7.5, 13).dx, p(7.5, 13).dy)
          ..close();
        final rightPan = Path()
          ..moveTo(p(19, 8).dx, p(19, 8).dy)
          ..lineTo(p(16.5, 13).dx, p(16.5, 13).dy)
          ..lineTo(p(21.5, 13).dx, p(21.5, 13).dy)
          ..close();
        canvas.drawPath(leftPan, paint);
        canvas.drawPath(rightPan, paint);
        canvas.drawLine(p(5, 8), p(19, 8), paint);
        canvas.drawLine(p(3, 20), p(9, 20), paint);
        canvas.drawLine(p(15, 20), p(21, 20), paint);
        break;

      case CmpysNavGlyph.you:
        // Head + shoulders.
        canvas.drawCircle(p(12, 8.5), r(3.5), paint);
        final shoulders = Path()
          ..moveTo(p(5.5, 19.5).dx, p(5.5, 19.5).dy)
          ..arcToPoint(p(18.5, 19.5), radius: Radius.circular(r(6.5)), clockwise: true);
        canvas.drawPath(shoulders, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
