import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/entrance.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/motion/skeleton.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/presentation/backend_plan_widgets.dart';
import '../../plan/state/current_plan_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';

typedef _PlanStoreView = ({
  CmpysIdol idol,
  String? blueprintMd,
  List<CmpysCustomTask> custom,
  Map<String, bool> tasks,
});

/// CMPYS Plan tab — Roadmap (generated 12-week plan) / Daily habits split.
///
/// The roadmap renders the backend-generated plan (weeks 1–12, primary
/// missions + daily rhythm per week) once it exists; while the generation job
/// runs it shows live progress, and it falls back to the seeded pillars when
/// no plan is available.
class CmpysPlanScreen extends ConsumerStatefulWidget {
  const CmpysPlanScreen({super.key});

  @override
  ConsumerState<CmpysPlanScreen> createState() => _CmpysPlanScreenState();
}

class _CmpysPlanScreenState extends ConsumerState<CmpysPlanScreen> {
  int _view = 0; // 0 = Roadmap, 1 = Daily habits

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(
      cmpysStoreProvider.select(
        (s) => (
          idol: s.idol,
          blueprintMd: s.blueprintMd,
          custom: s.custom,
          tasks: s.tasks,
        ),
      ),
    );
    final planState = ref.watch(currentPlanProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: EntranceScope(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              14,
              18,
              AppShell.bottomNavClearance(context),
            ),
            children: EntranceGroup.wrap([
              _header(st, planState.plan),
              const SizedBox(height: 18),
              _viewToggle(),
              const SizedBox(height: 18),
              if (_view == 0) ..._roadmap(st, planState) else ..._habits(st),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(_PlanStoreView st, BackendPlan? plan) {
    // Never fall back to the seed plan's title — it names the demo idol.
    final title = plan != null
        ? 'Your ${plan.durationWeeks}-week path'
        : 'Your path with ${st.idol.short}';
    final subtitle = plan != null
        ? 'With ${plan.idolName ?? st.idol.short} · ${plan.weeklyHours}h a week'
        : 'A personalized plan, written with ${st.idol.short}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CmpysKicker('Your growth plan'),
        const SizedBox(height: 4),
        Text(
          title,
          style: AppTypography.display.copyWith(
            fontSize: 30,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: AppTypography.bodyDim.copyWith(fontSize: 14.5)),
      ],
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleChip('Roadmap', 0)),
          Expanded(child: _toggleChip('Daily habits', 1)),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, int idx) {
    final active = _view == idx;
    return GestureDetector(
      onTap: () => setState(() => _view = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? [
                  const BoxShadow(
                    color: Color(0x1416161C),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.bodyMedium.copyWith(
            fontSize: 14,
            color: active ? AppColors.ink : AppColors.ink2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ─── Roadmap ───
  List<Widget> _roadmap(_PlanStoreView st, CurrentPlanState planState) {
    final blueprint = <Widget>[
      if (st.blueprintMd != null && st.blueprintMd!.trim().isNotEmpty) ...[
        _blueprintCard(st),
        const SizedBox(height: 14),
      ],
    ];

    switch (planState.status) {
      case CurrentPlanStatus.ready:
        final roadmap = backendPlanRoadmapBlocks(planState.plan!);
        return [
          // The active focus must be the first actionable surface on this
          // page. Supporting blueprint/progress context follows it.
          roadmap.first,
          if (st.blueprintMd != null && st.blueprintMd!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _blueprintCard(st),
          ],
          // Spread so each week card is its own ListView child (lazy build).
          ...roadmap.skip(1),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '"The whole secret is small things, done daily."',
              style: AppTypography.readingQuote.copyWith(
                color: AppColors.ink3,
                fontSize: 15,
              ),
            ),
          ),
        ];
      case CurrentPlanStatus.generating:
        return [
          ...blueprint,
          PlanGeneratingCard(
            progress: planState.jobProgress,
            line: planState.jobLine,
          ),
        ];
      case CurrentPlanStatus.loading:
        return [
          ...blueprint,
          const CmpysSkeleton.block(height: 120),
          const SizedBox(height: 12),
          const CmpysSkeleton.block(height: 120),
          const SizedBox(height: 12),
          const CmpysSkeleton.block(height: 120),
        ];
      case CurrentPlanStatus.failed:
        return [
          ...blueprint,
          CmpysCardSurface(
            onTap: () => ref.read(currentPlanProvider.notifier).refresh(),
            child: Row(
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.ink3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Couldn’t load your 12-week plan — tap to retry.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink2,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
      case CurrentPlanStatus.empty:
        // No generated plan for the active idol yet. Never fall back to the
        // seeded demo plan here — it belongs to a different mentor.
        return [
          ...blueprint,
          _planPendingCard(st),
          if (st.custom.isNotEmpty) ...[
            const SizedBox(height: 18),
            CmpysKicker('Added from your chats with ${st.idol.short}'),
            const SizedBox(height: 10),
            CmpysCardSurface(
              pad: const EdgeInsets.all(6),
              child: Column(
                children: [
                  for (var i = 0; i < st.custom.length; i++)
                    _customRow(st, st.custom[i], first: i == 0),
                ],
              ),
            ),
          ],
        ];
    }
  }

  /// Empty state: the plan for the active idol hasn't been generated (or
  /// hasn't landed) yet. Tapping re-checks and re-enqueues when possible.
  Widget _planPendingCard(_PlanStoreView st) {
    return CmpysCardSurface(
      onTap: () => ref.read(currentPlanProvider.notifier).retry(),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsRegular.sparkle,
            size: 18,
            color: AppColors.ink3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your plan with ${st.idol.short} isn’t ready yet.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ink,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to check again.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The LLM-written blueprint from onboarding — the mentor's own roadmap.
  Widget _blueprintCard(_PlanStoreView st) {
    final idol = st.idol;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        CmpysPageRoute(
          builder: (_) => CmpysMarkdownScreen(
            kicker: 'From ${idol.short}',
            title: 'Your blueprint',
            markdown: st.blueprintMd!,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.gradGreen,
          borderRadius: AppRadii.card,
          boxShadow: [
            BoxShadow(
              color: AppColors.green2.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: Colors.white,
              size: 44,
              border: Border.all(color: Colors.white, width: 2),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WRITTEN BY ${idol.short.toUpperCase()}',
                    style: AppTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your blueprint — read it in full',
                    style: AppTypography.h4.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customRow(
    _PlanStoreView st,
    CmpysCustomTask c, {
    required bool first,
  }) {
    final done = st.tasks[c.id] ?? false;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(cmpysStoreProvider.notifier).toggleTask(c.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: done ? AppColors.green : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done ? AppColors.green : AppColors.hair2,
                  width: 2,
                ),
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 15,
                    color: done ? AppColors.ink3 : AppColors.ink,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Suggested in chat',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            PhosphorIconsRegular.chatTeardrop,
            size: 16,
            color: AppColors.hair2,
          ),
        ],
      ),
    );
  }

  // ─── Daily habits view ───
  List<Widget> _habits(_PlanStoreView st) {
    // Backend-generated daily rhythm (current plan week). Mirrors the
    // roadmap's status handling — the seeded demo rituals never show, since
    // they belong to a different mentor than the one the user chose.
    final planState = ref.watch(currentPlanProvider);
    switch (planState.status) {
      case CurrentPlanStatus.ready:
        final today = ref.watch(todayViewProvider).valueOrNull;
        if (today == null) {
          return [const CmpysSkeleton.block(height: 96)];
        }
        if (today.items.isEmpty) {
          return [
            Text(
              'No daily rhythm tasks this week — check the roadmap.',
              style: AppTypography.bodyDim,
            ),
          ];
        }
        return _backendHabits(today);
      case CurrentPlanStatus.generating:
        return [
          PlanGeneratingCard(
            progress: planState.jobProgress,
            line: planState.jobLine,
          ),
        ];
      case CurrentPlanStatus.loading:
        return [
          const CmpysSkeleton.block(height: 96),
          const SizedBox(height: 12),
          const CmpysSkeleton.block(height: 220),
        ];
      case CurrentPlanStatus.failed:
        return [
          CmpysCardSurface(
            onTap: () => ref.read(currentPlanProvider.notifier).refresh(),
            child: Row(
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.ink3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Couldn’t load your daily rhythm — tap to retry.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink2,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
      case CurrentPlanStatus.empty:
        return [_planPendingCard(st)];
    }
  }

  Widget _streakChip(int streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsFill.flame,
            size: 15,
            color: const Color(0xFFFFD166),
          ),
          const SizedBox(width: 6),
          Text(
            '$streak-day streak',
            style: AppTypography.captionMedium.copyWith(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _backendHabits(TodayView today) {
    final done = today.items.where((i) => i.completedToday).length;
    final total = today.items.length;
    final pct = total == 0 ? 0.0 : done / total * 100;

    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.gradViolet,
          borderRadius: AppRadii.lg,
          boxShadow: [
            BoxShadow(
              color: AppColors.lilac.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            CmpysRing(
              value: pct,
              size: 76,
              stroke: 7,
              color: Colors.white,
              track: Colors.white.withValues(alpha: 0.25),
              child: Text(
                '$done/$total',
                style: AppTypography.h3.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your daily rhythm',
                    style: AppTypography.h4.copyWith(
                      color: Colors.white,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'These reset every day. The roadmap moves forward — these keep you moving.',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (today.streak > 0) ...[
                    const SizedBox(height: 10),
                    _streakChip(today.streak),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Padding(
        padding: EdgeInsets.only(left: 2),
        child: CmpysKicker('Every day'),
      ),
      const SizedBox(height: 10),
      CmpysCardSurface(
        pad: const EdgeInsets.all(6),
        child: Column(
          children: [
            for (var i = 0; i < today.items.length; i++)
              _backendRitualRow(today.items[i], first: i == 0),
          ],
        ),
      ),
    ];
  }

  Future<void> _toggleDaily(TodayTaskItem item) async {
    final wasDone = item.completedToday;
    try {
      await ref.read(planRepositoryProvider).toggleDailyTask(item.id);
      ref.invalidate(todayViewProvider);
      if (!wasDone && mounted) {
        showCmpysToast(
          context,
          'Nice. Kept your word.',
          icon: Icons.check_rounded,
          tone: AppColors.green,
        );
      }
    } catch (_) {
      if (mounted) {
        showCmpysToast(
          context,
          'Couldn’t update — try again.',
          icon: Icons.error_outline_rounded,
          tone: AppColors.ink2,
        );
      }
    }
  }

  Widget _backendRitualRow(TodayTaskItem item, {required bool first}) {
    final done = item.completedToday;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleDaily(item),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: done ? AppColors.green : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done ? AppColors.green : AppColors.hair2,
                    width: 2,
                  ),
                ),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => openBackendPlanItemById(context, item.id),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTypography.bodyMedium.copyWith(
                        fontSize: 15,
                        color: done ? AppColors.ink3 : AppColors.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Daily · ~${item.estimatedHours}h this week',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink3,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.hair2,
            ),
          ),
        ],
      ),
    );
  }
}
