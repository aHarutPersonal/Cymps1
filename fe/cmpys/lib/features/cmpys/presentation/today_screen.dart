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
import '../data/cmpys_seed.dart';
import '../state/cmpys_backend_sync.dart';
import '../state/cmpys_store.dart';

/// CMPYS Today tab — the "next best action" home screen.
///
/// Daily habits come from the AI-generated 12-week plan (current week's
/// daily-rhythm items via GET /plans/{id}/today, toggled per-day through
/// /daily-toggle). Until that plan exists, the screen shows an explicit plan
/// state instead of substituting demo tasks.
class CmpysTodayScreen extends ConsumerWidget {
  const CmpysTodayScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  int? _planDay(CurrentPlanState planState) {
    final createdAt = planState.plan?.createdAt?.toLocal();
    if (createdAt == null) return null;
    final start = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = today.difference(start).inDays + 1;
    return day < 1 ? 1 : day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeView = ref.watch(
      cmpysStoreProvider.select((s) => (idol: s.idol, user: s.user)),
    );
    final idol = storeView.idol;
    // Hydrate mentor + AI results from the backend (source of truth).
    ref.watch(cmpysBackendSyncProvider);

    // The plan and today's view are the only sources of task data. In
    // particular, empty/loading/failed plan states must never render the
    // prototype's seeded habits.
    final planState = ref.watch(currentPlanProvider);
    final planReady = planState.status == CurrentPlanStatus.ready;
    final todayAsync = ref.watch(todayViewProvider);
    final backendToday = todayAsync.valueOrNull;
    final backendItems = backendToday?.items ?? const <TodayTaskItem>[];
    final todayLoading =
        planReady && todayAsync.isLoading && backendToday == null;
    final todayFailed =
        planReady && todayAsync.hasError && backendToday == null;
    final planDay = _planDay(planState);

    final totalToday = backendToday?.totalToday ?? backendItems.length;
    final doneToday =
        backendToday?.completedToday ??
        backendItems.where((i) => i.completedToday).length;
    final pct = totalToday == 0 ? 0.0 : doneToday / totalToday * 100;
    final name = storeView.user.name.isEmpty ? 'friend' : storeView.user.name;

    final backendUndone = backendItems.where((i) => !i.completedToday).toList();
    final nextBackendItem = backendUndone.isEmpty ? null : backendUndone.first;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: EntranceScope(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pageGutter(MediaQuery.sizeOf(context).width),
              14,
              AppSpacing.pageGutter(MediaQuery.sizeOf(context).width),
              AppShell.bottomNavClearance(context),
            ),
            children: EntranceGroup.wrap([
              _topBar(context, idol, name, planDay),
              const SizedBox(height: 18),
              if (!planReady)
                _planStateCard(context, ref, idol, planState)
              else if (todayLoading)
                const CmpysSkeleton.block(height: 124)
              else if (todayFailed)
                _todayErrorCard(ref)
              else
                _heroCard(
                  pct,
                  doneToday,
                  totalToday,
                  backendToday?.streak ?? 0,
                ),
              if (planReady && backendToday != null) ...[
                const SizedBox(height: 16),
                if (nextBackendItem != null)
                  _backendNextActionCard(context, nextBackendItem)
                else if (backendItems.isNotEmpty)
                  _allDoneCard(),
                const SizedBox(height: 22),
                _sectionHeader(
                  context,
                  'Today’s habits',
                  onFullPlan: () => context.go(AppRoutes.plan),
                ),
                const SizedBox(height: 12),
                if (backendItems.isNotEmpty)
                  CmpysCardSurface(
                    pad: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        for (var i = 0; i < backendItems.length; i++)
                          _backendHabitTile(
                            context,
                            ref,
                            backendItems[i],
                            first: i == 0,
                          ),
                      ],
                    ),
                  )
                else
                  Text(
                    'No daily habits in your plan this week.',
                    style: AppTypography.bodyDim,
                  ),
              ],
              const SizedBox(height: 22),
              _compareNudge(context, storeView.user, idol, name),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _planStateCard(
    BuildContext context,
    WidgetRef ref,
    CmpysIdol idol,
    CurrentPlanState planState,
  ) {
    switch (planState.status) {
      case CurrentPlanStatus.loading:
        return const CmpysSkeleton.block(height: 124);
      case CurrentPlanStatus.generating:
        return CmpysCardSurface(
          onTap: () => context.go(AppRoutes.plan),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your plan with ${idol.short} is being written.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.ink,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${planState.jobProgress}% complete',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink3,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.hair2,
              ),
            ],
          ),
        );
      case CurrentPlanStatus.empty:
        return CmpysCardSurface(
          onTap: () => ref.read(currentPlanProvider.notifier).retry(),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsRegular.sparkle,
                size: 20,
                color: AppColors.ink3,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You don’t have a plan yet.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.ink,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
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
      case CurrentPlanStatus.failed:
        return CmpysCardSurface(
          onTap: () => ref.read(currentPlanProvider.notifier).retry(),
          child: Row(
            children: [
              const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: AppColors.ink3,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Couldn’t load your plan — tap to retry.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink2,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        );
      case CurrentPlanStatus.ready:
        return const SizedBox.shrink();
    }
  }

  Widget _todayErrorCard(WidgetRef ref) {
    return CmpysCardSurface(
      onTap: () => ref.invalidate(todayViewProvider),
      child: Row(
        children: [
          const Icon(Icons.refresh_rounded, size: 20, color: AppColors.ink3),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Couldn’t load today’s habits — tap to retry.',
              style: AppTypography.caption.copyWith(
                color: AppColors.ink2,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDaily(
    BuildContext context,
    WidgetRef ref,
    TodayTaskItem item,
  ) async {
    final wasDone = item.completedToday;
    try {
      await ref.read(planRepositoryProvider).toggleDailyTask(item.id);
      ref.invalidate(todayViewProvider);
      if (!wasDone && context.mounted) {
        showCmpysToast(
          context,
          'Nice. Kept your word.',
          icon: Icons.check_rounded,
          tone: AppColors.green,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showCmpysToast(
          context,
          'Couldn’t update — try again.',
          icon: Icons.error_outline_rounded,
          tone: AppColors.ink2,
        );
      }
    }
  }

  /// Next-best-action card for a plan-generated daily task, including the
  /// mentor's daily instructions when present.
  Widget _backendNextActionCard(BuildContext context, TodayTaskItem item) {
    return CmpysPressable(
      semanticLabel: 'Start ${item.title}',
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
            Text(
              'YOUR NEXT BEST ACTION',
              style: AppTypography.kicker.copyWith(
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              style: AppTypography.h3.copyWith(
                color: Colors.white,
                fontSize: 21,
                height: 1.2,
              ),
            ),
            if (item.dailyInstructions != null &&
                item.dailyInstructions!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.dailyInstructions!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Daily rhythm · ~${item.estimatedHours}h this week',
                    maxLines: 2,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBC24A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Start',
                        style: AppTypography.button.copyWith(
                          color: const Color(0xFF211F1A),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Color(0xFF211F1A),
                      ),
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
    BuildContext context,
    WidgetRef ref,
    TodayTaskItem item, {
    required bool first,
  }) {
    final done = item.completedToday;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          Semantics(
            checked: done,
            label: item.title,
            child: CmpysPressable(
              semanticLabel: done ? 'Mark as incomplete' : 'Mark as complete',
              onTap: () => _toggleDaily(context, ref, item),
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
          ),
          Expanded(
            child: CmpysPressable(
              onTap: () => openBackendPlanItemById(context, item.id),
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

  Widget _topBar(
    BuildContext context,
    CmpysIdol idol,
    String name,
    int? planDay,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CmpysKicker(
                planDay == null
                    ? 'With ${idol.short}'
                    : 'Day $planDay · with ${idol.short}',
              ),
              const SizedBox(height: 6),
              Text(
                '${_greeting()}, ${name.trim().split(RegExp(r'\s+')).first}.',
                style: AppTypography.display.copyWith(
                  fontSize: 30,
                  letterSpacing: -0.6,
                  height: 1.08,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _circleAction(
            icon: PhosphorIconsRegular.lightbulb,
            onTap: () => context.goToIdeas(),
          ),
        ),
      ],
    );
  }

  Widget _circleAction({required IconData icon, required VoidCallback onTap}) {
    return Tooltip(
      message: 'Explore ideas',
      child: CmpysPressable(
        semanticLabel: 'Explore ideas',
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
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
    final left = (total - doneToday).clamp(0, total);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.hair),
      ),
      child: Row(
        children: [
          CmpysRing(
            value: pct,
            size: 80,
            stroke: 7,
            color: AppColors.green2,
            track: AppColors.greenSoft,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$doneToday',
                    style: AppTypography.h2.copyWith(
                      color: AppColors.ink,
                      fontSize: 23,
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text: '/$total',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink2,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? 'No habits scheduled today.'
                      : pct >= 100
                      ? 'Today’s habits are complete'
                      : '$left ${left == 1 ? 'habit' : 'habits'} left today',
                  style: AppTypography.h4.copyWith(
                    color: AppColors.ink,
                    fontSize: 17,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? 'Use the roadmap to see what’s ahead.'
                      : pct >= 100
                      ? 'A little progress, every day.'
                      : 'Small things, done daily.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink2,
                    fontSize: 13.5,
                  ),
                ),
                if (streak > 0) ...[
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ochreSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsFill.flame,
                          size: 16,
                          color: AppColors.green2,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$streak-day streak',
                            maxLines: 2,
                            style: AppTypography.captionMedium.copyWith(
                              color: AppColors.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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

  Widget _allDoneCard() {
    return CmpysCardSurface(
      color: AppColors.greenSoft,
      border: false,
      pad: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.check_rounded, size: 30, color: AppColors.green),
          const SizedBox(height: 10),
          Text(
            'All daily habits complete.',
            style: AppTypography.h3.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            'Come back tomorrow — or get ahead in your plan.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyDim.copyWith(fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    VoidCallback? onFullPlan,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 6,
        children: [
          CmpysKicker(title),
          if (onFullPlan != null)
            TextButton(
              onPressed: onFullPlan,
              child: Text(
                'Full plan',
                style: AppTypography.captionMedium.copyWith(
                  color: AppColors.green2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _compareNudge(
    BuildContext context,
    CmpysUser user,
    CmpysIdol idol,
    String name,
  ) {
    final initial = name.isNotEmpty && name != 'friend'
        ? name[0].toUpperCase()
        : 'Y';
    return CmpysCardSurface(
      onTap: () => context.go(AppRoutes.vault),
      child: Row(
        children: [
          SizedBox(
            // 34px offset + 44px avatar — anything narrower clips the idol
            // avatar against the Stack's hard edge.
            width: 78,
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
                Text(
                  user.age > 0
                      ? 'You vs ${idol.short} at ${user.age}'
                      : 'You vs ${idol.short}',
                  style: AppTypography.bodyMedium.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'See where you stand today',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 19,
            color: AppColors.ink3,
          ),
        ],
      ),
    );
  }
}
