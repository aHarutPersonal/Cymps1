import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/presentation/backend_plan_widgets.dart';
import '../../plan/state/current_plan_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import '../state/habit_toggle.dart';
import '../state/plan_data.dart';
import '../state/plan_providers.dart';
import '../state/today_data.dart';
import 'week_unlock_trigger.dart';

typedef _PlanStoreView = ({
  CmpysIdol idol,
  String? blueprintMd,
  List<CmpysCustomTask> custom,
  Map<String, bool> tasks,
});

/// CMPYS Plan tab (`PlanTab` in `v3/plan.jsx`): the "N weeks with X" header
/// with the overall ring, the hours and week tags, and a Roadmap / Daily
/// habits split.
///
/// Data: [currentPlanProvider] (the plan, its weeks and missions, and the
/// generation progress); each mission's tutorials, through the cards in
/// `backend_plan_widgets.dart` ([todayMissionDetailProvider] for the mission
/// to work on, exactly as Today reads it, and [planMissionPeekProvider], a
/// read that never starts generation, for the rest);
/// [todayViewProvider] (the habits) with [habitDailyStatusProvider] (each
/// habit's own week; [todayStreakProvider] stands in if that fails); and the
/// store's blueprint markdown. While a plan is being written the tab
/// shows its progress; with none, it says so.
class CmpysPlanScreen extends ConsumerStatefulWidget {
  const CmpysPlanScreen({super.key, this.clock});

  /// The local time to render for; defaults to [DateTime.now]. For tests.
  final DateTime Function()? clock;

  @override
  ConsumerState<CmpysPlanScreen> createState() => _CmpysPlanScreenState();
}

