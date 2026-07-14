import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'achievement_sheet.dart';
import 'book_reader_screen.dart';
import 'cycle_completion_screen.dart';
import 'lesson_reader_screen.dart';
import 'material_reader_screen.dart';
import 'material_video_screen.dart';
import 'material_web_screen.dart';

/// Detail view for one generated plan item — description, success metric,
/// teach-first lesson steps, and materials (GET /plan-items/{id}/detailed).
///
/// Lesson details are generated lazily by a Celery worker; while
/// `details_status` is pending this screen polls and reveals the lesson when
/// it lands.
class PlanItemDetailScreen extends ConsumerStatefulWidget {
  const PlanItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<PlanItemDetailScreen> createState() =>
      _PlanItemDetailScreenState();
}

class _PlanItemDetailScreenState extends ConsumerState<PlanItemDetailScreen> {
  static const _foregroundPollBudget = Duration(minutes: 2);
  static const _maxForegroundPollAttempts = 20;

  PlanItemDetailed? _detailed;
  PlanJobStatus? _detailJob;
  String? _activeDetailJobId;
  String? _terminalDetailError;
  String? _error;
  bool _toggling = false;
  bool _retrying = false;
  bool _loading = false;
  bool _pollingJob = false;
  bool _detailJobPollingUnsupported = false;
  bool _takingLong = false;
  DateTime? _pollStartedAt;
  int _pollAttempt = 0;
  Timer? _poll;
  final Map<String, String> _resolvedBookGuideIds = {};
  final Set<String> _preparingBookGuideKeys = {};

