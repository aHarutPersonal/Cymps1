// Widgets rendering the backend-generated 12-week plan (GET /plans/current):
// the week-by-week roadmap (primary missions + daily rhythm per week) and the
// "plan is being generated" progress card shown while the Celery job runs.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../models/plan_models.dart';
import 'plan_item_detail_screen.dart';

void openBackendPlanItem(BuildContext context, BackendPlanItem item) {
  openBackendPlanItemById(context, item.id);
}

void openBackendPlanItemById(BuildContext context, String itemId) {
  Navigator.of(context).push(CmpysPageRoute(
    builder: (_) => PlanItemDetailScreen(itemId: itemId),
  ));
}

/// Progress card while the 12-week plan is still being written by the worker.
class PlanGeneratingCard extends StatelessWidget {
  const PlanGeneratingCard({
    super.key,
    required this.progress,
    this.line = '',
  });

  final int progress;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradInk,
        borderRadius: AppRadii.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('YOUR 12-WEEK PLAN IS BEING WRITTEN',
                    style: AppTypography.kicker.copyWith(
                        color: Colors.white.withValues(alpha: 0.65))),
              ),
              Text('$progress%',
                  style: AppTypography.captionMedium.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (progress.clamp(0, 100)) / 100,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFFFB020)),
            ),
          ),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(line,
                style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// The week-by-week roadmap for a generated plan, as a flat list of blocks.
///
/// Spread the result directly into the surrounding ListView's children so
/// each week card is its own list child and builds lazily — one big Column

/// The roadmap is deliberately progressive: one active week, reviewable past
/// weeks, and preview-only future weeks. This keeps the page calm and prevents
/// users from substituting browsing for finishing the work in front of them.
List<Widget> backendPlanRoadmapBlocks(BackendPlan plan) {
  final focusWeek = plan.focusWeek;
  return [
    _CurrentFocusCard(plan: plan, week: focusWeek),
    const SizedBox(height: 14),
    _PlanProgressCard(plan: plan),
    if (plan.roadmapThesis != null &&
        plan.roadmapThesis!.trim().isNotEmpty) ...[
      const SizedBox(height: 14),
      _PlanThesisCard(plan: plan),
    ],
    const SizedBox(height: 22),
    Row(
      children: [
        const Expanded(child: CmpysKicker('Your roadmap')),
        Text(
          'ONE WEEK AT A TIME',
          style: AppTypography.kicker.copyWith(
            color: AppColors.ink3,
            fontSize: 9.5,
          ),
        ),
      ],
    ),
    for (var week = 1; week <= plan.durationWeeks; week++) ...[
      const SizedBox(height: 10),
      _WeekBlock(
        plan: plan,
        week: week,
        access: plan.allMissionWorkComplete
            ? _WeekAccess.completed
            : week < focusWeek
                ? _WeekAccess.completed
                : week == focusWeek
                    ? _WeekAccess.current
                    : _WeekAccess.locked,
        activeWeek: focusWeek,
      ),
    ],
  ];
}

class _CurrentFocusCard extends StatelessWidget {
  const _CurrentFocusCard({required this.plan, required this.week});

  final BackendPlan plan;
  final int week;

  @override
  Widget build(BuildContext context) {
    final missions = plan.missionsForWeek(week);
    final completed = missions.where((item) => item.isCompleted).length;
    final remaining = missions.length - completed;
    final progress = missions.isEmpty ? 0.0 : completed / missions.length;
    final focus = plan.focusedItemForWeek(week);
    final complete = plan.allMissionWorkComplete;

    return GestureDetector(
      onTap: focus == null ? null : () => openBackendPlanItem(context, focus),
      child: Container(
        key: const Key('current-week-focus'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: complete ? AppColors.gradInk : AppColors.gradGreen,
          borderRadius: AppRadii.lg,
          boxShadow: [
            BoxShadow(
              color: (complete ? AppColors.ink : AppColors.green2)
                  .withValues(alpha: 0.24),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: complete
            ? _completedPlan()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'WEEK $week · CURRENT FOCUS',
                          style: AppTypography.kicker.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: AppRadii.brFull,
                        ),
                        child: Text(
                          '$completed/${missions.length}',
                          style: AppTypography.captionMedium.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    focus?.title ?? 'Complete this week’s mission',
                    style: AppTypography.display.copyWith(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.12,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (focus != null && focus.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      focus.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: AppRadii.brFull,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    week >= plan.durationWeeks
                        ? remaining == 1
                            ? 'Finish the last mission to complete your plan.'
                            : 'Finish the last $remaining missions to complete your plan.'
                        : remaining == 1
                            ? 'Finish 1 mission to unlock Week ${week + 1}.'
                            : 'Finish $remaining missions to unlock Week ${week + 1}.',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12.5,
                    ),
                  ),
                  if (focus != null) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: AppRadii.brFull,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    focus.status == 'in_progress'
                                        ? 'Continue focus'
                                        : 'Start focus',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        AppTypography.captionMedium.copyWith(
                                      color: AppColors.green2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: AppColors.green2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          PhosphorIconsRegular.clock,
                          size: 15,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '~${focus.estimatedHours}h',
                          style: AppTypography.captionMedium.copyWith(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _completedPlan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          PhosphorIconsFill.sealCheck,
          size: 28,
          color: AppColors.green,
        ),
        const SizedBox(height: 13),
        Text(
          'Plan complete',
          style: AppTypography.display.copyWith(
            color: Colors.white,
            fontSize: 27,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Every mission is complete. Your roadmap is open for review.',
          style: AppTypography.body.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}

class _PlanProgressCard extends StatelessWidget {
  const _PlanProgressCard({required this.plan});

  final BackendPlan plan;

  @override
  Widget build(BuildContext context) {
    final pct = plan.overallProgress.round();
    return CmpysCardSurface(
      pad: const EdgeInsets.all(17),
      child: Row(
        children: [
          CmpysRing(
            value: pct.toDouble(),
            size: 58,
            stroke: 6,
            color: AppColors.ochre,
            track: AppColors.hair,
            child: Text(
              '$pct%',
              style: AppTypography.captionMedium.copyWith(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Whole-plan progress',
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${plan.completedItems} of ${plan.totalItems} tasks complete',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${plan.durationWeeks} WEEKS',
            style: AppTypography.kicker.copyWith(
              color: AppColors.ink3,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanThesisCard extends StatelessWidget {
  const _PlanThesisCard({required this.plan});

  final BackendPlan plan;

  @override
  Widget build(BuildContext context) {
    return CmpysCardSurface(
      color: AppColors.greenSoft,
      border: false,
      pad: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CmpysKicker('The thesis', color: AppColors.green),
          const SizedBox(height: 8),
          Text(
            plan.roadmapThesis!,
            style: AppTypography.body.copyWith(fontSize: 14.5, height: 1.5),
          ),
          if (plan.antiGoals.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final goal in plan.antiGoals)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        PhosphorIconsRegular.prohibit,
                        size: 13,
                        color: AppColors.ink2,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        goal,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.ink2,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

enum _WeekAccess { completed, current, locked }

class _WeekBlock extends StatefulWidget {
  const _WeekBlock({
    required this.plan,
    required this.week,
    required this.access,
    required this.activeWeek,
  });

  final BackendPlan plan;
  final int week;
  final _WeekAccess access;
  final int activeWeek;

  @override
  State<_WeekBlock> createState() => _WeekBlockState();
}

class _WeekBlockState extends State<_WeekBlock> {
  late bool _expanded = widget.access == _WeekAccess.current;

  @override
  void didUpdateWidget(_WeekBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access != widget.access) {
      _expanded = widget.access == _WeekAccess.current;
    }
  }

  @override
  Widget build(BuildContext context) {
    final missions = widget.plan.missionsForWeek(widget.week);
    final rhythm = widget.plan.dailyRhythmForWeek(widget.week);
    if (missions.isEmpty && rhythm.isEmpty) return const SizedBox.shrink();

    final completed = missions.where((item) => item.isCompleted).length;
    final remaining = missions.length - completed;
    final hours = missions.fold<int>(
          0,
          (total, item) => total + item.estimatedHours,
        ) +
        rhythm.fold<int>(0, (total, item) => total + item.estimatedHours);
    final locked = widget.access == _WeekAccess.locked;
    final current = widget.access == _WeekAccess.current;
    final complete = widget.access == _WeekAccess.completed;

    return CmpysCardSurface(
      key: Key(
        'week-${widget.week}-${locked ? 'locked' : current ? 'current' : 'completed'}',
      ),
      color: locked ? AppColors.paper2 : AppColors.card,
      raised: current,
      pad: const EdgeInsets.fromLTRB(15, 14, 15, 12),
      onTap: locked
          ? () => _showLockedSheet(context)
          : complete
              ? () => setState(() => _expanded = !_expanded)
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _weekIcon(locked: locked, current: current),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current
                          ? 'Week ${widget.week} · Current'
                          : complete
                              ? 'Week ${widget.week} · Completed'
                              : 'Week ${widget.week}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: locked ? AppColors.ink3 : AppColors.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locked
                          ? 'Complete Week ${widget.activeWeek} to unlock'
                          : current
                              ? '$remaining mission${remaining == 1 ? '' : 's'} remaining · ~${hours}h'
                              : 'Tap to review · ${missions.length} mission${missions.length == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: locked ? AppColors.ink3 : AppColors.ink2,
                        fontSize: 11.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                locked
                    ? PhosphorIconsRegular.lockSimple
                    : complete
                        ? (_expanded
                            ? Icons.expand_less_rounded
                            : Icons.check_rounded)
                        : Icons.keyboard_arrow_up_rounded,
                size: 19,
                color: locked
                    ? AppColors.ink3
                    : complete
                        ? AppColors.green
                        : AppColors.ink3,
              ),
            ],
          ),
          if (current) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: AppRadii.brFull,
              child: LinearProgressIndicator(
                value: missions.isEmpty ? 0 : completed / missions.length,
                minHeight: 5,
                backgroundColor: AppColors.hair,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.green),
              ),
            ),
          ],
          if (_expanded && !locked) ...[
            const SizedBox(height: 9),
            for (final item in missions)
              _itemRow(context, item, isRhythm: false),
            if (rhythm.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 2),
                child: Text(
                  'DAILY RHYTHM · DOES NOT BLOCK PROGRESS',
                  style: AppTypography.kicker.copyWith(
                    color: AppColors.ink3,
                    fontSize: 8.5,
                  ),
                ),
              ),
              for (final item in rhythm)
                _itemRow(context, item, isRhythm: true),
            ],
          ],
        ],
      ),
    );
  }

  Widget _weekIcon({required bool locked, required bool current}) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: locked
            ? AppColors.card.withValues(alpha: 0.6)
            : current
                ? AppColors.greenSoft
                : AppColors.mintSoft,
        shape: BoxShape.circle,
      ),
      child: locked
          ? const Icon(
              PhosphorIconsRegular.lockSimple,
              size: 17,
              color: AppColors.ink3,
            )
          : current
              ? Text(
                  '${widget.week}',
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.green2,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.green2,
                ),
    );
  }

  Widget _itemRow(
    BuildContext context,
    BackendPlanItem item, {
    required bool isRhythm,
  }) {
    final done = item.isCompleted;
    return InkWell(
      onTap: () => openBackendPlanItem(context, item),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                done
                    ? Icons.check_circle_rounded
                    : isRhythm
                        ? PhosphorIconsRegular.arrowClockwise
                        : PhosphorIconsRegular.target,
                size: 18,
                color: done
                    ? AppColors.green
                    : isRhythm
                        ? AppColors.ochre2
                        : AppColors.ink2,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 14.5,
                      color: done ? AppColors.ink3 : AppColors.ink,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isRhythm
                        ? 'Daily rhythm · ~${item.estimatedHours}h this week'
                        : item.progressPercent > 0
                            ? '${item.progressPercent}% complete · ~${item.estimatedHours}h'
                            : '~${item.estimatedHours}h',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink3,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.hair2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLockedSheet(BuildContext context) async {
    final activeMissions = widget.plan.missionsForWeek(widget.activeWeek);
    final completed =
        activeMissions.where((item) => item.isCompleted).length;
    final remaining = activeMissions.length - completed;
    final focus = widget.plan.focusedItemForWeek(widget.activeWeek);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hair2,
                    borderRadius: AppRadii.brFull,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.ochreSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsRegular.lockSimple,
                  color: AppColors.ochre2,
                  size: 22,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Week ${widget.week} is locked',
                style: AppTypography.h2.copyWith(fontSize: 23),
              ),
              const SizedBox(height: 7),
              Text(
                remaining == 1
                    ? 'Finish the remaining mission in Week ${widget.activeWeek}. Then this week opens automatically.'
                    : 'Finish the $remaining remaining missions in Week ${widget.activeWeek}. Then this week opens automatically.',
                style: AppTypography.body.copyWith(
                  color: AppColors.ink2,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (focus != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: AppRadii.br16,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsRegular.target,
                        color: AppColors.green2,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          focus.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ink,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              CmpysButton(
                full: true,
                onTap: () => Navigator.of(sheetContext).pop(),
                leadingIcon: Icons.arrow_upward_rounded,
                child: const Text('Back to current focus'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
