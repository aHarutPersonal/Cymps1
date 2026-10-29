import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/assets.dart';
import '../../../../app/design_tokens.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/ui/motion/motion_config.dart';
import '../../../../core/ui/v3/v3.dart';
import '../../../plan/data/plan_repository.dart';
import '../../../plan/models/plan_models.dart';
import '../../../session/data/session_repository.dart';
import '../../data/cmpys_seed.dart';
import '../../state/plan_providers.dart' show planSupportsPeek;
import 'mentor_image.dart';
import 'results_streamer.dart';

/// Post-interview transition (`v3/onboard2.jsx` `Lab`) that runs the complete
/// results pipeline while the learner watches five stages land.
///
/// Comparison and blueprint are generated first because they are required
/// strategic inputs to the plan. The staged plan job is dispatched alongside
/// them and polled until the actual 12-week plan is persisted. Entry is
/// enabled only at that point, never after an arbitrary animation or delay.
///
/// Stage signals (all real; nothing is timed):
/// 1. Written comparison: the `comparison` section of the results stream. It
///    is done once the `blueprint` section starts (the server saves the
///    comparison first).
/// 2. Dimension assessment: the stream's `comparison_scores` event.
/// 3. Strategic blueprint: the `blueprint` section, done when the stream moves
///    past it (`comparison_scores`, or the end of the stream).
/// 4. Plan backbone: the `plan_job` event, then job polling: running once the
///    job reports progress, done at step `preparing_current_week`, 95 % or
///    completion (the plan rows exist by then).
/// 5. Tutorial 1: done only when the job reports a ready lesson (a ready
///    count, or a `first_lesson_ready` / `lessons_ready` step). A plan job
///    that completes without one leaves it in progress, "Preparing — it’ll
///    open on Today": the lessons are prepared by per-item jobs the lab
///    cannot see, and the learner enters the app either way. Once per visit
///    the lab then peeks mission 1 (`?peek=true`, a pure read that never
///    starts generation, and only on a server that can peek): a written
///    first tutorial ticks the stage after all.
class CmpysMentorLabStep extends ConsumerStatefulWidget {
  const CmpysMentorLabStep({
    super.key,
    required this.idol,
    required this.draft,
    required this.onDone,
    this.onPlan,
  });

  final CmpysIdol idol;
  final CmpysOnboardingDraft draft;

  /// "Go to Today": enter the app on the home tab.
  final VoidCallback onDone;

  /// "See the full plan": enter the app on the plan tab. Falls back to
  /// [onDone] when the host has no separate destination.
  final VoidCallback? onPlan;

  @override
  ConsumerState<CmpysMentorLabStep> createState() => _CmpysMentorLabStepState();
}

enum _StageState { wait, run, done, fail }

/// Indices into the five stages, in display order.
const int _cmp = 0, _dim = 1, _bp = 2, _plan = 3, _t1 = 4;

const List<String> _stageIds = ['cmp', 'dim', 'bp', 'plan', 't1'];
const List<String> _stageTitles = [
  'Written comparison',
  'Dimension assessment',
  'Strategic blueprint',
  'Plan backbone',
  'Tutorial 1',
];

/// `oklch(0.8 0.1 285)`, `oklch(0.82 0.1 42)` and `oklch(0.7 0.14 285)` in sRGB.
const Color _irisLight = Color(0xFFB7B5FC);
const Color _emberLight = Color(0xFFFCAF91);
const Color _haloColor = Color(0xFF9690F1);

/// Over the lab video: `linear-gradient(180deg, rgba(14,12,20,.55) 0%,
/// rgba(14,12,20,.25) 28%, rgba(14,12,20,.7) 55%, rgba(14,12,20,.92) 100%)`.
const LinearGradient _labVideoShade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x8C0E0C14),
    Color(0x400E0C14),
    Color(0xB30E0C14),
    Color(0xEB0E0C14),
  ],
  stops: [0, 0.28, 0.55, 1],
);

