import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../../core/ui/thinking_stream.dart';
import '../../idols/data/jobs_repository.dart';
import '../../idols/models/job_models.dart';
import '../controllers/plans_controller.dart';
import '../data/plans_repository.dart';
import '../models/plan_models.dart';
import 'book_ideas_screen.dart';
import 'widgets/path_design_helpers.dart';

/// Screen to display task/plan item details with steps and materials.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  PlanItemDetailsResponse? _details;
  bool _isLoading = true;
  bool _isRegenerating = false;
  bool _isPollingJob = false;
  String? _error;
  JobStatus? _jobStatus;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ref.read(plansRepositoryProvider);
      final details = await repository.getPlanItem(widget.itemId);

      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
        });

        // If details are pending or generating, start polling
        if (details.detailsStatus == DetailsStatus.pending ||
            details.detailsStatus == DetailsStatus.generating) {
          if (details.jobId != null) {
            _startJobPolling(details.jobId!);
          }
        }
        // NOTE: Never auto-call _regenerateDetails() here — the API handles
        // job creation automatically. Calling it here caused an infinite loop.
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _startJobPolling(String jobId) {
    _isPollingJob = true;
    _pollTimer?.cancel();

    // Use a separate async function to handle the stream
    _runJobPolling(jobId);
  }

  Future<void> _runJobPolling(String jobId) async {
    try {
      final jobsRepo = ref.read(jobsRepositoryProvider);
      await for (final status in jobsRepo.watchJob(jobId)) {
        if (!mounted) return;

        setState(() {
          _jobStatus = status;
        });

        if (status.isTerminal) {
          setState(() {
            _isPollingJob = false;
            _isRegenerating = false;
          });

          if (status.isCompleted) {
            _loadDetails();
          } else if (status.isFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to generate details: ${status.errorMessage ?? "Unknown error"}',
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Job polling error: $e');
      if (mounted) {
        setState(() {
          _isPollingJob = false;
          _isRegenerating = false;
        });
      }
    }
  }

  Future<void> _toggleItemComplete() async {
    try {
      final repository = ref.read(plansRepositoryProvider);
      final result = await repository.togglePlanItemComplete(widget.itemId);
      if (mounted && _details != null) {
        setState(() {
          _details = _details!.copyWith(
            completed: result.completed,
            progress: result.progress,
          );
        });

        // Also update the plans controller to refresh the week summary
        final item = _details!.item;
        final weekNumber = item.weekStart;
        if (weekNumber != null) {
          ref
              .read(plansControllerProvider.notifier)
              .refreshWeekSummary(weekNumber);
        }
        // Refresh the local plan state too
        ref.read(plansControllerProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _toggleStep(String stepId) async {
    try {
      final repository = ref.read(plansRepositoryProvider);
      final result = await repository.togglePlanStep(widget.itemId, stepId);
      if (mounted && _details?.details != null) {
        // Update the step in local state
        final updatedSteps = _details!.details!.steps.map((step) {
          if (step.id == stepId) {
            return step.copyWith(completed: result.completed);
          }
          return step;
        }).toList();

        setState(() {
          _details = _details!.copyWith(
            completed: result.itemCompleted,
            progress: result.progress,
            details: _details!.details!.copyWith(steps: updatedSteps),
          );
        });

        // Also update the plans controller to refresh the week summary
        final item = _details!.item;
        final weekNumber = item.weekStart;
        if (weekNumber != null) {
          ref
              .read(plansControllerProvider.notifier)
              .refreshWeekSummary(weekNumber);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update step: $e')));
      }
    }
  }

  Future<void> _regenerateDetails() async {
    setState(() {
      _isRegenerating = true;
    });

    try {
      final repository = ref.read(plansRepositoryProvider);
      final response = await repository.regeneratePlanItemDetails(
        widget.itemId,
      );

      if (mounted) {
        // Start polling the job
        _startJobPolling(response.jobId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Regenerating details...'),
            backgroundColor: AppColors.info,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRegenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _openMaterial(PlanMaterial material) async {
    // Reusable book modules are 15-minute reads inside CMPYS.
    if (material.isBook && material.contentMarkdown != null) {
      context.goToInAppLesson(
        title: material.title,
        markdown: material.contentMarkdown!,
        materialId: material.id,
        durationMinutes: material.durationMinutes ?? 15,
        initialProgressPercent: 0,
        initialIsCompleted: false,
      );
      return;
    }

    // prototype-style ideas — open swipeable card reader
    if (material.hasIdeas) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              BookIdeasScreen(bookTitle: material.title, ideas: material.ideas),
        ),
      );
      return;
    }

    // Fallback: markdown content in lesson screen
    if (material.isInAppLesson && material.contentMarkdown != null) {
      context.goToInAppLesson(
        title: material.title,
        markdown: material.contentMarkdown!,
        materialId: material.id,
        durationMinutes: material.durationMinutes,
        initialProgressPercent: 0,
        initialIsCompleted: false,
      );
      return;
    }

    // Video — play in-app with YouTube player
    if (material.isVideo && material.url != null) {
      context.goToPlanVideo(
        title: material.title,
        url: material.url!,
        materialId: material.id,
        source: null,
        reason: material.reason,
      );
      return;
    }

    if (material.isVideo && material.url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This video is not available in-app yet.'),
        ),
      );
      return;
    }

    // External URL
    if (material.url != null) {
      final uri = Uri.tryParse(material.url!);
      if (uri != null) {
        try {
          await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open: ${material.url}')),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PrototypeGridBackground(
        gridSize: 20,
        child: SafeArea(bottom: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingState(message: 'Loading task details...');
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_details == null) {
      return const Center(child: Text('No details available'));
    }

    // Show loading state only while actively polling for details
    // Don't show pending state if there's no job to poll
    if (_isPollingJob) {
      return _buildPendingDetailsState();
    }

    return _buildPathDetail();
  }

  Widget _buildPathDetail() {
    final item = _details!.item;
    final details = _details!.details;
    final actualSteps = details?.steps ?? [];
    final actualMaterials = details?.materials ?? [];
    final syntheticSteps = pathSyntheticSteps(item);
    final syntheticMaterials = pathSyntheticMaterials(item);

    return Column(
      children: [
        _TaskPrototypeHeader(
          taskCode: item.weekStart != null
              ? 'TASK_${item.weekStart}.${item.id.hashCode.abs() % 9}.B'
              : 'TASK_DETAIL',
          onBack: () => Navigator.of(context).pop(),
          onRegenerate: _isRegenerating || _isPollingJob
              ? null
              : _regenerateDetails,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadDetails,
            color: AppColors.mint,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 112),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  item.title,
                  style: AppTypography.h1.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  pathItemSubtitle(item),
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                if (_details!.isGenerating || _isRegenerating) ...[
                  const SizedBox(height: 20),
                  _buildPathGeneratingState(),
                ],
                const SizedBox(height: 34),
                const _PrototypeSectionLabel('Required_Absorption'),
                const SizedBox(height: 16),
                if (actualMaterials.isNotEmpty)
                  ...actualMaterials.map(
                    (material) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PrototypePlanMaterialCard(
                        material: material,
                        onTap: () => _openMaterial(material),
                      ),
                    ),
                  )
                else
                  ...syntheticMaterials.map(
                    (material) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PrototypeSyntheticMaterialCard(
                        material: material,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                const _PrototypeSectionLabel('Execution_Log'),
                const SizedBox(height: 16),
                if (actualSteps.isNotEmpty)
                  ...actualSteps.asMap().entries.map(
                    (entry) => _ExecutionStepCard(
                      step: entry.value,
                      index: entry.key + 1,
                      onToggle: () => _toggleStep(entry.value.id),
                    ),
                  )
                else
                  ...syntheticSteps.asMap().entries.map(
                    (entry) => _ExecutionSyntheticStepCard(
                      step: entry.value,
                      index: entry.key + 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _toggleItemComplete,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
              ),
              child: Text(
                _details!.completed ? 'Reopen Task' : 'Complete Task',
                style: AppTypography.h3.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingDetailsState() {
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_jobStatus?.thinkingStream != null) ...[
              ThinkingStreamWidget(stream: _jobStatus!.thinkingStream!),
              const SizedBox(height: AppSpacing.s32),
            ] else ...[
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              Text('Generating Task Details', style: AppTypography.h3),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'AI is creating personalized steps and resources for this task...',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s32),
            ],
            // Show task title while loading
            if (_details != null) ...[
              CmpysCard(
                padding: AppSpacing.p16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_details!.item.title, style: AppTypography.bodyMedium),
                    if (_details!.item.description != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        _details!.item.description!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return PathEmptyState(
      title: 'Unable to Load Section',
      message: _error!,
      action: CmpysButton(label: 'Try Again', onPressed: _loadDetails),
    );
  }

  Widget _buildPathGeneratingState() {
    return PathGlassPanel(
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.brandAccent),
            ),
          ),
          const SizedBox(width: AppSpacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Generating sections', style: AppTypography.bodyMedium),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Creating steps and materials for this plan item.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPrototypeHeader extends StatelessWidget {
  const _TaskPrototypeHeader({
    required this.taskCode,
    required this.onBack,
    required this.onRegenerate,
  });

  final String taskCode;
  final VoidCallback onBack;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(24, 58, 24, 24),
      child: Row(
        children: [
          _IconFrame(icon: Icons.chevron_left_rounded, onTap: onBack),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Module.Action_Detail',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  taskCode,
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _IconFrame(icon: Icons.bookmark_border_rounded, onTap: onRegenerate),
        ],
      ),
    );
  }
}

class _IconFrame extends StatelessWidget {
  const _IconFrame({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.br12,
      child: InkWell(
        borderRadius: AppRadii.br12,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadii.br12,
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 24),
        ),
      ),
    );
  }
}

class _PrototypeSectionLabel extends StatelessWidget {
  const _PrototypeSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.captionUpper.copyWith(
        color: AppColors.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _PrototypePlanMaterialCard extends StatelessWidget {
  const _PrototypePlanMaterialCard({
    required this.material,
    required this.onTap,
  });

  final PlanMaterial material;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = material.isVideo;
    final isBook = material.isBook || material.contentMarkdown != null;
    final accent = isVideo ? AppColors.brandAccent : AppColors.mint;
    final label = isVideo
        ? 'VIDEO BRIEF'
        : isBook
        ? '15-MIN BOOK'
        : material.kindLabel.toUpperCase();
    final action = isVideo
        ? 'WATCH SESSION'
        : isBook
        ? 'READ NOW'
        : 'OPEN MODULE';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.br16,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br16,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _MaterialThumb(isVideo: isVideo, accent: accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.captionUpper.copyWith(
                        color: accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      material.title,
                      style: AppTypography.h4.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      action,
                      style: AppTypography.captionUpper.copyWith(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrototypeSyntheticMaterialCard extends StatelessWidget {
  const _PrototypeSyntheticMaterialCard({required this.material});

  final PathSyntheticMaterial material;

  @override
  Widget build(BuildContext context) {
    final isVideo = material.kindLabel.toLowerCase().contains('video');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _MaterialThumb(isVideo: isVideo, accent: material.color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.kindLabel.toUpperCase(),
                  style: AppTypography.captionUpper.copyWith(
                    color: material.color,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  material.subtitle,
                  style: AppTypography.h4.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _MaterialThumb extends StatelessWidget {
  const _MaterialThumb({required this.isVideo, required this.accent});

  final bool isVideo;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isVideo ? 56 : 56,
      height: isVideo ? 56 : 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: AppRadii.br8,
        boxShadow: isVideo ? null : AppShadows.sm,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isVideo
                ? Icons.play_circle_outline_rounded
                : Icons.menu_book_rounded,
            color: accent,
            size: isVideo ? 28 : 24,
          ),
        ],
      ),
    );
  }
}

class _ExecutionStepCard extends StatelessWidget {
  const _ExecutionStepCard({
    required this.step,
    required this.index,
    required this.onToggle,
  });

  final PlanStep step;
  final int index;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final detail = step.displayInstruction.trim();
    final expected = step.expectedOutput?.trim();

    return _ExecutionCardShell(
      completed: step.completed,
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExecutionHeader(
            index: index,
            title: step.title,
            completed: step.completed,
            meta: step.estimateMinutes == null
                ? null
                : '${step.estimateMinutes} MIN',
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              detail,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
          if (step.substeps.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...step.substeps.asMap().entries.map(
              (entry) => _SubstepLine(number: entry.key + 1, text: entry.value),
            ),
          ],
          if (expected?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            _ExpectedOutput(text: expected!),
          ],
        ],
      ),
    );
  }
}

class _ExecutionSyntheticStepCard extends StatelessWidget {
  const _ExecutionSyntheticStepCard({required this.step, required this.index});

  final PathSyntheticStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    return _ExecutionCardShell(
      completed: step.completed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExecutionHeader(
            index: index,
            title: step.title,
            completed: step.completed,
          ),
          if (step.subtitle?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              step.subtitle!.trim(),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutionCardShell extends StatelessWidget {
  const _ExecutionCardShell({
    required this.completed,
    required this.child,
    this.onTap,
  });

  final bool completed;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.br12,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: completed ? AppColors.surfaceHighlight : AppColors.surface,
              borderRadius: AppRadii.br12,
              border: Border.all(color: AppColors.borderLight),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ExecutionHeader extends StatelessWidget {
  const _ExecutionHeader({
    required this.index,
    required this.title,
    required this.completed,
    this.meta,
  });

  final int index;
  final String title;
  final bool completed;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            border: Border.all(
              color: completed ? AppColors.mint : AppColors.border,
            ),
            borderRadius: AppRadii.br8,
          ),
          child: completed
              ? const Icon(Icons.check_rounded, size: 13, color: AppColors.mint)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: AppTypography.caption.copyWith(
              color: completed
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
        if (meta != null) ...[
          const SizedBox(width: 8),
          Text(
            meta!,
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9,
            ),
          ),
        ] else
          Text(
            index.toString().padLeft(2, '0'),
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.mint,
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

class _SubstepLine extends StatelessWidget {
  const _SubstepLine({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number.',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.brandAccent,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpectedOutput extends StatelessWidget {
  const _ExpectedOutput({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.mint.withValues(alpha: 0.08),
        borderRadius: AppRadii.br12,
        border: Border.all(color: AppColors.mint.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: AppColors.mint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
