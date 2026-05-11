import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../controllers/plans_controller.dart';
import '../models/plan_models.dart';
import 'widgets/path_design_helpers.dart';

class WeekDetailScreen extends ConsumerStatefulWidget {
  const WeekDetailScreen({super.key, required this.weekNumber});

  final int weekNumber;

  @override
  ConsumerState<WeekDetailScreen> createState() => _WeekDetailScreenState();
}

class _WeekDetailScreenState extends ConsumerState<WeekDetailScreen> {
  final Set<String> _expandedItems = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(plansControllerProvider);
      if (state is PlansInitial) {
        ref.read(plansControllerProvider.notifier).load();
      }
      ref
          .read(plansControllerProvider.notifier)
          .loadWeekSummary(widget.weekNumber);
    });
  }

  Future<void> _onRefresh() async {
    await ref.read(plansControllerProvider.notifier).refresh();
    await ref
        .read(plansControllerProvider.notifier)
        .loadWeekSummary(widget.weekNumber);
  }

  @override
  Widget build(BuildContext context) {
    final plansState = ref.watch(plansControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PrototypeGridBackground(
        gridSize: 20,
        child: SafeArea(bottom: false, child: _buildBody(plansState)),
      ),
    );
  }

  Widget _buildBody(PlansState state) {
    return switch (state) {
      PlansInitial() ||
      PlansLoading() => const LoadingState(message: 'Loading week...'),
      PlansGenerating() => const LoadingState(message: 'Generating path...'),
      PlansNoPlan() => _emptyState(),
      PlansError(:final message) => PathEmptyState(
        title: 'Week Unavailable',
        message: message,
        action: CmpysButton(
          label: 'Retry',
          onPressed: () => ref.read(plansControllerProvider.notifier).load(),
        ),
      ),
      PlansLoaded(:final plan) => _buildWeek(plan, state),
    };
  }

  Widget _buildWeek(Plan plan, PlansLoaded state) {
    final weekItems = plan.itemsForWeek(widget.weekNumber);
    final summary = state.getWeekSummary(widget.weekNumber);
    final (localCompleted, localTotal, localProgress) = state
        .calculateWeekProgress(widget.weekNumber);
    final completed = summary?.completedItems ?? localCompleted;
    final total = summary?.totalItems ?? localTotal;
    final title = pathWeekTitle(widget.weekNumber, weekItems, summary: summary);

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.brandAccent,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _WeekPrototypeHeader(
              weekNumber: widget.weekNumber,
              title: title,
              completed: completed,
              total: total,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: _WeekStatusPanel(completed: completed, total: total),
            ),
          ),
          if (weekItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(compact: true),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 112),
              sliver: SliverList.builder(
                itemCount: weekItems.length,
                itemBuilder: (context, index) {
                  final item = weekItems[index];
                  final isExpanded =
                      _expandedItems.contains(item.id) ||
                      (_expandedItems.isEmpty && index == 0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _WeekPlanItemCard(
                      item: item,
                      index: index,
                      isExpanded: isExpanded,
                      onToggleExpand: () {
                        setState(() {
                          if (_expandedItems.contains(item.id)) {
                            _expandedItems.remove(item.id);
                          } else {
                            _expandedItems.add(item.id);
                          }
                        });
                      },
                      onOpen: () => context.goToTaskDetail(item.id),
                      onToggleComplete: () => ref
                          .read(plansControllerProvider.notifier)
                          .toggleItemCompletion(
                            item.id,
                            weekNumber: widget.weekNumber,
                          ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState({bool compact = false}) {
    return PathEmptyState(
      title: compact ? 'No Items This Week' : 'No Plan Found',
      message: compact
          ? 'This week is empty. Regenerate the path to fill it with plan items.'
          : 'Generate a path before opening week detail.',
      action: compact
          ? null
          : CmpysButton(
              label: 'Back to Path',
              onPressed: () => Navigator.of(context).pop(),
            ),
    );
  }
}

class _WeekPrototypeHeader extends StatelessWidget {
  const _WeekPrototypeHeader({
    required this.weekNumber,
    required this.title,
    required this.completed,
    required this.total,
    required this.onBack,
  });

  final int weekNumber;
  final String title;
  final int completed;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(24, 58, 24, 24),
      child: Row(
        children: [
          _PrototypeIconButton(icon: Icons.chevron_left_rounded, onTap: onBack),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Week_${weekNumber.toString().padLeft(2, '0')} . Protocol',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
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

class _PrototypeIconButton extends StatelessWidget {
  const _PrototypeIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.br12,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.br12,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadii.br12,
          ),
          child: Icon(icon, size: 24, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _WeekStatusPanel extends StatelessWidget {
  const _WeekStatusPanel({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: AppRadii.br16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current_Status',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$completed of $total Tasks',
                  style: AppTypography.h3.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.mint),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekPlanItemCard extends StatelessWidget {
  const _WeekPlanItemCard({
    required this.item,
    required this.index,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onOpen,
    required this.onToggleComplete,
  });

  final PlanItem item;
  final int index;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpen;
  final VoidCallback onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final steps = pathSyntheticSteps(item);
    final duration = item.estimatedHours == null
        ? '45 MIN'
        : '${(item.estimatedHours! * 60).round()} MIN';
    final stateLabel = item.isCompleted
        ? 'Completed'
        : index == 0
        ? 'In_Progress'
        : 'Queued';
    final stateColor = item.isCompleted
        ? AppColors.textTertiary
        : index == 0
        ? AppColors.mint
        : AppColors.textTertiary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.br16,
        onTap: onToggleExpand,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br16,
            border: Border(
              left: BorderSide(
                color: index == 0 ? AppColors.mint : AppColors.border,
                width: index == 0 ? 4 : 1,
              ),
              top: const BorderSide(color: AppColors.border),
              right: const BorderSide(color: AppColors.border),
              bottom: const BorderSide(color: AppColors.border),
            ),
            boxShadow: AppShadows.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.isCompleted
                        ? Icons.check_circle_outline_rounded
                        : index == 0
                        ? Icons.circle
                        : Icons.radio_button_unchecked_rounded,
                    color: stateColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stateLabel,
                      style: AppTypography.captionUpper.copyWith(
                        color: stateColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Text(
                    duration,
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                item.title,
                style: AppTypography.h4.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pathItemSubtitle(item),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  _TaskTag(pathItemKind(item).toUpperCase()),
                  const _TaskTag('LOGIC'),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 14),
                ...steps.map(
                  (step) => _CompactStepLine(
                    title: step.title,
                    completed: step.completed,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: Text(
                      'OPEN WORKSPACE',
                      style: AppTypography.captionUpper.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.br12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: onToggleComplete,
                  child: Text(
                    item.isCompleted ? 'MARK INCOMPLETE' : 'MARK COMPLETE',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTag extends StatelessWidget {
  const _TaskTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: AppRadii.br8,
      ),
      child: Text(
        label,
        style: AppTypography.captionUpper.copyWith(
          color: AppColors.textTertiary,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CompactStepLine extends StatelessWidget {
  const _CompactStepLine({required this.title, required this.completed});

  final String title;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            completed ? Icons.check_rounded : Icons.circle_outlined,
            size: 16,
            color: completed ? AppColors.mint : AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
