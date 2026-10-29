import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/presentation/book_narration_checkpoint.dart';
import '../../plan/presentation/book_reader_screen.dart';
import '../../plan/presentation/material_reader_screen.dart';
import '../../plan/presentation/material_web_screen.dart';
import '../../plan/presentation/open_lesson_reader.dart';
import '../../plan/presentation/plan_item_detail_screen.dart';
import '../../plan/presentation/reading_library_screen.dart';
import '../../plan/presentation/book_narration_dock.dart';
import '../../plan/state/book_narration_remote_controller.dart';
import '../../plan/state/current_plan_provider.dart';
import '../../session/models/content_resource.dart';
import '../data/cmpys_ideas_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_backend_sync.dart';
import '../state/cmpys_store.dart';
import '../state/habit_toggle.dart';
import '../state/reader_settings.dart';
import '../state/today_data.dart';
import 'onboarding/mentor_image.dart';
import 'week_unlock_trigger.dart';

/// The design's reflection prompt (`v3/today.jsx`). The plan has no per-day
/// prompt, so this is always the one shown.
const _reflectionPrompt =
    'Which number in today’s reading did you not trust, and why?';

/// Idea-card grounds from the design's `IDEAS[].bg` (oklch → sRGB).
const _ideaGrounds = <Color>[
  Color(0xFF22203B), // oklch(0.26 0.05 285)
  Color(0xFF502514), // oklch(0.32 0.07 42)
  Color(0xFF12301E), // oklch(0.28 0.05 155)
  Color(0xFF261D16), // oklch(0.24 0.02 60)
];

/// NextUp glows: oklch(0.55 0.16 42 / .55) and oklch(0.5 0.15 285 / .5).
const _emberGlow = Color(0x8CBA480D);
const _irisGlow = Color(0x805D52B4);

int _stableIndex(String key, int length) =>
    key.codeUnits.fold<int>(0, (a, b) => a + b) % length;

/// A shelf cover's ground: by resource id when the material is a CMPYS
/// resource (the library shows the same book in the same colour), else by
/// position.
Color _shelfGround(PlanMaterialDetail material, int index) {
  final id = material.contentResourceId?.trim();
  return id != null && id.isNotEmpty
      ? v3CoverGround(id)
      : kV3CoverGrounds[index % kV3CoverGrounds.length];
}

enum _ReflectionStatus { idle, typing, saving, saved }

/// Key on the transform that fills today's streak cell (its y scale is
/// habits done / habits total), for tests.
const todayStreakFillKey = ValueKey<String>('today-streak-fill');

/// Key on the liquid crest riding the top of a partly filled streak cell.
const todayStreakCrestKey = ValueKey<String>('today-streak-crest');

/// CMPYS Today tab (`TodayTab` in `v3/today.jsx`): the date and greeting, the
/// next tutorial of the current mission, today's habits, the streak and
/// comparison cards, a reflection kept on this device, an idea from the feed
/// and the books for this week.
///
/// Data: [currentPlanProvider] and [todayViewProvider] (plan, habits and
/// their per-day toggles), [todayMissionDetailProvider] (the current
/// mission's tutorials and materials), [todayStreakProvider] (/streak),
/// [cmpysIdeasProvider] (the idea feed) and [todayContinueReadingProvider].
/// Until a plan exists the screen shows the plan state instead of habits.
class CmpysTodayScreen extends ConsumerStatefulWidget {
  const CmpysTodayScreen({super.key, this.clock});

  /// The local time to render for; defaults to [DateTime.now]. For tests.
  final DateTime Function()? clock;

  static const Key reflectionFieldKey = Key('today-reflection-field');

  @override
  ConsumerState<CmpysTodayScreen> createState() => _CmpysTodayScreenState();
}

