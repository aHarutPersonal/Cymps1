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
  PlanItemDetailed? _detailed;
  String? _error;
  bool _toggling = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    try {
      final detailed =
          await ref.read(planRepositoryProvider).getPlanItemDetailed(widget.itemId);
      if (!mounted) return;
      setState(() {
        _detailed = detailed;
        _error = null;
      });
      if (!detailed.detailsReady) {
        // Worker is still writing the lesson — re-fetch until it lands.
        _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
      }
    } catch (e) {
      debugPrint('⚠️ plan item detail load failed (${widget.itemId}): $e');
      if (!mounted) return;
      // A failed background poll must not replace already-loaded content —
      // keep the screen and retry on the next tick.
      if (_detailed != null) {
        if (!_detailed!.detailsReady) {
          _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
        }
        return;
      }
      final isConnection = e is TimeoutError || e is NetworkError;
      setState(() => _error = isConnection
          ? 'Couldn’t load this task. Check your connection and try again.'
          : 'Something went wrong loading this task — try again.');
    }
  }

  Future<void> _toggleComplete() async {
    final detailed = _detailed;
    if (detailed == null || _toggling) return;
    setState(() => _toggling = true);
    try {
      final result = await ref
          .read(planRepositoryProvider)
          .toggleItemComplete(detailed.item.id);
      if (!mounted) return;
      if (result.completed) {
        showCmpysToast(context, "Marked done. Kept your word.",
            icon: Icons.check_rounded, tone: AppColors.green);
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
        showCmpysToast(context, "Couldn’t update - try again.",
            icon: Icons.error_outline_rounded, tone: AppColors.ink2);
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.green),
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
            Text(_error!,
                textAlign: TextAlign.center, style: AppTypography.bodyDim),
            const SizedBox(height: 18),
            CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.md,
              leadingIcon: Icons.refresh_rounded,
              onTap: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(PlanItemDetailed d) {
    final item = d.item;
    return ListView(
      padding: EdgeInsets.fromLTRB(22, 4, 22, AppShell.bottomNavClearance(context)),
      children: [
        CmpysKicker(
          item.isDailyRhythm
              ? 'Daily rhythm · Week ${item.weekStart}'
              : 'Week ${item.weekStart}'
                  '${item.weekEnd != item.weekStart ? '–${item.weekEnd}' : ''} mission',
        ),
        const SizedBox(height: 8),
        Text(item.title,
            style: AppTypography.h1
                .copyWith(fontSize: 26, letterSpacing: -0.4, height: 1.25)),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip(_typeMeta(item.type).icon, _typeMeta(item.type).label),
            const SizedBox(width: 8),
            _chip(PhosphorIconsRegular.clock, '~${item.estimatedHours}h'),
            if (d.completed) ...[
              const SizedBox(width: 8),
              _chip(Icons.check_rounded, 'Done', tone: AppColors.green),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(item.description,
            style: AppTypography.body.copyWith(fontSize: 15, height: 1.55)),
        if (item.successMetric.isNotEmpty) ...[
          const SizedBox(height: 16),
          CmpysCardSurface(
            color: AppColors.greenSoft,
            border: false,
            pad: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(PhosphorIconsRegular.target,
                    size: 18, color: AppColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.successMetric,
                      style: AppTypography.bodyMedium
                          .copyWith(fontSize: 14, height: 1.45)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        if (!d.detailsReady)
          _generatingCard()
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
        if (d.steps.isEmpty)
          CmpysButton(
            variant:
                d.completed ? CmpysBtnVariant.dark : CmpysBtnVariant.primary,
            size: CmpysBtnSize.lg,
            full: true,
            disabled: _toggling,
            leadingIcon:
                d.completed ? Icons.undo_rounded : Icons.check_rounded,
            onTap: _toggleComplete,
            child: Text(d.completed ? 'Mark as not done' : 'Mark as done'),
          )
        else if (d.completed)
          CmpysCardSurface(
            color: AppColors.greenSoft,
            border: false,
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.green2,
                ),
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

  Widget _generatingCard() {
    return CmpysCardSurface(
      pad: const EdgeInsets.all(18),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.green),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Writing your lesson — steps and materials will appear here in a moment.',
              style: AppTypography.body.copyWith(
                  fontSize: 13.5,
                  color: AppColors.ink2,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lessonCard(PlanItemDetailed detailed, PlanStepDetail step, int index) {
    final completed = detailed.isStepCompleted(step.id);
    final unlocked = detailed.isStepUnlocked(index);
    final active = unlocked && !completed;
    final hasLesson =
        step.lessonContent != null && step.lessonContent!.trim().isNotEmpty;

    return CmpysCardSurface(
      key: Key('lesson-${index + 1}-${completed ? 'completed' : active ? 'active' : 'locked'}'),
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
  void _openMaterial(PlanMaterialDetail m) {
    final videoId = m.youtubeVideoId;
    Widget? screen;
    if (videoId != null) {
      screen = MaterialVideoScreen(material: m, videoId: videoId);
    } else if (m.type == 'book' && m.contentResourceId != null) {
      screen = BookReaderScreen(
          resourceId: m.contentResourceId!, fallbackTitle: m.title);
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

  ({IconData icon, String label})? _materialAction(PlanMaterialDetail m) {
    if (m.youtubeVideoId != null) {
      return (icon: PhosphorIconsFill.playCircle, label: 'Watch');
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
    return CmpysCardSurface(
      onTap: action != null ? () => _openMaterial(m) : null,
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
                Text(m.title,
                    style: AppTypography.bodyMedium.copyWith(fontSize: 14.5)),
                if (m.authorOrCreator != null &&
                    m.authorOrCreator!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(m.authorOrCreator!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.ink3, fontSize: 12.5)),
                ],
                if (m.reason != null && m.reason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(m.reason!,
                      style: AppTypography.caption.copyWith(
                          color: AppColors.ink2, fontSize: 13, height: 1.4)),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 14, color: AppColors.green2),
                  const SizedBox(width: 5),
                  Text(action.label,
                      style: AppTypography.caption.copyWith(
                          color: AppColors.green2,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
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
          Text(label,
              style: AppTypography.caption.copyWith(
                  color: tone, fontSize: 12, fontWeight: FontWeight.w600)),
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
