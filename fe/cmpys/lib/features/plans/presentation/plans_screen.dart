import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../../core/ui/thinking_stream.dart';
import '../../idols/models/job_models.dart';
import '../controllers/plans_controller.dart';
import '../models/plan_models.dart';
import 'widgets/path_design_helpers.dart';

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  final Set<int> _expandedWeeks = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(plansControllerProvider.notifier).load();
    });
  }

  Future<void> _onRefresh() async {
    await ref.read(plansControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final plansState = ref.watch(plansControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PrototypeGridBackground(
        child: SafeArea(bottom: false, child: _buildBody(plansState)),
      ),
    );
  }

  Widget _buildBody(PlansState state) {
    return switch (state) {
      PlansInitial() ||
      PlansLoading() => const LoadingState(message: 'Loading your path...'),
      PlansGenerating(:final jobStatus) => _buildGeneratingState(jobStatus),
      PlansNoPlan() => _buildNoPlanState(),
      PlansError(:final message) => _buildErrorState(message),
      PlansLoaded(:final plan) => _buildPath(plan, state),
    };
  }

  Widget _buildPath(Plan plan, PlansLoaded state) {
    final totalWeeks = plan.durationWeeks.clamp(1, 52).toInt();
    final currentWeek = plan.currentWeek.clamp(1, totalWeeks).toInt();
    final completedItems = plan.items.where((item) => item.isCompleted).length;
    final totalItems = plan.items.length;
    final progress = totalItems == 0 ? 0.0 : completedItems / totalItems;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.mint,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 104, 24, 0),
              child: _PathPrototypeHeader(
                progress: progress,
                currentWeek: currentWeek,
                onRegenerate: _showRegenerateDialog,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 112),
            sliver: SliverList.builder(
              itemCount: totalWeeks,
              itemBuilder: (context, index) {
                final week = index + 1;
                final items = plan.itemsForWeek(week);
                final summary = state.getWeekSummary(week);
                final (completed, total, weekProgress) = state
                    .calculateWeekProgress(week);
                final isExpanded =
                    _expandedWeeks.contains(week) ||
                    (_expandedWeeks.isEmpty && week == currentWeek);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (summary == null && mounted && items.isNotEmpty) {
                    ref
                        .read(plansControllerProvider.notifier)
                        .loadWeekSummary(week);
                  }
                });

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _PrototypeWeekAccordion(
                    week: week,
                    title: pathWeekTitle(week, items, summary: summary),
                    summary: pathWeekSummary(week, items, summary: summary),
                    items: items,
                    completed: summary?.completedItems ?? completed,
                    total: summary?.totalItems ?? total,
                    progress:
                        (summary?.progressPercent ?? (weekProgress * 100)) /
                        100,
                    isCurrent: week == currentWeek,
                    isPast: week < currentWeek,
                    isExpanded: isExpanded,
                    onToggle: () {
                      setState(() {
                        if (_expandedWeeks.contains(week)) {
                          _expandedWeeks.remove(week);
                        } else {
                          _expandedWeeks.add(week);
                        }
                      });
                    },
                    onOpenWeek: () => context.goToWeekDetail(week),
                    onOpenItem: (item) => context.goToTaskDetail(item.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingState(JobStatus? jobStatus) {
    return Padding(
      padding: AppSpacing.screenH,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.s48),
          Text('Building Your Path', style: AppTypography.h1),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Turning the intake into weeks, plan items, steps, and learning sections.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s24),
          PathGlassPanel(
            child: Column(
              children: [
                PathProgressStrip(
                  progress: (jobStatus?.progressPercent ?? 0) / 100,
                ),
                const SizedBox(height: AppSpacing.s12),
                Text(
                  jobStatus?.step ?? 'Preparing plan structure...',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
          if (jobStatus?.thinkingStream != null)
            Expanded(
              child: SingleChildScrollView(
                child: ThinkingStreamWidget(stream: jobStatus!.thinkingStream!),
              ),
            )
          else
            const Expanded(
              child: LoadingState(message: 'Reasoning through your plan...'),
            ),
        ],
      ),
    );
  }

  Widget _buildNoPlanState() {
    return PathEmptyState(
      title: 'No Path Charted',
      message:
          'Generate a personalized 12-week learning path from your idol, gaps, and goals.',
      action: CmpysButton(
        label: 'Generate Plan',
        onPressed: () =>
            ref.read(plansControllerProvider.notifier).generatePlan(),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    final needsIdol =
        message.toLowerCase().contains('idol') ||
        message.toLowerCase().contains('choose an idol');

    return PathEmptyState(
      title: needsIdol ? 'Choose Your North Star' : 'Path Unavailable',
      message: needsIdol
          ? 'Pick a benchmark before opening your growth path.'
          : 'We could not load your Path right now. Please try again.',
      action: CmpysButton(
        label: needsIdol ? 'Choose Idol' : 'Retry',
        onPressed: needsIdol
            ? () => context.goToIdolSuggest()
            : () => ref.read(plansControllerProvider.notifier).load(),
      ),
    );
  }

  void _showRegenerateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.br24),
        title: Text('Regenerate Plan?', style: AppTypography.h3),
        content: Text(
          'This will replace the current path with a new 12-week structure.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTypography.buttonSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(plansControllerProvider.notifier).generatePlan();
            },
            child: Text(
              'Regenerate',
              style: AppTypography.buttonSmall.copyWith(
                color: AppColors.brandAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathPrototypeHeader extends StatelessWidget {
  const _PathPrototypeHeader({
    required this.progress,
    required this.currentWeek,
    required this.onRegenerate,
  });

  final double progress;
  final int currentWeek;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Console.Pathfinder',
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 9,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trajectory Roadmap',
                    style: AppTypography.h2.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onRegenerate,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.10),
                  borderRadius: AppRadii.brFull,
                ),
                child: Text(
                  'WK_${currentWeek.toString().padLeft(2, '0')}',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Overall_Progression',
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
            Text(
              '${(progress * 100).round()}% COMPLETED',
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.mint,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: AppRadii.brFull,
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress.clamp(0, 1),
            backgroundColor: AppColors.borderLight,
            valueColor: const AlwaysStoppedAnimation(AppColors.mint),
          ),
        ),
      ],
    );
  }
}

class _PrototypeWeekAccordion extends StatelessWidget {
  const _PrototypeWeekAccordion({
    required this.week,
    required this.title,
    required this.summary,
    required this.items,
    required this.completed,
    required this.total,
    required this.progress,
    required this.isCurrent,
    required this.isPast,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenWeek,
    required this.onOpenItem,
  });

  final int week;
  final String title;
  final String summary;
  final List<PlanItem> items;
  final int completed;
  final int total;
  final double progress;
  final bool isCurrent;
  final bool isPast;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenWeek;
  final ValueChanged<PlanItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final tint = isCurrent ? AppColors.mint : AppColors.textTertiary;
    final opacity = isPast ? 0.58 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: isPast
              ? AppColors.surfaceHighlight
              : AppColors.surface.withValues(alpha: 0.96),
          borderRadius: AppRadii.br16,
          border: Border.all(
            color: isCurrent ? AppColors.mint : AppColors.border,
          ),
          boxShadow: isCurrent ? AppShadows.sm : null,
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: AppRadii.br16,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.mint
                            : AppColors.surfaceHighlight,
                        borderRadius: AppRadii.br12,
                        border: Border.all(
                          color: isCurrent
                              ? Colors.transparent
                              : AppColors.borderLight,
                        ),
                      ),
                      child: Icon(
                        isPast
                            ? Icons.check_circle_outline_rounded
                            : isCurrent
                            ? Icons.play_arrow_rounded
                            : Icons.lock_outline_rounded,
                        color: isCurrent
                            ? Colors.white
                            : AppColors.textTertiary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Week ${week.toString().padLeft(2, '0')}',
                            style: AppTypography.captionUpper.copyWith(
                              color: tint,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            style: AppTypography.h4.copyWith(
                              color: isPast
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: AppDurations.fast,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: isCurrent
                            ? AppColors.mint
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1, color: AppColors.borderLight),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  children: [
                    _PrototypeBullet(
                      active: isCurrent,
                      text: items.isNotEmpty
                          ? pathItemSubtitle(items.first)
                          : summary,
                    ),
                    if (items.length > 1)
                      _PrototypeBullet(
                        active: false,
                        text: pathItemSubtitle(items[1]),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Expected Outcome: ${_outcomeLabel(summary)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.captionUpper.copyWith(
                              color: AppColors.brandAccent,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onOpenWeek,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.mint,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'RESUME',
                            style: AppTypography.captionUpper.copyWith(
                              color: AppColors.mint,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...items
                          .take(2)
                          .map(
                            (item) => _PrototypePlanItemRow(
                              item: item,
                              onTap: () => onOpenItem(item),
                            ),
                          ),
                    ],
                    if (total > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              value: progress.clamp(0, 1),
                              backgroundColor: AppColors.borderLight,
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.mint,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$completed/$total',
                            style: AppTypography.captionUpper.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _outcomeLabel(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'Strategic Audit';
    final words = clean.split(RegExp(r'\s+')).take(3).join(' ');
    return words;
  }
}

class _PrototypeBullet extends StatelessWidget {
  const _PrototypeBullet({required this.active, required this.text});

  final bool active;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              color: active ? AppColors.mint : AppColors.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: active
                    ? AppColors.textSecondary
                    : AppColors.textTertiary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrototypePlanItemRow extends StatelessWidget {
  const _PrototypePlanItemRow({required this.item, required this.onTap});

  final PlanItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.br8,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              item.isCompleted
                  ? Icons.check_circle_outline_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: item.isCompleted ? AppColors.mint : AppColors.textTertiary,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
