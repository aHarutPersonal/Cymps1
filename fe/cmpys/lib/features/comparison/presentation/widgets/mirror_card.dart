import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

class MirrorCard extends StatelessWidget {
  const MirrorCard({
    super.key,
    required this.age,
    required this.userEvent,
    required this.idolEvent,
    required this.isMatched,
  });

  final int age;
  final String? userEvent;
  final String idolEvent;
  final bool isMatched;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // User Side (Left)
            Expanded(
              child: Container(
                padding: AppSpacing.p16,
                decoration: BoxDecoration(
                  color: userEvent != null 
                    ? AppColors.primary.withOpacity(0.05) 
                    : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                  border: userEvent != null
                    ? Border.all(color: AppColors.primary.withOpacity(0.3))
                    : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (userEvent != null) ...[
                      Text(
                        userEvent!,
                        textAlign: TextAlign.right,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (isMatched) 
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(Icons.check_circle, size: 14, color: AppColors.primary),
                        ),
                    ] else
                      Text(
                        'No data',
                        textAlign: TextAlign.right,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary.withOpacity(0.3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // Center Axis (Age)
            Container(
              width: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(color: AppColors.cardBorder, width: 1),
                ),
                gradient: LinearGradient(
                  colors: [
                    AppColors.bg,
                    AppColors.surface,
                    AppColors.bg,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bg,
                  border: Border.all(
                    color: isMatched ? AppColors.primary : AppColors.cardBorder,
                  ),
                  boxShadow: isMatched ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ] : null,
                ),
                child: Text(
                  age.toString(),
                  style: AppTypography.monoLabel.copyWith(
                    color: isMatched ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Idol Side (Right)
            Expanded(
              child: Container(
                padding: AppSpacing.p16,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.05),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                  border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      idolEvent,
                      textAlign: TextAlign.left,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
