// Widgets rendering the backend-generated 12-week plan (GET /plans/current):
// the week-by-week roadmap (primary missions + daily rhythm per week) and the
// "plan is being generated" progress card shown while the Celery job runs.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../models/plan_models.dart';
import 'plan_item_detail_screen.dart';

void openBackendPlanItem(BuildContext context, BackendPlanItem item) {
  openBackendPlanItemById(context, item.id);
}

void openBackendPlanItemById(BuildContext context, String itemId) {
  Navigator.of(context).push(MaterialPageRoute(
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
/// child would inflate all 12 weeks (100+ rows) eagerly.
List<Widget> backendPlanRoadmapBlocks(BackendPlan plan) {
  final currentWeek = plan.currentWeek();
  return [
    _PlanProgressCard(plan: plan),
    if (plan.roadmapThesis != null &&
        plan.roadmapThesis!.trim().isNotEmpty) ...[
      const SizedBox(height: 14),
      _PlanThesisCard(plan: plan),
    ],
    for (var week = 1; week <= plan.durationWeeks; week++) ...[
      const SizedBox(height: 14),
      _WeekBlock(
        plan: plan,
        week: week,
        isCurrent: week == currentWeek,
      ),
    ],
  ];
}

class _PlanProgressCard extends StatelessWidget {
  const _PlanProgressCard({required this.plan});

  final BackendPlan plan;

  @override
  Widget build(BuildContext context) {
    final pct = plan.overallProgress.round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: AppColors.gradInk, borderRadius: AppRadii.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pct%',
                        style: AppTypography.display.copyWith(
                            color: Colors.white,
                            fontSize: 38,
                            height: 1,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '${plan.completedItems} of ${plan.totalItems} tasks complete',
                        style: AppTypography.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13)),
                  ],
                ),
              ),
              Text('${plan.durationWeeks} WEEKS',
                  style: AppTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: 0.55))),
            ],
          ),
          const SizedBox(height: 14),
          CmpysSegBar(
            total: plan.totalItems == 0 ? 1 : plan.totalItems,
            done: plan.completedItems,
            color: const Color(0xFFFFB020),
            track: Colors.white.withValues(alpha: 0.18),
            height: 8,
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
          Text(plan.roadmapThesis!,
              style:
                  AppTypography.body.copyWith(fontSize: 14.5, height: 1.5)),
          if (plan.antiGoals.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final g in plan.antiGoals)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(PhosphorIconsRegular.prohibit,
                          size: 13, color: AppColors.ink2),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(g,
                          style: AppTypography.caption.copyWith(
                              color: AppColors.ink2,
                              fontSize: 13,
                              height: 1.4)),
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

class _WeekBlock extends StatelessWidget {
  const _WeekBlock({
    required this.plan,
    required this.week,
    required this.isCurrent,
  });

  final BackendPlan plan;
  final int week;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final missions = plan.missionsForWeek(week);
    final rhythm = plan.dailyRhythmForWeek(week);
    if (missions.isEmpty && rhythm.isEmpty) return const SizedBox.shrink();

    // Count once instead of allocating a spread list ([...missions, ...rhythm])
    // and re-filtering it inside the header Text on every rebuild.
    final totalCount = missions.length + rhythm.length;
    final completedCount = missions.where((i) => i.isCompleted).length +
        rhythm.where((i) => i.isCompleted).length;

    return CmpysCardSurface(
      pad: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      raised: isCurrent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CmpysKicker('Week $week',
                  color: isCurrent ? AppColors.green : null),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('You are here',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
              const Spacer(),
              Text(
                '$completedCount/$totalCount',
                style: AppTypography.captionMedium.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in missions)
            _itemRow(context, item, isRhythm: false),
          for (final item in rhythm) _itemRow(context, item, isRhythm: true),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, BackendPlanItem item,
      {required bool isRhythm}) {
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
                    : (isRhythm
                        ? PhosphorIconsRegular.arrowClockwise
                        : PhosphorIconsRegular.target),
                size: 18,
                color: done
                    ? AppColors.green
                    : (isRhythm ? AppColors.ochre2 : AppColors.ink2),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: AppTypography.bodyMedium.copyWith(
                          fontSize: 14.5,
                          color: done ? AppColors.ink3 : AppColors.ink,
                          decoration:
                              done ? TextDecoration.lineThrough : null)),
                  const SizedBox(height: 2),
                  Text(
                      isRhythm
                          ? 'Daily rhythm · ~${item.estimatedHours}h this week'
                          : '~${item.estimatedHours}h',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.ink3, fontSize: 12)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.hair2),
            ),
          ],
        ),
      ),
    );
  }
}
