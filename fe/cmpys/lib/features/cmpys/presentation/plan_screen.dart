import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/presentation/backend_plan_widgets.dart';
import '../../plan/state/current_plan_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'detail_screens.dart';
import 'pillar_detail_screen.dart';

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
    final st = ref.watch(cmpysStoreProvider);
    final planState = ref.watch(currentPlanProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, AppShell.bottomNavClearance(context)),
          children: [
            _header(st, planState.plan),
            const SizedBox(height: 18),
            _viewToggle(),
            const SizedBox(height: 18),
            if (_view == 0) ..._roadmap(st, planState) else ..._habits(st),
          ],
        ),
      ),
    );
  }

  Widget _header(CmpysState st, BackendPlan? plan) {
    final title = plan != null
        ? 'Your ${plan.durationWeeks}-week path'
        : cmpysPlan.title;
    final subtitle = plan != null
        ? 'With ${plan.idolName ?? st.idol.short} · ${plan.weeklyHours}h a week'
        : '${cmpysPlan.subtitle} · ${cmpysPlan.durationDays} days';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CmpysKicker('Your growth plan'),
        const SizedBox(height: 4),
        Text(title,
            style: AppTypography.display
                .copyWith(fontSize: 30, letterSpacing: -0.5, height: 1.1)),
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
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? [
                  const BoxShadow(
                      color: Color(0x1416161C),
                      blurRadius: 8,
                      offset: Offset(0, 2)),
                ]
              : null,
        ),
        child: Text(label,
            style: AppTypography.bodyMedium.copyWith(
                fontSize: 14,
                color: active ? AppColors.ink : AppColors.ink2,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ─── Roadmap ───
  List<Widget> _roadmap(CmpysState st, CurrentPlanState planState) {
    final blueprint = <Widget>[
      if (st.blueprintMd != null && st.blueprintMd!.trim().isNotEmpty) ...[
        _blueprintCard(st),
        const SizedBox(height: 14),
      ],
    ];

    switch (planState.status) {
      case CurrentPlanStatus.ready:
        return [
          ...blueprint,
          // Spread so each week card is its own ListView child (lazy build).
          ...backendPlanRoadmapBlocks(planState.plan!),
          const SizedBox(height: 18),
          Center(
            child: Text('"The whole secret is small things, done daily."',
                style: AppTypography.readingQuote
                    .copyWith(color: AppColors.ink3, fontSize: 15)),
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
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
                ),
              ),
            ),
          ),
        ];
      case CurrentPlanStatus.failed:
        return [
          ...blueprint,
          CmpysCardSurface(
            onTap: () => ref.read(currentPlanProvider.notifier).refresh(),
            child: Row(
              children: [
                const Icon(Icons.refresh_rounded,
                    size: 18, color: AppColors.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Couldn’t load your 12-week plan — tap to retry.',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.ink2, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ];
      case CurrentPlanStatus.empty:
        return _seedRoadmap(st);
    }
  }

  /// Pre-plan fallback: the seeded pillar roadmap (design demo content).
  List<Widget> _seedRoadmap(CmpysState st) {
    final roadItems = cmpysPlan.pillars
        .expand((p) => p.items)
        .where((it) => it.repeat == CmpysRepeat.once)
        .toList();
    final roadDone = roadItems.where((it) => st.tasks[it.id] ?? false).length;
    final pct = roadItems.isEmpty ? 0 : (roadDone / roadItems.length * 100).round();

    return [
      if (st.blueprintMd != null && st.blueprintMd!.trim().isNotEmpty) ...[
        _blueprintCard(st),
        const SizedBox(height: 14),
      ],
      Container(
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
                      Text('$roadDone of ${roadItems.length} steps complete',
                          style: AppTypography.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13)),
                    ],
                  ),
                ),
                Text('${cmpysPlan.pillars.length} PILLARS',
                    style: AppTypography.kicker.copyWith(
                        color: Colors.white.withValues(alpha: 0.55))),
              ],
            ),
            const SizedBox(height: 14),
            CmpysSegBar(
              total: roadItems.length,
              done: roadDone,
              color: const Color(0xFFFFB020),
              track: Colors.white.withValues(alpha: 0.18),
              height: 8,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      for (final p in cmpysPlan.pillars) ...[
        _pillarBlock(st, p),
        const SizedBox(height: 12),
      ],
      if (st.custom.isNotEmpty) ...[
        const SizedBox(height: 6),
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
      const SizedBox(height: 18),
      Center(
        child: Text('"The whole secret is small things, done daily."',
            style: AppTypography.readingQuote
                .copyWith(color: AppColors.ink3, fontSize: 15)),
      ),
    ];
  }

  /// The LLM-written blueprint from onboarding — the mentor's own roadmap.
  Widget _blueprintCard(CmpysState st) {
    final idol = st.idol;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(CmpysPageRoute(
        builder: (_) => CmpysMarkdownScreen(
          kicker: 'From ${idol.short}',
          title: 'Your blueprint',
          markdown: st.blueprintMd!,
        ),
      )),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.gradGreen,
          borderRadius: AppRadii.card,
          boxShadow: [
            BoxShadow(
                color: AppColors.green2.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8)),
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
                  Text('WRITTEN BY ${idol.short.toUpperCase()}',
                      style: AppTypography.kicker.copyWith(
                          color: Colors.white.withValues(alpha: 0.75))),
                  const SizedBox(height: 4),
                  Text('Your blueprint — read it in full',
                      style: AppTypography.h4.copyWith(
                          color: Colors.white, fontSize: 16, height: 1.25)),
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
              child: const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillarBlock(CmpysState st, CmpysPillar pillar) {
    final steps =
        pillar.items.where((it) => it.repeat == CmpysRepeat.once).toList();
    final rituals =
        pillar.items.where((it) => it.repeat != CmpysRepeat.once).toList();
    final done = steps.where((it) => st.tasks[it.id] ?? false).length;

    final kinds = <CmpysItemKind>{...steps.map((s) => s.kind)};

    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(CmpysPageRoute(builder: (_) => PillarDetailScreen(pillar: pillar))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
        decoration: BoxDecoration(
          color: pillar.accent,
          borderRadius: AppRadii.card,
          boxShadow: [
            BoxShadow(
                color: pillar.accent.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(pillar.kicker.toUpperCase(),
                    style: AppTypography.kicker.copyWith(
                        color: Colors.white.withValues(alpha: 0.78))),
                const Spacer(),
                Text('$done/${steps.length}',
                    style: AppTypography.captionMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(pillar.title,
                style: AppTypography.h2.copyWith(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.1,
                    letterSpacing: -0.3)),
            const SizedBox(height: 14),
            CmpysSegBar(
              total: steps.length,
              done: done,
              color: Colors.white,
              track: Colors.white.withValues(alpha: 0.3),
              height: 7,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in kinds)
                  _kindChip(pillar, k, steps.where((s) => s.kind == k).length),
                if (rituals.isNotEmpty)
                  _ritualChip(pillar, rituals.length),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindChip(CmpysPillar pillar, CmpysItemKind kind, int n) {
    final meta = _kindMeta(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text('$n ${meta.label}',
              style: AppTypography.caption.copyWith(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _ritualChip(CmpysPillar pillar, int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.arrowClockwise, size: 13, color: pillar.accent),
          const SizedBox(width: 5),
          Text('$n daily',
              style: AppTypography.caption.copyWith(
                  color: pillar.accent, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _customRow(CmpysState st, CmpysCustomTask c, {required bool first}) {
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
                    color: done ? AppColors.green : AppColors.hair2, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title,
                    style: AppTypography.bodyMedium.copyWith(
                        fontSize: 15,
                        color: done ? AppColors.ink3 : AppColors.ink,
                        decoration: done ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 2),
                Text('Suggested in chat',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.ink3, fontSize: 12)),
              ],
            ),
          ),
          const Icon(PhosphorIconsRegular.chatTeardrop,
              size: 16, color: AppColors.hair2),
        ],
      ),
    );
  }

  // ─── Daily habits view ───
  List<Widget> _habits(CmpysState st) {
    // Backend-generated daily rhythm (current plan week) when the plan
    // exists; seeded rituals only as a pre-plan fallback. Once a plan is
    // ready the seed never shows — a placeholder covers the today fetch.
    final planReady =
        ref.watch(currentPlanProvider).status == CurrentPlanStatus.ready;
    if (!planReady) return _seedHabits(st);

    final today = ref.watch(todayViewProvider).valueOrNull;
    if (today == null) {
      return [
        Container(
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.paper2,
            borderRadius: AppRadii.lg,
          ),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
              ),
            ),
          ),
        ),
      ];
    }
    if (today.items.isEmpty) {
      return [
        Text('No daily rhythm tasks this week — check the roadmap.',
            style: AppTypography.bodyDim),
      ];
    }
    return _backendHabits(today);
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
          Icon(PhosphorIconsFill.flame, size: 15, color: const Color(0xFFFFD166)),
          const SizedBox(width: 6),
          Text('$streak-day streak',
              style: AppTypography.captionMedium.copyWith(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
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
            gradient: AppColors.gradViolet, borderRadius: AppRadii.lg,
            boxShadow: [
              BoxShadow(
                  color: AppColors.lilac.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 10)),
            ]),
        child: Row(
          children: [
            CmpysRing(
              value: pct,
              size: 76,
              stroke: 7,
              color: Colors.white,
              track: Colors.white.withValues(alpha: 0.25),
              child: Text('$done/$total',
                  style: AppTypography.h3.copyWith(
                      color: Colors.white, fontSize: 18, height: 1)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your daily rhythm',
                      style: AppTypography.h4.copyWith(
                          color: Colors.white, fontSize: 17)),
                  const SizedBox(height: 4),
                  Text(
                      'These reset every day. The roadmap moves forward — these keep you moving.',
                      style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13, height: 1.4)),
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
          padding: EdgeInsets.only(left: 2), child: CmpysKicker('Every day')),
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
        showCmpysToast(context, 'Nice. Kept your word.',
            icon: Icons.check_rounded, tone: AppColors.green);
      }
    } catch (_) {
      if (mounted) {
        showCmpysToast(context, 'Couldn’t update — try again.',
            icon: Icons.error_outline_rounded, tone: AppColors.ink2);
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
                      width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 15, color: Colors.white)
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
                    Text(item.title,
                        style: AppTypography.bodyMedium.copyWith(
                            fontSize: 15,
                            color: done ? AppColors.ink3 : AppColors.ink,
                            decoration:
                                done ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 2),
                    Text('Daily · ~${item.estimatedHours}h this week',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.ink3, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.hair2),
          ),
        ],
      ),
    );
  }

  /// Pre-plan fallback: seeded rituals (design demo content).
  List<Widget> _seedHabits(CmpysState st) {
    final daily = cmpysPlan.pillars
        .expand((p) => p.items.map((it) => (item: it, pillar: p)))
        .where((e) => e.item.repeat == CmpysRepeat.daily)
        .toList();
    final weekly = cmpysPlan.pillars
        .expand((p) => p.items.map((it) => (item: it, pillar: p)))
        .where((e) => e.item.repeat == CmpysRepeat.weekly)
        .toList();
    final dailyDone =
        daily.where((e) => st.tasks[e.item.id] ?? false).length;
    final pct = daily.isEmpty ? 0.0 : dailyDone / daily.length * 100;

    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppColors.gradViolet, borderRadius: AppRadii.lg,
            boxShadow: [
              BoxShadow(
                  color: AppColors.lilac.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 10)),
            ]),
        child: Row(
          children: [
            CmpysRing(
              value: pct,
              size: 76,
              stroke: 7,
              color: Colors.white,
              track: Colors.white.withValues(alpha: 0.25),
              child: Text('$dailyDone/${daily.length}',
                  style: AppTypography.h3.copyWith(
                      color: Colors.white, fontSize: 18, height: 1)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Repeatable rituals',
                      style: AppTypography.h4.copyWith(
                          color: Colors.white, fontSize: 17)),
                  const SizedBox(height: 4),
                  Text('These reset every day. The roadmap moves forward — these keep you moving.',
                      style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13, height: 1.4)),
                  if (st.streak > 0) ...[
                    const SizedBox(height: 10),
                    _streakChip(st.streak),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (daily.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.only(left: 2), child: CmpysKicker('Every day')),
        const SizedBox(height: 10),
        CmpysCardSurface(
          pad: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (var i = 0; i < daily.length; i++)
                _ritualRow(st, daily[i].item, daily[i].pillar, first: i == 0),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
      if (weekly.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.only(left: 2), child: CmpysKicker('Every week')),
        const SizedBox(height: 10),
        CmpysCardSurface(
          pad: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (var i = 0; i < weekly.length; i++)
                _ritualRow(st, weekly[i].item, weekly[i].pillar, first: i == 0),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(PhosphorIconsRegular.info, size: 15, color: AppColors.ink3),
          const SizedBox(width: 6),
          Expanded(
            child: Text('The color dot shows which pillar each ritual belongs to.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.ink3, fontSize: 12.5)),
          ),
        ],
      ),
    ];
  }

  Widget _ritualRow(CmpysState st, CmpysPlanItem item, CmpysPillar pillar,
      {required bool first}) {
    final done = st.tasks[item.id] ?? false;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(cmpysStoreProvider.notifier).toggleTask(item.id),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: done ? pillar.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: done ? pillar.accent : AppColors.hair2, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : null,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => openCmpysPlanItem(context, item),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: AppTypography.bodyMedium.copyWith(
                            fontSize: 15,
                            color: done ? AppColors.ink3 : AppColors.ink,
                            decoration:
                                done ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 2),
                    Text(
                        'Task · ${item.repeat == CmpysRepeat.weekly ? 'Weekly' : 'Daily'} · ${item.minutes} min',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.ink3, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: pillar.accent, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label}) _kindMeta(CmpysItemKind kind) {
    switch (kind) {
      case CmpysItemKind.task:
        return (icon: PhosphorIconsRegular.target, label: 'Task');
      case CmpysItemKind.read:
        return (icon: PhosphorIconsRegular.fileText, label: 'Read');
      case CmpysItemKind.video:
        return (icon: PhosphorIconsFill.playCircle, label: 'Watch');
      case CmpysItemKind.book:
        return (icon: PhosphorIconsRegular.bookOpen, label: 'Lesson');
    }
  }
}
