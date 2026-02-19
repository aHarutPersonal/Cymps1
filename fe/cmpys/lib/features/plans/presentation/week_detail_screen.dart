import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/progress_bar.dart';
import '../controllers/plans_controller.dart';
import '../models/plan_models.dart';

class WeekDetailScreen extends ConsumerStatefulWidget {
  const WeekDetailScreen({
    super.key,
    required this.weekNumber,
  });

  final int weekNumber;

  @override
  ConsumerState<WeekDetailScreen> createState() => _WeekDetailScreenState();
}

class _WeekDetailScreenState extends ConsumerState<WeekDetailScreen> {

  Future<void> _onRefresh() async {
    await ref.read(plansControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final plansState = ref.watch(plansControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Week ${widget.weekNumber}', style: AppTypography.h3),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: switch (plansState) {
          PlansInitial() || PlansLoading() => const LoadingState(message: 'Loading plan...'),
          PlansGenerating() => const LoadingState(message: 'Generating...'), // Should not happen here
          PlansNoPlan() => const Center(child: Text('No plan found')),
          PlansError(:final message) => Center(child: Text(message)),
          PlansLoaded(:final plan) => _buildContent(plan, plansState),
        },
      ),
    );
  }

  Widget _buildContent(Plan plan, PlansLoaded state) {
    // Logic from original PlansScreen _buildPlanContent
    final selectedWeekNum = widget.weekNumber;
    final weekItems = plan.itemsForWeek(selectedWeekNum);
    
    // Get week-specific progress
    final weekSummary = state.getWeekSummary(selectedWeekNum);
    final (localCompleted, localTotal, localProgress) = state.calculateWeekProgress(selectedWeekNum);
    
    final weekCompletedCount = weekSummary?.completedItems ?? localCompleted;
    final weekTotalCount = weekSummary?.totalItems ?? localTotal;
    final weekProgress = weekSummary?.progressPercent ?? (localProgress * 100);
    
    // Load summary if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (weekSummary == null && mounted) {
        ref.read(plansControllerProvider.notifier).loadWeekSummary(selectedWeekNum);
      }
    });

    final dailyTypes = ['habit', 'reading', 'practice'];
    final dailyItems = weekItems.where((i) => dailyTypes.contains(i.type.toLowerCase())).toList();
    final primaryItems = weekItems.where((i) => !dailyTypes.contains(i.type.toLowerCase())).toList();

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.s20),
            
            // Week Progress summary
            Padding(
              padding: AppSpacing.screenH,
              child: CmpysCard(
                padding: AppSpacing.p16,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$weekCompletedCount of $weekTotalCount completed',
                            style: AppTypography.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          ProgressBar(
                            progress: weekProgress / 100,
                            height: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                        vertical: AppSpacing.s6,
                      ),
                      decoration: BoxDecoration(
                        color: weekProgress >= 100
                            ? AppColors.success.withOpacity(0.15)
                            : AppColors.primary.withOpacity(0.15),
                        borderRadius: AppRadii.brFull,
                      ),
                      child: Text(
                        '${weekProgress.round()}%',
                        style: AppTypography.buttonSmall.copyWith(
                          color: weekProgress >= 100 ? AppColors.success : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            
            // TABS
            Padding(
              padding: AppSpacing.screenH,
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: AppRadii.br12,
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.br8,
                    boxShadow: AppShadows.card,
                  ),
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textTertiary,
                  labelStyle: AppTypography.buttonSmall,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Primary Goals'),
                    Tab(text: 'Daily Rhythm'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            
            // TAB VIEW CONTENT
            Expanded(
              child: TabBarView(
                children: [
                  _buildTasksList(primaryItems, 'Focus Items', selectedWeekNum, plan),
                  _buildTasksList(dailyItems, 'Repeatable Habits', selectedWeekNum, plan),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList(List<PlanItem> items, String header, int weekNum, Plan plan) {
    final isPrimary = header.contains('Focus');

    if (items.isEmpty && !isPrimary) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.s24),
            _buildEmptyWeek(),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        left: AppSpacing.s24,
        right: AppSpacing.s24,
        bottom: AppSpacing.s100, 
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.s24),
          Text(
            header,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          
          if (items.isEmpty)
             _buildEmptyWeek()
          else
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: _PlanItemCard(
                item: item,
                onTap: () => context.goToTaskDetail(item.id),
                onToggle: () => ref
                    .read(plansControllerProvider.notifier)
                    .toggleItemCompletion(item.id, weekNumber: weekNum),
              ),
            )),

          if (isPrimary && plan.items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s24),
            Text(
              'All Plan Items',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            ...plan.items
                .where((item) => !items.contains(item))
                .take(5)
                .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                  child: _WeeklyGoalCard(
                    item: item,
                    onTap: () => context.goToTaskDetail(item.id),
                    onToggle: () => ref
                        .read(plansControllerProvider.notifier)
                        .toggleItemCompletion(item.id, weekNumber: item.weekStart),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyWeek() {
    return CmpysCard(
      padding: AppSpacing.p20,
      child: Column(
        children: [
          SvgPicture.asset(
            AppAssets.iconCalendar,
            width: 32,
            height: 32,
            colorFilter: const ColorFilter.mode(
              AppColors.textTertiary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'No tasks for this week',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanItemCard extends StatelessWidget {
  const _PlanItemCard({
    required this.item,
    required this.onTap,
    required this.onToggle,
  });

  final PlanItem item;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      onTap: onTap,
      padding: AppSpacing.p16,
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s12),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.isCompleted ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: item.isCompleted
                      ? null
                      : Border.all(color: AppColors.border, width: 2),
                ),
                child: item.isCompleted
                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                    : null,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTypography.body.copyWith(
                    color: item.isCompleted
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    item.description!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          SvgPicture.asset(
            AppAssets.iconChevronRight,
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(
              AppColors.textTertiary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyGoalCard extends StatelessWidget {
  const _WeeklyGoalCard({
    required this.item,
    required this.onTap,
    required this.onToggle,
  });

  final PlanItem item;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      onTap: onTap,
      padding: AppSpacing.p16,
      borderColor: item.isCompleted ? AppColors.success.withOpacity(0.3) : null,
      backgroundColor: item.isCompleted ? AppColors.success.withOpacity(0.05) : null,
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: AppRadii.br12,
              ),
              child: Center(
                child: item.isCompleted
                    ? SvgPicture.asset(
                        AppAssets.iconCheckCircle,
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          AppColors.success,
                          BlendMode.srcIn,
                        ),
                      )
                    : SvgPicture.asset(
                        AppAssets.iconTarget,
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          AppColors.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTypography.bodyMedium.copyWith(
                    decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                    color: item.isCompleted
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
