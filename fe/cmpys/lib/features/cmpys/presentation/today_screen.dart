import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/entrance.dart';
import '../../../core/ui/motion/skeleton.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/presentation/backend_plan_widgets.dart';
import '../../plan/state/current_plan_provider.dart';
import '../data/cmpys_ideas_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_backend_sync.dart';
import '../state/cmpys_store.dart';
import 'detail_screens.dart';

/// Lazily-built lookup from plan-item id to its (item, pillar). `cmpysPlan` is
/// a top-level const, so this is computed once for the whole app instead of
/// re-scanning every pillar/item on each habit tile render (was O(pillars×items)
/// per tile).
final Map<String, ({CmpysPlanItem item, CmpysPillar pillar})> _pillarByItemId = {
  for (final p in cmpysPlan.pillars)
    for (final it in p.items) it.id: (item: it, pillar: p),
};

/// CMPYS Today tab — the "next best action" home screen.
///
/// Daily habits come from the AI-generated 12-week plan (current week's
/// daily-rhythm items via GET /plans/{id}/today, toggled per-day through
/// /daily-toggle). The seeded habits are only a fallback while no plan
/// exists; while the plan job runs a slim progress hint shows instead.
class CmpysTodayScreen extends ConsumerWidget {
  const CmpysTodayScreen({super.key});

  List<CmpysPlanItem> get _dailyItems => cmpysPlan.pillars
      .expand((p) => p.items)
      .where((it) => it.repeat == CmpysRepeat.daily)
      .toList();

  ({CmpysPlanItem item, CmpysPillar pillar})? _pillarFor(String id) =>
      _pillarByItemId[id];

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(cmpysStoreProvider);
    final idol = st.idol;
    // Hydrate mentor + AI results from the backend (source of truth).
    ref.watch(cmpysBackendSyncProvider);

    // Daily rhythm from the generated plan. Once a plan exists the seed
    // habits never show — while today's view loads we show a placeholder
    // rather than flashing demo content.
    final planReady =
        ref.watch(currentPlanProvider).status == CurrentPlanStatus.ready;
    final backendToday = ref.watch(todayViewProvider).valueOrNull;
    final backendItems = backendToday?.items ?? const <TodayTaskItem>[];
    final todayLoading = planReady && backendToday == null;

    final daily = planReady ? const <CmpysPlanItem>[] : _dailyItems;
    final totalToday = planReady ? backendItems.length : daily.length;
    final doneToday = planReady
        ? backendItems.where((i) => i.completedToday).length
        : daily.where((it) => st.tasks[it.id] ?? false).length;
    final pct = totalToday == 0 ? 0.0 : doneToday / totalToday * 100;
    // AI-generated idea cards — no static fallback.
    final ideasAsync = ref.watch(cmpysIdeasProvider);
    final name = st.user.name.isEmpty ? 'friend' : st.user.name;

