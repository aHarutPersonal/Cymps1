import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

/// Active Protocol card for the Hub screen.
/// Shows the current week's task with a progress bar.
class ActiveProtocolCard extends StatelessWidget {
  const ActiveProtocolCard({
    super.key,
    required this.title,
    required this.description,
    this.progress = 0.0,
    this.progressLabel,
    this.onTap,
  });

  final String title;
  final String description;
  final double progress; // 0.0 to 1.0
  final String? progressLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.br24,
          boxShadow: AppShadows.sm,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
          ),
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(title, style: AppTypography.h4)),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: AppRadii.brFull,
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        backgroundColor: AppColors.surfaceHighlight,
                        color: AppColors.accent,
                        minHeight: 4,
                      ),
                    ),
                  ),
                  if (progressLabel != null) ...[
                    const SizedBox(width: 12),
                    Text(progressLabel!, style: AppTypography.captionUpper),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
