import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/state/plan_data.dart'
    show TutorialRowState, tutorialRowStates;
import '../../cmpys/state/today_data.dart' show accessTypeForMaterial;
import '../data/plan_repository.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'achievement_sheet.dart';
import 'backend_plan_widgets.dart' show TutorialGlowDisc, TutorialShake;
import 'book_narration_checkpoint.dart';
import 'book_reader_screen.dart';
import 'cycle_completion_screen.dart';
import 'first_tutorial_auto_open.dart';
import 'habit_detail_view.dart';
import 'material_row.dart';
import 'material_reader_screen.dart';
import 'material_video_screen.dart';
import 'material_web_screen.dart';
import 'mission_detail_data.dart';
import 'open_lesson_reader.dart';
import '../../../core/ui/narration_dock_page.dart';

/// `oklch(0.8 0.1 285)` in sRGB: the night card's "Mental model" kick.
const Color _irisLight = Color(0xFFB7B5FC);

/// Detail view for one generated plan item (GET /plan-items/{id}/detailed).
/// A mission is the v3 `MissionScreen` (`v3/plan.jsx`): kick, workload,
/// tutorial timeline, deliverable with its definition of done, the mental
/// model card and the materials with their reading access; a daily item is
/// [HabitDetailView].
///
/// Lesson details are generated lazily by a Celery worker; while
/// `details_status` is pending this screen polls and reveals the lesson when
/// it lands.
class PlanItemDetailScreen extends ConsumerStatefulWidget {
  const PlanItemDetailScreen({
    super.key,
    required this.itemId,
    this.shellBranchIndex = ActiveBookNarrationResume.planBranchIndex,
  });

  final String itemId;

  /// The shell branch this screen was opened from (Today or Plan), handed to
  /// the book reader and the tutorial reader it opens.
  final int shellBranchIndex;

  @override
  ConsumerState<PlanItemDetailScreen> createState() =>
      _PlanItemDetailScreenState();
}