    final backendUndone =
        backendItems.where((i) => !i.completedToday).toList();
    final nextBackendItem = backendUndone.isEmpty ? null : backendUndone.first;
    final nextItem = daily.firstWhere((it) => !(st.tasks[it.id] ?? false),
        orElse: () => daily.isNotEmpty ? daily.first : cmpysPlan.pillars.first.items.first);
    final nextHasUndone =
        planReady ? false : daily.any((it) => !(st.tasks[it.id] ?? false));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, AppShell.bottomNavClearance(context)),
          children: EntranceGroup.wrap([
            _topBar(context, st, idol, name),
            const SizedBox(height: 18),
            _heroCard(pct, doneToday, totalToday, st.streak),
            ..._planGeneratingHint(context, ref),
            const SizedBox(height: 16),
            if (nextBackendItem != null)
              _backendNextActionCard(context, nextBackendItem)
            else if (planReady && backendItems.isNotEmpty)
              _allDoneCard()
            else if (todayLoading)
              const SizedBox.shrink()
            else if (nextHasUndone)
              _nextActionCard(context, nextItem)
            else if (!planReady)
              _allDoneCard(),
            const SizedBox(height: 22),
            _sectionHeader(context, 'Today’s habits', onFullPlan: () => context.go(AppRoutes.plan)),
            const SizedBox(height: 12),
            if (todayLoading)
              _habitsLoadingCard()
            else if (planReady && backendItems.isNotEmpty)
              CmpysCardSurface(
                pad: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    for (var i = 0; i < backendItems.length; i++)
                      _backendHabitTile(context, ref, backendItems[i],
                          first: i == 0),
                  ],
                ),
              )
            else if (daily.isEmpty)
              Text('No daily habits in your plan yet.',
                  style: AppTypography.bodyDim)
            else
              CmpysCardSurface(
                pad: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    for (var i = 0; i < daily.length; i++)
                      _habitTile(context, ref, daily[i], st.tasks[daily[i].id] ?? false,
                          first: i == 0),
                  ],
                ),
              ),
            const SizedBox(height: 22),
            ideasAsync.when(
              data: (ideas) =>
                  _ideaCard(context, ideas[st.dayNum % ideas.length]),
              loading: () => _ideaLoadingCard(),
              error: (_, _) => _ideaErrorCard(ref),
            ),
            const SizedBox(height: 22),
            _compareNudge(context, st, idol, name),
          ]),
        ),
      ),
    );
  }

  /// Slim progress hint while the 12-week plan job is still running.
  List<Widget> _planGeneratingHint(BuildContext context, WidgetRef ref) {
    final planState = ref.watch(currentPlanProvider);
    if (planState.status != CurrentPlanStatus.generating) return const [];
    return [
      const SizedBox(height: 16),
      CmpysCardSurface(
        onTap: () => context.go(AppRoutes.plan),
        pad: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your 12-week plan is being written — ${planState.jobProgress}%',
                style: AppTypography.caption
                    .copyWith(color: AppColors.ink2, fontSize: 13.5),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.hair2),
          ],
        ),
      ),
    ];
  }

  Future<void> _toggleDaily(
      BuildContext context, WidgetRef ref, TodayTaskItem item) async {
    final wasDone = item.completedToday;
    try {
      await ref.read(planRepositoryProvider).toggleDailyTask(item.id);
      ref.invalidate(todayViewProvider);
      if (!wasDone && context.mounted) {
        showCmpysToast(context, 'Nice. Kept your word.',
            icon: Icons.check_rounded, tone: AppColors.green);
      }
    } catch (_) {
      if (context.mounted) {
        showCmpysToast(context, 'Couldn’t update — try again.',
            icon: Icons.error_outline_rounded, tone: AppColors.ink2);
      }
    }
  }

  /// Next-best-action card for a plan-generated daily task, including the
  /// mentor's daily instructions when present.
  Widget _backendNextActionCard(BuildContext context, TodayTaskItem item) {
    return GestureDetector(
      onTap: () => openBackendPlanItemById(context, item.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: AppColors.gradInk,
          borderRadius: AppRadii.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR NEXT BEST ACTION',
                style: AppTypography.kicker.copyWith(
                    color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 10),
            Text(item.title,
                style: AppTypography.h3.copyWith(
                    color: Colors.white, fontSize: 21, height: 1.2)),
            if (item.dailyInstructions != null &&
                item.dailyInstructions!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.dailyInstructions!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      height: 1.45)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Daily rhythm · ~${item.estimatedHours}h this week',
                    style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBC24A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Start',
                          style: AppTypography.button.copyWith(
                              color: const Color(0xFF211F1A), fontSize: 14)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: Color(0xFF211F1A)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _backendHabitTile(
      BuildContext context, WidgetRef ref, TodayTaskItem item,
      {required bool first}) {
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
            onTap: () => _toggleDaily(context, ref, item),
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

  Widget _topBar(BuildContext context, CmpysState st, CmpysIdol idol, String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CmpysKicker('Day ${st.dayNum} · with ${idol.short}'),
              const SizedBox(height: 6),
              Text('${_greeting()}, $name.',
                  style: AppTypography.display.copyWith(
                      fontSize: 30, letterSpacing: -0.6, height: 1.08)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _circleAction(
            icon: PhosphorIconsRegular.bellSimple,
            onTap: () => context.goToIdeas(),
          ),
        ),
      ],
    );
  }

  Widget _circleAction({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hair),
          ),
          child: Icon(icon, color: AppColors.ink2, size: 20),
        ),
      ),
    );
  }

  Widget _heroCard(double pct, int doneToday, int total, int streak) {
    final left = total - doneToday;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: AppColors.gradGreen,
        borderRadius: AppRadii.lg,
        boxShadow: [
          BoxShadow(
            color: AppColors.green2.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CmpysRing(
            value: pct,
            size: 80,
            stroke: 7,
            color: const Color(0xFFEBC24A),
            track: Colors.white.withValues(alpha: 0.22),
            child: RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: '$doneToday',
                    style: AppTypography.h2.copyWith(
                        color: Colors.white, fontSize: 23, height: 1)),
                TextSpan(
                    text: '/$total',
                    style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pct >= 100 ? 'Today is done. Well held.' : '$left habits left today',
                  style: AppTypography.h4.copyWith(
                      color: Colors.white, fontSize: 17, height: 1.2),
                ),
                const SizedBox(height: 4),
                Text(
                  pct >= 100
                      ? 'Consistency is the whole game.'
                      : 'Small things, done daily.',
                  style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5),
                ),
                if (streak > 0) ...[
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsFill.flame,
                            size: 16, color: const Color(0xFFEBC24A)),
                        const SizedBox(width: 6),
                        Text('$streak-day streak',
                            style: AppTypography.captionMedium.copyWith(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextActionCard(BuildContext context, CmpysPlanItem item) {
    final pf = _pillarFor(item.id);
    return GestureDetector(
      onTap: () => _openItem(context, item),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: AppColors.gradInk,
          borderRadius: AppRadii.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR NEXT BEST ACTION',
                style: AppTypography.kicker.copyWith(
                    color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 10),
            Text(item.title,
                style: AppTypography.h3.copyWith(
                    color: Colors.white, fontSize: 21, height: 1.2)),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('${item.minutes} min · ${pf?.pillar.kicker ?? ""}',
                    style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBC24A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Start',
                          style: AppTypography.button.copyWith(
                              color: const Color(0xFF211F1A), fontSize: 14)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: Color(0xFF211F1A)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _allDoneCard() {
    return CmpysCardSurface(
      color: AppColors.greenSoft,
      border: false,
      pad: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.check_rounded, size: 30, color: AppColors.green),
          const SizedBox(height: 10),
          Text('All daily habits complete.',
              style: AppTypography.h3.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text('Come back tomorrow — or get ahead in your plan.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyDim.copyWith(fontSize: 13.5)),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title,
      {VoidCallback? onFullPlan}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          CmpysKicker(title),
          const Spacer(),
          if (onFullPlan != null)
            GestureDetector(
              onTap: onFullPlan,
              child: Text('Full plan',
                  style: AppTypography.captionMedium.copyWith(
                      color: AppColors.green, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _habitTile(BuildContext context, WidgetRef ref, CmpysPlanItem item,
      bool done,
      {required bool first}) {
    final pf = _pillarFor(item.id);
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              ref.read(cmpysStoreProvider.notifier).toggleTask(item.id);
              if (!done) {
                showCmpysToast(context, 'Nice. Kept your word.',
                    icon: Icons.check_rounded, tone: AppColors.green);
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: done ? (pf?.pillar.accent ?? AppColors.green) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done ? (pf?.pillar.accent ?? AppColors.green) : AppColors.hair2,
                    width: 2,
                  ),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : null,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _openItem(context, item),
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
                    Text('Task · Daily · ${item.minutes} min',
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

  Widget _habitsLoadingCard() {
    return const CmpysSkeleton.block(height: 96);
  }

  Widget _ideaLoadingCard() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 2, bottom: 12),
          child: CmpysKicker('Idea for you today'),
        ),
        CmpysSkeleton.block(height: 120),
      ],
    );
  }

  Widget _ideaErrorCard(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 12),
          child: CmpysKicker('Idea for you today'),
        ),
        CmpysCardSurface(
          onTap: () => ref.invalidate(cmpysIdeasProvider),
          child: Row(
            children: [
              const Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Couldn’t load today’s idea — tap to retry.',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.ink2, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ideaCard(BuildContext context, CmpysIdea idea) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 12),
          child: CmpysKicker('Idea for you today'),
        ),
        GestureDetector(
          onTap: () => context.goToIdeas(),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: idea.tone,
              borderRadius: AppRadii.lg,
              boxShadow: [
                BoxShadow(
                    color: idea.tone.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsFill.quotes,
                    size: 26, color: Colors.white.withValues(alpha: 0.55)),
                const SizedBox(height: 10),
                Text(idea.text,
                    style: AppTypography.h3.copyWith(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.35,
                        letterSpacing: -0.2)),
                const SizedBox(height: 12),
                Text('— ${idea.author}',
                    style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _compareNudge(
      BuildContext context, CmpysState st, CmpysIdol idol, String name) {
    final initial = name.isNotEmpty && name != 'friend'
        ? name[0].toUpperCase()
        : 'Y';
    return CmpysCardSurface(
      onTap: () => context.go(AppRoutes.vault),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 44,
            child: Stack(
              children: [
                CmpysMonogram(
                  initials: initial,
                  size: 44,
                  color: AppColors.ochre2,
                  tint: AppColors.ochreSoft,
                ),
                Positioned(
                  left: 34,
                  child: CmpysMentorAvatar(
                    slug: idol.slug,
                    initials: idol.initials,
                    color: idol.color,
                    tint: idol.tint,
                    size: 44,
                    border: Border.all(color: AppColors.card, width: 2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You vs ${idol.short} at ${cmpysComparison.age}',
                    style: AppTypography.bodyMedium.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text('See where you stand today',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.ink2, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 19, color: AppColors.ink3),
        ],
      ),
    );
  }

  void _openItem(BuildContext context, CmpysPlanItem item) {
    openCmpysPlanItem(context, item);
  }
}
