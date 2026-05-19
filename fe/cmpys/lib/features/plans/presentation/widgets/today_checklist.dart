import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../models/daily_task_models.dart';
import '../../providers/daily_tasks_provider.dart';

/// Today's checklist card for the home screen.
class TodayChecklist extends ConsumerWidget {
  const TodayChecklist({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyTasksProvider);
    final notifier = ref.read(dailyTasksProvider.notifier);

    return switch (state) {
      DailyTasksInitial() => const SizedBox.shrink(),
      DailyTasksLoading() => _buildLoadingCard(),
      DailyTasksError() => const SizedBox.shrink(),
      DailyTasksLoaded(:final overview) => overview.hasDailyTasks
          ? _buildCard(context, ref, overview, notifier)
          : const SizedBox.shrink(),
    };
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System.Today',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.mint,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: AppRadii.br8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    TodayOverview overview,
    DailyTasksNotifier notifier,
  ) {
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
          // Terminal label
          Text(
            'System.Today',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.mint,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),

          // Task rows
          ...overview.items.map(
            (task) => _DailyTaskRow(
              task: task,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.toggleDailyTask(task.id);
              },
            ),
          ),

          // Bottom summary
          if (overview.totalToday > 0) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${overview.completedToday}/${overview.totalToday} completed',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (overview.streak > 0) ...[
                  const SizedBox(width: 12),
                  const Icon(
                    PhosphorIconsRegular.fire,
                    color: AppColors.brandAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${overview.streak} day streak',
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.brandAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DailyTaskRow extends StatelessWidget {
  const _DailyTaskRow({required this.task, required this.onTap});

  final DailyTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Checkbox icon
            AnimatedContainer(
              duration: AppDurations.fast,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.completedToday
                    ? AppColors.mint
                    : Colors.transparent,
                border: task.completedToday
                    ? null
                    : Border.all(
                        color: AppColors.borderFocus,
                        width: 1.5,
                      ),
              ),
              child: task.completedToday
                  ? const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Title
            Expanded(
              child: Text(
                task.title,
                style: AppTypography.body.copyWith(
                  color: task.completedToday
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  decoration: task.completedToday
                      ? TextDecoration.lineThrough
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Duration
            Text(
              task.durationLabel,
              style: AppTypography.captionUpper.copyWith(
                color: task.completedToday
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