class _PlanItemDetailScreenState extends ConsumerState<PlanItemDetailScreen>
    with WidgetsBindingObserver {
  static const _foregroundPollBudget = Duration(minutes: 2);
  static const _maxForegroundPollAttempts = 20;
  static const _backgroundPollBudget = Duration(minutes: 10);
  static const _maxBackgroundPollAttempts = 52;
  static const _backgroundPollInterval = Duration(seconds: 15);
  static const _lessonCheckpointSteps = <String>{
    'first_lesson_ready',
    'lessons_ready',
    // Version-2 jobs may still finish with these legacy stage names.
    '2_lessons_ready',
    '3_lessons_ready',
  };
  static const _detailFailureMessage =
      'This lesson could not be prepared. Please generate it again.';

  PlanItemDetailed? _detailed;
  PlanJobStatus? _detailJob;
  String? _activeDetailJobId;
  String? _terminalDetailError;
  String? _error;
  bool _toggling = false;
  bool _retrying = false;
  bool _loading = false;
  bool _pollingJob = false;
  bool _foreground = true;
  int _pollRevision = 0;
  bool _detailJobPollingUnsupported = false;
  bool _takingLong = false;
  bool _descriptionExpanded = false;
  DateTime? _pollStartedAt;
  int _pollAttempt = 0;
  Timer? _poll;
  final Map<String, String> _resolvedBookGuideIds = {};
  final Set<String> _preparingBookGuideKeys = {};
  final Map<String, BookReadingAccess> _bookAccess = {};
  final Map<String, Future<BookReadingAccess>> _bookAccessFlights = {};

  /// A load showed "preparing your first tutorial" and tutorial 1 has not
  /// opened since: when it becomes readable it opens by itself.
  bool _awaitingFirstTutorial = false;

  /// Tutorial 1 became readable while something covered this screen (a
  /// page, a sheet or a dialog): it opens once that is gone.
  PlanItemDetailed? _pendingFirstTutorial;
  Timer? _pendingFirstTutorialRetry;
  static const _autoOpenRetryEvery = Duration(milliseconds: 500);

  /// Taps on each locked tutorial, which rock its lock.
  final Map<String, int> _shakes = {};

  /// Books whose reading access is being checked before their sheet opens.
  final Set<String> _checkingAccessKeys = {};

  /// Bumped when a book's reading access resolves, so an open material
  /// sheet shows what its CTA will now open.
  final ValueNotifier<int> _accessRevision = ValueNotifier(0);

  /// How long a material tap waits for an in-flight access check.
  static const _accessWait = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(resetPolling: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _poll?.cancel();
    if (foreground) {
      // A worker can finish while the phone is locked or after our bounded
      // polling window ends. Reconcile persisted content when the app returns;
      // this is a read only refresh, never another generation request.
      _load(resetPolling: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollRevision++;
    _poll?.cancel();
    _pendingFirstTutorialRetry?.cancel();
    _accessRevision.dispose();
    super.dispose();
  }

  Future<void> _load({bool resetPolling = false}) async {
    if (_loading) return;
    _loading = true;
    _poll?.cancel();
    if (resetPolling) {
      _pollRevision++;
      _pollStartedAt = DateTime.now();
      _pollAttempt = 0;
      _detailJob = null;
      _detailJobPollingUnsupported = false;
      _terminalDetailError = null;
      _takingLong = false;
    }
    final revision = _pollRevision;
    try {
      final detailed = await ref
          .read(planRepositoryProvider)
          .getPlanItemDetailed(widget.itemId);
      if (!mounted || revision != _pollRevision) return;
      final previousReadyCount = _detailed?.readyLessonCount;
      final receivedNewTutorial =
          detailed.isTutorialSequence &&
          previousReadyCount != null &&
          detailed.readyLessonCount > previousReadyCount;
      setState(() {
        _detailed = detailed;
        if (receivedNewTutorial) {
          // A long sequence can continue while the learner works. Bound idle
          // polling rather than the total lifetime of an advancing sequence.
          _pollStartedAt = DateTime.now();
          _pollAttempt = 0;
          _takingLong = false;
        }
        _error = null;
        if (detailed.generationParked) {
          // One ahead is written and generation waits for the learner: a
          // finished job (or a retry's) has nothing more to report.
          _activeDetailJobId = null;
          _detailJob = null;
        }
        if (detailed.detailsReady || detailed.completed) {
          _activeDetailJobId = null;
          _terminalDetailError = null;
          _detailJob = null;
        } else if (detailed.detailsFailed &&
            _activeDetailJobId != null &&
            detailed.jobId?.trim() == _activeDetailJobId) {
          // A failed response for the exact retry job is authoritative. A
          // failed response for an older id can be a brief post-retry race and
          // must not replace the active job returned by the POST.
          _activeDetailJobId = null;
          _terminalDetailError = detailed.detailsError ?? _detailFailureMessage;
        }
      });
      for (final material in detailed.materials) {
        if (material.type == 'book' &&
            _bookResourceId(material) == null &&
            material.directUrl == null) {
          unawaited(
            _checkBookAccess(
              material,
            ).then<void>((_) {}, onError: (Object _) {}),
          );
        }
      }
      _noteFirstTutorial(detailed);
      if (_shouldPollDetails(detailed)) {
        _pollStartedAt ??= DateTime.now();
        _scheduleDetailPoll();
      } else {
        _pollStartedAt = null;
        _takingLong = false;
      }
    } catch (e) {
      debugPrint('⚠️ plan item detail load failed (${widget.itemId}): $e');
      if (!mounted || revision != _pollRevision) return;
      // A failed background poll must not replace already-loaded content —
      // keep the screen and use bounded backoff.
      if (_detailed != null) {
        if (_shouldPollDetails(_detailed)) {
          _scheduleDetailPoll();
        }
        return;
      }
      final isConnection = e is TimeoutError || e is NetworkError;
      setState(
        () => _error = isConnection
            ? 'Couldn’t load this task. Check your connection and try again.'
            : 'Something went wrong loading this task — try again.',
      );
    } finally {
      _loading = false;
      if (mounted && revision != _pollRevision) _scheduleDetailPoll();
    }
  }

  /// Opens tutorial 1 by itself the moment it becomes readable, when every
  /// load since this screen showed it being prepared said so (a stop in
  /// between ends the wait): once per mission per app session, only while
  /// nothing covers this screen and the app is in front, and never after the
  /// learner opened it.
  void _noteFirstTutorial(PlanItemDetailed detailed) {
    if (detailed.firstTutorialPreparing && !_preparationStopped(detailed)) {
      _awaitingFirstTutorial = true;
      return;
    }
    if (!_awaitingFirstTutorial) return;
    _awaitingFirstTutorial = false;
    if (!detailed.firstTutorialReadable) return;
    _pendingFirstTutorial = detailed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingFirst());
  }

  /// Opens the pending tutorial 1 when this screen is the visible page with
  /// nothing over it; while something covers it, tries again until that is
  /// gone. In the background the chance has passed.
  void _openPendingFirst() {
    _pendingFirstTutorialRetry?.cancel();
    final detailed = _pendingFirstTutorial;
    if (!mounted || detailed == null) return;
    if (!_foreground) {
      _pendingFirstTutorial = null;
      return;
    }
    // Covered (an opaque page also turns tickers off below it): wait.
    if (!routeIsOnTop(context)) {
      _pendingFirstTutorialRetry = Timer(
        _autoOpenRetryEvery,
        _openPendingFirst,
      );
      return;
    }
    // On top but tickers off: another shell tab is showing.
    if (!TickerMode.of(context)) {
      _pendingFirstTutorial = null;
      return;
    }
    _pendingFirstTutorial = null;
    if (!FirstTutorialAutoOpen.claim(detailed.item.id)) return;
    unawaited(_openLesson(detailed, detailed.steps.first, 0));
  }

  String? get _pollingDetailJobId {
    final activeJobId = _activeDetailJobId?.trim();
    if (activeJobId != null && activeJobId.isNotEmpty) return activeJobId;
    final responseJobId = _detailed?.jobId?.trim();
    if (responseJobId != null && responseJobId.isNotEmpty) {
      return responseJobId;
    }
    return null;
  }

  bool _shouldPollDetails(PlanItemDetailed? detailed) {
    if (detailed == null ||
        detailed.completed ||
        detailed.detailsReady ||
        // Parked one ahead: nothing runs until the learner moves on.
        (detailed.generationParked && _activeDetailJobId == null) ||
        _terminalDetailError != null) {
      return false;
    }
    if (detailed.detailsFailed &&
        detailed.detailsStep == 'catalog_not_available') {
      return false;
    }
    return detailed.detailsLoading || _pollingDetailJobId != null;
  }

  void _beginDetailJobPolling(String jobId) {
    final normalizedJobId = jobId.trim();
    if (normalizedJobId.isEmpty) {
      throw StateError('Lesson regeneration did not return a job id.');
    }
    _poll?.cancel();
    _pollRevision++;
    setState(() {
      _activeDetailJobId = normalizedJobId;
      _terminalDetailError = null;
      _detailJob = null;
      _detailJobPollingUnsupported = false;
      _pollStartedAt = DateTime.now();
      _pollAttempt = 0;
      _takingLong = false;
      _error = null;
    });
    _scheduleDetailPoll();
  }

  void _scheduleDetailPoll() {
    _poll?.cancel();
    if (!mounted || !_foreground || !_shouldPollDetails(_detailed)) return;
    final startedAt = _pollStartedAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(startedAt);
    if (_pollAttempt >= _maxBackgroundPollAttempts ||
        elapsed >= _backgroundPollBudget) {
      if (!_takingLong) setState(() => _takingLong = true);
      return;
    }
    if (!_takingLong &&
        (_pollAttempt >= _maxForegroundPollAttempts ||
            elapsed >= _foregroundPollBudget)) {
      setState(() => _takingLong = true);
    }
    final delay = _takingLong
        ? _backgroundPollInterval
        : _pollAttempt < 4
        ? const Duration(seconds: 2)
        : _pollAttempt < 10
        ? const Duration(seconds: 4)
        : const Duration(seconds: 8);
    _poll = Timer(delay, _pollDetailJob);
  }

  Future<void> _pollDetailJob() async {
    if (!mounted || !_foreground || _pollingJob) return;
    final detailed = _detailed;
    if (!_shouldPollDetails(detailed)) return;
    _pollingJob = true;
    final revision = _pollRevision;
    _pollAttempt++;
    try {
      final jobId = _pollingDetailJobId;
      if (jobId == null || jobId.isEmpty || _detailJobPollingUnsupported) {
        await _load();
        return;
      }

      final job = await ref
          .read(planRepositoryProvider)
          .getPlanDetailJobStatus(jobId);
      if (!mounted || revision != _pollRevision) return;
      setState(() => _detailJob = job);
      if (job.isFailed) {
        setState(() {
          _activeDetailJobId = null;
          // Job errors are operational diagnostics (provider names, exception
          // text, database details) and must not be rendered to end users.
          // The detailed endpoint supplies product copy when available; keep
          // this safe fallback terminal if that refresh fails or races.
          _terminalDetailError = _detailFailureMessage;
        });
        _poll?.cancel();
        // Prefer the detailed endpoint's user-facing error when it is
        // available. The job failure remains terminal if this refresh races
        // the backend or the network, so polling cannot restart forever.
        await _load();
      } else if (job.isCompleted) {
        await _load();
      } else if ((job.readyLessonCount ?? 0) > detailed!.readyLessonCount ||
          (_lessonCheckpointSteps.contains(job.step) &&
              job.progressPercent > detailed.detailsProgress) ||
          // Fetch the syllabus once the outline exists; the detail step
          // guard keeps this to one refresh if the API returns none.
          (job.step == 'outline_ready' &&
              detailed.steps.isEmpty &&
              detailed.detailsStep != 'outline_ready')) {
        // Ready counts survive transient stage changes and rounded percentages
        // in long tutorial sequences. Refresh the persisted content whenever
        // another tutorial is ready, including while the reader is open.
        await _load();
      } else {
        _scheduleDetailPoll();
      }
    } catch (e) {
      if (!mounted || revision != _pollRevision) return;
      // Older APIs may not support the typed detail-job lookup. Fall back to
      // the detailed endpoint, still under the same bounded polling budget.
      if (e is ApiError && e.statusCode == 404) {
        _detailJobPollingUnsupported = true;
        await _load();
      } else {
        _scheduleDetailPoll();
      }
    } finally {
      _pollingJob = false;
      if (mounted && revision != _pollRevision) _scheduleDetailPoll();
    }
  }

  Future<void> _checkDetailsAgain() async {
    await _load(resetPolling: true);
  }

  Future<void> _toggleComplete() async {
    final detailed = _detailed;
    if (detailed == null || _toggling) return;
    setState(() => _toggling = true);
    try {
      final result = await ref
          .read(planRepositoryProvider)
          .toggleItemComplete(
            detailed.item.id,
            artifactJobId: detailed.artifactJobId,
            // The state the learner asked for, so a retry after a lost
            // response never flips the mission back.
            complete: !detailed.completed,
          );
      if (!mounted) return;
      if (result.completed) {
        showV3Toast(
          context,
          "Marked done. Kept your word.",
          icon: V3Icons.check,
          tone: V3ToastTone.success,
        );
      }
      // Refresh both this screen and the plan-wide progress numbers.
      await _load();
      if (!mounted) return;
      ref.read(currentPlanProvider.notifier).refresh();
      if (!mounted) return;

      final item = detailed.item;
      final plan = ref.read(currentPlanProvider).plan;

      // Show achievement sheet for completed mission tasks (project/course/reading).
      if (item.isMissionTask && result.completed) {
        await showAchievementSheet(
          context,
          ref: ref,
          item: item,
          // No plan loaded yet: the achievement carries no plan id.
          planId: plan?.id,
          cycleNumber: plan?.cycleNumber ?? 1,
        );
      }

      // Show cycle completion recap + next-plan CTA when the last mission
      // task is marked done and the backend signals planComplete.
      if (!mounted) return;
      if (result.planComplete && plan != null) {
        await showCycleCompletion(context, plan: plan);
      }
    } catch (_) {
      if (mounted) {
        showV3Toast(
          context,
          "Couldn’t update - try again.",
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _retryDetails() async {
    final detailed = _detailed;
    if (detailed == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      final retryJobId = await ref
          .read(planRepositoryProvider)
          .regeneratePlanItemDetails(detailed.item.id);
      if (!mounted) return;
      // The detailed endpoint can briefly fail or still describe the previous
      // failed job after a successful retry POST. Keep the authoritative job
      // id returned by POST and poll it until refreshed details catch up.
      if (retryJobId.trim().isNotEmpty) {
        _beginDetailJobPolling(retryJobId);
        await _load();
      } else {
        // An empty id means the retry endpoint found that the lesson or
        // mission had already become terminal while the request was in flight.
        await _load(resetPolling: true);
      }
    } catch (_) {
      if (mounted) {
        showV3Toast(
          context,
          'Couldn’t restart this lesson — try again.',
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailed = _detailed;
    if (_error == null && detailed != null && detailed.item.isDailyRhythm) {
      return HabitDetailView(detailed: detailed, onReload: _load);
    }
    final loaded = _error == null ? detailed : null;
    final workload = loaded == null
        ? null
        : missionWorkload(
            loaded.item,
            loaded.steps,
            tutorialsPending: !loaded.detailsReady,
          );
    // Watched here, in this element's own build: the footer scaffold builds
    // the body later, inside its own build.
    final kick = loaded == null
        ? ''
        : ref.watch(
            currentPlanProvider.select(
              (state) => missionKick(loaded.item, state.plan),
            ),
          );
    final topBar = V3TopBar(
      onBack: () => Navigator.of(context).maybePop(),
      right: workload == null || workload.total <= 0
          ? null
          : V3Tag(
              icon: V3Icons.clock,
              // With the tutorials' time unknown only the allocation is
              // true, so the tag shows that alone.
              child: Text(
                workload.splitKnown
                    ? '${workload.total}/${workload.allocated} min'
                    : '${workload.allocated} min',
                style: AppTypography.tnum,
              ),
            ),
    );
    Widget body(BuildContext context, double bottom) => _error != null
        ? _errorView()
        : loaded == null
        ? _loadingView()
        : _content(loaded, workload!, kick, bottom);
    final footer = loaded == null ? null : _footer(loaded);
    return NarrationDockPage(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        // Reserve the floating dock outside the scroll viewport. End padding
        // alone lets a retry button sit under the dock partway through a scroll.
        body: Padding(
          padding: EdgeInsets.only(
            bottom: AppShell.isWithinShell(context)
                ? AppShell.bottomNavClearance(context)
                : 0,
          ),
          child: footer == null
              ? Column(
                  children: [
                    topBar,
                    Expanded(child: body(context, 0)),
                  ],
                )
              : V3FooterScaffold(topBar: topBar, body: body, footer: footer),
        ),
      ),
    );
  }

  Widget _loadingView() {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: const [
            Align(
              alignment: Alignment.centerLeft,
              child: V3Skel(width: 150, height: 12),
            ),
            SizedBox(height: 14),
            V3Skel(height: 34, radius: 10),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: V3Skel(width: 190, height: 34, radius: 10),
            ),
            SizedBox(height: 16),
            V3Skel(height: 14),
            SizedBox(height: 8),
            V3Skel(height: 14),
            SizedBox(height: 18),
            V3Skel(height: 96, radius: AppRadii.r),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: v3Card(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.paper2,
                  shape: BoxShape.circle,
                ),
                child: const V3Icon(
                  V3Icons.alert,
                  size: 20,
                  color: AppColors.ink3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.sans(
                  15,
                  FontWeight.w500,
                ).copyWith(color: AppColors.ink2, height: 1.45),
              ),
              const SizedBox(height: 18),
              V3Button(
                size: V3Size.md,
                icon: V3Icons.refresh,
                onPressed: () => _load(resetPolling: true),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Mark as done" for a mission without tutorials (its only way to finish).
  Widget? _footer(PlanItemDetailed d) {
    if (!d.detailsReady && !d.completed) return null;
    if (d.steps.isNotEmpty) return null;
    return d.completed
        ? V3Button(
            kind: V3ButtonKind.soft,
            full: true,
            icon: V3Icons.refresh,
            disabled: _toggling,
            onPressed: _toggleComplete,
            child: const Text('Mark as not done'),
          )
        : V3Button(
            full: true,
            icon: V3Icons.check,
            disabled: _toggling,
            onPressed: _toggleComplete,
            child: const Text('Mark as done'),
          );
  }

  Widget _content(
    PlanItemDetailed d,
    MissionWorkload workload,
    String kick,
    double bottom,
  ) {
    final item = d.item;
    // A stopped job stays quiet while the current tutorial is readable; the
    // learner meets the retry when they reach the tutorial that is missing.
    // Tutorials are written one ahead, so while the current one is readable
    // the next one being written is no news either.
    final showPreparation =
        !d.completed &&
        !d.detailsReady &&
        !(d.currentStepReadable &&
            (d.isTutorialSequence || _preparationStopped(d)));
    // The syllabus shows as soon as the outline exists; unready tutorials
    // stay locked or preparing until they are published.
    final showTimeline =
        d.steps.isNotEmpty &&
        (d.detailsReady || d.hasReadyLesson || d.detailsLoading);
    final states = _rowStates(d);
    final doneCount = states.where((s) => s == TutorialRowState.done).length;
    final doneLines = definitionOfDoneLines(d.definitionOfDone);
    final model = splitMentalModel(d.mentalModel);
    final metric = item.successMetric.trim();
    final completion = _completionNote(d);
    return ListView(
      key: const Key('plan-detail-scroll'),
      padding: EdgeInsets.only(
        bottom: math.max(
          bottom,
          AppShell.isWithinShell(context)
              ? 24
              : AppShell.bottomNavClearance(context),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              V3Rise(
                child: Text(kick.toUpperCase(), style: AppTypography.kick),
              ),
              const SizedBox(height: 10),
              V3Rise(
                delay: const Duration(milliseconds: 50),
                child: Text(
                  item.title,
                  style: AppTypography.display(
                    40,
                  ).copyWith(color: AppColors.ink),
                ),
              ),
              if (item.description.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                V3Rise(
                  delay: const Duration(milliseconds: 100),
                  child: _missionBackground(item),
                ),
              ],
              if (showPreparation) ...[
                const SizedBox(height: 18),
                _generatingCard(d),
              ],
              if (workload.splitKnown && workload.total > 0) ...[
                const SizedBox(height: 18),
                V3Rise(
                  delay: const Duration(milliseconds: 150),
                  child: _workloadCard(workload),
                ),
              ],
            ],
          ),
        ),
        if (d.completed && d.steps.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
            child: _completedWithoutLessonCard(),
          )
        else if (showTimeline)
          V3Section(
            title:
                '${d.isTutorialSequence ? 'Tutorials' : 'Lessons'} · '
                '$doneCount of ${d.steps.length}',
            child: _timeline(d, states),
          ),
        if (metric.isNotEmpty || doneLines.isNotEmpty || model != null)
          V3Section(
            title: 'Deliverable',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (metric.isNotEmpty || doneLines.isNotEmpty)
                  _deliverableCard(metric, doneLines),
                if (model != null) ...[
                  if (metric.isNotEmpty || doneLines.isNotEmpty)
                    const SizedBox(height: 10),
                  _mentalModelCard(model),
                ],
              ],
            ),
          ),
        if (d.materials.isNotEmpty)
          V3Section(
            title: 'Materials',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < d.materials.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _materialRow(d.materials[i]),
                ],
                const SizedBox(height: 10),
                Text(
                  'Required practice is solvable inside CMPYS. Materials are optional depth.',
                  style: AppTypography.sans(
                    12.5,
                  ).copyWith(color: AppColors.ink3, height: 1.5),
                ),
              ],
            ),
          ),
        if (completion != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: completion,
          ),
      ],
    );
  }

  /// The closing line under a mission with tutorials: accomplished, or how
  /// it finishes.
  Widget? _completionNote(PlanItemDetailed d) {
    if (d.steps.isEmpty) return null;
    if (d.completed) {
      return _noteCard(
        color: AppColors.sageSoft,
        icon: V3Icons.check,
        tone: AppColors.sage2,
        text: d.isTutorialSequence
            ? 'All tutorials are complete. Mission accomplished.'
            : 'All focused lessons are complete. Mission accomplished.',
      );
    }
    if (!d.detailsReady) return null;
    return _noteCard(
      color: AppColors.paper2,
      icon: V3Icons.lock,
      tone: AppColors.ink2,
      text: d.isTutorialSequence
          ? 'Complete all tutorials in order to finish this mission.'
          : 'Complete all lessons in order to finish this mission.',
    );
  }

  Widget _noteCard({
    required Color color,
    required V3Icons icon,
    required Color tone,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: AppRadii.brR),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: V3Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.sans(
                14,
                FontWeight.w500,
              ).copyWith(color: tone, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  // ── workload ───────────────────────────────────────────────────────────

  Widget _workloadCard(MissionWorkload w) {
    final parts = [
      (
        minutes: w.reading,
        color: AppColors.iris,
        id: 'reading',
        label: 'Reading',
      ),
      (
        minutes: w.practice,
        color: AppColors.ember,
        id: 'practice',
        label: 'Practice',
      ),
      (
        minutes: w.deliverable,
        color: AppColors.gold,
        id: 'deliverable',
        label: 'Deliverable',
      ),
    ];
    final filled = [
      for (final part in parts)
        if (part.minutes > 0) part,
    ];
    final small = AppTypography.sans(13).copyWith(color: AppColors.ink2);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Workload',
                  style: AppTypography.sans(
                    13,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${w.total} / ${w.allocated} min allocated',
                  textAlign: TextAlign.end,
                  style: small.merge(AppTypography.tnum),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              key: const Key('workload-bar'),
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < filled.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: filled[i].minutes,
                      child: V3Rise(
                        delay: Duration(milliseconds: 200 + i * 120),
                        duration: const Duration(milliseconds: 700),
                        offset: 10,
                        child: ColoredBox(
                          key: Key('workload-${filled[i].id}'),
                          color: filled[i].color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final part in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: part.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${part.label} ${part.minutes}',
                        style: AppTypography.sans(12)
                            .copyWith(color: AppColors.ink2)
                            .merge(AppTypography.tnum),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── deliverable ────────────────────────────────────────────────────────

  Widget _deliverableCard(String metric, List<String> doneLines) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (metric.isNotEmpty)
            Text(
              metric,
              style: AppTypography.sans(
                15,
              ).copyWith(color: AppColors.ink, height: 1.5),
            ),
          if (doneLines.isNotEmpty) ...[
            SizedBox(height: metric.isNotEmpty ? 16 : 0),
            Text('DEFINITION OF DONE', style: AppTypography.kick),
            const SizedBox(height: 4),
            for (var i = 0; i < doneLines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: Key('done-check-$i'),
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.hair2, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doneLines[i],
                        style: AppTypography.sans(
                          14,
                        ).copyWith(color: AppColors.ink2, height: 1.45),
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

  Widget _mentalModelCard(({String? title, String body}) model) {
    if (mentalModelIsAboutFarm(model)) return _MentalModelFarmCard(model);
    return _mentalModelTextCard(model);
  }

  /// The text-only card: every mental model that isn't about a farm, and a
  /// farm model whose images can't load.
  Widget _mentalModelTextCard(({String? title, String body}) model) {
    return ClipRRect(
      key: const Key('mental-model-card'),
      borderRadius: AppRadii.brR,
      child: ColoredBox(
        color: AppColors.night,
        child: Stack(
          children: [
            const Positioned.fill(child: V3Grain()),
            _MentalModelText(model),
          ],
        ),
      ),
    );
  }

  Widget _missionBackground(BackendPlanItem item) {
    final description = item.description.trim();
    final collapsible =
        item.isMissionTask &&
        (description.length > 300 || '\n'.allMatches(description).length > 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          key: const Key('mission-background'),
          maxLines: collapsible && !_descriptionExpanded ? 4 : null,
          overflow: collapsible && !_descriptionExpanded
              ? TextOverflow.ellipsis
              : null,
          style: AppTypography.sans(
            15,
          ).copyWith(color: AppColors.ink2, height: 1.5),
        ),
        if (collapsible)
          V3Pressable(
            key: const Key('mission-background-toggle'),
            onTap: () =>
                setState(() => _descriptionExpanded = !_descriptionExpanded),
            pressedScale: 1,
            focusRadius: BorderRadius.circular(8),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                _descriptionExpanded
                    ? 'Show less background'
                    : 'Read full mission background',
                style: AppTypography.sans(
                  13.5,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink),
              ),
            ),
          ),
      ],
    );
  }

  Widget _completedWithoutLessonCard() {
    return _noteCard(
      color: AppColors.sageSoft,
      icon: V3Icons.check,
      tone: AppColors.sage2,
      text:
          'This mission was completed before focused lessons were added. '
          'Your completion is preserved—there is nothing left to load.',
    );
  }

  bool _preparationStopped(PlanItemDetailed detailed) {
    final activeRetry =
        _activeDetailJobId != null && _terminalDetailError == null;
    return _terminalDetailError != null ||
        (detailed.detailsFailed && !activeRetry);
  }

  Widget _generatingCard(PlanItemDetailed detailed) {
    final activeRetry =
        _activeDetailJobId != null && _terminalDetailError == null;
    final catalogUnavailable =
        !activeRetry &&
        ((detailed.detailsFailed &&
                detailed.detailsStep == 'catalog_not_available') ||
            (_detailJob?.isFailed == true &&
                _detailJob?.step == 'catalog_not_available'));
    final bodyStyle = AppTypography.sans(
      13.5,
    ).copyWith(color: AppColors.ink2, height: 1.45);
    if (catalogUnavailable) {
      return _statusCard(
        children: [
          Text(
            'This lesson isn’t available yet.',
            style: AppTypography.sans(
              15,
              FontWeight.w600,
            ).copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'The learning materials and practice for this task aren’t ready. '
            'Retrying now won’t prepare them. Your completed work is saved.',
            style: bodyStyle,
          ),
          const SizedBox(height: 14),
          V3Button(
            size: V3Size.md,
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back to plan'),
          ),
        ],
      );
    }
    final failureMessage = _terminalDetailError ?? detailed.detailsError;
    if (_terminalDetailError != null ||
        (detailed.detailsFailed && !activeRetry)) {
      final hasReadyLessons = detailed.steps.any(
        (step) => step.lessonContent?.trim().isNotEmpty == true,
      );
      return _statusCard(
        children: [
          const V3Icon(V3Icons.alert, size: 22, color: AppColors.gold2),
          const SizedBox(height: 10),
          Text(
            hasReadyLessons
                ? 'Some lessons could not be prepared. Your ready lessons '
                      'and progress are saved.'
                : failureMessage ??
                      'This lesson could not be prepared. Please try again.',
            style: bodyStyle,
          ),
          const SizedBox(height: 14),
          V3Button(
            key: const Key('plan-detail-regenerate'),
            size: V3Size.md,
            icon: V3Icons.refresh,
            disabled: _retrying,
            onPressed: _retryDetails,
            child: Text(_retrying ? 'Restarting…' : 'Generate again'),
          ),
        ],
      );
    }
    if (_takingLong) {
      return _statusCard(
        children: [
          const V3Icon(V3Icons.clock, size: 22, color: AppColors.gold2),
          const SizedBox(height: 10),
          Text(
            detailed.isTutorialSequence
                ? '${_tutorialProgressCopy(detailed)} You can leave this screen and return later—your place is saved.'
                : 'This lesson is still being prepared in the background. You can '
                      'leave this screen and return later—your place is saved.',
            style: bodyStyle,
          ),
          const SizedBox(height: 14),
          V3Button(
            kind: V3ButtonKind.line,
            size: V3Size.md,
            icon: V3Icons.refresh,
            onPressed: _checkDetailsAgain,
            child: const Text('Check status'),
          ),
        ],
      );
    }

    final progress = (_detailJob?.progressPercent ?? detailed.detailsProgress)
        .clamp(0, 100);
    final step = _detailJob?.step ?? detailed.detailsStep;
    return _statusCard(
      children: [
        Row(
          children: [
            const V3Spinner(color: AppColors.ember, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                detailed.isTutorialSequence
                    ? _tutorialProgressCopy(detailed)
                    : _detailProgressCopy(step),
                style: bodyStyle,
              ),
            ),
            if (progress > 0) ...[
              const SizedBox(width: 8),
              Text(
                '$progress%',
                style: AppTypography.sans(
                  12.5,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink2).merge(AppTypography.tnum),
              ),
            ],
          ],
        ),
        if (progress > 0) ...[
          const SizedBox(height: 12),
          V3Bar(value: progress / 100, height: 4),
        ],
      ],
    );
  }

  Widget _statusCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// Shown only while the learner's own tutorial is not readable: tutorials
  /// are written one ahead, as the learner reaches them.
  String _tutorialProgressCopy(PlanItemDetailed detailed) {
    if (detailed.firstTutorialPreparing) {
      return 'Preparing your first tutorial…';
    }
    if (detailed.readyLessonCount == detailed.steps.length) {
      return 'All tutorials are ready. Finishing the learning materials…';
    }
    return 'Preparing your next tutorial…';
  }

  String _detailProgressCopy(String? step) {
    return switch (step) {
      'prefetch_queued' ||
      'user_priority' ||
      'loading_context' => 'Preparing the mentor context for your lesson…',
      'generating_curriculum' =>
        'Designing the right-sized lesson sequence and guided practice…',
      'generating_lessons' => 'Writing your first focused lesson…',
      'outline_ready' => 'The lesson sequence is ready. Writing lesson one…',
      'first_lesson_ready' =>
        'Lesson one is ready. Writing the remaining lessons…',
      'lessons_ready' =>
        'More lessons are ready. Finishing the remaining curriculum…',
      '2_lessons_ready' => 'Two lessons are ready. Finishing the last one…',
      '3_lessons_ready' => 'All lessons are ready. Checking materials…',
      'repairing_lessons' =>
        'Strengthening the lessons that missed a quality check…',
      'resolving_materials' => 'Checking and organizing your materials…',
      'finalizing_steps' => 'Finalizing the lesson sequence…',
      _ =>
        'Writing your lesson — steps and materials will appear here shortly.',
    };
  }

  // ── tutorial timeline ──────────────────────────────────────────────────

  /// [tutorialRowStates], with this screen's own view of a stop: a job that
  /// failed while polling stops preparation, and an explicit retry restarts
  /// it even while the loaded details still say "failed".
  List<TutorialRowState> _rowStates(PlanItemDetailed d) {
    final base = tutorialRowStates(d);
    final stopped = _preparationStopped(d);
    if (stopped == d.detailsFailed) return base;
    // A retry writes one ahead too: only the window's unwritten step.
    final writing = d.unwrittenWindowStepIndex;
    return [
      for (var i = 0; i < base.length; i++)
        if (base[i] == TutorialRowState.done || d.steps[i].hasContent)
          base[i]
        else if (!stopped)
          i == writing || !d.isTutorialSequence
              ? TutorialRowState.preparing
              : TutorialRowState.locked
        else if (i == d.activeStepIndex)
          TutorialRowState.stopped
        else
          TutorialRowState.locked,
    ];
  }

  Widget _timeline(PlanItemDetailed d, List<TutorialRowState> states) {
    final count = d.steps.length;
    final done = states.where((s) => s == TutorialRowState.done).length;
    final fill = count <= 1
        ? (done > 0 ? 1.0 : 0.0)
        : (done / (count - 1)).clamp(0.0, 1.0);
    final motion = MotionConfig.enabled(context);
    return Stack(
      children: [
        Positioned(
          key: const Key('tutorial-progress-line'),
          left: 21,
          top: 22,
          bottom: 22,
          width: 2,
          child: ColoredBox(
            color: AppColors.hair,
            child: Align(
              alignment: Alignment.topCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fill),
                duration: motion ? const Duration(seconds: 1) : Duration.zero,
                curve: AppMotion.out,
                builder: (context, value, _) => FractionallySizedBox(
                  heightFactor: value,
                  widthFactor: 1,
                  child: const ColoredBox(color: AppColors.sage),
                ),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++)
              V3Rise(
                key: ValueKey('rise-${d.steps[i].id}'),
                delay: Duration(milliseconds: i * 50),
                duration: const Duration(milliseconds: 500),
                child: _tutorialRow(d, i, states[i]),
              ),
          ],
        ),
      ],
    );
  }

  Widget _tutorialRow(PlanItemDetailed d, int index, TutorialRowState state) {
    final step = d.steps[index];
    final number = index + 1;
    final unit = step.isTutorial || d.isTutorialSequence
        ? 'Tutorial'
        : 'Lesson';
    final completed = d.isStepCompleted(step.id);
    final active = d.isStepUnlocked(index) && !completed;
    final open = step.hasContent ? () => _openLesson(d, step, index) : null;
    final onTap = switch (state) {
      TutorialRowState.done || TutorialRowState.current => open,
      TutorialRowState.preparing => () => showV3Toast(
        context,
        'Still being prepared and reviewed',
        icon: V3Icons.clock,
        tone: V3ToastTone.warn,
      ),
      TutorialRowState.locked => () {
        setState(() => _shakes[step.id] = (_shakes[step.id] ?? 0) + 1);
        showV3Toast(
          context,
          'Finish ${unit.toLowerCase()} ${d.activeStepIndex + 1} first',
          icon: V3Icons.lock,
          tone: V3ToastTone.warn,
        );
      },
      // "Generate again" sits in the status card above.
      TutorialRowState.stopped => null,
    };
    final label = switch (state) {
      TutorialRowState.done => '$unit $number: ${step.title}, done',
      TutorialRowState.current =>
        '$unit $number: ${step.title}, current. Continue',
      TutorialRowState.locked => '$unit $number: ${step.title}, locked',
      TutorialRowState.preparing =>
        step.title.trim().isEmpty
            ? '$unit $number, preparing and reviewing'
            : '$unit $number: ${step.title.trim()}, preparing and reviewing',
      TutorialRowState.stopped =>
        '$unit $number: ${step.title}, couldn’t be prepared',
    };
    return V3Pressable(
      key: Key(
        'lesson-$number-${completed
            ? 'completed'
            : active
            ? 'active'
            : 'locked'}',
      ),
      onTap: onTap,
      minTapTarget: 0,
      focusRadius: BorderRadius.circular(18),
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _tutorialDisc(step, state),
            const SizedBox(width: 14),
            Expanded(child: _tutorialBody(step, unit, number, state, open)),
          ],
        ),
      ),
    );
  }

  Widget _tutorialDisc(PlanStepDetail step, TutorialRowState state) {
    Widget plain(Color fill, Widget child, {bool border = false}) => Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: border ? Border.all(color: AppColors.hair2, width: 1.5) : null,
      ),
      child: child,
    );
    return switch (state) {
      TutorialRowState.done => plain(
        AppColors.sage,
        const V3Icon(
          V3Icons.check,
          size: 18,
          strokeWidth: 2.8,
          color: Colors.white,
        ),
      ),
      TutorialRowState.current => const TutorialGlowDisc(
        size: 44,
        child: V3Icon(V3Icons.play, size: 16, color: Colors.white),
      ),
      TutorialRowState.preparing => plain(
        AppColors.card,
        const V3Spinner(color: AppColors.ink3, size: 16),
        border: true,
      ),
      TutorialRowState.stopped => plain(
        AppColors.card,
        const V3Icon(V3Icons.alert, size: 16, color: AppColors.gold2),
        border: true,
      ),
      TutorialRowState.locked => plain(
        AppColors.card,
        TutorialShake(
          tick: _shakes[step.id] ?? 0,
          child: const V3Icon(V3Icons.lock, size: 16, color: AppColors.ink3),
        ),
        border: true,
      ),
    };
  }

  Widget _tutorialBody(
    PlanStepDetail step,
    String unit,
    int number,
    TutorialRowState state,
    VoidCallback? open,
  ) {
    final small = AppTypography.sans(12).copyWith(color: AppColors.ink3);
    if (state == TutorialRowState.preparing) {
      final title = step.title.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The outline title when the syllabus has one; else the design's
          // skeleton line.
          if (title.isEmpty)
            const FractionallySizedBox(
              widthFactor: 0.7,
              child: V3Skel(height: 14),
            )
          else
            Text(
              title,
              style: AppTypography.sans(
                15.5,
                FontWeight.w500,
              ).copyWith(color: AppColors.ink2, height: 1.3),
            ),
          const SizedBox(height: 6),
          Text('$unit $number · preparing and reviewing', style: small),
        ],
      );
    }
    final current = state == TutorialRowState.current;
    final minutes = _minutesLine(step);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state == TutorialRowState.stopped
              ? '$unit $number · couldn’t be prepared'
              : '$unit $number',
          style: AppTypography.sans(
            12,
            FontWeight.w600,
          ).copyWith(color: AppColors.ink3),
        ),
        const SizedBox(height: 2),
        Text(
          step.title,
          style:
              AppTypography.sans(
                15.5,
                current ? FontWeight.w600 : FontWeight.w500,
              ).copyWith(
                color: state == TutorialRowState.locked
                    ? AppColors.ink2
                    : AppColors.ink,
                height: 1.3,
              ),
        ),
        if (state == TutorialRowState.stopped) ...[
          const SizedBox(height: 3),
          Text(
            'Your outline is saved. Check the status above for next steps.',
            style: small.copyWith(height: 1.4),
          ),
        ] else if (minutes != null) ...[
          const SizedBox(height: 3),
          Text(minutes, style: small.merge(AppTypography.tnum)),
        ],
        if (current) ...[
          const SizedBox(height: 12),
          V3Button(
            size: V3Size.sm,
            icon: V3Icons.play,
            onPressed: open,
            child: const Text('Continue'),
          ),
        ],
      ],
    );
    if (!current) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hair),
      ),
      child: content,
    );
  }

  /// "{read} min read + {prac} min practice", or whichever half is known.
  String? _minutesLine(PlanStepDetail step) {
    final read = step.effectiveReadingMinutes;
    final practice = step.effectivePracticeMinutes;
    return switch ((read, practice)) {
      (final r?, final p?) => '$r min read + $p min practice',
      (final r?, null) => '$r min read',
      (null, final p?) => '$p min practice',
      _ => null,
    };
  }

  Future<void> _openLesson(
    PlanItemDetailed detailed,
    PlanStepDetail step,
    int index,
  ) async {
    final changed = await openLessonReader(
      context,
      ref,
      detailed,
      index,
      shellBranchIndex: widget.shellBranchIndex,
    );
    if (!mounted) return;
    // Returning after a long reading/practice session starts a new foreground
    // window even if the learner backed out without completing the tutorial.
    await _load(resetPolling: true);
    if (!mounted) return;
    if (changed) {
      final next = index + 1 < detailed.steps.length
          ? (_detailed ?? detailed).steps.elementAtOrNull(index + 1)
          : null;
      showV3Toast(
        context,
        index == detailed.steps.length - 1
            ? 'Mission complete.'
            : step.isTutorial
            ? (next == null || next.hasContent
                  ? 'Tutorial complete. Your next tutorial is unlocked.'
                  : 'Tutorial complete. Your next one is being prepared.')
            : 'Lesson complete. The next lesson is unlocked.',
        icon: V3Icons.check,
        tone: V3ToastTone.success,
      );
    }
  }

  Future<BookReadingAccess> _checkBookAccess(PlanMaterialDetail material) {
    final key = _bookPreparationKey(material);
    final cached = _bookAccess[key];
    if (cached != null) return Future.value(cached);
    return _bookAccessFlights.putIfAbsent(key, () async {
      try {
        final access = await ref
            .read(planRepositoryProvider)
            .resolveBookReadingAccess(
              material.canonicalKey ?? '',
              material.title,
              material.authorOrCreator,
            );
        if (mounted) {
          setState(() {
            _bookAccess[key] = access;
            if (access.resourceId != null) {
              _resolvedBookGuideIds[material.canonicalKey ?? ''] =
                  access.resourceId!;
            }
          });
          _accessRevision.value++;
        }
        return access;
      } finally {
        _bookAccessFlights.remove(key);
      }
    });
  }

  /// Open a material in-app: YouTube player for videos, chaptered book
  /// reader for books backed by a shared resource (full public-domain text
  /// or LLM module), markdown reader for lessons, web view for plain links.
  Future<void> _openMaterial(PlanMaterialDetail m) async {
    final videoId = m.youtubeVideoId;
    final canonicalKey = (m.canonicalKey ?? '').trim();
    final preparationKey = _bookPreparationKey(m);
    var bookResourceId = _bookResourceId(m);
    BookReadingSource? readingSource;
    if (m.type == 'book' && bookResourceId == null && m.directUrl == null) {
      if (_preparingBookGuideKeys.contains(preparationKey)) return;
      setState(() => _preparingBookGuideKeys.add(preparationKey));
      try {
        final repository = ref.read(planRepositoryProvider);
        final access = await _checkBookAccess(m);
        bookResourceId = access.resourceId;
        readingSource = access.source;
        if (bookResourceId == null && readingSource == null) {
          if (access.unavailable != null) throw access.unavailable!;
          bookResourceId = await repository.waitForContentResourceId(
            canonicalKey,
          );
          // A subsequent check may see the completed job or its final status.
          _bookAccess.remove(preparationKey);
        }
      } on BookGuideUnavailableException catch (error) {
        if (!mounted) return;
        setState(() => _preparingBookGuideKeys.remove(preparationKey));
        showV3Toast(
          context,
          error.message,
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() => _preparingBookGuideKeys.remove(preparationKey));
        showV3Toast(
          context,
          'Could not open the book. Try again.',
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _preparingBookGuideKeys.remove(preparationKey);
        if (bookResourceId != null) {
          _resolvedBookGuideIds[canonicalKey] = bookResourceId;
        }
      });
      if (bookResourceId == null && readingSource == null) {
        showV3Toast(
          context,
          'The book is not available yet. Try another resource or check again later.',
          icon: V3Icons.clock,
          tone: V3ToastTone.warn,
        );
        return;
      }
    }
    Widget? screen;
    final missionTitle = _detailed?.item.title.trim() ?? '';
    final openedFrom = missionTitle.isEmpty ? null : 'Mission · $missionTitle';
    if (videoId != null) {
      screen = MaterialVideoScreen(material: m, videoId: videoId);
    } else if (m.type == 'book' && bookResourceId != null) {
      screen = BookReaderScreen(
        resourceId: bookResourceId,
        fallbackTitle: m.title,
        fallbackSourceUrl: m.directUrl,
        shellBranchIndex: widget.shellBranchIndex,
      );
    } else if (readingSource != null) {
      screen = MaterialWebScreen(
        title: m.title,
        url: readingSource.url,
        sourceDescription: readingSource.description,
        initialSectionTitle: readingSource.sectionTitle,
        access: readingSource.scope == 'excerpt'
            ? AccessType.excerpt
            : AccessType.original,
        openedFrom: openedFrom,
      );
    } else if (m.prefersExternalLink) {
      screen = MaterialWebScreen(
        title: m.title,
        url: m.directUrl!,
        access: AccessType.web,
        openedFrom: openedFrom,
      );
    } else if (m.hasInAppContent) {
      screen = MaterialReaderScreen(material: m);
    } else if (m.directUrl != null) {
      screen = MaterialWebScreen(
        title: m.title,
        url: m.directUrl!,
        access: AccessType.web,
        openedFrom: openedFrom,
      );
    }
    if (screen == null) return;
    final route = CmpysPageRoute<void>(builder: (_) => screen!);
    // Books remain inside the state-preserving Plan branch so narration keeps
    // playing when another tab is selected. Other material viewers still own
    // the whole display above the shell.
    final navigator = screen is BookReaderScreen
        ? Navigator.of(context)
        : Navigator.of(context, rootNavigator: true);
    navigator.push(route);
  }

  String? _bookResourceId(PlanMaterialDetail material) {
    final directId = material.contentResourceId?.trim();
    if (directId != null && directId.isNotEmpty) return directId;
    final canonicalKey = material.canonicalKey?.trim();
    if (canonicalKey == null || canonicalKey.isEmpty) return null;
    return _resolvedBookGuideIds[canonicalKey];
  }

  String _bookPreparationKey(PlanMaterialDetail material) {
    final key = material.canonicalKey?.trim();
    return key != null && key.isNotEmpty
        ? key
        : 'original:${material.title}:${material.authorOrCreator ?? ""}';
  }

  bool _isPreparingBookGuide(PlanMaterialDetail material) =>
      _preparingBookGuideKeys.contains(_bookPreparationKey(material));

  // ── materials ──────────────────────────────────────────────────────────

  AccessType _accessType(PlanMaterialDetail m) => accessTypeForMaterial(
    m,
    resolvedGuideId: _bookResourceId(m),
    bookAccess: _bookAccess[_bookPreparationKey(m)],
  );

  /// A book whose reading access the screen has not resolved yet (the same
  /// books [_load] checks).
  bool _accessUnresolved(PlanMaterialDetail m) =>
      m.type == 'book' &&
      _bookResourceId(m) == null &&
      m.directUrl == null &&
      _bookAccess[_bookPreparationKey(m)] == null;

  Widget _materialRow(PlanMaterialDetail m) {
    final preparing = _isPreparingBookGuide(m);
    final checking = _checkingAccessKeys.contains(_bookPreparationKey(m));
    return MaterialRow(
      material: m,
      type: _accessType(m),
      preparing: preparing,
      checking: checking,
      // Single flight: a guide being prepared, or a sheet waiting on its
      // access check, is not opened again.
      onTap: preparing || checking ? null : () => _showMaterialSheet(m),
    );
  }

  /// `MaterialSheet`: why the material is here, what CMPYS can show of it,
  /// and its one action, which runs [_openMaterial] once the sheet closes.
  ///
  /// A book whose access is still being checked waits for that check (at
  /// most [_accessWait], with the row's spinner) so the sheet names what its
  /// CTA opens; a slower check updates the open sheet when it lands. If this
  /// page is no longer on top when the wait ends, the sheet does not open.
  Future<void> _showMaterialSheet(PlanMaterialDetail m) async {
    final key = _bookPreparationKey(m);
    if (_accessUnresolved(m)) {
      setState(() => _checkingAccessKeys.add(key));
      try {
        await _checkBookAccess(m).timeout(_accessWait);
      } catch (_) {
        // Slow or failed: open on what is known; the sheet follows the check.
      }
      if (!mounted) return;
      setState(() => _checkingAccessKeys.remove(key));
      // The learner may have moved on during the wait (another page is over
      // this one): never open the sheet on top of it.
      if (ModalRoute.of(context)?.isCurrent != true) return;
    }
    final open = await showV3Sheet<bool>(
      context,
      builder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: _accessRevision,
        builder: (context, _, _) => _materialSheetBody(sheetContext, m),
      ),
    );
    if (open == true && mounted) await _openMaterial(m);
  }

  Widget _materialSheetBody(BuildContext sheetContext, PlanMaterialDetail m) =>
      MaterialSheetBody(
        material: m,
        type: _accessType(m),
        onOpen: () => Navigator.of(sheetContext).pop(true),
      );
}

