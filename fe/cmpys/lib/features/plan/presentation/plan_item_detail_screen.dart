import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'achievement_sheet.dart';
import 'book_reader_screen.dart';
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
      if (!mounted) return;
      setState(() => _error =
          'Couldn’t load this task. Check your connection and try again.');
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

      // Show achievement sheet for completed mission tasks (non-habit types).
      if (!item.isDailyRhythm && result.completed) {
        await showAchievementSheet(
          context,
          ref: ref,
          item: item,
          planId: plan?.id ?? '',
          cycleNumber: 1, // BackendPlan has no cycleNumber field yet; Task 10 will update
        );
      }

      // Placeholder for cycle-completion flow — implemented in Task 10.
      if (result.planComplete) {
        // cycle completion — implemented in Task 10
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
            const CmpysKicker('Lesson steps'),
            const SizedBox(height: 12),
            for (var i = 0; i < d.steps.length; i++) ...[
              _stepCard(d.steps[i], i + 1),
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
        CmpysButton(
          variant: d.completed ? CmpysBtnVariant.dark : CmpysBtnVariant.primary,
          size: CmpysBtnSize.lg,
          full: true,
          disabled: _toggling,
          leadingIcon:
              d.completed ? Icons.undo_rounded : Icons.check_rounded,
          onTap: _toggleComplete,
          child: Text(d.completed ? 'Mark as not done' : 'Mark as done'),
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

  Widget _stepCard(PlanStepDetail step, int number) {
    final hasLesson =
        step.lessonContent != null && step.lessonContent!.trim().isNotEmpty;
    return CmpysCardSurface(
      pad: const EdgeInsets.all(4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: AppTypography.captionMedium.copyWith(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          title: Text(step.title,
              style: AppTypography.bodyMedium.copyWith(fontSize: 15)),
          subtitle: step.estimateMinutes != null
              ? Text('${step.estimateMinutes} min',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.ink3, fontSize: 12))
              : null,
          children: [
            if (step.description != null && step.description!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(step.description!,
                    style: AppTypography.body
                        .copyWith(fontSize: 14, height: 1.5)),
              ),
            if (step.substeps.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final s in step.substeps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(Icons.circle,
                            size: 6, color: AppColors.ink3),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s,
                            style: AppTypography.body
                                .copyWith(fontSize: 13.5, height: 1.45)),
                      ),
                    ],
                  ),
                ),
            ],
            if (hasLesson) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.hair, height: 1),
              const SizedBox(height: 12),
              CmpysMarkdown(step.lessonContent!),
            ],
            if (step.expectedOutput != null &&
                step.expectedOutput!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(PhosphorIconsRegular.flagCheckered,
                      size: 15, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Done when: ${step.expectedOutput!}',
                        style: AppTypography.caption.copyWith(
                            color: AppColors.ink2,
                            fontSize: 13,
                            height: 1.4)),
                  ),
                ],
              ),
            ],
          ],
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
    final route = MaterialPageRoute<void>(builder: (_) => screen!);
    Navigator.of(context).push(route);
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
