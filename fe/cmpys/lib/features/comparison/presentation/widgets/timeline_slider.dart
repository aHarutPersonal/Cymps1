import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

/// A vertical timeline slider/scroller is handled by ListView in the parent.
/// This widget acts as a visual indicator or connector if needed.
/// Actually, for "TimelineSlider", if we want a manual age selector:

class TimelineSlider extends StatelessWidget {
  const TimelineSlider({
    super.key,
    required this.currentAge,
    required this.minAge,
    required this.maxAge,
    required this.onChanged,
  });

  final double currentAge;
  final double minAge;
  final double maxAge;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AGE ${currentAge.toInt()}',
                style: AppTypography.monoNum.copyWith(color: AppColors.primary),
              ),
              Text(
                'MAX ${maxAge.toInt()}',
                style: AppTypography.monoLabel.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.cardBorder,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: currentAge,
            min: minAge,
            max: maxAge,
            divisions: (maxAge - minAge).toInt(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