/// The mental model card with the farm images (`ModelCard` in
/// `v3/plan.jsx`; owner ruling: farm models only).
///
/// - Once 30% of the card is on screen it is "seen" (once).
/// - A 210 pt image area opens (`height .8s var(--out)`) as soon as one
///   image has loaded; until then, and for good if neither loads, it is the
///   text-only card.
/// - Both images loaded: one shows at a time and they crossfade every 6 s
///   (`opacity 1.6s var(--io)`). Before seen both sit at 1.15; after, the
///   shown one settles to 1.0 and the hidden one to 1.08, over 7 s on
///   `cubic-bezier(.2,.6,.3,1)`.
/// - A gradient, a frosted "Mental model" tag, then the title (fades and
///   rises 10 pt, `.8s var(--out) .2s`) and the description (`opacity .8s
///   .35s`), revealed once seen.
/// - Reduced motion: one static image, no crossfade or zoom, text shown.
class _MentalModelFarmCard extends StatefulWidget {
  const _MentalModelFarmCard(this.model);

  final ({String? title, String body}) model;

  /// Keys for tests.
  static const imageAreaKey = Key('mental-model-images');
  static const tagKey = Key('mental-model-tag');

  @override
  State<_MentalModelFarmCard> createState() => _MentalModelFarmCardState();
}