class _CmpysTodayScreenState extends ConsumerState<CmpysTodayScreen>
    with WidgetsBindingObserver, HabitToggleMixin<CmpysTodayScreen> {
  String? _openHabit;

  // While the current mission's tutorials are being written, NextUp
  // re-reads them every 15 s, at most 40 times per visible stretch. The poll
  // runs only while Today is on screen: its branch is the selected tab
  // (`TickerMode`), no page is pushed over it (`ModalRoute.isCurrent`) and
  // the app is in the foreground.
  Timer? _preparingPoll;
  String? _pollingFor;
  String? _preparingFor;
  int _preparingPolls = 0;
  bool _onScreen = true;
  bool _appForeground = true;
  static const _preparingPollEvery = Duration(seconds: 15);
  static const _preparingPollLimit = 40;

  bool get _pollAllowed => _onScreen && _appForeground;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appForeground = lifecycle == null || _isForeground(lifecycle);
    // Date symbols for the device locale, for the kicker. Local data loads
    // at once; until then the kicker falls back to English.
    initializeDateFormatting().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onScreen =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    if (onScreen != _onScreen) {
      _onScreen = onScreen;
      _visibilityChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = _isForeground(state);
    if (foreground != _appForeground) {
      _appForeground = foreground;
      _visibilityChanged();
    }
  }

  static bool _isForeground(AppLifecycleState state) =>
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preparingPoll?.cancel();
    super.dispose();
  }

  // ── actions ──

  void _reload() {
    final plan = ref.read(currentPlanProvider);
    if (plan.status == CurrentPlanStatus.failed ||
        plan.status == CurrentPlanStatus.empty) {
      ref.read(currentPlanProvider.notifier).retry();
    }
    ref.invalidate(todayViewProvider);
    ref.invalidate(todayStreakProvider);
    ref.invalidate(todayMissionDetailProvider);
    ref.invalidate(todayContinueReadingProvider);
    _preparingPolls = 0;
  }

  Future<void> _openPlanItem(String itemId) async {
    await Navigator.of(context).push(
      CmpysPageRoute<void>(
        builder: (_) => PlanItemDetailScreen(
          itemId: itemId,
          shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
        ),
      ),
    );
    if (!mounted) return;
    ref.invalidate(todayViewProvider);
    ref.invalidate(todayMissionDetailProvider);
  }

  Future<void> _openTutorial(PlanItemDetailed detail) => openLessonReader(
    context,
    ref,
    detail,
    detail.activeStepIndex,
    shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
  );

  /// A reveal is running (a second tap waits for it to finish).
  bool _revealing = false;

  bool _weekUnlockQueued = false;

  /// After this frame, shows "Week n unlocked" once if the loaded plan has
  /// moved to a new week this account hasn't seen (the rule is shared with
  /// the Plan tab: [maybeShowWeekUnlock]). "Start week n" goes to Plan.
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
      if (result == WeekUnlockResult.start && mounted) {
        context.go(AppRoutes.plan);
      }
    });
  }

  /// Continue: an ink circle in the reader's background colour (the user's
  /// reading theme) grows from the play button [at]; the tutorial opens
  /// under it once it covers the screen. Reduced motion: a colour fade.
  void _continueTutorial(PlanItemDetailed detail, Offset at) {
    if (_revealing) return;
    _revealing = true;
    final color = ref.read(readerSettingsProvider).theme.bg;
    unawaited(
      showInkReveal(
        context,
        at: at,
        color: color,
        onCovered: () {
          if (mounted) unawaited(_openTutorial(detail));
        },
      ).whenComplete(() => _revealing = false),
    );
  }

  Future<void> _openBook(ContentResource book, {bool listen = false}) async {
    // Books open inside Today's shell branch, so the reader stays mounted,
    // and keeps narrating, when its App menu switches tabs; the player says
    // "Today" and a cold-start resume restores into Today.
    await Navigator.of(context).push(
      CmpysPageRoute<void>(
        builder: (_) => BookReaderScreen(
          resourceId: book.id,
          fallbackTitle: book.title,
          fallbackSourceUrl: book.sourceUrl,
          shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
          startNarrationOnOpen: listen,
        ),
      ),
    );
    if (mounted) ref.invalidate(todayContinueReadingProvider);
  }

  void _listen(ContentResource book) {
    // As the library's Listen: the book being narrated toggles in place, any
    // other book opens and takes over narration.
    final remote = ref.read(bookNarrationRemoteControllerProvider);
    if (remote.narrates(book.id)) {
      unawaited(remote.toggle());
      return;
    }
    unawaited(_openBook(book, listen: true));
  }

  Future<void> _openLibrary() async {
    await Navigator.of(context).push(
      CmpysPageRoute<void>(
        builder: (_) => const ReadingLibraryScreen(
          shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
        ),
      ),
    );
    if (mounted) ref.invalidate(todayContinueReadingProvider);
  }

  void _openMaterial(PlanMaterialDetail material, String missionId) {
    final access = accessTypeForMaterial(material);
    final resourceId = material.contentResourceId?.trim();
    if (access == AccessType.guide &&
        material.type == 'book' &&
        resourceId != null &&
        resourceId.isNotEmpty) {
      Navigator.of(context).push(
        CmpysPageRoute<void>(
          builder: (_) => BookReaderScreen(
            resourceId: resourceId,
            fallbackTitle: material.title,
            fallbackSourceUrl: material.directUrl,
            shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
          ),
        ),
      );
      return;
    }
    if (access == AccessType.guide &&
        material.type != 'book' &&
        material.hasInlineContent) {
      Navigator.of(context, rootNavigator: true).push(
        CmpysPageRoute<void>(
          builder: (_) => MaterialReaderScreen(material: material),
        ),
      );
      return;
    }
    final url = material.directUrl;
    if (access == AccessType.web && url != null) {
      Navigator.of(context, rootNavigator: true).push(
        CmpysPageRoute<void>(
          builder: (_) => MaterialWebScreen(
            title: material.title,
            url: url,
            access: AccessType.web,
          ),
        ),
      );
      return;
    }
    // A guide still being prepared, or nothing readable: the mission screen
    // resolves availability and explains it.
    unawaited(_openPlanItem(missionId));
  }

  /// Build reports which mission is "Preparing" (or null); the timer itself
  /// is started after the frame, never during build.
  void _notePreparing(String? itemId) {
    if (itemId == _preparingFor) return;
    _preparingFor = itemId;
    _preparingPolls = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPreparingPoll();
    });
  }

  /// Today came back on screen (tab, route or app) or left it. Coming back
  /// re-reads a preparing mission once and restarts the 40-read budget.
  void _visibilityChanged() {
    if (!_pollAllowed) {
      _stopPreparingPoll();
      return;
    }
    _preparingPolls = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pollAllowed) return;
      final itemId = _preparingFor;
      if (itemId != null) ref.invalidate(todayMissionDetailProvider(itemId));
      _syncPreparingPoll();
    });
  }

  void _stopPreparingPoll() {
    _preparingPoll?.cancel();
    _preparingPoll = null;
    _pollingFor = null;
  }

  void _syncPreparingPoll() {
    final itemId = _preparingFor;
    if (itemId == null || !_pollAllowed) {
      _stopPreparingPoll();
      return;
    }
    if (_pollingFor == itemId && (_preparingPoll?.isActive ?? false)) return;
    _stopPreparingPoll();
    _pollingFor = itemId;
    _preparingPoll = Timer.periodic(_preparingPollEvery, (timer) {
      if (!mounted ||
          !_pollAllowed ||
          _preparingFor != itemId ||
          _preparingPolls >= _preparingPollLimit) {
        timer.cancel();
        return;
      }
      _preparingPolls++;
      ref.invalidate(todayMissionDetailProvider(itemId));
    });
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final dateKey = reflectionDateKey(now);
    final store = ref.watch(
      cmpysStoreProvider.select(
        (s) => (
          user: s.user,
          idol: s.idol,
          scores: s.liveComparisonScores,
          reflection: s.reflections[dateKey] ?? '',
        ),
      ),
    );
    // Hydrate mentor + AI results from the backend (source of truth).
    ref.watch(cmpysBackendSyncProvider);

    watchFreshHabits();

    final planState = ref.watch(currentPlanProvider);
    final plan = planState.plan;
    final planReady =
        planState.status == CurrentPlanStatus.ready && plan != null;
    _queueWeekUnlock(planReady ? plan : null);
    final todayAsync = ref.watch(todayViewProvider);
    final todayView = todayAsync.valueOrNull;
    final todayFailed = planReady && todayAsync.hasError && todayView == null;

    final mission = planReady ? plan.focusedItemForWeek(plan.focusWeek) : null;
    final detailAsync = mission == null
        ? null
        : ref.watch(todayMissionDetailProvider(mission.id));
    final detail = detailAsync?.valueOrNull;

    final idol = store.idol;
    final name = _firstName(store.user.name);
    final width = MediaQuery.sizeOf(context).width;

    final nextUp = _nextUpSlot(
      planState: planState,
      idol: idol,
      todayFailed: todayFailed,
      mission: mission,
      detailAsync: detailAsync,
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      // A tab branch owns its keyboard inset (the shell's Scaffold does not
      // resize), so the reflection field stays above the keyboard.
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: AppShell.bottomNavClearance(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, now, idol),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _greeting(now, name, planReady ? plan : null, idol),
            ),
            if (nextUp != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: V3Rise(
                  delay: const Duration(milliseconds: 140),
                  child: nextUp,
                ),
              ),
            if (planReady && !todayFailed)
              V3Rise(
                delay: const Duration(milliseconds: 200),
                child: V3Section(
                  title: 'Today’s habits',
                  child: _habitsCard(todayView),
                ),
              ),
            if (planReady && todayView != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: V3Rise(
                  delay: const Duration(milliseconds: 260),
                  child: _streakAndCompare(
                    context,
                    now: now,
                    view: todayView,
                    user: store.user,
                    idol: idol,
                    scores: store.scores,
                    wide: width >= 340,
                  ),
                ),
              ),
            V3Rise(
              delay: const Duration(milliseconds: 320),
              child: V3Section(
                title: 'Reflection',
                child: _ReflectionCard(
                  key: ValueKey<String>(dateKey),
                  prompt: _reflectionPrompt,
                  saved: store.reflection,
                  onSave: (text) => ref
                      .read(cmpysStoreProvider.notifier)
                      .setReflection(dateKey, text),
                ),
              ),
            ),
            _ideaCard(context),
            _bookShelf(context, mission: mission, detail: detail),
          ],
        ),
      ),
    );
  }

  String _firstName(String full) {
    final first = full.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'friend' : first;
  }

  // ── header ──

  Widget _header(BuildContext context, DateTime now, CmpysIdol idol) {
    final top = math.max(MediaQuery.paddingOf(context).top + 8, 20.0);
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              todayKicker(now, locale: locale),
              style: AppTypography.kick,
            ),
          ),
          const SizedBox(width: 4),
          V3IconButton(
            icon: V3Icons.bulb,
            label: 'Idea reels',
            // The feed exposes no seen state, so the dot always shows.
            badge: true,
            onPressed: () => context.goToIdeas(),
          ),
          V3Pressable(
            semanticLabel: 'Chat with mentor',
            onTap: () => context.go(AppRoutes.chat),
            child: V3Avatar(
              image: cmpysIdolImage(idol),
              initials: idol.initials,
              tint: idol.tint,
              size: 40,
              gray: true,
              ring: AppColors.ember,
            ),
          ),
        ],
      ),
    );
  }

  Widget _greeting(
    DateTime now,
    String name,
    BackendPlan? plan,
    CmpysIdol idol,
  ) {
    final day = plan == null ? null : planDayOf(plan, now);
    final mentor = idol.id == cmpysPlaceholderIdol.id ? '' : idol.short.trim();
    final week = plan?.focusWeek;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `BlurWords`: the greeting, then the name in italics 160 ms later.
        V3BlurWords(
          text: greetingForHour(now.hour),
          style: AppTypography.display(44).copyWith(color: AppColors.ink),
        ),
        V3BlurWords(
          text: '$name.',
          delay: const Duration(milliseconds: 160),
          style: AppTypography.displayItalic(44).copyWith(color: AppColors.ink),
        ),
        if (day != null || week != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: V3Rise(
              delay: const Duration(milliseconds: 80),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (day != null)
                    _fitted(
                      V3Tag(
                        icon: V3Icons.calendar,
                        child: Text('Day ${day.day} of ${day.total}'),
                      ),
                    ),
                  if (week != null)
                    _fitted(
                      V3Tag(
                        icon: V3Icons.plan,
                        child: Text(
                          mentor.isEmpty
                              ? 'Week $week'
                              : 'Week $week · $mentor',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Keeps a one-line pill inside narrow or large-text layouts.
  Widget _fitted(Widget child) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );

  // ── NextUp slot ──

  Widget? _nextUpSlot({
    required CurrentPlanState planState,
    required CmpysIdol idol,
    required bool todayFailed,
    required BackendPlanItem? mission,
    required AsyncValue<PlanItemDetailed>? detailAsync,
  }) {
    String? preparing;
    Widget? slot;
    switch (planState.status) {
      case CurrentPlanStatus.loading:
        slot = const _NightCard(child: _NightSkeleton());
      case CurrentPlanStatus.generating:
        slot = _PlanWritingCard(
          mentor: idol.short,
          progress: planState.jobProgress,
          onTap: () => context.go(AppRoutes.plan),
        );
      case CurrentPlanStatus.empty:
        slot = _NoPlanCard(
          onTap: () => ref.read(currentPlanProvider.notifier).retry(),
        );
      case CurrentPlanStatus.failed:
        slot = _FailedCard(onRetry: _reload);
      case CurrentPlanStatus.ready:
        if (todayFailed) {
          slot = _FailedCard(onRetry: _reload);
          break;
        }
        if (mission == null || detailAsync == null) break;
        final detail = detailAsync.valueOrNull;
        if (detail == null) {
          slot = detailAsync.hasError
              ? _FailedCard(onRetry: _reload)
              : const _NightCard(child: _NightSkeleton());
          break;
        }
        if (detail.completed || (detail.steps.isEmpty && detail.detailsReady)) {
          break;
        }
        if (detail.currentStepReadable) {
          slot = _NextUpCard(
            detail: detail,
            idol: idol,
            onContinue: (at) => _continueTutorial(detail, at),
            onMission: () => _openPlanItem(detail.item.id),
          );
        } else if (detail.detailsFailed) {
          // Generation stopped: a reload would only read the failure again
          // (the server never re-enqueues a failed job on read). "Generate
          // again" lives on the mission screen.
          slot = _LessonUnavailableCard(
            detail: detail,
            onOpenMission: () => _openPlanItem(mission.id),
          );
        } else {
          preparing = mission.id;
          slot = _PreparingCard(onTap: () => _openPlanItem(mission.id));
        }
    }
    _notePreparing(preparing);
    return slot;
  }

  // ── habits ──

  Widget _habitsCard(TodayView? view) {
    if (view == null) {
      return Container(
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
      );
    }
    final items = view.items;
    if (items.isEmpty) {
      return Text(
        'No daily habits in your plan this week.',
        style: AppTypography.sans(14).copyWith(color: AppColors.ink2),
      );
    }
    final done = items.where(isHabitDone).length;
    final left = items
        .where((i) => !isHabitDone(i))
        .fold<int>(0, (sum, i) => sum + habitSessionMinutes(i));
    return Container(
      decoration: v3Card(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.hair)),
            ),
            child: Row(
              children: [
                V3Ring(
                  value: done / items.length,
                  size: 38,
                  strokeWidth: 3.5,
                  color: AppColors.sage2,
                  child: Text(
                    '$done/${items.length}',
                    style: AppTypography.sans(
                      12,
                      FontWeight.w700,
                    ).merge(AppTypography.tnum).copyWith(color: AppColors.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    done == items.length
                        ? 'All done. Counted for today only.'
                        : 'About $left minutes left',
                    style: AppTypography.sans(
                      13.5,
                    ).copyWith(color: AppColors.ink2, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            _habitRow(view, items[i], first: i == 0),
        ],
      ),
    );
  }

  Widget _habitRow(TodayView view, TodayTaskItem item, {required bool first}) {
    final on = isHabitDone(item);
    final open = _openHabit == item.id;
    final motion = MotionConfig.enabled(context);
    final instructions = item.dailyInstructions?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V3Pressable(
            onTap: () => _openPlanItem(item.id),
            pressedScale: 1,
            minTapTarget: 0,
            focusRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              child: Row(
                children: [
                  V3CheckDot(
                    done: on,
                    onPressed: () => toggleHabit(view, item),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: motion
                              ? const Duration(milliseconds: 300)
                              : Duration.zero,
                          style: AppTypography.sans(15, FontWeight.w500)
                              .copyWith(
                                color: on ? AppColors.ink3 : AppColors.ink,
                                decoration: on
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                decorationColor: AppColors.hair2,
                              ),
                          child: Text(item.title),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${habitSessionMinutes(item)} min',
                          style: AppTypography.sans(12)
                              .merge(AppTypography.tnum)
                              .copyWith(color: AppColors.ink3),
                        ),
                      ],
                    ),
                  ),
                  V3Pressable(
                    semanticLabel: 'Show instructions',
                    onTap: () =>
                        setState(() => _openHabit = open ? null : item.id),
                    child: AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: motion
                          ? const Duration(milliseconds: 300)
                          : Duration.zero,
                      curve: AppMotion.out,
                      child: const V3Icon(
                        V3Icons.down,
                        size: 16,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: motion
                  ? const Duration(milliseconds: 400)
                  : Duration.zero,
              curve: AppMotion.out,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(60, 0, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (instructions.isNotEmpty)
                            Text(
                              instructions,
                              style: AppTypography.sans(
                                13.5,
                              ).copyWith(color: AppColors.ink2, height: 1.5),
                            ),
                          V3Pressable(
                            onTap: () => _openPlanItem(item.id),
                            focusRadius: BorderRadius.circular(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Open habit',
                                  style: AppTypography.sans(
                                    13,
                                    FontWeight.w600,
                                  ).copyWith(color: AppColors.ember2),
                                ),
                                const SizedBox(width: 4),
                                const V3Icon(
                                  V3Icons.right,
                                  size: 14,
                                  color: AppColors.ember2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }

  // ── streak + compare ──

  Widget _streakAndCompare(
    BuildContext context, {
    required DateTime now,
    required TodayView view,
    required CmpysUser user,
    required CmpysIdol idol,
    required Map<String, dynamic>? scores,
    required bool wide,
  }) {
    final summary = ref.watch(todayStreakProvider).valueOrNull;
    final current = summary?.current ?? view.streak;
    final best = math.max(summary?.longest ?? 0, current);
    final habitsTotal = view.items.length;
    final habitsDone = view.items.where((i) => isHabitDone(i)).length;
    final streak = _StreakCard(
      current: current,
      best: best,
      week: streakWeek(summary, now),
      habitsDone: habitsDone,
      habitsTotal: habitsTotal,
    );
    final compare = _CompareCard(
      user: user,
      idol: idol,
      counts: comparableDimensions(scores),
      onTap: () => context.go(AppRoutes.vault),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [streak, const SizedBox(height: 10), compare],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: streak),
          const SizedBox(width: 10),
          Expanded(child: compare),
        ],
      ),
    );
  }

  // ── idea ──

  Widget _ideaCard(BuildContext context) {
    final ideas = ref.watch(cmpysIdeasProvider).valueOrNull;
    if (ideas == null || ideas.isEmpty) return const SizedBox.shrink();
    final idea = ideas.first;
    final ground = _ideaGrounds[_stableIndex(idea.tag, _ideaGrounds.length)];
    final meta = AppTypography.sans(12.5).copyWith(color: AppColors.nink3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: V3Rise(
        delay: const Duration(milliseconds: 380),
        child: V3Pressable(
          onTap: () => context.goToIdeas(),
          focusRadius: AppRadii.brR,
          child: ClipRRect(
            borderRadius: AppRadii.brR,
            child: ColoredBox(
              color: ground,
              child: Stack(
                children: [
                  const Positioned.fill(child: V3Grain()),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const V3Icon(
                              V3Icons.bulb,
                              size: 14,
                              color: AppColors.nink2,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Idea for today',
                                style: AppTypography.sans(
                                  12,
                                  FontWeight.w600,
                                ).copyWith(color: AppColors.nink2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '“${idea.text}”',
                          style: AppTypography.read(
                            19,
                          ).copyWith(color: Colors.white, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: Text(idea.author, style: meta)),
                            const SizedBox(width: 8),
                            Flexible(child: Text('More ideas', style: meta)),
                            const V3Icon(
                              V3Icons.right,
                              size: 14,
                              color: AppColors.nink3,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── books ──

  Widget _bookShelf(
    BuildContext context, {
    required BackendPlanItem? mission,
    required PlanItemDetailed? detail,
  }) {
    final resume = ref.watch(todayContinueReadingProvider).valueOrNull;
    // The design leaves videos off the shelf.
    final materials = mission == null || detail == null
        ? const <PlanMaterialDetail>[]
        : detail.materials
              .where(
                (m) =>
                    m.type != 'video' &&
                    accessTypeForMaterial(m) != AccessType.video,
              )
              .toList();
    if (resume == null && materials.isEmpty) return const SizedBox.shrink();
    // `listening = N && N.book === resume.id` (v3/today.jsx).
    final (listening, listeningPlaying) = ref.watch(
      bookNarrationRemoteControllerProvider.select((r) {
        final mine = resume != null && r.narrates(resume.id);
        return (mine, mine && (r.playing || r.preparing));
      }),
    );
    return V3Rise(
      delay: const Duration(milliseconds: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V3Section(
            title: 'Your books',
            action: 'Library',
            onAction: _openLibrary,
            child: resume == null
                ? const SizedBox.shrink()
                : _ContinueReadingCard(
                    book: resume,
                    listening: listening,
                    playing: listeningPlaying,
                    onOpen: () => _openBook(resume),
                    onListen: () => _listen(resume),
                  ),
          ),
          if (materials.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(20, resume == null ? 0 : 18, 20, 10),
              child: Text(
                'For this week’s mission'.toUpperCase(),
                style: AppTypography.kick,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < materials.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    _MaterialCover(
                      material: materials[i],
                      ground: _shelfGround(materials[i], i),
                      onTap: () => _openMaterial(materials[i], mission!.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NextUp and the cards that share its slot
// ─────────────────────────────────────────────────────────────────────────────

/// The night surface the NextUp slot uses for its loading, writing and
/// preparing states (radius 30, padding 22).
class _NightCard extends StatelessWidget {
  const _NightCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.circular(30),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: child,
      ),
    );
    if (onTap == null) return card;
    return V3Pressable(
      onTap: onTap,
      focusRadius: BorderRadius.circular(30),
      child: card,
    );
  }
}

class _NightSkeleton extends StatelessWidget {
  const _NightSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V3Skel(dark: true, height: 14, width: 150),
        SizedBox(height: 18),
        FractionallySizedBox(
          widthFactor: .8,
          child: V3Skel(dark: true, height: 30),
        ),
        SizedBox(height: 8),
        FractionallySizedBox(
          widthFactor: .55,
          child: V3Skel(dark: true, height: 30),
        ),
      ],
    );
  }
}

/// "Preparing this week’s tutorials" (the design's `preparing` state).
class _PreparingCard extends StatelessWidget {
  const _PreparingCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NightCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const V3Spinner(
                size: 14,
                color: AppColors.nink2,
                semanticLabel: null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Preparing this week’s tutorials',
                  style: AppTypography.sans(
                    13,
                  ).copyWith(color: AppColors.nink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const FractionallySizedBox(
            widthFactor: .8,
            child: V3Skel(dark: true, height: 30),
          ),
          const SizedBox(height: 8),
          const FractionallySizedBox(
            widthFactor: .55,
            child: V3Skel(dark: true, height: 30),
          ),
          const SizedBox(height: 16),
          Text(
            'Your first tutorial opens as soon as it passes review. Habits '
            'below are ready now.',
            style: AppTypography.sans(
              13,
            ).copyWith(color: AppColors.nink3, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// The plan itself is still being written (existing copy, night surface).
class _PlanWritingCard extends StatelessWidget {
  const _PlanWritingCard({
    required this.mentor,
    required this.progress,
    required this.onTap,
  });

  final String mentor;
  final int progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NightCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const V3Spinner(
                size: 14,
                color: AppColors.nink2,
                semanticLabel: null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your plan with $mentor is being written.',
                  style: AppTypography.sans(
                    13,
                  ).copyWith(color: AppColors.nink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const FractionallySizedBox(
            widthFactor: .8,
            child: V3Skel(dark: true, height: 30),
          ),
          const SizedBox(height: 8),
          const FractionallySizedBox(
            widthFactor: .55,
            child: V3Skel(dark: true, height: 30),
          ),
          const SizedBox(height: 16),
          Text(
            '$progress% complete',
            style: AppTypography.sans(
              13,
            ).merge(AppTypography.tnum).copyWith(color: AppColors.nink3),
          ),
        ],
      ),
    );
  }
}

/// No plan and nothing generating (existing copy, v3 card).
class _NoPlanCard extends StatelessWidget {
  const _NoPlanCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      onTap: onTap,
      focusRadius: AppRadii.brR,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: v3Card(),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.paper2,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const V3Icon(
                V3Icons.sparkle,
                size: 18,
                color: AppColors.ink2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You don’t have a plan yet.',
                    style: AppTypography.sans(
                      16,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tap to check again.',
                    style: AppTypography.sans(
                      13,
                    ).copyWith(color: AppColors.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "We couldn’t load your plan" with "Try again" (the design's `failed`).
class _FailedCard extends StatelessWidget {
  const _FailedCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.dangerSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const V3Icon(
                  V3Icons.wifiOff,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'We couldn’t load your plan',
                  style: AppTypography.sans(
                    16,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
            child: Text(
              'Nothing was lost. Your progress is saved on the server; this '
              'screen just failed to read it.',
              style: AppTypography.sans(
                14,
              ).copyWith(color: AppColors.ink2, height: 1.5),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: V3Button(
              kind: V3ButtonKind.dark,
              size: V3Size.md,
              icon: V3Icons.refresh,
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The current mission's tutorial generation stopped (failed, partly failed
/// after the ready tutorials, or no catalog for it). The copy is the mission
/// screen's, which is where "Generate again" lives.
class _LessonUnavailableCard extends StatelessWidget {
  const _LessonUnavailableCard({
    required this.detail,
    required this.onOpenMission,
  });

  final PlanItemDetailed detail;
  final VoidCallback onOpenMission;

  static const openMissionKey = Key('today-lesson-unavailable-open-mission');

  @override
  Widget build(BuildContext context) {
    final catalogMissing = detail.detailsStep == 'catalog_not_available';
    final (String title, String body) = catalogMissing
        ? (
            'This lesson isn’t available yet.',
            'The learning materials and practice for this task aren’t ready. '
                'Retrying now won’t prepare them. Your completed work is saved.',
          )
        : detail.hasReadyLesson
        ? (
            'Some lessons could not be prepared.',
            'Your ready lessons and progress are saved.',
          )
        : ('This lesson could not be prepared.', 'Please generate it again.');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.goldSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const V3Icon(
                  V3Icons.alert,
                  size: 18,
                  color: AppColors.gold2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.sans(
                    16,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
            child: Text(
              body,
              style: AppTypography.sans(
                14,
              ).copyWith(color: AppColors.ink2, height: 1.5),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: V3Button(
              key: openMissionKey,
              kind: V3ButtonKind.dark,
              size: V3Size.md,
              iconRight: V3Icons.right,
              onPressed: onOpenMission,
              child: const Text('Open mission'),
            ),
          ),
        ],
      ),
    );
  }
}

/// `NextUp`: the night card with two breathing glows and grain, the current
/// tutorial of the current mission, its progress segments and the pulsing
/// play button.
class _NextUpCard extends StatefulWidget {
  const _NextUpCard({
    required this.detail,
    required this.idol,
    required this.onContinue,
    required this.onMission,
  });

  final PlanItemDetailed detail;
  final CmpysIdol idol;

  /// Continue, with the play button's centre in global coordinates (where
  /// the reveal starts).
  final ValueChanged<Offset> onContinue;
  final VoidCallback onMission;

  @override
  State<_NextUpCard> createState() => _NextUpCardState();
}

class _NextUpCardState extends State<_NextUpCard>
    with TickerProviderStateMixin {
  // breathe 6s / 8s (1s delay), blink 1.6s, glowPulse 2.2s; all infinite.
  late final AnimationController _breatheA = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final AnimationController _breatheB = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  final GlobalKey _playKey = GlobalKey();
  Timer? _breatheBDelay;
  bool? _motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = MotionConfig.enabled(context);
    if (motion == _motion) return;
    _motion = motion;
    _breatheBDelay?.cancel();
    if (motion) {
      _breatheA.repeat();
      _blink.repeat();
      _pulse.repeat();
      _breatheBDelay = Timer(const Duration(seconds: 1), () {
        if (mounted) _breatheB.repeat();
      });
    } else {
      for (final c in [_breatheA, _breatheB, _blink, _pulse]) {
        c
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _breatheBDelay?.cancel();
    _breatheA.dispose();
    _breatheB.dispose();
    _blink.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// A 0 → 1 → 0 keyframe position (`0%,100%` / `50%`) eased per half.
  static double _wave(double t, Curve curve) =>
      curve.transform(t < .5 ? t * 2 : (1 - t) * 2);

  Widget _glow(AnimationController controller, Color color) {
    final circle = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // CSS `circle` = farthest-corner on a square box.
          radius: 0.7071,
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, .65],
        ),
      ),
    );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final k = _wave(controller.value, Curves.easeInOut);
          return Opacity(
            opacity: .55 + .35 * k,
            child: Transform.scale(scale: 1 + .08 * k, child: child),
          );
        },
        child: circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final steps = detail.steps;
    final current = detail.activeStepIndex;
    final step = steps[current];
    final read = step.effectiveReadingMinutes;
    final practice = step.effectivePracticeMinutes;
    final minutes = [
      if (read != null) '$read min read',
      if (practice != null) '$practice min practice',
    ].join(' · ');

    // `<Tilt max={6}>`: leans toward the finger (inert with reduced
    // motion); taps on its buttons still land.
    return V3Tilt(
      max: 6,
      child: _card(context, detail, steps, current, step, minutes),
    );
  }

  /// The play button's centre on screen (where the reveal starts).
  Offset _playCentre() {
    final box = _playKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(box.size.center(Offset.zero));
    }
    final card = context.findRenderObject();
    if (card is RenderBox && card.hasSize) {
      return card.localToGlobal(card.size.center(Offset.zero));
    }
    return Offset.zero;
  }

  Widget _card(
    BuildContext context,
    PlanItemDetailed detail,
    List<PlanStepDetail> steps,
    int current,
    PlanStepDetail step,
    String minutes,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB30E0C14),
            offset: Offset(0, 30),
            blurRadius: 50,
            spreadRadius: -30,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: ColoredBox(
          color: AppColors.night,
          child: Stack(
            children: [
              Positioned(
                right: -60,
                top: -40,
                width: 260,
                height: 260,
                child: _glow(_breatheA, _emberGlow),
              ),
              Positioned(
                left: -80,
                bottom: -100,
                width: 260,
                height: 260,
                child: _glow(_breatheB, _irisGlow),
              ),
              const Positioned.fill(child: V3Grain()),
              Padding(
                // The 44 pt "Up next" target supplies the top 14 pt.
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    V3Pressable(
                      onTap: widget.onMission,
                      focusRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Up next · Tutorial ${current + 1} of '
                              '${steps.length}',
                              style: AppTypography.sans(
                                12,
                                FontWeight.w600,
                              ).copyWith(color: AppColors.nink2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const V3Icon(
                            V3Icons.right,
                            size: 13,
                            color: AppColors.nink2,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      step.title,
                      style: AppTypography.display(
                        36,
                      ).copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mission · ${detail.item.title}',
                      style: AppTypography.sans(
                        13.5,
                      ).copyWith(color: AppColors.nink3),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (var i = 0; i < steps.length; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(child: _segment(i, current)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        V3Pressable(
                          key: _playKey,
                          semanticLabel: 'Continue tutorial',
                          onTap: () => widget.onContinue(_playCentre()),
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) {
                              final k = _wave(_pulse.value, Curves.ease);
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.ember.withValues(
                                        alpha: .45 * (1 - k),
                                      ),
                                      spreadRadius: 8 * k,
                                    ),
                                  ],
                                ),
                                child: child,
                              );
                            },
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: const BoxDecoration(
                                color: AppColors.ember,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const V3Icon(
                                V3Icons.play,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Continue',
                                style: AppTypography.sans(
                                  15,
                                  FontWeight.w600,
                                ).copyWith(color: Colors.white),
                              ),
                              if (minutes.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  minutes,
                                  style: AppTypography.sans(12.5)
                                      .merge(AppTypography.tnum)
                                      .copyWith(color: AppColors.nink3),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Opacity(
                          opacity: .9,
                          child: V3Avatar(
                            image: cmpysIdolImage(widget.idol),
                            initials: widget.idol.initials,
                            tint: widget.idol.tint,
                            size: 44,
                            gray: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(int index, int current) {
    final done = widget.detail.isStepCompleted(widget.detail.steps[index].id);
    final bar = Container(
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: done
            ? AppColors.sage
            : index == current
            ? AppColors.ember
            : const Color(0x24FFFFFF), // rgba(255,255,255,.14)
      ),
    );
    if (done || index != current) return bar;
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) => Opacity(
        opacity: _motion == true
            ? .25 + .75 * _wave(_blink.value, Curves.ease)
            : 1,
        child: child,
      ),
      child: bar,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Streak and compare
// ─────────────────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.current,
    required this.best,
    required this.week,
    required this.habitsDone,
    required this.habitsTotal,
  });

  final int current;
  final int best;

  /// Monday → Sunday from [streakWeek]; null is today.
  final List<bool?> week;

  /// Today's habits ticked, of [habitsTotal].
  final int habitsDone;
  final int habitsTotal;

  bool get _todayDone => habitsTotal > 0 && habitsDone >= habitsTotal;

  static const _letters = 'MTWTFSS';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // `<Flame s={22} />`: flickers while there is a streak to
              // keep; static at 0 and with reduced motion.
              V3Flame(size: 22, lit: current > 0),
              const SizedBox(width: 6),
              Flexible(
                child: V3CountUp(
                  to: current,
                  style: AppTypography.display(
                    34,
                  ).copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'day streak · best $best',
            style: AppTypography.sans(12).copyWith(color: AppColors.ink3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(child: _day(i)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _day(int i) {
    final today = week[i] == null;
    final on = today ? _todayDone : week[i]!;
    final Widget cell;
    if (today) {
      cell = _TodayStreakCell(done: habitsDone, total: habitsTotal);
    } else {
      cell = AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 18,
        decoration: BoxDecoration(
          color: on ? AppColors.ember : AppColors.paper2,
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }
    return Column(
      children: [
        V3Pop(child: cell),
        const SizedBox(height: 4),
        Text(
          _letters[i],
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: AppTypography.sans(
            9.5,
            FontWeight.w600,
          ).copyWith(color: AppColors.ink3),
        ),
      ],
    );
  }
}

/// Today's streak cell: an ember fill rising from the bottom by habits done
/// of [total] (`scaleY(done/total)`, `.9s var(--spring)`), inside a
/// `1.5px dashed` ember outline until every habit is done. While partly
/// full, a liquid crest rides the fill's top: a 6 pt rounded ellipse
/// (radius 45%) twice the cell's width, spinning every 2.4 s. The cell clips
/// both to its radius 6.
///
/// Reduced motion: the fill jumps and there is no crest.
class _TodayStreakCell extends StatefulWidget {
  const _TodayStreakCell({required this.done, required this.total});

  final int done;
  final int total;

  @override
  State<_TodayStreakCell> createState() => _TodayStreakCellState();
}

class _TodayStreakCellState extends State<_TodayStreakCell>
    with SingleTickerProviderStateMixin {
  // `spin 2.4s linear infinite`.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool get _partial => widget.done > 0 && widget.done < widget.total;
  bool _motion = true;

  void _syncSpin() {
    if (_motion && _partial) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionConfig.enabled(context);
    _syncSpin();
  }

  @override
  void didUpdateWidget(_TodayStreakCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion;
    final total = widget.total;
    final fraction = total <= 0
        ? 0.0
        : (widget.done / total).clamp(0.0, 1.0).toDouble();
    final allDone = total > 0 && widget.done >= total;
    final crest = motion && _partial;
    return SizedBox(
      width: double.infinity,
      height: 18,
      child: CustomPaint(
        painter: allDone
            ? null
            : const _DashedRRectPainter(color: AppColors.ember),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction),
            duration: motion
                ? const Duration(milliseconds: 900)
                : Duration.zero,
            curve: AppMotion.spring,
            builder: (context, scale, _) => LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                return Transform(
                  key: todayStreakFillKey,
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(1, math.max(0, scale), 1),
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: AppColors.ember),
                      if (crest)
                        Positioned(
                          key: todayStreakCrestKey,
                          left: -width / 2,
                          top: -3,
                          width: width * 2,
                          height: 6,
                          child: RotationTransition(
                            turns: _spin,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.ember,
                                borderRadius: BorderRadius.all(
                                  Radius.elliptical(width * 2 * .45, 6 * .45),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// `1.5px dashed` round-rect outline (radius 6) for today's open streak day.
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 3, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 2.5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.user,
    required this.idol,
    required this.counts,
    required this.onTap,
  });

  final CmpysUser user;
  final CmpysIdol idol;
  final ({int comparable, int total})? counts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = user.name.trim();
    final initial = name.isEmpty ? 'Y' : name[0].toUpperCase();
    final short = idol.short.trim();
    final counts = this.counts;
    return V3Pressable(
      onTap: onTap,
      focusRadius: AppRadii.brR,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: v3Card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 58,
              height: 34,
              child: Stack(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 2),
                    ),
                    child: Text(
                      initial,
                      style: AppTypography.sans(
                        13,
                        FontWeight.w600,
                      ).copyWith(color: Colors.white),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                      child: V3Avatar(
                        image: cmpysIdolImage(idol),
                        initials: idol.initials,
                        tint: idol.tint,
                        size: 30,
                        gray: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.age > 0
                        ? 'You and $short at ${user.age}'
                        : 'You and $short',
                    style: AppTypography.sans(
                      14,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink, height: 1.3),
                  ),
                  if (counts != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${counts.comparable} of ${counts.total} comparable',
                      style: AppTypography.sans(
                        12,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Reflection
// ─────────────────────────────────────────────────────────────────────────────

/// `Reflection`: the prompt and a two-line field that autosaves on this
/// device: "Unsaved" while typing, "Saving" after 900 ms, then "Saved for
/// today" 600 ms later.
class _ReflectionCard extends StatefulWidget {
  const _ReflectionCard({
    super.key,
    required this.prompt,
    required this.saved,
    required this.onSave,
  });

  final String prompt;
  final String saved;
  final ValueChanged<String> onSave;

  @override
  State<_ReflectionCard> createState() => _ReflectionCardState();
}

class _ReflectionCardState extends State<_ReflectionCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.saved,
  );
  late _ReflectionStatus _status = widget.saved.isEmpty
      ? _ReflectionStatus.idle
      : _ReflectionStatus.saved;
  Timer? _debounce;
  Timer? _commit;

  @override
  void didUpdateWidget(_ReflectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The store hydrates from the device after the first build. Take a newly
    // arrived saved text unless the user is editing (our own save leaves the
    // field already showing the new text).
    final editing =
        _status == _ReflectionStatus.typing ||
        _status == _ReflectionStatus.saving;
    if (oldWidget.saved != widget.saved &&
        !editing &&
        _controller.text == oldWidget.saved) {
      _controller.text = widget.saved;
      _status = widget.saved.isEmpty
          ? _ReflectionStatus.idle
          : _ReflectionStatus.saved;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _commit?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _commit?.cancel();
    if (value == widget.saved) {
      setState(
        () => _status = widget.saved.isEmpty
            ? _ReflectionStatus.idle
            : _ReflectionStatus.saved,
      );
      return;
    }
    setState(() => _status = _ReflectionStatus.typing);
    _debounce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _status = _ReflectionStatus.saving);
      _commit = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        widget.onSave(value);
        setState(() => _status = _ReflectionStatus.saved);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    const none = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide.none,
    );
    final statusStyle = AppTypography.sans(12, FontWeight.w500).copyWith(
      color: _status == _ReflectionStatus.saved
          ? AppColors.sage2
          : AppColors.ink3,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.prompt,
            style: AppTypography.read(
              17,
            ).copyWith(color: AppColors.ink, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            key: CmpysTodayScreen.reflectionFieldKey,
            controller: _controller,
            onChanged: _changed,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            cursorColor: AppColors.ink,
            style: AppTypography.sans(
              15,
            ).copyWith(color: AppColors.ink, height: 1.45),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.paper,
              hintText: 'A sentence is enough',
              hintStyle: AppTypography.sans(
                15,
              ).copyWith(color: AppColors.ink3, height: 1.45),
              contentPadding: const EdgeInsets.all(12),
              border: none,
              enabledBorder: none,
              focusedBorder: none,
              disabledBorder: none,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: Semantics(
              liveRegion: true,
              child: DefaultTextStyle(
                style: statusStyle,
                child: Row(
                  children: switch (_status) {
                    _ReflectionStatus.idle => const <Widget>[],
                    _ReflectionStatus.typing => const [Text('Unsaved')],
                    _ReflectionStatus.saving => const [
                      V3Spinner(size: 12, semanticLabel: null),
                      SizedBox(width: 6),
                      Text('Saving'),
                    ],
                    _ReflectionStatus.saved => const [
                      V3Icon(
                        V3Icons.check,
                        size: 13,
                        strokeWidth: 2.6,
                        color: AppColors.sage2,
                      ),
                      SizedBox(width: 6),
                      Text('Saved for today'),
                    ],
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Books
// ─────────────────────────────────────────────────────────────────────────────

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.book,
    required this.listening,
    this.playing = false,
    required this.onOpen,
    required this.onListen,
  });

  final ContentResource book;
  final bool listening;

  /// [listening] and playing: the design swaps the headphones for waves.
  final bool playing;
  final VoidCallback onOpen;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final pct = book.progressPercent.clamp(0, 100);
    final chapter = (book.cursorJson?['chapter'] as num?)?.toInt();
    final author = book.authorOrCreator?.trim() ?? '';
    final sub = chapter != null ? 'Ch. ${chapter + 1}' : author;
    return V3Pressable(
      onTap: onOpen,
      focusRadius: AppRadii.brR,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: v3Card(),
        child: Row(
          children: [
            V3Cover(
              title: v3CoverTitle(book.title),
              author: author,
              background: v3CoverGround(book.id),
              foreground: kV3CoverInk,
              width: 64,
              height: 92,
              radius: 8,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continue reading'.toUpperCase(),
                    style: AppTypography.kick.copyWith(
                      fontSize: 10,
                      letterSpacing: 10 * .12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      15.5,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink, height: 1.25),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.sans(
                        12.5,
                      ).copyWith(color: AppColors.ink3),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: V3Bar(
                          value: pct / 100,
                          height: 4,
                          delay: const Duration(milliseconds: 500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: AppTypography.sans(11.5, FontWeight.w600)
                            .merge(AppTypography.tnum)
                            .copyWith(color: AppColors.ink2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            V3Pressable(
              semanticLabel: listening ? 'Listening' : 'Listen',
              onTap: onListen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: listening ? AppColors.ember : AppColors.ink,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: playing
                    ? const SizedBox(
                        width: 20,
                        child: BookNarrationWaves(
                          playing: true,
                          count: 4,
                          height: 14,
                        ),
                      )
                    : const V3Icon(
                        V3Icons.headphones,
                        size: 19,
                        color: Colors.white,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialCover extends StatelessWidget {
  const _MaterialCover({
    required this.material,
    required this.ground,
    required this.onTap,
  });

  final PlanMaterialDetail material;
  final Color ground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final access = accessTypeForMaterial(material);
    final none = access == AccessType.none;
    return V3Pressable(
      onTap: onTap,
      focusRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: none ? .6 : 1,
        child: SizedBox(
          width: 118,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  V3Cover(
                    title: v3CoverTitle(material.title),
                    author: material.authorOrCreator ?? '',
                    background: ground,
                    foreground: kV3CoverInk,
                    width: 118,
                    height: 164,
                    radius: 12,
                  ),
                  if (none)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x590E0C14), // rgba(14,12,20,.35)
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: V3Icon(
                            V3Icons.lock,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                material.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  13,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink, height: 1.25),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: V3AccessBadge(type: access),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
