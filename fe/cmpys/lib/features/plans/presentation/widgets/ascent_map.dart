import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

class AscentMap extends StatelessWidget {
  const AscentMap({
    super.key,
    required this.weeks,
    required this.onWeekSelected,
  });

  final List<Map<String, dynamic>> weeks;
  final ValueChanged<int> onWeekSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      itemCount: weeks.length,
      // We want Week 1 at the bottom.
      // Option 1: reverse: true. Item 0 is at bottom. Week 1 is Item 0.
      // Option 2: reverse: false. Item 0 is top. Week 1 is bottom.
      // "Ascent" implies climbing up. So scrolling up reveals higher weeks.
      // Standard List view: Item 0 is top.
      // So if we want Week 1 at bottom, we should render Week 12 at top, Week 1 at bottom.
      // weeks list is usually [1, 2, ... 12].
      // So reversedWeeks is [12, ... 1].
      itemBuilder: (context, index) {
        // Calculate logical index (0 = bottom-most item)
        // If we use standard list, bottom item is index = length-1.
        // Let's use reverse: true on ListView for "Chat like" scrolling (starts at bottom).
        // Then Item 0 is the first item visually at the bottom.
        // So Item 0 corresponds to Week 1.

        final week =
            weeks[index]; // With reverse:true, index 0 is Week 1? No, index 0 is first in 'weeks' list.
        // If weeks = [W1, W2, ...], and reverse: true:
        // Visual Bottom: Item 0 -> W1.
        // Visual Top: Item N -> WN.
        // So we keep 'weeks' as is.

        // Sine wave position
        // x ranges from -1 to 1.
        // We want a gentle curve.
        // 0 -> Center
        // 1 -> Right
        // 2 -> Center
        // 3 -> Left
        // 4 -> Center
        final double xOffset =
            sin(index * pi / 2) * 0.4; // 0.4 is 40% of screen width offset

        // Use a CustomPainter to draw the line to the NEXT item (index + 1)
        // Since we are building from bottom (index 0), the "next" item in ascent is index + 1.
        final bool hasNext = index < weeks.length - 1;
        final double nextXOffset = hasNext
            ? sin((index + 1) * pi / 2) * 0.4
            : 0;

        return _MapNodeItem(
          week: week,
          xOffset: xOffset,
          nextXOffset: nextXOffset,
          isLast: !hasNext,
          onTap: () => onWeekSelected(week['number']),
        );
      },
      reverse: true, // Start from bottom
    );
  }
}

class _MapNodeItem extends StatelessWidget {
  const _MapNodeItem({
    required this.week,
    required this.xOffset,
    required this.nextXOffset,
    required this.isLast,
    required this.onTap,
  });

  final Map<String, dynamic> week;
  final double xOffset;
  final double nextXOffset;
  final bool isLast;
  final VoidCallback onTap;

  static const double itemHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Path Line
          if (!isLast)
            Positioned.fill(
              child: CustomPaint(
                painter: _PathPainter(
                  startOffset: xOffset,
                  endOffset: nextXOffset,
                  color:
                      (week['isCompleted'] == true || week['isCurrent'] == true)
                      ? AppColors.primary
                      : AppColors.cardBorder,
                ),
              ),
            ),