  @override
  void initState() {
    super.initState();
    _load(resetPolling: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool resetPolling = false}) async {
    if (_loading) return;
    _loading = true;
    _poll?.cancel();
    if (resetPolling) {
      _pollStartedAt = DateTime.now();
      _pollAttempt = 0;
      _detailJob = null;
      _detailJobPollingUnsupported = false;
      _terminalDetailError = null;
      _takingLong = false;
    }
    try {
      final detailed = await ref
          .read(planRepositoryProvider)
          .getPlanItemDetailed(widget.itemId);
      if (!mounted) return;
      setState(() {
        _detailed = detailed;
        _error = null;
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
          _terminalDetailError =
              detailed.detailsError ??
              'This lesson could not be prepared. Please generate it again.';
        }
      });
      if (_shouldPollDetails(detailed)) {
        _pollStartedAt ??= DateTime.now();
        _scheduleDetailPoll();
      } else {
        _pollStartedAt = null;
        _takingLong = false;
      }
    } catch (e) {
      debugPrint('⚠️ plan item detail load failed (${widget.itemId}): $e');
      if (!mounted) return;
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
    }
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
        _terminalDetailError != null) {
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
    if (!mounted || _takingLong || !_shouldPollDetails(_detailed)) return;
    final startedAt = _pollStartedAt ??= DateTime.now();
    if (_pollAttempt >= _maxForegroundPollAttempts ||
        DateTime.now().difference(startedAt) >= _foregroundPollBudget) {
      setState(() => _takingLong = true);
      return;
    }
    final delay = _pollAttempt < 4
        ? const Duration(seconds: 2)
        : _pollAttempt < 10
        ? const Duration(seconds: 4)
        : const Duration(seconds: 8);
    _poll = Timer(delay, _pollDetailJob);
  }

  Future<void> _pollDetailJob() async {
    if (!mounted || _pollingJob || _takingLong) return;
    final detailed = _detailed;
    if (!_shouldPollDetails(detailed)) return;
    _pollingJob = true;
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
      if (!mounted) return;
      setState(() => _detailJob = job);
      if (job.isFailed) {
        final reportedError = job.errorMessage?.trim();
        setState(() {
          _activeDetailJobId = null;
          _terminalDetailError =
              reportedError != null && reportedError.isNotEmpty
              ? reportedError
              : 'This lesson could not be prepared. Please generate it again.';
        });
        _poll?.cancel();
        // Prefer the detailed endpoint's user-facing error when it is
        // available. The job failure remains terminal if this refresh races
        // the backend or the network, so polling cannot restart forever.
        await _load();
      } else if (job.isCompleted) {
        await _load();
      } else {
        _scheduleDetailPoll();
      }
    } catch (e) {
      if (!mounted) return;
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
    }
  }

  Future<void> _checkDetailsAgain() async {
    await _load(resetPolling: true);
  }

  Future<void> _toggleComplete() async {
    final detailed = _detailed;
    if (detailed == null || _toggling) return;
    if (detailed.item.isDailyRhythm) {
      await _toggleDaily();
      return;
    }
    setState(() => _toggling = true);
    try {
      final result = await ref
          .read(planRepositoryProvider)
          .toggleItemComplete(detailed.item.id);
      if (!mounted) return;
      if (result.completed) {
        showCmpysToast(
          context,
          "Marked done. Kept your word.",
          icon: Icons.check_rounded,
          tone: AppColors.green,
        );
      }
      // Refresh both this screen and the plan-wide progress numbers.
      await _load();
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
          planId: plan?.id ?? '',
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
        showCmpysToast(
          context,
          "Couldn’t update - try again.",
          icon: Icons.error_outline_rounded,
          tone: AppColors.ink2,
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _toggleDaily() async {
    final detailed = _detailed;
    if (detailed == null || _toggling) return;
    setState(() => _toggling = true);
    try {
      final completed = await ref
          .read(planRepositoryProvider)
          .toggleDailyTask(detailed.item.id);
      if (!mounted) return;
      await _load();
      ref.invalidate(todayViewProvider);
      if (!mounted) return;
      showCmpysToast(
        context,
        completed ? 'Daily rhythm complete.' : 'Daily rhythm reopened.',
        icon: completed ? Icons.check_rounded : Icons.undo_rounded,
        tone: completed ? AppColors.green : AppColors.ink2,
      );
    } catch (_) {
      if (mounted) {
        showCmpysToast(
          context,
          'Couldn’t update today’s rhythm — try again.',
          icon: Icons.error_outline_rounded,
          tone: AppColors.ink2,
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
        showCmpysToast(
          context,
          'Couldn’t restart this lesson — try again.',
          icon: Icons.error_outline_rounded,
          tone: AppColors.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _error != null
          ? _errorView()
          : _detailed == null
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
                ),
              ),
            )
          : _content(_detailed!),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 32, color: AppColors.ink3),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyDim,
            ),
            const SizedBox(height: 18),
            CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.md,
              leadingIcon: Icons.refresh_rounded,
              onTap: () => _load(resetPolling: true),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(PlanItemDetailed d) {
    final item = d.item;
    final done = item.isDailyRhythm ? d.completedToday : d.completed;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        22,
        4,
        22,
        AppShell.bottomNavClearance(context),
      ),
      children: [
        CmpysKicker(
          item.isDailyRhythm
              ? 'Daily rhythm · Week ${item.weekStart}'
              : 'Week ${item.weekStart}'
                    '${item.weekEnd != item.weekStart ? '–${item.weekEnd}' : ''} mission',
        ),
        const SizedBox(height: 8),
        Text(
          item.title,
          style: AppTypography.h1.copyWith(
            fontSize: 26,
            letterSpacing: -0.4,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip(_typeMeta(item.type).icon, _typeMeta(item.type).label),
            const SizedBox(width: 8),
            _chip(PhosphorIconsRegular.clock, '~${item.estimatedHours}h'),
            if (done) ...[
              const SizedBox(width: 8),
              _chip(Icons.check_rounded, 'Done', tone: AppColors.green),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(
          item.description,
          style: AppTypography.body.copyWith(fontSize: 15, height: 1.55),
        ),
        if (item.successMetric.isNotEmpty) ...[
          const SizedBox(height: 16),
          CmpysCardSurface(
            color: AppColors.greenSoft,
            border: false,
            pad: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  PhosphorIconsRegular.target,
                  size: 18,
                  color: AppColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.successMetric,
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        if (item.isDailyRhythm)
          _dailyRhythmCard(d)
        else if (d.completed && d.steps.isEmpty)
          _completedWithoutLessonCard()
        else if (!d.detailsReady)
          _generatingCard(d)
        else ...[
          if (d.steps.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(child: CmpysKicker('Focused lessons')),
                Text(
                  '${d.completedStepIds.length}/${d.steps.length}',
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.green2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Complete one lesson at a time. Finishing the active lesson unlocks the next.',
              style: AppTypography.caption.copyWith(
                color: AppColors.ink3,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < d.steps.length; i++) ...[
              _lessonCard(d, d.steps[i], i),
              const SizedBox(height: 12),
            ],
          ],
          if (d.materials.isNotEmpty) ...[
            const SizedBox(height: 10),
            const CmpysKicker('Materials'),
            const SizedBox(height: 12),
            for (final m in d.materials) ...[
              _materialCard(m),
              const SizedBox(height: 12),
            ],
          ],
        ],
        const SizedBox(height: 18),
        if (item.isDailyRhythm)
          CmpysButton(
            variant: d.completedToday
                ? CmpysBtnVariant.dark
                : CmpysBtnVariant.primary,
            size: CmpysBtnSize.lg,
            full: true,
            disabled: _toggling,
            leadingIcon: d.completedToday
                ? Icons.undo_rounded
                : Icons.check_rounded,
            onTap: _toggleDaily,
            child: Text(
              d.completedToday
                  ? 'Mark as not done today'
                  : 'Complete for today',
            ),
          )
        else if (!d.detailsReady && !d.completed)
          const SizedBox.shrink()
        else if (d.steps.isEmpty)
          CmpysButton(
            variant: d.completed
                ? CmpysBtnVariant.dark
                : CmpysBtnVariant.primary,
            size: CmpysBtnSize.lg,
            full: true,
            disabled: _toggling,
            leadingIcon: d.completed ? Icons.undo_rounded : Icons.check_rounded,
            onTap: _toggleComplete,
            child: Text(d.completed ? 'Mark as not done' : 'Mark as done'),
          )
        else if (d.completed)
          CmpysCardSurface(
            color: AppColors.greenSoft,
            border: false,
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.green2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All focused lessons are complete. Mission accomplished.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.green2,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          CmpysCardSurface(
            color: AppColors.paper2,
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.lockSimple,
                  color: AppColors.ink3,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Complete all lessons in order to finish this mission.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink2,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dailyRhythmCard(PlanItemDetailed detailed) {
    final instructions = detailed.dailyInstructions?.trim();
    return CmpysCardSurface(
      color: AppColors.greenSoft,
      border: false,
      pad: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsRegular.repeat,
                size: 19,
                color: AppColors.green2,
              ),
              const SizedBox(width: 9),
              Text(
                'TODAY’S RHYTHM',
                style: AppTypography.kicker.copyWith(color: AppColors.green2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            instructions == null || instructions.isEmpty
                ? detailed.item.description
                : instructions,
            style: AppTypography.body.copyWith(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(
            'This resets each day and never blocks the next week.',
            style: AppTypography.caption.copyWith(
              color: AppColors.ink3,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _completedWithoutLessonCard() {
    return CmpysCardSurface(
      color: AppColors.greenSoft,
      border: false,
      pad: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.green2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This mission was completed before focused lessons were added. '
              'Your completion is preserved—there is nothing left to load.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.green2,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generatingCard(PlanItemDetailed detailed) {
    final activeRetry =
        _activeDetailJobId != null && _terminalDetailError == null;
    final failureMessage = _terminalDetailError ?? detailed.detailsError;
    if (_terminalDetailError != null ||
        (detailed.detailsFailed && !activeRetry)) {
      return CmpysCardSurface(
        pad: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 24,
              color: AppColors.ochre2,
            ),
            const SizedBox(height: 10),
            Text(
              failureMessage ??
                  'This lesson could not be prepared. Please try again.',
              style: AppTypography.body.copyWith(
                fontSize: 13.5,
                color: AppColors.ink2,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.md,
              leadingIcon: Icons.refresh_rounded,
              disabled: _retrying,
              onTap: _retryDetails,
              child: Text(_retrying ? 'Restarting…' : 'Generate again'),
            ),
          ],
        ),
      );
    }
    if (_takingLong) {
      return CmpysCardSurface(
        pad: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              PhosphorIconsRegular.clock,
              size: 24,
              color: AppColors.ochre2,
            ),
            const SizedBox(height: 10),
            Text(
              'This lesson is still being prepared in the background. You can '
              'leave this screen and return later—your place is saved.',
              style: AppTypography.body.copyWith(
                fontSize: 13.5,
                color: AppColors.ink2,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            CmpysButton(
              variant: CmpysBtnVariant.outline,
              size: CmpysBtnSize.md,
              leadingIcon: Icons.refresh_rounded,
              onTap: _checkDetailsAgain,
              child: const Text('Check status'),
            ),
          ],
        ),
      );
    }

    final progress = (_detailJob?.progressPercent ?? detailed.detailsProgress)
        .clamp(0, 100);
    final step = _detailJob?.step ?? detailed.detailsStep;
    final progressValue = progress > 0 ? progress / 100.0 : null;
    return CmpysCardSurface(
      pad: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  value: progressValue,
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.green,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _detailProgressCopy(step),
                  style: AppTypography.body.copyWith(
                    fontSize: 13.5,
                    color: AppColors.ink2,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (progress > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$progress%',
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.green2,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 4,
              backgroundColor: AppColors.hair,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.green),
            ),
          ),
        ],
      ),
    );
  }

  String _detailProgressCopy(String? step) {
    return switch (step) {
      'prefetch_queued' ||
      'user_priority' ||
      'loading_context' => 'Preparing the mentor context for your lesson…',
      'generating_curriculum' =>
        'Writing your three focused lessons and guided practice…',
      'generating_lessons' => 'Writing your focused lessons in parallel…',
      'repairing_lessons' =>
        'Strengthening the lessons that missed a quality check…',
      'resolving_materials' => 'Checking and organizing your materials…',
      'finalizing_steps' => 'Finalizing the lesson sequence…',
      _ =>
        'Writing your lesson — steps and materials will appear here shortly.',
    };
  }

  Widget _lessonCard(
    PlanItemDetailed detailed,
    PlanStepDetail step,
    int index,
  ) {
    final completed = detailed.isStepCompleted(step.id);
    final unlocked = detailed.isStepUnlocked(index);
    final active = unlocked && !completed;
    final hasLesson =
        step.lessonContent != null && step.lessonContent!.trim().isNotEmpty;

    return CmpysCardSurface(
      key: Key(
        'lesson-${index + 1}-${completed
            ? 'completed'
            : active
            ? 'active'
            : 'locked'}',
      ),
      color: active
          ? AppColors.greenSoft
          : unlocked
          ? AppColors.card
          : AppColors.paper2,
      raised: active,
      onTap: !unlocked
          ? () => _showLessonLocked(index, detailed.activeStepIndex)
          : hasLesson
          ? () => _openLesson(detailed, step, index)
          : null,
      pad: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: completed
                  ? AppColors.green
                  : active
                  ? Colors.white
                  : AppColors.card.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: completed
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : unlocked
                ? Text(
                    '${index + 1}',
                    style: AppTypography.captionMedium.copyWith(
                      color: AppColors.green2,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : const Icon(
                    PhosphorIconsRegular.lockSimple,
                    color: AppColors.ink3,
                    size: 16,
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? 'CURRENT LESSON'
                      : completed
                      ? 'COMPLETED · TAP TO REVIEW'
                      : 'LOCKED',
                  style: AppTypography.kicker.copyWith(
                    color: active
                        ? AppColors.green2
                        : completed
                        ? AppColors.green
                        : AppColors.ink3,
                    fontSize: 8.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  step.title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: unlocked ? AppColors.ink : AppColors.ink3,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  children: [
                    _lessonMeta(
                      PhosphorIconsRegular.bookOpenText,
                      '${step.readingMinutes ?? _lessonReadMinutes(step)} min read',
                    ),
                    _lessonMeta(
                      PhosphorIconsRegular.timer,
                      '${step.practiceMinutes ?? _lessonPracticeMinutes(step)} min practice',
                    ),
                    if (step.resources.isNotEmpty)
                      _lessonMeta(
                        PhosphorIconsRegular.books,
                        '${step.resources.length} reference${step.resources.length == 1 ? '' : 's'}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(
              unlocked ? Icons.chevron_right_rounded : Icons.lock_outline,
              color: active ? AppColors.green2 : AppColors.ink3,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lessonMeta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.ink3),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.ink3,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  int _lessonReadMinutes(PlanStepDetail step) {
    final words = (step.lessonContent ?? '').split(RegExp(r'\s+')).length;
    return (words / 200).ceil().clamp(1, 60);
  }

  int _lessonPracticeMinutes(PlanStepDetail step) =>
      ((step.estimateMinutes ?? 45) - _lessonReadMinutes(step)).clamp(20, 55);

  Future<void> _openLesson(
    PlanItemDetailed detailed,
    PlanStepDetail step,
    int index,
  ) async {
    final completed = detailed.isStepCompleted(step.id);
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      CmpysPageRoute<bool>(
        builder: (_) => LessonReaderScreen(
          itemId: detailed.item.id,
          missionTitle: detailed.item.title,
          step: step,
          stepNumber: index + 1,
          totalSteps: detailed.steps.length,
          materials: detailed.materials,
          completed: completed,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _load();
      ref.read(currentPlanProvider.notifier).refresh();
      if (mounted) {
        showCmpysToast(
          context,
          index == detailed.steps.length - 1
              ? 'Mission complete.'
              : 'Lesson complete. The next lesson is unlocked.',
          icon: Icons.check_rounded,
          tone: AppColors.green,
        );
      }
    }
  }

  Future<void> _showLessonLocked(int index, int activeIndex) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                PhosphorIconsRegular.lockSimple,
                color: AppColors.ochre2,
                size: 30,
              ),
              const SizedBox(height: 13),
              Text(
                'Lesson ${index + 1} is locked',
                style: AppTypography.h2.copyWith(fontSize: 23),
              ),
              const SizedBox(height: 7),
              Text(
                'Complete Lesson ${activeIndex + 1} first. Your next lesson will unlock automatically.',
                style: AppTypography.body.copyWith(
                  color: AppColors.ink2,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              CmpysButton(
                full: true,
                onTap: () => Navigator.of(sheetContext).pop(),
                child: const Text('Back to current lesson'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Open a material in-app: YouTube player for videos, chaptered book
  /// reader for books backed by a shared resource (full public-domain text
  /// or LLM module), markdown reader for lessons, web view for plain links.
  Future<void> _openMaterial(PlanMaterialDetail m) async {
    final videoId = m.youtubeVideoId;
    final canonicalKey = (m.canonicalKey ?? '').trim();
    var bookResourceId = _bookResourceId(m);
    if (m.type == 'book' && bookResourceId == null && canonicalKey.isNotEmpty) {
      if (_preparingBookGuideKeys.contains(canonicalKey)) return;
      setState(() => _preparingBookGuideKeys.add(canonicalKey));
      try {
        bookResourceId = await ref
            .read(planRepositoryProvider)
            .waitForContentResourceId(canonicalKey);
      } catch (_) {
        if (!mounted) return;
        setState(() => _preparingBookGuideKeys.remove(canonicalKey));
        showCmpysToast(
          context,
          'Could not check the book guide. Try again.',
          icon: Icons.cloud_off_rounded,
          tone: AppColors.danger,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _preparingBookGuideKeys.remove(canonicalKey);
        if (bookResourceId != null) {
          _resolvedBookGuideIds[canonicalKey] = bookResourceId;
        }
      });
      if (bookResourceId == null) {
        showCmpysToast(
          context,
          'The guide is taking longer than expected. Try again in a moment.',
          icon: PhosphorIconsRegular.hourglass,
          tone: AppColors.ochre2,
        );
        return;
      }
    }
    Widget? screen;
    if (videoId != null) {
      screen = MaterialVideoScreen(material: m, videoId: videoId);
    } else if (m.type == 'book' && bookResourceId != null) {
      screen = BookReaderScreen(
        resourceId: bookResourceId,
        fallbackTitle: m.title,
      );
    } else if (m.prefersExternalLink) {
      screen = MaterialWebScreen(title: m.title, url: m.url!);
    } else if (m.hasInAppContent) {
      screen = MaterialReaderScreen(material: m);
    } else if (m.url != null && m.url!.isNotEmpty) {
      screen = MaterialWebScreen(title: m.title, url: m.url!);
    }
    if (screen == null) return;
    final route = CmpysPageRoute<void>(builder: (_) => screen!);
    // Material players/readers own their bottom controls. Present them above
    // AppShell so the floating five-tab bar cannot cover those controls.
    Navigator.of(context, rootNavigator: true).push(route);
  }

  String? _bookResourceId(PlanMaterialDetail material) {
    final directId = material.contentResourceId?.trim();
    if (directId != null && directId.isNotEmpty) return directId;
    final canonicalKey = material.canonicalKey?.trim();
    if (canonicalKey == null || canonicalKey.isEmpty) return null;
    return _resolvedBookGuideIds[canonicalKey];
  }

  bool _isPreparingBookGuide(PlanMaterialDetail material) {
    final canonicalKey = material.canonicalKey?.trim();
    return canonicalKey != null &&
        canonicalKey.isNotEmpty &&
        _preparingBookGuideKeys.contains(canonicalKey);
  }

  ({IconData icon, String label})? _materialAction(PlanMaterialDetail m) {
    if (m.youtubeVideoId != null) {
      return (icon: PhosphorIconsFill.playCircle, label: 'Watch');
    }
    if (m.type == 'book' && _bookResourceId(m) != null) {
      return (icon: PhosphorIconsRegular.bookOpen, label: 'Read');
    }
    if (m.type == 'book' && (m.canonicalKey ?? '').trim().isNotEmpty) {
      if (_isPreparingBookGuide(m)) {
        return (icon: PhosphorIconsRegular.hourglass, label: 'Preparing…');
      }
      return (icon: PhosphorIconsRegular.bookOpen, label: 'Open guide');
    }
    if (m.prefersExternalLink) {
      return (icon: PhosphorIconsRegular.globe, label: 'Open');
    }
    if (m.hasInAppContent) {
      return (icon: PhosphorIconsRegular.bookOpen, label: 'Read');
    }
    if (m.url != null && m.url!.isNotEmpty) {
      return (icon: PhosphorIconsRegular.globe, label: 'Open');
    }
    return null;
  }

  Widget _materialCard(PlanMaterialDetail m) {
    final action = _materialAction(m);
    final preparingBookGuide = _isPreparingBookGuide(m);
    return CmpysCardSurface(
      onTap: action != null && !preparingBookGuide
          ? () => _openMaterial(m)
          : null,
      pad: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_materialIcon(m.type), size: 20, color: AppColors.ink2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title,
                  style: AppTypography.bodyMedium.copyWith(fontSize: 14.5),
                ),
                if (m.authorOrCreator != null &&
                    m.authorOrCreator!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    m.authorOrCreator!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink3,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (m.reason != null && m.reason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    m.reason!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink2,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 14, color: AppColors.green2),
                  const SizedBox(width: 5),
                  Text(
                    action.label,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.green2,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
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

  Widget _chip(IconData icon, String label, {Color tone = AppColors.ink2}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label}) _typeMeta(String type) {
    switch (type) {
      case 'habit':
        return (icon: PhosphorIconsRegular.arrowClockwise, label: 'Daily');
      case 'reading':
        return (icon: PhosphorIconsRegular.bookOpen, label: 'Reading');
      case 'course':
        return (icon: PhosphorIconsRegular.graduationCap, label: 'Course');
      case 'practice':
        return (icon: PhosphorIconsRegular.barbell, label: 'Practice');
      case 'reflection':
        return (icon: PhosphorIconsRegular.notePencil, label: 'Reflection');
      default:
        return (icon: PhosphorIconsRegular.target, label: 'Project');
    }
  }

  IconData _materialIcon(String? type) {
    switch (type) {
      case 'book':
        return PhosphorIconsRegular.bookOpen;
      case 'video':
        return PhosphorIconsFill.playCircle;
      case 'article':
        return PhosphorIconsRegular.fileText;
      case 'in_app_lesson':
        return PhosphorIconsRegular.chalkboardTeacher;
      default:
        return PhosphorIconsRegular.link;
    }
  }
}
