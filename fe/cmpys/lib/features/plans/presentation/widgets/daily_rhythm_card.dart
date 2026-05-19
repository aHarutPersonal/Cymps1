import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/design_tokens.dart';
import '../../models/daily_task_models.dart';

/// A card showing a daily habit with a 7-day dot grid.
class DailyRhythmCard extends StatelessWidget {
  const DailyRhythmCard({
    super.key,
    required this.task,
    required this.weekStatus,
    this.onDayTap,
  });

  final DailyTask task;
  final DailyTaskWeekStatus? weekStatus;
  final void Function(String itemId, String date)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final minutes = task.estimatedHours != null
        ? (task.estimatedHours! * 60).round()
        : 30;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: type badge + duration
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.12),
                  borderRadius: AppRadii.br8,
                ),
                child: Text(
                  task.type.toUpperCase(),
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '~$minutes min/day',
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            task.title,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // Dot grid
          if (weekStatus != null) ...[
            const SizedBox(height: 16),
            _DayDotGrid(
              days: weekStatus!.days,
              completedCount: weekStatus!.completedCount,
              totalDays: weekStatus!.totalDays,
              onDayTap: onDayTap != null
                  ? (date) => onDayTap!(task.id, date)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _DayDotGrid extends StatelessWidget {
  const _DayDotGrid({
    required this.days,
    required this.completedCount,
    required this.totalDays,
    this.onDayTap,
  });

  final List<DailyDot> days;
  final int completedCount;
  final int totalDays;
  final void Function(String date)? onDayTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day dots row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: days.map((dot) {
            return _DayDot(
              dot: dot,
              onTap: onDayTap != null && !dot.isFuture
                  ? () {
                      HapticFeedback.selectionClick();
                      onDayTap!(dot.date);
                    }
                  : null,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Summary
        Text(
          '$completedCount/$totalDays this week',
          style: AppTypography.captionUpper.copyWith(
            color: AppColors.textTertiary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.dot, this.onTap});

  final DailyDot dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFuture = dot.isFuture;
    final dayLetter = dot.dayName.isNotEmpty ? dot.dayName[0] : '';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          // Day letter
          Text(
            dayLetter,
            style: AppTypography.captionUpper.copyWith(
              color: isFuture
                  ? AppColors.textTertiary.withValues(alpha: 0.5)
                  : AppColors.textTertiary,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 4),
          // Dot
          AnimatedContainer(
            duration: AppDurations.fast,
            width: isFuture ? 10 : 14,
            height: isFuture ? 10 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot.completed
                  ? AppColors.mint
                  : isFuture
                  ? AppColors.borderLight
                  : AppColors.border,
              border: dot.completed
                  ? null
                  : Border.all(
                      color: isFuture
                          ? AppColors.borderLight
                          : AppColors.borderFocus,
                    ),
            ),
            child: dot.completed && !isFuture
                ? const Icon(
                    Icons.check,
                    size: 8,
                    color: Colors.white,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