          // Node
          Align(
            alignment: Alignment(
              xOffset * 2,
              0,
            ), // alignment x is -1 to 1. xOffset is 0.4, so 0.8
            child: _buildNodeContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeContent(BuildContext context) {
    final bool isCompleted = week['isCompleted'] ?? false;
    final bool isCurrent = week['isCurrent'] ?? false;
    final bool isLocked = week['isLocked'] ?? false;
    final int number = week['number'];

    // Node Size
    final double size = isCurrent ? 80 : 64;

    return GestureDetector(
      onTap: isLocked ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isCurrent
              ? AppColors.bg
              : (isCompleted ? AppColors.primary : AppColors.surface),
          shape: BoxShape.circle,
          border: isCurrent
              ? Border.all(color: AppColors.primary, width: 4)
              : (isCompleted
                    ? null
                    : Border.all(color: AppColors.border, width: 2)),
          boxShadow: isCurrent
              ? AppShadows.glowLime
              : (isCompleted
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null),
        ),
        child: Center(
          child: isCompleted && !isCurrent
              ? const Icon(Icons.check, color: AppColors.bg, size: 32)
              : Text(
                  '$number',
                  style: AppTypography.h3.copyWith(
                    color: isCurrent
                        ? AppColors.primary
                        : (isCompleted
                              ? AppColors.bg
                              : AppColors.textSecondary),
                    fontSize: isCurrent ? 24 : 18,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.startOffset,
    required this.endOffset,
    required this.color,
  });

  final double startOffset;
  final double endOffset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Convert alignment (-1 to 1) to pixels
    // Note: alignment x=0 is center.
    // Simpler: center + (offset * width) if offset is percentage.
    // xOffset was 0.4. Alignment takes -1 to 1.
    // If xOffset is 0.4, alignment is 0.8.
    // Let's rely on size.width.
    // If alignment is 0, x = w/2.
    // If alignment is 1, x = w.
    // x = (alignment + 1) / 2 * w

    final sX = (size.width / 2) + (startOffset * size.width); // 0.4 * width
    final eX = (size.width / 2) + (endOffset * size.width);

    final startPoint = Offset(sX, size.height / 2);
    // End point is vertically ABOVE (since we are ascending visually in a reversed list? No wait).
    // ListView reverse: true means index 0 is at bottom, index 1 is above it.
    // But we are drawing inside a SizedBox.
    // "Next" item is visually ABOVE.
    // But this widget only draws inside its bounds. It cannot draw into the next widget's bounds.
    // So we draw a line from Current Center (h/2) to Top Center (-h/2)?
    // No.
    // Standard approach: Draw line from Current Center to Next Item's Center using a FULL HEIGHT painter that connects logic points?
    // Or: Draw half-lines?
    // Best: Draw line from bottom-center to top-center?

    // Logic:
    // We are at index i.
    // We want to connect to index i+1.
    // Index i+1 is visually ABOVE index i (since list starts at bottom).
    // So "Next" is UP (-y direction in standard coord, but here we are in a stack item).

    // Wait, in a Column/ListView:
    // Item 1 (Bottom)
    // Item 2 (Top)

    // In Item 1, we draw a line from Item 1 Center to Item 2 Center.
    // Item 2 Center is at (0, -height/2) relative to Item 1 Top?
    // Item 1 Height = 140. Center = 70.
    // Item 2 starts at -140 (relative to Item 1 top? No).

    // Let's assume the line is drawn from Center (height/2) to Top (0) -> This connects to...
    // No, standard linked list visualization usually uses `Stack` with `Positioned` lines or a `CustomPainter` overlay over the whole list.
    // But overlay over whole list doesn't scroll with list.

    // Trick: Draw line from Center of current to Center of "Previous" (visually below)?
    // Or "Next" (visually above).
    // Let's connect "Current" to "Next" (Above).
    // Point A: (currentX, height/2).
    // Point B: (nextX, -height/2).
    // Yes, drawing outside bounds is allowed in Flutter if clipBehavior is none.

    final endPoint = Offset(eX, -size.height / 2);

    final path = Path();
    path.moveTo(startPoint.dx, startPoint.dy);

    // Bezier Curve
    final controlPoint1 = Offset(startPoint.dx, startPoint.dy - 30);
    final controlPoint2 = Offset(endPoint.dx, endPoint.dy + 30);

    path.cubicTo(
      controlPoint1.dx,
      controlPoint1.dy,
      controlPoint2.dx,
      controlPoint2.dy,
      endPoint.dx,
      endPoint.dy,
    );

    // Dashed line if locked?
    // For now, solid.

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