class _CmpysPlanScreenState extends ConsumerState<CmpysPlanScreen>
    with HabitToggleMixin<CmpysPlanScreen> {
  int _view = 0; // 0 = Roadmap, 1 = Daily habits

  bool _onScreen = true;

  /// The roadmap's "This week" section, which "Start week n" scrolls to.
  final GlobalKey _thisWeekKey = GlobalKey();

  /// A "Week unlocked" check is waiting for the next frame.
  bool _weekUnlockQueued = false;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Coming back to this tab: tutorials that were still being written when
    // it was last on screen may be ready now. (Today polls its own mission
    // while it is visible; this tab re-reads once on return.)
    final onScreen = TickerMode.of(context);
    if (onScreen && !_onScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshPreparing();
      });
    }
    _onScreen = onScreen;
  }

  void _refreshPreparing() {
    final plan = ref.read(currentPlanProvider).plan;
    if (plan == null) return;
    final week = plan.focusWeek;
    final missions = plan.missionsForWeek(week);
    final statuses = planMissionStatuses(plan, week);
    for (var i = 0; i < missions.length; i++) {
      final provider = planMissionDetailProvider(
        missions[i].id,
        peek: statuses[i] != PlanMissionStatus.current,
        peekSupported: planSupportsPeek(plan),
      );
      if (provider == null) continue;
      final detail = ref.read(provider).valueOrNull;
      if (detail != null &&
          tutorialRowStates(
            detail,
          ).any((s) => s == TutorialRowState.preparing)) {
        ref.invalidate(provider);
      }
    }
  }

  // The week's mission reads are autoDispose and watched only by the roadmap,
  // so switching to Daily habits would drop them and the next switch back
  // would read every mission again. A manual listener per read keeps each
  // alive while this tab is mounted.
  final Map<String, ProviderSubscription<Object?>> _held = {};
  String _heldFor = '';

  void _holdWeekReads(BackendPlan? plan) {
    final wanted = <String, AutoDisposeFutureProvider<PlanItemDetailed>>{};
    if (plan != null && !plan.allMissionWorkComplete) {
      final week = plan.focusWeek;
      final missions = plan.missionsForWeek(week);
      final statuses = planMissionStatuses(plan, week);
      for (var i = 0; i < missions.length; i++) {
        final peek = statuses[i] != PlanMissionStatus.current;
        final provider = planMissionDetailProvider(
          missions[i].id,
          peek: peek,
          peekSupported: planSupportsPeek(plan),
        );
        if (provider == null) continue;
        wanted['${peek ? 'peek' : 'read'}:${missions[i].id}'] = provider;
      }
    }
    final signature = (wanted.keys.toList()..sort()).join(',');
    if (signature == _heldFor) return;
    _heldFor = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final key in _held.keys.toList()) {
        if (!wanted.containsKey(key)) _held.remove(key)?.close();
      }
      for (final entry in wanted.entries) {
        _held.putIfAbsent(
          entry.key,
          () => ref.listenManual<AsyncValue<PlanItemDetailed>>(
            entry.value,
            (previous, next) {},
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    for (final subscription in _held.values) {
      subscription.close();
    }
    _held.clear();
    super.dispose();
  }

  // ── build ──

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
    watchFreshHabits();
    final planState = ref.watch(currentPlanProvider);
    final plan = planState.status == CurrentPlanStatus.ready
        ? planState.plan
        : null;
    _holdWeekReads(plan);
    _queueWeekUnlock(plan);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: AppShell.bottomNavClearance(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, st, plan),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: V3Rise(
                delay: const Duration(milliseconds: 180),
                child: V3Seg<int>(
                  items: const [
                    V3SegItem(0, 'Roadmap'),
                    V3SegItem(1, 'Daily habits'),
                  ],
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),
            ),
            if (_view == 0)
              ..._roadmap(st, planState)
            else
              ..._habits(st, planState),
          ],
        ),
      ),
    );
  }

  // ── week unlocked ──

  /// After this frame, shows "Week n unlocked" once if the plan has moved
  /// to a new week this account hasn't seen ([maybeShowWeekUnlock]).
  void _queueWeekUnlock(BackendPlan? plan) {
    if (plan == null || _weekUnlockQueued) return;
    final week = weekUnlockDueWeek(plan);
    if (week == null ||
        !ref
            .read(cmpysStoreProvider.notifier)
            .shouldShowWeekUnlock(plan.id, week)) {
      return;
    }
    _weekUnlockQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _weekUnlockQueued = false;
      if (!mounted) return;
      final result = await maybeShowWeekUnlock(context, ref, plan);
      if (result == WeekUnlockResult.start && mounted) _showThisWeek();
    });
  }

  /// "Start week n": stay on Plan, on the roadmap, scrolled to the week.
  void _showThisWeek() {
    if (_view != 0) setState(() => _view = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _thisWeekKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: MotionConfig.enabled(context)
            ? const Duration(milliseconds: 600)
            : Duration.zero,
        curve: AppMotion.out,
      );
    });
  }

  // ── header ──

  Widget _header(BuildContext context, _PlanStoreView st, BackendPlan? plan) {
    final top = math.max(MediaQuery.paddingOf(context).top + 8, 20.0);
    final weeks = plan?.durationWeeks ?? 12;
    final mentor = st.idol.id == cmpysPlaceholderIdol.id
        ? ''
        : st.idol.short.trim();
    final progress = plan == null ? 0.0 : planOverallProgress(plan);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V3Rise(child: Text('YOUR PLAN', style: AppTypography.kick)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: V3Rise(
                  delay: const Duration(milliseconds: 50),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$weeks weeks'),
                        if (mentor.isNotEmpty) ...[
                          const TextSpan(text: '\n'),
                          TextSpan(
                            text: 'with $mentor',
                            style: AppTypography.displayItalic(42),
                          ),
                        ],
                      ],
                    ),
                    style: AppTypography.display(
                      42,
                    ).copyWith(color: AppColors.ink),
                  ),
                ),
              ),
              if (plan != null)
                V3Rise(
                  delay: const Duration(milliseconds: 100),
                  child: V3Ring(
                    value: progress,
                    size: 64,
                    strokeWidth: 5,
                    child: V3CountUp(
                      to: (progress * 100).round(),
                      format: (v) => '${v.round()}%',
                      style: AppTypography.sans(15, FontWeight.w700)
                          .merge(AppTypography.tnum)
                          .copyWith(color: AppColors.ink),
                    ),
                  ),
                ),
            ],
          ),
          if (plan != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: V3Rise(
                delay: const Duration(milliseconds: 140),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _fitted(
                      V3Tag(
                        icon: V3Icons.clock,
                        child: Text(
                          '${formatHalfHours(planWeeklyMinutes(plan))} h / week',
                        ),
                      ),
                    ),
                    _fitted(
                      V3Tag(
                        icon: V3Icons.flag,
                        child: Text(
                          'Week ${plan.focusWeek} of ${plan.durationWeeks}',
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

  /// Keeps a one-line pill inside narrow or large-text layouts.
  Widget _fitted(Widget child) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );

  // ── roadmap ──

  List<Widget> _roadmap(_PlanStoreView st, CurrentPlanState planState) {
    final blueprint = _blueprint(st);
    switch (planState.status) {
      case CurrentPlanStatus.ready:
        final plan = planState.plan!;
        return [
          V3Rise(
            delay: const Duration(milliseconds: 220),
            child: PlanWeekStrip(plan: plan, onTapWeek: _tapWeek(plan)),
          ),
          if (blueprint != null) blueprint,
          V3Rise(
            key: _thisWeekKey,
            delay: const Duration(milliseconds: 300),
            child: V3Section(
              title: 'This week',
              child: plan.allMissionWorkComplete
                  ? PlanCompleteCard(plan: plan)
                  : PlanThisWeek(plan: plan),
            ),
          ),
          V3Rise(
            delay: const Duration(milliseconds: 340),
            child: V3Section(
              title: 'All weeks',
              child: PlanAllWeeks(plan: plan),
            ),
          ),
        ];
      case CurrentPlanStatus.generating:
        return [
          if (blueprint != null) blueprint,
          _statusPad(
            PlanGeneratingCard(
              progress: planState.jobProgress,
              line: planState.jobLine,
            ),
          ),
        ];
      case CurrentPlanStatus.loading:
        return [
          if (blueprint != null) blueprint,
          _statusPad(_skeletonBlocks()),
        ];
      case CurrentPlanStatus.failed:
        return [
          if (blueprint != null) blueprint,
          _statusPad(
            _noticeCard(
              icon: V3Icons.refresh,
              onTap: () => ref.read(currentPlanProvider.notifier).refresh(),
              title: 'Couldn’t load your 12-week plan — tap to retry.',
            ),
          ),
        ];
      case CurrentPlanStatus.empty:
        // No generated plan for the active idol yet. Never fall back to the
        // seeded demo plan: it belongs to a different mentor.
        return [
          if (blueprint != null) blueprint,
          _statusPad(_pendingCard(st)),
          if (st.custom.isNotEmpty) _customTasks(st),
        ];
    }
  }

  Widget _statusPad(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
    child: V3Rise(delay: const Duration(milliseconds: 220), child: child),
  );

  Widget _skeletonBlocks() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        const V3Skel(height: 120, radius: AppRadii.r),
      ],
    ],
  );

  /// A tappable hairline card with an icon and a title (and optional note).
  Widget _noticeCard({
    required V3Icons icon,
    required VoidCallback onTap,
    required String title,
    String? note,
  }) {
    return V3Pressable(
      onTap: onTap,
      minTapTarget: 0,
      focusRadius: AppRadii.brR,
      child: Container(
        constraints: const BoxConstraints(minHeight: kV3TapTarget),
        padding: const EdgeInsets.all(16),
        decoration: v3Card(),
        child: Row(
          children: [
            V3Icon(icon, size: 18, color: AppColors.ink3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.sans(14, FontWeight.w500).copyWith(
                      color: note == null ? AppColors.ink2 : AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: AppTypography.sans(
                        12.5,
                      ).copyWith(color: AppColors.ink3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty state: the plan for the active idol hasn't been generated (or
  /// hasn't landed) yet. Tapping re-checks and re-enqueues when possible.
  Widget _pendingCard(_PlanStoreView st) => _noticeCard(
    icon: V3Icons.sparkle,
    onTap: () => ref.read(currentPlanProvider.notifier).retry(),
    title: 'Your plan with ${st.idol.short} isn’t ready yet.',
    note: 'Tap to check again.',
  );

  /// The blueprint card, or null without a blueprint. It opens in place; the
  /// full markdown stays one tap away.
  Widget? _blueprint(_PlanStoreView st) {
    final markdown = st.blueprintMd;
    final parsed = parseBlueprint(markdown);
    if (markdown == null || parsed == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: V3Rise(
        delay: const Duration(milliseconds: 260),
        child: PlanBlueprintCard(
          blueprint: parsed,
          onReadFull: () => Navigator.of(context).push(
            CmpysPageRoute<void>(
              builder: (_) => CmpysMarkdownScreen(
                kicker: 'From ${st.idol.short}',
                title: 'Your blueprint',
                markdown: markdown,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Week chips: locked weeks toast, the current one opens its mission and a
  /// finished one opens its first mission for review.
  void Function(int, PlanWeekState) _tapWeek(BackendPlan plan) {
    return (week, state) {
      switch (state) {
        case PlanWeekState.locked:
          showV3Toast(
            context,
            'Week $week unlocks after week ${week - 1}',
            icon: V3Icons.lock,
            tone: V3ToastTone.warn,
          );
        case PlanWeekState.current:
          final mission = plan.focusedItemForWeek(week);
          if (mission != null) _openItem(mission.id);
        case PlanWeekState.done:
          final missions = plan.missionsForWeek(week);
          if (missions.isNotEmpty) _openItem(missions.first.id);
      }
    };
  }

  Future<void> _openItem(String itemId) async {
    await openBackendPlanItemById(context, itemId);
    if (!mounted) return;
    ref.invalidate(todayViewProvider);
    ref.invalidate(todayStreakProvider);
    ref.invalidate(habitDailyStatusProvider(itemId));
    ref.invalidate(todayMissionDetailProvider(itemId));
    ref.invalidate(planMissionPeekProvider(itemId));
  }

  /// Habits suggested in chat, kept on this device.
  Widget _customTasks(_PlanStoreView st) {
    return V3Section(
      title: 'Added from your chats with ${st.idol.short}',
      child: Container(
        decoration: v3Card(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < st.custom.length; i++)
              _customRow(st, st.custom[i], first: i == 0),
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
      padding: const EdgeInsets.fromLTRB(9, 4, 16, 4),
      child: Row(
        children: [
          V3CheckDot(
            done: done,
            semanticLabel: c.title,
            onPressed: () =>
                ref.read(cmpysStoreProvider.notifier).toggleTask(c.id),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  style: AppTypography.sans(15, FontWeight.w500).copyWith(
                    color: done ? AppColors.ink3 : AppColors.ink,
                    decoration: done
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: AppColors.hair2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Suggested in chat',
                  style: AppTypography.sans(12).copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
          const V3Icon(V3Icons.chat, size: 16, color: AppColors.hair2),
        ],
      ),
    );
  }

  // ── daily habits ──

  List<Widget> _habits(_PlanStoreView st, CurrentPlanState planState) {
    switch (planState.status) {
      case CurrentPlanStatus.ready:
        final todayState = ref.watch(todayViewProvider);
        final today = todayState.valueOrNull;
        if (today == null && todayState.hasError) {
          return [
            _statusPad(
              Container(
                decoration: v3Card(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Couldn’t load your daily habits.',
                      style: AppTypography.sans(
                        14,
                        FontWeight.w500,
                      ).copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: 12),
                    V3Button(
                      kind: V3ButtonKind.dark,
                      size: V3Size.md,
                      onPressed: () => ref.invalidate(todayViewProvider),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ];
        }
        if (today == null) {
          return [
            _statusPad(
              Container(
                decoration: v3Card(),
                padding: const EdgeInsets.all(16),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    V3Skel(height: 16),
                    SizedBox(height: 14),
                    V3Skel(height: 16, width: 220),
                    SizedBox(height: 14),
                    V3Skel(height: 16, width: 180),
                  ],
                ),
              ),
            ),
          ];
        }
        if (today.items.isEmpty) {
          return [
            _statusPad(
              Text(
                'No daily rhythm tasks this week — check the roadmap.',
                style: AppTypography.sans(
                  14,
                ).copyWith(color: AppColors.ink2, height: 1.5),
              ),
            ),
          ];
        }
        return [_habitsList(today)];
      case CurrentPlanStatus.generating:
        return [
          _statusPad(
            PlanGeneratingCard(
              progress: planState.jobProgress,
              line: planState.jobLine,
            ),
          ),
        ];
      case CurrentPlanStatus.loading:
        return [_statusPad(_skeletonBlocks())];
      case CurrentPlanStatus.failed:
        return [
          _statusPad(
            _noticeCard(
              icon: V3Icons.refresh,
              onTap: () => ref.read(currentPlanProvider.notifier).refresh(),
              title: 'Couldn’t load your daily rhythm — tap to retry.',
            ),
          ),
        ];
      case CurrentPlanStatus.empty:
        return [_statusPad(_pendingCard(st))];
    }
  }

  Widget _habitsList(TodayView view) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V3Rise(
            child: Text(
              'Habits repeat daily for this week. Tap one to open it, or check '
              'it off right here. It counts for today only.',
              style: AppTypography.sans(
                13.5,
              ).copyWith(color: AppColors.ink2, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < view.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            V3Rise(
              delay: Duration(milliseconds: 60 + i * 60),
              child: _habitCard(view, view.items[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _habitCard(TodayView view, TodayTaskItem item) {
    final on = isHabitDone(item);
    final week = watchHabitWeek(ref, item.id, _now);
    final motion = MotionConfig.enabled(context);
    final instructions = item.dailyInstructions?.trim() ?? '';
    return V3Pressable(
      key: Key('plan-habit-${item.id}'),
      onTap: () => _openItem(item.id),
      minTapTarget: 0,
      focusRadius: AppRadii.brR,
      child: AnimatedContainer(
        duration: motion ? const Duration(milliseconds: 300) : Duration.zero,
        padding: const EdgeInsets.fromLTRB(9, 9, 16, 16),
        decoration: v3Card(borderColor: on ? AppColors.sage : AppColors.hair),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V3CheckDot(
                  key: ValueKey('toggle-daily-${item.id}'),
                  done: on,
                  onPressed: () => toggleHabit(view, item, toastOnUndo: true),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: motion
                              ? const Duration(milliseconds: 300)
                              : Duration.zero,
                          style: AppTypography.sans(15.5, FontWeight.w600)
                              .copyWith(
                                color: on ? AppColors.ink3 : AppColors.ink,
                                decoration: on
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                decorationColor: AppColors.hair2,
                              ),
                          child: Text(item.title),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          instructions.isNotEmpty
                              ? instructions
                              : '${habitSessionMinutes(item)} min',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            13,
                          ).copyWith(color: AppColors.ink2, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 11, left: 8),
                  child: V3Icon(V3Icons.right, size: 16, color: AppColors.ink3),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14, left: 7),
              child: _weekGrid(item.id, week, todayDone: on),
            ),
          ],
        ),
      ),
    );
  }

  static const _letters = 'MTWTFSS';

  /// Monday to Sunday: sage for a day in the streak run, today from the
  /// habit itself. /streak keeps no per-habit history, so earlier days show
  /// the days with any habit done.
  Widget _weekGrid(String itemId, List<bool?> week, {required bool todayDone}) {
    return Row(
      children: [
        for (var k = 0; k < 7; k++) ...[
          if (k > 0) const SizedBox(width: 4),
          Expanded(child: _gridDay(itemId, k, week[k], todayDone)),
        ],
      ],
    );
  }

  Widget _gridDay(String itemId, int k, bool? past, bool todayDone) {
    final today = past == null;
    final done = today ? todayDone : past;
    final Widget cell = today && !done
        ? const PlanDashedCell(height: 26)
        : AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: 26,
            decoration: BoxDecoration(
              color: done ? AppColors.sage : AppColors.paper2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: done
                ? const Center(
                    child: V3Icon(
                      V3Icons.check,
                      size: 12,
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : null,
          );
    return Column(
      children: [
        V3Pop(key: Key('plan-habit-$itemId-day-$k'), child: cell),
        const SizedBox(height: 4),
        Text(
          today ? 'Today' : _letters[k],
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: AppTypography.sans(
            10,
            FontWeight.w600,
          ).copyWith(color: today ? AppColors.ink : AppColors.ink3),
        ),
      ],
    );
  }
}