const _farmImages = [
  AppAssets.imageMentalModelFarmA,
  AppAssets.imageMentalModelFarmB,
];

/// `transform 7s cubic-bezier(.2,.6,.3,1)`.
const Cubic _slowZoom = Cubic(0.2, 0.6, 0.3, 1);

class _MentalModelFarmCardState extends State<_MentalModelFarmCard>
    with SingleTickerProviderStateMixin {
  // Title at .2 s and description at .35 s, each .8 s: 1.15 s in all.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );
  final List<bool> _loaded = [false, false];
  final List<bool> _failed = [false, false];
  bool _seen = false;
  bool _motion = true;
  int _active = 0;
  Timer? _crossfade;
  ScrollPosition? _scroll;

  bool get _bothLoaded => _loaded[0] && _loaded[1];
  bool get _anyLoaded => _loaded[0] || _loaded[1];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionConfig.enabled(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _scroll)) {
      _scroll?.removeListener(_onScroll);
      _scroll = _seen ? null : position;
      _scroll?.addListener(_onScroll);
    }
    if (!_motion) {
      _reveal.value = 1;
      _crossfade?.cancel();
      _crossfade = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSeen());
  }

  @override
  void dispose() {
    _scroll?.removeListener(_onScroll);
    _crossfade?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  bool _checkQueued = false;

  /// A scroll moved the card: check once the frame has laid it out.
  void _onScroll() {
    if (_checkQueued || _seen) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _checkSeen();
    });
  }

  /// `IntersectionObserver` at .3, once: at least 30% of the card's height
  /// inside the screen and every enclosing scroll view.
  void _checkSeen() {
    if (_seen || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (box.size.height <= 0) return;
    final card = box.localToGlobal(Offset.zero) & box.size;
    var visible = card.intersect(Offset.zero & MediaQuery.sizeOf(context));
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    ) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) continue;
      visible = visible.intersect(
        viewport.localToGlobal(Offset.zero) & viewport.size,
      );
    }
    if (visible.width <= 0 || visible.height < card.height * .3) return;
    setState(() => _seen = true);
    _scroll?.removeListener(_onScroll);
    _scroll = null;
    if (_motion) _reveal.forward();
    _syncCrossfade();
  }

  void _syncCrossfade() {
    if (!_motion || !_bothLoaded) {
      _crossfade?.cancel();
      _crossfade = null;
      return;
    }
    _crossfade ??= Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _active = 1 - _active);
    });
  }

  void _onLoaded(int i) {
    if (_loaded[i] || _failed[i]) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loaded[i]) return;
      setState(() => _loaded[i] = true);
      _syncCrossfade();
      // The card grew: it may be seen now.
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkSeen());
    });
  }

  void _onFailed(int i) {
    if (_failed[i]) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _failed[i]) return;
      setState(() {
        _failed[i] = true;
        _loaded[i] = false;
      });
      _syncCrossfade();
    });
  }

  /// Whether image [i] is the one showing.
  bool _shows(int i) {
    if (!_loaded[i]) return false;
    if (!_motion) return i == (_loaded[0] ? 0 : 1);
    return _bothLoaded ? i == _active : true;
  }

  double _scaleOf(int i) {
    if (!_motion) return 1;
    if (!_seen) return 1.15;
    return _shows(i) ? 1 : 1.08;
  }

  Widget _image(int i) {
    // Reduced motion keeps one image: the second is never built unless the
    // first has failed.
    return AnimatedOpacity(
      key: ValueKey('mental-model-image-$i'),
      opacity: _shows(i) ? 1 : 0,
      duration: _motion ? const Duration(milliseconds: 1600) : Duration.zero,
      curve: AppMotion.io,
      child: AnimatedScale(
        scale: _scaleOf(i),
        duration: _motion ? const Duration(seconds: 7) : Duration.zero,
        curve: _slowZoom,
        child: Image.asset(
          _farmImages[i],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, sync) {
            if (frame != null || sync) _onLoaded(i);
            return child;
          },
          errorBuilder: (context, error, stack) {
            _onFailed(i);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _tag() {
    return ClipRRect(
      key: _MentalModelFarmCard.tagKey,
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // rgba(14,12,20,.55)
          color: const Color(0x8C0E0C14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const V3Icon(V3Icons.sparkle, size: 12, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Mental model',
                style: AppTypography.sans(
                  11.5,
                  FontWeight.w600,
                ).copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageArea(double height) {
    const overlap = 26.0;
    return SizedBox(
      key: _MentalModelFarmCard.imageAreaKey,
      // The text starts 26 pt above the images' bottom (`margin-top: -26`).
      height: math.max(0, height - overlap),
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: height,
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < _farmImages.length; i++)
                if (_motion || i == 0 || _failed[0]) _image(i),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x590E0C14),
                        Color(0x000E0C14),
                        Color(0x990E0C14),
                        AppColors.night,
                      ],
                      stops: [0, .35, .75, 1],
                    ),
                  ),
                ),
              ),
              if (_anyLoaded) Positioned(left: 16, top: 14, child: _tag()),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final shown = _anyLoaded;
    final titleIn = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(200 / 1150, 1000 / 1150, curve: AppMotion.out),
    );
    final bodyIn = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(350 / 1150, 1, curve: Curves.ease),
    );
    final text = shown
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (model.title case final title?)
                  AnimatedBuilder(
                    animation: titleIn,
                    builder: (context, child) => Opacity(
                      opacity: titleIn.value,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - titleIn.value)),
                        child: child,
                      ),
                    ),
                    child: Text(
                      title,
                      style: AppTypography.display(
                        30,
                      ).copyWith(color: Colors.white),
                    ),
                  ),
                if (model.body.isNotEmpty) ...[
                  SizedBox(height: model.title == null ? 0 : 8),
                  FadeTransition(
                    opacity: bodyIn,
                    child: Text(
                      model.body,
                      style: AppTypography.read(
                        15,
                      ).copyWith(color: AppColors.nink2, height: 1.55),
                    ),
                  ),
                ],
              ],
            ),
          )
        : null;

    return ClipRRect(
      key: const Key('mental-model-card'),
      borderRadius: AppRadii.brR,
      child: ColoredBox(
        color: AppColors.night,
        child: Stack(
          children: [
            const Positioned.fill(child: V3Grain()),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: shown ? 210 : 0),
                  duration: _motion
                      ? const Duration(milliseconds: 800)
                      : Duration.zero,
                  curve: AppMotion.out,
                  builder: (context, height, _) => _imageArea(height),
                ),
                text ?? _MentalModelText(model),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The text-only card's content (kicker, title, body), shared by the text
/// card and a farm card whose images haven't loaded.
class _MentalModelText extends StatelessWidget {
  const _MentalModelText(this.model);

  final ({String? title, String body}) model;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MENTAL MODEL',
            style: AppTypography.kick.copyWith(color: _irisLight),
          ),
          if (model.title case final title?) ...[
            const SizedBox(height: 8),
            Text(
              title,
              style: AppTypography.display(28).copyWith(color: Colors.white),
            ),
          ],
          if (model.body.isNotEmpty) ...[
            SizedBox(height: model.title == null ? 8 : 6),
            Text(
              model.body,
              style: AppTypography.read(
                15,
              ).copyWith(color: AppColors.nink2, height: 1.55),
            ),
          ],
        ],
      ),
    );
  }
}
