import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

class WeekNode extends StatelessWidget {
  const WeekNode({
    super.key,
    required this.weekNumber,
    required this.title,
    required this.isCompleted,
    required this.isCurrent,
    required this.isLocked,
    required this.onTap,
  });

  final int weekNumber;
  final String title;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Design Pivot: Softer, "EdTech" style but in Dark Mode.
    // Use fills instead of outlines. rounded corners.
    
    final isAvailable = !isLocked;
    
    return GestureDetector(
      onTap: isLocked ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12), // More breathing room
        padding: const EdgeInsets.all(AppSpacing.s20),
        decoration: BoxDecoration(
          // Use a solid/gradient fill for active items to match the "Card" look
          color: isCurrent 
              ? AppColors.primary 
              : (isCompleted ? AppColors.surface : AppColors.surface.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(24), // Softer, rounder corners (matches EdTech vibe)
          border: isCurrent 
              ? null // No border for filled active card
              : Border.all(color: isCompleted ? AppColors.success.withOpacity(0.3) : AppColors.cardBorder),
          boxShadow: isCurrent 
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon / Number badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isCurrent 
                    ? Colors.white.withOpacity(0.2) 
                    : (isCompleted ? AppColors.success.withOpacity(0.1) : AppColors.bg),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? Icon(Icons.check, color: isCurrent ? Colors.black : AppColors.success)
                    : Text(
                        '$weekNumber',
                        style: AppTypography.h3.copyWith(
                          color: isCurrent ? Colors.black : (isLocked ? AppColors.textTertiary : AppColors.textPrimary),
                          fontSize: 18,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.s20),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEEK $weekNumber',
                    style: AppTypography.monoLabel.copyWith(
                      color: isCurrent ? Colors.black.withOpacity(0.6) : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                       color: isCurrent ? Colors.black : (isLocked ? AppColors.textSecondary : AppColors.textPrimary),
                       fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (isCurrent) ...[
                     const SizedBox(height: 8),
                     Container(
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                       decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.1),
                         borderRadius: BorderRadius.circular(8),
                       ),
                       child: Text(
                         'IN PROGRESS',
                         style: AppTypography.monoLabel.copyWith(
                           color: Colors.black,
                           fontSize: 10,
                           fontWeight: FontWeight.bold,
                         ),
                       ),
                     )
                  ]
                ],
              ),
            ),
            
            // Chevron is simpler in the "Clean" design, or a specific "Play" button?
            if (isCurrent)
               Container(
                 width: 32,
                 height: 32,
                 decoration: const BoxDecoration(
                   color: Colors.white,
                   shape: BoxShape.circle,
                 ),
                 child: const Icon(Icons.play_arrow, color: AppColors.primary, size: 20),
               )
            else if (!isLocked)
               Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
