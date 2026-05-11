import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

/// Metric card (replaces StatTile) for the System Vitals grid.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subLabel,
    this.trailingIcon,
    this.trailingIconColor,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String? subLabel;
  final IconData? trailingIcon;
  final Color? trailingIconColor;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardCream,
          borderRadius: AppRadii.br24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.cardTextSecondary,
                  ),
                ),
                if (trailingIcon != null)
                  Icon(
                    trailingIcon,
                    size: 16,
                    color: trailingIconColor ?? AppColors.coral,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: AppTypography.h2.copyWith(
                color: valueColor ?? AppColors.cardTextPrimary,
              ),
            ),
            if (subLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                subLabel!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.cardTextSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