class _CmpysMentorLabStepState extends ConsumerState<CmpysMentorLabStep>
    with WidgetsBindingObserver {
  Timer? _jobTimer;
  Timer? _retryTimer;

  /// The user-facing line for the failing stage, and which stage that is.
  String? _error;
  int? _failedStage;
  bool _connectionInterrupted = false;
  int _retrySeconds = 0;
  String? _pollingJobId;
  bool _checkingJob = false;
  bool _starting = false;
  bool _jobCompleted = false;
  bool _planReady = false;
  bool _jobFailed = false;
  bool _resultsComplete = false;
  int _pollFailures = 0;
  int _attempt = 0;

  // Stage signals. The first three survive a retry: the server has saved them.
  bool _comparisonDone = false;
  bool _scoresDone = false;
  bool _blueprintDone = false;
  bool _planStarted = false;
  bool _backboneDone = false;
  bool _tutorialDone = false;
  int? _totalLessons;
  int? _planWeeklyMinutes;
  bool _factsRequested = false;

  /// Mission 1 has been peeked for a ready Tutorial 1 (once per visit).
  bool _tutorialPeeked = false;

  /// The background video is playing (its shade and grain show).
  bool _videoPlaying = false;

  /// The background video gave up (error or timeout): the lab stays as it
  /// was before the video, cards included.
  bool _videoFailed = false;

  /// The footer's measured height: the scroll body leaves exactly that much
  /// room at its end so the last card can scroll clear of the buttons.
  final GlobalKey _footerKey = GlobalKey();
  double _footerHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resultsComplete =
        !widget.draft.resultsFailed &&
        widget.draft.comparisonMd?.trim().isNotEmpty == true &&
        widget.draft.blueprintMd?.trim().isNotEmpty == true;
    _comparisonDone = _scoresDone = _blueprintDone = _resultsComplete;
    _startPipeline();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _jobTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final jobId = _pollingJobId;
      if (jobId != null && !_planReady && !_jobFailed && !_jobCompleted) {
        _startJobPolling(jobId, reconnect: true);
      }
    }
  }

  // ── Failure bookkeeping ────────────────────────────────────────────────────

  /// "…Earlier steps are saved." in the design's wording, for [stage].
  String _failureLine(int stage, {bool connection = false}) {
    final saved = stage == _cmp
        ? 'Your answers are saved.'
        : 'Earlier steps are saved.';
    if (connection) return 'The connection dropped. $saved';
    final what = switch (stage) {
      _cmp => 'The comparison didn’t finish.',
      _dim => 'The dimension assessment didn’t finish.',
      _bp => 'The blueprint request didn’t finish.',
      _plan => 'The plan backbone didn’t finish.',
      _ => 'The first tutorial didn’t finish.',
    };
    return '$what $saved';
  }

  /// The stage a results-stream failure belongs to when the server did not say.
  int _streamFrontier() {
    if (!_comparisonDone) return _cmp;
    if (!_blueprintDone) return _bp;
    if (!_scoresDone) return _dim;
    return _plan;
  }

  int _stageForSection(String? section) => switch (section) {
    'comparison' => _cmp,
    'blueprint' => _bp,
    'plan' => _plan,
    _ => _streamFrontier(),
  };

  int get _planFailureStage => _backboneDone ? _t1 : _plan;

  // ── Pipeline ──────────────────────────────────────────────────────────────

  Future<void> _startPipeline() async {
    final sessionId = widget.draft.sessionId;
    if (sessionId == null || _starting || _retrySeconds > 0) {
      if (sessionId == null && mounted) {
        setState(() {
          _failedStage = _cmp;
          _error = 'No active session. Go back and try again.';
        });
      }
      return;
    }

    _jobTimer?.cancel();
    _jobTimer = null;
    _pollingJobId = null;
    final attempt = ++_attempt;
    final savedJob = widget.draft.planJobId;
    final recoverPlan =
        _resultsComplete &&
        (_jobFailed || savedJob == null || savedJob.isEmpty);
    var requestStage = 'results';
    setState(() {
      _starting = true;
      _jobCompleted = false;
      _planReady = false;
      _error = null;
      _failedStage = null;
      _connectionInterrupted = false;
      _pollFailures = 0;
      _jobFailed = false;
      // A failed attempt may have reached a later stage than its valid saved
      // work. The plan stages restart from the results boundary; the next
      // server status restores any further progress that actually survived.
      // The comparison, scores and blueprint the server already saved stay done.
      // With the results saved, the plan is the only work left, so it runs.
      _planStarted = _resultsComplete;
      _backboneDone = false;
      _tutorialDone = false;
      _factsRequested = false;
      widget.draft.resultsFailed = false;
    });

    try {
      if (recoverPlan) {
        requestStage = 'saved_session';
        var idolId = widget.draft.backendIdolId;
        var targetAge = widget.draft.age;
        if (idolId == null || idolId.isEmpty) {
          // Older drafts may not retain the server mentor identity. New
          // restores and intake completion already have it, so restarting a
          // failed plan does not depend on another session read.
          final session = await ref
              .read(sessionRepositoryProvider)
              .getSession(sessionId);
          if (!mounted || attempt != _attempt) return;
          idolId = session.selectedIdol?.id;
          targetAge = session.userAge;
          widget.draft.backendIdolId = idolId;
        }
        if (idolId == null || idolId.isEmpty) {
          throw StateError('Missing mentor');
        }
        requestStage = 'plan_restart';
        final jobId = await ref
            .read(planRepositoryProvider)
            .generatePlan(
              idolId: idolId,
              targetAge: targetAge,
              sessionId: sessionId,
            );
        if (!mounted || attempt != _attempt) return;
        if (jobId.isEmpty) throw StateError('Missing plan job');
        widget.draft.planJobId = jobId;
        _startJobPolling(jobId);
        return;
      }
      if (_resultsComplete && savedJob?.isNotEmpty == true) {
        _startJobPolling(savedJob!);
        return;
      }
      await streamGenerateResults(
        repo: ref.read(sessionRepositoryProvider),
        sessionId: sessionId,
        onSection: (section) {
          // The server saves the comparison before it opens the blueprint.
          if (section == 'blueprint' && mounted && attempt == _attempt) {
            setState(() => _comparisonDone = true);
          }
        },
        onComparison: (value) {
          widget.draft.comparisonMd = value;
          if (mounted && attempt == _attempt) setState(() {});
        },
        onBlueprint: (value) {
          widget.draft.blueprintMd = value;
          if (mounted && attempt == _attempt) setState(() {});
        },
        onPlanJob: (jobId) {
          widget.draft.planJobId = jobId;
          _startJobPolling(jobId);
        },
        onComparisonScores: (_) {
          // Best effort on the server: `ready: false` is retried there, and
          // must not hold the learner up. The scores follow the blueprint.
          if (!mounted || attempt != _attempt) return;
          setState(() => _comparisonDone = _blueprintDone = _scoresDone = true);
          _markReadyIfComplete();
        },
        onDone: () {
          // The server's own end-of-pipeline signal: every result is saved.
          if (!mounted || attempt != _attempt) return;
          widget.draft.resultsFailed = false;
          setState(() {
            _starting = false;
            _resultsComplete = true;
            _comparisonDone = _blueprintDone = _scoresDone = true;
          });
          _markReadyIfComplete();
        },
      );
      if (!mounted || attempt != _attempt) return;
      _resultsComplete = true;
      widget.draft.resultsFailed = false;
      setState(() => _comparisonDone = _blueprintDone = _scoresDone = true);
      _markReadyIfComplete();
      final jobId = widget.draft.planJobId;
      if (jobId == null || jobId.isEmpty) {
        throw StateError('The plan job was not created.');
      }
      if (!_planReady) _startJobPolling(jobId);
    } catch (e) {
      if (!mounted || attempt != _attempt || _planReady) return;
      // Log only diagnostic metadata, never the session, answers, response
      // body, or credentials. A server error during the saved-session lookup
      // must be distinguishable from a plan dispatch failure.
      debugPrint(
        'Mentor lab request failed: stage=$requestStage type=${e.runtimeType}'
        '${e is ResultsGenerationException ? ' code=${e.code}' : ''}'
        '${e is ApiError ? ' status=${e.statusCode} code=${e.code}' : ''}',
      );
      widget.draft.resultsFailed = true;
      // A running plan remains recoverable even if the results connection
      // closes. Do not discard its polling handle.
      if (recoverPlan) _jobFailed = true;
      if (e is ResultsGenerationException) {
        // The plan cannot run before its strategy exists. Keep the saved job
        // identity, but stop polling its waiting state until an explicit retry.
        _jobTimer?.cancel();
        _jobTimer = null;
        _pollingJobId = null;
        _retrySeconds = e.retryAfterSeconds;
        _retryTimer?.cancel();
        if (_retrySeconds > 0) {
          _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) return timer.cancel();
            setState(() => _retrySeconds--);
            if (_retrySeconds <= 0) timer.cancel();
          });
        }
      }
      // The server dispatches the plan only after saving the comparison, so
      // a plan section failure leaves the comparison done (not "waiting").
      if (e is ResultsGenerationException && e.section == 'plan') {
        _comparisonDone = true;
      }
      final interrupted =
          e is NetworkError || e is TimeoutError || e is TimeoutException;
      final stage = switch (requestStage) {
        'saved_session' || 'plan_restart' => _plan,
        _ when e is ResultsGenerationException => _stageForSection(e.section),
        _ => _streamFrontier(),
      };
      setState(() {
        _connectionInterrupted = interrupted;
        _failedStage = stage;
        _error = switch (requestStage) {
          'saved_session' =>
            'Your saved session couldn’t be loaded. Your answers are safe. Try again.',
          'plan_restart' =>
            'Your plan couldn’t restart. Your progress is saved. Try again.',
          _
              when e is ResultsGenerationException &&
                  (e.code == 'generation_unavailable' ||
                      e.code == 'generation_rate_limited') =>
            e.message,
          _ => _failureLine(stage, connection: interrupted),
        };
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _startJobPolling(String jobId, {bool reconnect = false}) {
    if (_planReady ||
        (!reconnect &&
            _pollingJobId == jobId &&
            (_jobTimer?.isActive ?? false))) {
      return;
    }
    _jobTimer?.cancel();
    _pollingJobId = jobId;
    _jobTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPlanJob(jobId),
    );
    _checkPlanJob(jobId);
  }

  Future<void> _checkPlanJob(String jobId) async {
    if (_checkingJob || !mounted || _planReady) return;
    _checkingJob = true;
    try {
      final job = await ref.read(planRepositoryProvider).getJobStatus(jobId);
      if (!mounted || _pollingJobId != jobId) return;
      if (_pollFailures > 0) {
        _pollFailures = 0;
        if (_failedStage == _plan || _failedStage == _t1) {
          setState(() {
            _error = null;
            _failedStage = null;
          });
        }
      }
      if (job.isCompleted) {
        _jobCompleted = true;
        // Terminal: stop polling it, even when the results stream dropped
        // and the plan is not ready to enter yet.
        _jobTimer?.cancel();
        _jobTimer = null;
        setState(() {
          _planStarted = _backboneDone = true;
          // Tutorial 1 is ready only when the job says so; a finished plan
          // job alone does not mean its first lesson passed review.
          _tutorialDone = _tutorialDone || _firstLessonReady(job);
          _totalLessons = job.totalLessonCount ?? _totalLessons;
        });
        _requestPlanFacts();
        _markReadyIfComplete();
        if (!_tutorialDone) unawaited(_peekFirstTutorial());
      } else if (job.isFailed) {
        _jobTimer?.cancel();
        _jobTimer = null;
        _jobFailed = true;
        setState(() {
          _failedStage = _planFailureStage;
          _error = _failureLine(_planFailureStage);
        });
      } else {
        // The plan rows exist once the job reaches its publishing step.
        final backbone =
            job.step == 'preparing_current_week' || job.progressPercent >= 95;
        final firstLesson = _firstLessonReady(job);
        final started =
            job.status == 'running' || job.progressPercent > 0 || backbone;
        final total = job.totalLessonCount ?? _totalLessons;
        if ((started && !_planStarted) ||
            (backbone && !_backboneDone) ||
            (firstLesson && !_tutorialDone) ||
            total != _totalLessons) {
          setState(() {
            _planStarted = _planStarted || started;
            _backboneDone = _backboneDone || backbone || firstLesson;
            _tutorialDone = _tutorialDone || firstLesson;
            _totalLessons = total;
          });
        }
        if (_backboneDone) _requestPlanFacts();
      }
    } catch (error) {
      if (!mounted || _pollingJobId != jobId) return;
      _pollFailures++;
      if (error is ApiError && error.statusCode == 404) {
        _jobTimer?.cancel();
        _jobTimer = null;
        _jobFailed = true;
        setState(() {
          _failedStage = _planFailureStage;
          _error =
              'Your saved plan needs to be reconnected. Your answers are safe.';
        });
      } else if (_pollFailures >= 3) {
        _jobTimer?.cancel();
        _jobTimer = null;
        setState(() {
          _connectionInterrupted =
              error is NetworkError ||
              error is TimeoutError ||
              error is TimeoutException;
          _failedStage = _planFailureStage;
          _error = _connectionInterrupted
              ? 'We can’t check your plan right now. Check your connection and retry.'
              : 'We can’t check your plan right now. Please try again later.';
        });
      }
    } finally {
      _checkingJob = false;
    }
  }

  /// The job reports tutorial 1 ready to read.
  static bool _firstLessonReady(PlanJobStatus job) =>
      (job.readyLessonCount ?? 0) >= 1 ||
      job.step == 'first_lesson_ready' ||
      job.step == 'lessons_ready';

  /// The plan job finished while tutorial 1 is still being prepared.
  bool get _tutorialPending => _jobCompleted && !_tutorialDone;

  /// Once the backbone exists, read the plan's own weekly capacity for the
  /// stage subtitle. Best effort: the lab never waits on or fails for it.
  Future<void> _requestPlanFacts() async {
    if (_factsRequested) return;
    _factsRequested = true;
    try {
      final plan = await ref.read(planRepositoryProvider).getCurrentPlan();
      final minutes = plan?.weeklyMinutes;
      if (!mounted || minutes == null || minutes <= 0) return;
      setState(() => _planWeeklyMinutes = minutes);
    } catch (_) {
      // The subtitle keeps the capacity the learner gave in the interview.
    }
  }

  /// The plan job finished without reporting Tutorial 1 ready: the lessons
  /// are written by per-item jobs it doesn't see, so read mission 1 once with
  /// a peek (never the normal read, which can start generation; nothing on a
  /// server that can't peek). A written first tutorial ticks the stage; a
  /// failure or anything else keeps the copy as it is.
  Future<void> _peekFirstTutorial() async {
    if (_tutorialPeeked || _tutorialDone) return;
    _tutorialPeeked = true;
    try {
      final repository = ref.read(planRepositoryProvider);
      final plan = await repository.getCurrentPlan();
      if (plan == null || !planSupportsPeek(plan)) return;
      final mission = plan.missionsForWeek(1).firstOrNull;
      if (mission == null || !mounted) return;
      final detail = await repository.peekPlanItemDetailed(mission.id);
      final steps = detail.steps;
      final first =
          steps.where((step) => step.isTutorial).firstOrNull ??
          steps.firstOrNull;
      if (!mounted || first == null || !first.hasContent || _tutorialDone) {
        return;
      }
      setState(() => _tutorialDone = true);
    } catch (_) {
      // Best effort: the lab keeps "Tutorial 1 is on its way."
    }
  }

  void _markReadyIfComplete() {
    if (!mounted || !_jobCompleted || _planReady) return;
    if (!_comparisonDone || !_blueprintDone || !_scoresDone) return;
    final comparisonReady =
        widget.draft.comparisonMd?.trim().isNotEmpty == true;
    final blueprintReady = widget.draft.blueprintMd?.trim().isNotEmpty == true;
    if (!comparisonReady || !blueprintReady) return;
    _jobTimer?.cancel();
    _jobTimer = null;
    setState(() {
      _planReady = true;
      _error = null;
      _failedStage = null;
    });
  }

  // ── Derived state ─────────────────────────────────────────────────────────

  _StageState _stateOf(int stage) {
    if (_error != null && _failedStage == stage) return _StageState.fail;
    final done = switch (stage) {
      _cmp => _comparisonDone,
      _dim => _scoresDone,
      _bp => _blueprintDone,
      _plan => _backboneDone,
      _ => _tutorialDone,
    };
    if (done) return _StageState.done;
    // Behind a failure nothing else is running: it waits for the retry.
    if (_error != null) return _StageState.wait;
    final started = switch (stage) {
      _cmp => true,
      _dim || _bp => _comparisonDone,
      _plan => _planStarted,
      _ => _backboneDone,
    };
    return started ? _StageState.run : _StageState.wait;
  }

  /// The learner's weekly capacity in minutes: the plan's own once it is read,
  /// else what they answered in the interview on this device.
  int? get _weeklyMinutes {
    final fromPlan = _planWeeklyMinutes;
    if (fromPlan != null) return fromPlan;
    int? answered;
    for (final answer in widget.draft.intakeAnswers.values) {
      final match = RegExp(
        r'^\s*(\d+(?:[.,]\d+)?)\s*hours?\s+a\s+week',
        caseSensitive: false,
      ).firstMatch(answer);
      final hours = double.tryParse(
        match?.group(1)?.replaceAll(',', '.') ?? '',
      );
      if (hours != null && hours > 0) answered = (hours * 2).round() * 30;
    }
    return answered;
  }

  String _subtitle(int stage) {
    final age = widget.draft.age;
    final short = widget.idol.short;
    switch (stage) {
      case _cmp:
        return 'You at $age next to $short at $age';
      case _dim:
        return 'Five dimensions, evidence checked';
      case _bp:
        return 'Direction, priorities, rationale';
      case _plan:
        final minutes = _weeklyMinutes;
        return minutes == null
            ? '12 weeks'
            : '12 weeks · ${labHours(minutes)} h per week';
      default:
        return _tutorialPending
            ? 'Preparing — it’ll open on Today'
            : 'Ready to start while the rest prepares';
    }
  }

  String get _doneNote {
    final total = _totalLessons;
    // Naming "Tutorials 2–N" would imply tutorial 1 is ready.
    if (total == null || total < 2 || !_tutorialDone) {
      return 'Tutorials keep preparing in the background';
    }
    return total == 2
        ? 'Tutorial 2 keeps preparing in the background'
        : 'Tutorials 2–$total keep preparing in the background';
  }

  void _measureFooter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _footerKey.currentContext?.findRenderObject();
      final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
      if ((height - _footerHeight).abs() > 0.5) {
        setState(() => _footerHeight = height);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_planReady) _measureFooter();
    final failed = _error != null;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final comparison = labExcerpt(
      widget.draft.comparisonMd,
      complete: _comparisonDone,
    );
    final direction = labDirection(
      widget.draft.blueprintMd,
      complete: _blueprintDone,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: AppColors.night,
        child: DefaultTextStyle(
          style: AppTypography.sans(16).copyWith(color: Colors.white),
          child: Stack(
            children: [
              Positioned.fill(child: _background(failed: failed)),
              Positioned.fill(
                child: SingleChildScrollView(
                  key: const Key('mentor-lab-content'),
                  padding: EdgeInsets.only(
                    top: topInset + 28,
                    bottom: _planReady
                        ? math.max(190.0, _footerHeight + 16)
                        : 60 + bottomInset,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(failed: failed),
                          _stagesCard(),
                          if (comparison.isNotEmpty)
                            _previewCard(
                              key: const Key('lab-preview-comparison'),
                              top: 14,
                              kicker: 'From your comparison',
                              kickerColor: _irisLight,
                              child: V3Stream(
                                text: comparison,
                                speed: const Duration(milliseconds: 30),
                                style: AppTypography.read(
                                  15.5,
                                ).copyWith(height: 1.6, color: AppColors.nink2),
                              ),
                            ),
                          if (direction != null && direction.isNotEmpty)
                            _previewCard(
                              key: const Key('lab-preview-blueprint'),
                              top: 12,
                              kicker: 'Blueprint direction',
                              kickerColor: _emberLight,
                              child: V3Stream(
                                text: direction,
                                speed: const Duration(milliseconds: 40),
                                style: AppTypography.display(
                                  23,
                                ).copyWith(height: 1.2, color: Colors.white),
                              ),
                            ),
                          if (_backboneDone)
                            _previewCard(
                              key: const Key('lab-preview-roadmap'),
                              top: 12,
                              kicker: '12-week roadmap',
                              kickerColor: AppColors.nink3,
                              spaceAfterKicker: 12,
                              child: _roadmapGrid(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_planReady)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: KeyedSubtree(
                    key: _footerKey,
                    child: _DoneFooter(
                      key: const Key('lab-done-footer'),
                      note: _doneNote,
                      bottomInset: bottomInset,
                      onToday: widget.onDone,
                      onPlan: widget.onPlan ?? widget.onDone,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The lab video (`LAB_VIDEO`) behind everything: .6 while the lab runs,
  /// .85 once the plan is ready (zooming 1.1 → 1 over 3 s), and desaturated
  /// and dimmed while a stage has failed. Its shade and grain come in with
  /// it. Until it plays, if it can't, or with reduced motion, the night
  /// ground shows as before.
  Widget _background({required bool failed}) {
    final done = _planReady;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          V3LoopVideo(
            key: const Key('mentor-lab-video'),
            asset: AppAssets.videoMentorLab,
            fallback: const SizedBox.expand(),
            opacity: done ? 0.85 : 0.6,
            opacityDuration: const Duration(milliseconds: 1400),
            saturation: failed ? 0.3 : 1,
            brightness: failed ? 0.7 : 1,
            scale: done ? 1.0 : 1.1,
            scaleDuration: const Duration(seconds: 3),
            onReady: (ok) {
              if (!mounted) return;
              setState(() {
                _videoPlaying = ok;
                if (!ok) _videoFailed = true;
              });
            },
          ),
          AnimatedOpacity(
            key: const Key('mentor-lab-video-shade'),
            opacity: _videoPlaying ? 1 : 0,
            duration: const Duration(milliseconds: 1400),
            curve: AppMotion.out,
            child: const Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(gradient: _labVideoShade),
                ),
                V3Grain(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Frosted cards over the video; without one (it failed, or reduced
  /// motion) the cards are today's.
  bool get _frosted => !_videoFailed && MotionConfig.enabled(context);

  Widget _header({required bool failed}) {
    final short = widget.idol.short;
    final done = _planReady;
    final String first;
    final String second;
    if (done && _tutorialPending) {
      // The plan exists, but tutorial 1 is not ready: say so.
      first = 'Your plan is ready.';
      second = 'Tutorial 1 is on its way.';
    } else if (done) {
      first = 'Your plan is ready';
      second = 'to begin.';
    } else if (failed) {
      first = 'One step';
      second = 'didn’t finish.';
    } else {
      first = '$short is studying';
      second = 'your starting point.';
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        children: [
          _LabAvatar(idol: widget.idol, running: !done && !failed, done: done),
          const SizedBox(height: 22),
          Text(
            'MENTOR LAB',
            style: AppTypography.kick.copyWith(color: AppColors.nink3),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Semantics(
              header: true,
              label: '$first $second',
              excludeSemantics: true,
              child: Column(
                children: [
                  Text(
                    first,
                    textAlign: TextAlign.center,
                    style: AppTypography.display(34),
                  ),
                  Text(
                    second,
                    textAlign: TextAlign.center,
                    style: AppTypography.displayItalic(34),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stagesCard() {
    final rows = Column(
      children: [for (var i = 0; i < _stageIds.length; i++) _stageRow(i)],
    );
    const margin = EdgeInsets.fromLTRB(18, 26, 18, 0);
    if (_frosted) {
      return Padding(
        padding: margin,
        child: V3Frosted.stage(key: const Key('lab-stage-card'), child: rows),
      );
    }
    return Container(
      key: const Key('lab-stage-card'),
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: rows,
    );
  }

  Widget _stageRow(int stage) {
    final state = _stateOf(stage);
    final id = _stageIds[stage];
    final fail = state == _StageState.fail;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    final stateWord = switch (state) {
      _StageState.done => 'done',
      _StageState.run => 'in progress',
      _StageState.fail => 'failed',
      _StageState.wait => 'waiting',
    };
    final retry = fail
        ? Padding(
            padding: EdgeInsets.only(left: largeText ? 0 : 8),
            child: V3Button(
              key: const Key('mentor-lab-retry'),
              size: V3Size.sm,
              kind: V3ButtonKind.light,
              icon: V3Icons.refresh,
              loading: _starting,
              disabled: _retrySeconds > 0,
              onPressed: _startPipeline,
              child: Text(
                _retrySeconds > 0 ? 'Retry in ${_retrySeconds}s' : 'Retry',
              ),
            ),
          )
        : null;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '${_stageTitles[stage]}, $stateWord',
          excludeSemantics: true,
          child: Text(
            _stageTitles[stage],
            style: AppTypography.sans(14.5, FontWeight.w600),
          ),
        ),
        const SizedBox(height: 1),
        Semantics(
          liveRegion: fail,
          child: Text(
            fail ? _error! : _subtitle(stage),
            style: AppTypography.sans(12.5).copyWith(color: AppColors.nink3),
          ),
        ),
        if (retry != null && largeText)
          Padding(padding: const EdgeInsets.only(top: 8), child: retry),
      ],
    );
    return AnimatedOpacity(
      key: Key('lab-stage-$id'),
      opacity: state == _StageState.wait ? 0.4 : 1,
      duration: MotionConfig.enabled(context)
          ? const Duration(milliseconds: 400)
          : Duration.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: stage == 0
              ? null
              : Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
        ),
        child: Row(
          children: [
            _stageIcon(stage, state),
            const SizedBox(width: 12),
            Expanded(child: text),
            if (retry != null && !largeText) retry,
          ],
        ),
      ),
    );
  }

  Widget _stageIcon(int stage, _StageState state) {
    final id = _stageIds[stage];
    final Widget glyph = switch (state) {
      _StageState.done => const V3Pop(
        duration: Duration(milliseconds: 400),
        child: V3Icon(
          V3Icons.check,
          size: 14,
          strokeWidth: 3,
          color: Colors.white,
        ),
      ),
      _StageState.run => const V3Spinner(
        size: 14,
        color: Colors.white,
        semanticLabel: null,
      ),
      _StageState.fail => const V3Icon(
        V3Icons.x,
        size: 13,
        strokeWidth: 3,
        color: Colors.white,
      ),
      _StageState.wait => Text(
        '${stage + 1}',
        style: AppTypography.sans(
          11,
          FontWeight.w600,
        ).merge(AppTypography.tnum).copyWith(color: Colors.white),
      ),
    };
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: MotionConfig.enabled(context)
            ? const Duration(milliseconds: 400)
            : Duration.zero,
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: switch (state) {
            _StageState.done => AppColors.sage,
            _StageState.fail => AppColors.danger,
            _ => Colors.white.withValues(alpha: 0.08),
          },
        ),
        child: KeyedSubtree(
          key: Key('lab-stage-icon-$id-${state.name}'),
          child: glyph,
        ),
      ),
    );
  }

  Widget _previewCard({
    required Key key,
    required double top,
    required String kicker,
    required Color kickerColor,
    required Widget child,
    double spaceAfterKicker = 8,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: AppTypography.kick.copyWith(color: kickerColor),
        ),
        SizedBox(height: spaceAfterKicker),
        child,
      ],
    );
    final margin = EdgeInsets.fromLTRB(18, top, 18, 0);
    return V3Rise(
      key: key,
      child: _frosted
          ? Padding(
              padding: margin,
              child: SizedBox(
                width: double.infinity,
                child: V3Frosted.secondary(child: content),
              ),
            )
          : Container(
              margin: margin,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.night2,
                borderRadius: BorderRadius.circular(24),
              ),
              child: content,
            ),
    );
  }

  Widget _roadmapGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        mainAxisExtent: 40,
      ),
      itemBuilder: (context, i) => _StaggerPop(
        delay: Duration(milliseconds: i * 60),
        duration: const Duration(milliseconds: 450),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: i == 0
                ? AppColors.ember
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'W${i + 1}',
            style: AppTypography.sans(
              12.5,
              FontWeight.w600,
            ).merge(AppTypography.tnum).copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The avatar with its status ornaments: while [running], three halo rings
/// breathe outward and an ember dot orbits; when [done], the ring turns sage
/// and a check badge pops in.
class _LabAvatar extends StatefulWidget {
  const _LabAvatar({
    required this.idol,
    required this.running,
    required this.done,
  });

  final CmpysIdol idol;
  final bool running;
  final bool done;

  @override
  State<_LabAvatar> createState() => _LabAvatarState();
}

class _LabAvatarState extends State<_LabAvatar> with TickerProviderStateMixin {
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_LabAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Rings and orbit only run while work is in flight and motion is allowed.
  void _sync() {
    final animate = widget.running && MotionConfig.enabled(context);
    if (animate) {
      if (!_halo.isAnimating) _halo.repeat();
      if (!_orbit.isAnimating) _orbit.repeat();
    } else {
      _halo.stop();
      _orbit.stop();
    }
  }

  @override
  void dispose() {
    _halo.dispose();
    _orbit.dispose();
    super.dispose();
  }

  Widget _ring(int i) {
    return AnimatedBuilder(
      animation: _halo,
      builder: (context, _) {
        // `halo`: scale .7 → 2.2 while fading .6 → 0 over 2.4 s on --out,
        // each ring a third of a cycle behind the last.
        final phase = (_halo.value + i / 3) % 1;
        final eased = AppMotion.out.transform(phase);
        return Opacity(
          opacity: (0.6 * (1 - eased)).clamp(0, 1).toDouble(),
          child: Transform.scale(
            scale: 0.7 + 1.5 * eased,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _haloColor, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final ringMotion = motion
        ? const Duration(milliseconds: 600)
        : Duration.zero;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.running && motion)
            for (var i = 0; i < 3; i++)
              Positioned.fill(child: IgnorePointer(child: _ring(i))),
          Positioned(
            left: -14,
            top: -14,
            right: -14,
            bottom: -14,
            child: IgnorePointer(
              child: AnimatedOpacity(
                // Gone once the plan is ready, and while a stage is failed:
                // nothing is in flight to orbit.
                opacity: widget.running ? 1 : 0,
                duration: motion
                    ? const Duration(milliseconds: 500)
                    : Duration.zero,
                child: RotationTransition(
                  turns: _orbit,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.ember,
                        boxShadow: [
                          BoxShadow(color: AppColors.ember, blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: ringMotion,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.done
                        ? AppColors.sage
                        : Colors.white.withValues(alpha: 0.2),
                    spreadRadius: widget.done ? 4 : 1,
                  ),
                ],
              ),
              child: V3Avatar(
                image: cmpysIdolImage(widget.idol),
                initials: widget.idol.initials,
                tint: widget.idol.tint,
                name: widget.idol.name,
                size: 120,
                gray: true,
              ),
            ),
          ),
          if (widget.done)
            Positioned(
              right: -2,
              bottom: 4,
              child: V3Pop(
                duration: const Duration(milliseconds: 500),
                child: Container(
                  key: const Key('lab-done-badge'),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.sage,
                    border: Border.all(color: AppColors.night, width: 3),
                  ),
                  child: const Center(
                    child: V3Icon(
                      V3Icons.check,
                      size: 17,
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows [child] after [delay] with the design's `pop`; it holds its place
/// (invisible) until then. With reduced motion it is simply there.
class _StaggerPop extends StatefulWidget {
  const _StaggerPop({
    required this.delay,
    required this.duration,
    required this.child,
  });

  final Duration delay;
  final Duration duration;
  final Widget child;

  @override
  State<_StaggerPop> createState() => _StaggerPopState();
}

class _StaggerPopState extends State<_StaggerPop> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _shown = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return widget.child;
    if (!_shown) return Opacity(opacity: 0, child: widget.child);
    return V3Pop(duration: widget.duration, child: widget.child);
  }
}

/// The sticky footer that springs up once the plan is ready.
class _DoneFooter extends StatelessWidget {
  const _DoneFooter({
    super.key,
    required this.note,
    required this.bottomInset,
    required this.onToday,
    required this.onPlan,
  });

  final String note;
  final double bottomInset;
  final VoidCallback onToday;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    // A short fade into an opaque ground: the status line and the buttons
    // stand on solid night, so no card text shows through them.
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          child: SizedBox(
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.night.withValues(alpha: 0),
                    AppColors.night,
                  ],
                ),
              ),
            ),
          ),
        ),
        ColoredBox(
          key: const Key('lab-footer-ground'),
          color: AppColors.night,
          child: _body(),
        ),
      ],
    );
    if (!MotionConfig.enabled(context)) return footer;
    // translateY(120%) → 0 over .7 s on --spring.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: AppMotion.spring,
      child: footer,
      builder: (context, t, child) => FractionalTranslation(
        translation: Offset(0, 1.2 * (1 - t)),
        child: child,
      ),
    );
  }

  Widget _body() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            6,
            20,
            math.max(38.0, bottomInset + 18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const V3Spinner(
                      size: 12,
                      color: AppColors.nink3,
                      semanticLabel: null,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        note,
                        textAlign: TextAlign.center,
                        style: AppTypography.sans(
                          12.5,
                        ).copyWith(color: AppColors.nink3),
                      ),
                    ),
                  ],
                ),
              ),
              V3Button(
                key: const Key('mentor-lab-today'),
                full: true,
                iconRight: V3Icons.arrowR,
                onPressed: onToday,
                child: const Text('Go to Today'),
              ),
              const SizedBox(height: 10),
              V3Button(
                key: const Key('mentor-lab-plan'),
                full: true,
                kind: V3ButtonKind.glass,
                onPressed: onPlan,
                child: const Text('See the full plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Text extraction (public for tests) ─────────────────────────────────────

/// Markdown reduced to plain prose: headings, rules, tables and code fences
/// are dropped, list and quote markers and inline emphasis removed, paragraphs
/// joined by a space.
String _plainProse(String? markdown) {
  if (markdown == null || markdown.trim().isEmpty) return '';
  final out = <String>[];
  var inFence = false;
  for (final raw in markdown.split('\n')) {
    var line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || line.isEmpty) continue;
    if (RegExp(r'^#{1,6}(\s|$)').hasMatch(line)) continue;
    if (RegExp(r'^([-*_]\s*){3,}$').hasMatch(line)) continue;
    if (line.startsWith('|')) continue;
    line = line
        .replaceFirst(RegExp(r'^>+\s*'), '')
        .replaceFirst(RegExp(r'^([-*+]|\d+[.)])\s+'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'[*_`]+'), '')
        .trim();
    if (line.isNotEmpty) out.add(line);
  }
  return out.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'st',
  'vs',
  'jr',
  'sr',
  'no',
  'inc',
  'e.g',
  'i.e',
  'u.s',
};

/// Offsets just past each finished sentence of [text]. A terminator counts
/// only when a space follows it, or when [complete] and it ends the text, so a
/// streaming "4." that becomes "4.5" is never cut in half.
List<int> _sentenceEnds(String text, {required bool complete}) {
  final ends = <int>[];
  for (final match in RegExp(r'[.!?…]+["”’)\]]*').allMatches(text)) {
    final end = match.end;
    final atEnd = end >= text.length;
    if (atEnd ? !complete : text[end] != ' ') continue;
    final before = text.substring(0, match.start);
    final word = RegExp(
      r'([\w.]+)$',
    ).firstMatch(before)?.group(1)?.toLowerCase();
    if (word != null &&
        match.group(0) == '.' &&
        _abbreviations.contains(word)) {
      continue;
    }
    ends.add(end);
  }
  return ends;
}

String _clip(String text, int max) {
  if (text.length <= max) return text;
  final cut = text.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max * 0.6 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// Whether the last line of [text] is finished: the document is [complete],
/// or a line break already follows it.
bool _lineEnded(String text, {required bool complete}) =>
    complete || RegExp(r'\n\s*$').hasMatch(text);

/// The opening of the streamed comparison for the lab's "From your
/// comparison" card: the first two or three finished sentences (at most about
/// 420 characters) of its prose, headings and list markers removed.
///
/// While the text is still streaming only finished sentences count, so the
/// excerpt grows but never rewrites itself. Once the comparison is [complete]
/// a text with no sentence end shows whole (clipped). Empty until there is
/// something to show.
@visibleForTesting
String labExcerpt(String? markdown, {required bool complete}) {
  const maxChars = 420;
  final text = _plainProse(markdown);
  if (text.isEmpty) return '';
  final ended = _lineEnded(markdown!, complete: complete);
  final ends = _sentenceEnds(text, complete: ended);
  if (ends.isEmpty) return complete ? _clip(text, maxChars) : '';
  for (var count = math.min(3, ends.length); count >= 1; count--) {
    final excerpt = text.substring(0, ends[count - 1]).trim();
    if (excerpt.length <= maxChars || count == 1) {
      return _clip(excerpt, maxChars);
    }
  }
  return '';
}

/// The blueprint's direction line for the lab's "Blueprint direction" card.
///
/// The blueprint prompt ends its verdict with a "Twelve-Week Thesis" section:
/// the first sentence under a heading that names a thesis or direction is the
/// direction. A blueprint without one falls back to its first prose sentence,
/// and, with no prose at all, to its first heading. While the blueprint is
/// still streaming nothing shows until that line is finished, so the card
/// never rewrites itself; a [complete] blueprint always yields something.
@visibleForTesting
String? labDirection(String? markdown, {required bool complete}) {
  const maxChars = 200;
  if (markdown == null || markdown.trim().isEmpty) return null;
  final lines = markdown.split('\n');
  final headingPattern = RegExp(r'^#{1,6}\s');
  final headingIndex = lines.indexWhere(
    (line) =>
        headingPattern.hasMatch(line.trim()) &&
        RegExp(r'thesis|direction', caseSensitive: false).hasMatch(line),
  );

  /// The first sentence of [source]; [ended] says its last line is finished.
  String? firstSentence(String source, {required bool ended}) {
    final prose = _plainProse(source);
    if (prose.isEmpty) return null;
    final ends = _sentenceEnds(prose, complete: ended);
    if (ends.isNotEmpty) {
      return _clip(prose.substring(0, ends.first).trim(), maxChars);
    }
    return complete ? _clip(prose, maxChars) : null;
  }

  if (headingIndex >= 0) {
    final body = <String>[];
    var closedByHeading = false;
    for (final line in lines.skip(headingIndex + 1)) {
      if (headingPattern.hasMatch(line.trim())) {
        closedByHeading = true;
        break;
      }
      body.add(line);
    }
    final text = body.join('\n');
    final sentence = firstSentence(
      text,
      ended: closedByHeading || _lineEnded(text, complete: complete),
    );
    if (sentence != null) return sentence;
    if (!complete) return null;
  }
  // No thesis section yet: wait for it rather than show a line that the
  // thesis would then replace.
  if (!complete && headingIndex < 0) return null;
  final prose = firstSentence(markdown, ended: true);
  if (prose != null) return prose;
  for (final line in lines) {
    final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line.trim());
    if (heading != null) {
      return _clip(
        heading.group(1)!.replaceAll(RegExp(r'[*_`]+'), '').trim(),
        maxChars,
      );
    }
  }
  return null;
}

/// Weekly capacity for the plan stage's subtitle: hours in half-hour steps,
/// without a trailing ".0" (240 → "4", 270 → "4.5").
@visibleForTesting
String labHours(int minutes) {
  final hours = (minutes / 30).round() / 2;
  return hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toStringAsFixed(1);
}
