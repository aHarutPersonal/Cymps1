import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/progress_bar.dart';
import '../../../core/ui/thinking_stream.dart';
import '../../idols/data/jobs_repository.dart';
import '../../idols/models/job_models.dart';
import '../controllers/plans_controller.dart';
import '../data/plans_repository.dart';
import '../models/plan_models.dart';
import 'widgets/news_feed_widget.dart';

/// Screen to display task/plan item details with steps and materials.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.itemId,
  });

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
  String? _currentJobId;
  JobStatus? _jobStatus;
  Timer? _pollTimer;
  int _jobPollFailCount = 0;

  // Track expanded steps
  final Set<String> _expandedSteps = {};

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
        } else if ((details.details == null || details.details!.steps.isEmpty) && 
                   details.detailsStatus != DetailsStatus.failed &&
                   details.jobId == null) {
          // Auto-generate details if missing
          _regenerateDetails();
        }
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
    _currentJobId = jobId;
    _isPollingJob = true;
    _jobPollFailCount = 0;
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
                content: Text('Failed to generate details: ${status.errorMessage ?? "Unknown error"}'),
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
          ref.read(plansControllerProvider.notifier).refreshWeekSummary(weekNumber);
        }
        // Refresh the local plan state too
        ref.read(plansControllerProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
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
          ref.read(plansControllerProvider.notifier).refreshWeekSummary(weekNumber);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update step: $e')),
        );
      }
    }
  }

  Future<void> _regenerateDetails() async {
    setState(() {
      _isRegenerating = true;
    });

    try {
      final repository = ref.read(plansRepositoryProvider);
      final response = await repository.regeneratePlanItemDetails(widget.itemId);
      
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

  void _toggleStepExpansion(String stepId) {
    setState(() {
      if (_expandedSteps.contains(stepId)) {
        _expandedSteps.remove(stepId);
      } else {
        _expandedSteps.add(stepId);
      }
    });
  }

  Future<void> _openMaterial(PlanMaterial material) async {
    if (material.isInAppLesson && material.contentMarkdown != null) {
      // Navigate to in-app lesson screen
      context.goToInAppLesson(
        title: material.title,
        markdown: material.contentMarkdown!,
        materialId: material.id,
        durationMinutes: material.durationMinutes,
      );
    } else if (material.url != null) {
      // Open external URL
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            AppAssets.iconArrowLeft,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              AppColors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _details != null
            ? Text(
                'Task Details',
                style: AppTypography.bodyMedium,
              )
            : null,
      ),
      body: _buildBody(),
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
      return const Center(
        child: Text('No details available'),
      );
    }

    // Show loading state only while actively polling for details
    // Don't show pending state if there's no job to poll
    if (_isPollingJob) {
      return _buildPendingDetailsState();
    }

    return RefreshIndicator(
      onRefresh: _loadDetails,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title, week, estimated hours
            _buildHeader(),
            const SizedBox(height: AppSpacing.s20),

  // Progress section with progress bar
            _buildProgressSection(),
            const SizedBox(height: AppSpacing.s24),

            // News Feed Section
            if (_shouldShowNewsFeed(_details!.item)) ...[
              NewsFeedWidget(query: _details!.item.title),
              const SizedBox(height: AppSpacing.s24),
            ],

            // Regenerate button
            _buildRegenerateButton(),
            const SizedBox(height: AppSpacing.s24),

            // Steps section with expandable cards
            if (_details!.details?.steps.isNotEmpty ?? false) ...[
              _buildStepsSection(),
              const SizedBox(height: AppSpacing.s24),
            ],

            // Materials section
            if (_details!.details?.materials.isNotEmpty ?? false) ...[
              _buildMaterialsSection(),
              const SizedBox(height: AppSpacing.s24),
            ],

            // Generating state indicator
            if (_details!.isGenerating || _isRegenerating) ...[
              _buildGeneratingState(),
              const SizedBox(height: AppSpacing.s24),
            ],

            // Mark complete button
            _buildCompleteButton(),
            const SizedBox(height: AppSpacing.s48),
          ],
        ),
      ),
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
              Text(
                'Generating Task Details',
                style: AppTypography.h3,
              ),
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
                    Text(
                      _details!.item.title,
                      style: AppTypography.bodyMedium,
                    ),
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
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              AppAssets.iconAlertCircle,
              width: 48,
              height: 48,
              colorFilter: const ColorFilter.mode(
                AppColors.error,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text('Unable to load task', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.s8),
            Text(
              _error!,
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Try Again',
              onPressed: _loadDetails,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final item = _details!.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chip and week badge
        Row(
          children: [
            if (item.category != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: AppRadii.brFull,
                ),
                child: Text(
                  item.category!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.accent,
                  ),
                ),
              ),
            if (item.weekStart != null) ...[
              const SizedBox(width: AppSpacing.s8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: AppRadii.brFull,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      AppAssets.iconCalendar,
                      width: 12,
                      height: 12,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Text(
                      item.weekEnd != null && item.weekEnd != item.weekStart
                          ? 'Week ${item.weekStart}-${item.weekEnd}'
                          : 'Week ${item.weekStart}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s16),

        // Title
        Text(
          item.title,
          style: AppTypography.h2.copyWith(
            decoration: _details!.completed ? TextDecoration.lineThrough : null,
            color: _details!.completed
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),

        // Description
        if (item.description != null && item.description!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            item.description!,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],

        // Estimated hours
        if (item.estimatedHours != null) ...[
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              SvgPicture.asset(
                AppAssets.iconClock,
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  AppColors.textTertiary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                '${item.estimatedHours}h estimated',
                style: AppTypography.body.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildProgressSection() {
    final progressPercent = _details!.progressPercent;
    final progressFraction = progressPercent / 100;
    final details = _details!.details;
    final completedSteps = _details!.progress?.completedSteps ?? details?.completedStepsCount ?? 0;
    final totalSteps = _details!.progress?.totalSteps ?? details?.steps.length ?? 0;

    return CmpysCard(
      padding: AppSpacing.p16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress', style: AppTypography.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: _details!.completed
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.brFull,
                ),
                child: Text(
                  '${progressPercent.toStringAsFixed(0)}%',
                  style: AppTypography.buttonSmall.copyWith(
                    color: _details!.completed ? AppColors.success : AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          ProgressBar(
            progress: progressFraction,
            height: 8,
            backgroundColor: AppColors.surface2,
            progressColor: _details!.completed ? AppColors.success : AppColors.accent,
          ),
          if (totalSteps > 0) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              '$completedSteps of $totalSteps steps completed',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegenerateButton() {
    return CmpysButton(
      label: 'Regenerate Details',
      icon: AppAssets.iconRefreshCw,
      variant: CmpysButtonVariant.secondary,
      onPressed: _isRegenerating || _isPollingJob ? null : _regenerateDetails,
      isExpanded: true,
      isLoading: _isRegenerating || _isPollingJob,
    );
  }

  Widget _buildStepsSection() {
    final steps = _details!.details!.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Steps', style: AppTypography.h4),
            Text(
              '${steps.where((s) => s.completed).length}/${steps.length}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        ...steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isExpanded = _expandedSteps.contains(step.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: _ExpandableStepCard(
              step: step,
              index: index + 1,
              isExpanded: isExpanded,
              onToggleComplete: () => _toggleStep(step.id),
              onToggleExpand: () => _toggleStepExpansion(step.id),
              materials: _details!.details!.materials,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMaterialsSection() {
    final materials = _details!.details!.materials;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resources', style: AppTypography.h4),
        const SizedBox(height: AppSpacing.s12),
        ...materials.map((material) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _MaterialCard(
                material: material,
                onTap: () => _openMaterial(material),
              ),
            )),
      ],
    );
  }

  Widget _buildGeneratingState() {
    return CmpysCard(
      padding: AppSpacing.p20,
      backgroundColor: AppColors.info.withOpacity(0.05),
      borderColor: AppColors.info.withOpacity(0.2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.info),
            ),
          ),
          const SizedBox(width: AppSpacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Regenerating Details',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'AI is creating updated steps and resources...',
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

  Widget _buildCompleteButton() {
    return CmpysButton(
      label: _details!.completed ? 'Mark Incomplete' : 'Mark Complete',
      icon: _details!.completed ? AppAssets.iconX : AppAssets.iconCheck,
      variant: _details!.completed
          ? CmpysButtonVariant.secondary
          : CmpysButtonVariant.primary,
      onPressed: _toggleItemComplete,
      isExpanded: true,
    );
  }

  bool _shouldShowNewsFeed(PlanItem item) {
    // Check type or title
    final isReading = item.type.toLowerCase() == 'reading';
    final hasNewsKeyword = item.title.toLowerCase().contains('news') || 
                          item.title.toLowerCase().contains('market') ||
                          item.title.toLowerCase().contains('trend');
    
    return isReading && hasNewsKeyword;
  }
}

/// Expandable card widget for a step.
class _ExpandableStepCard extends StatelessWidget {
  const _ExpandableStepCard({
    required this.step,
    required this.index,
    required this.isExpanded,
    required this.onToggleComplete,
    required this.onToggleExpand,
    required this.materials,
  });

  final PlanStep step;
  final int index;
  final bool isExpanded;
  final VoidCallback onToggleComplete;
  final VoidCallback onToggleExpand;
  final List<PlanMaterial> materials;

  @override
  Widget build(BuildContext context) {
    // Get materials that are linked to this step
    final linkedMaterials = materials
        .where((m) => step.resources.contains(m.id))
        .toList();

    final hasExpandableContent = step.displayInstruction.isNotEmpty ||
        step.expectedOutput != null ||
        linkedMaterials.isNotEmpty;

    return CmpysCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row - always visible
          InkWell(
            onTap: hasExpandableContent ? onToggleExpand : null,
            borderRadius: AppRadii.br16,
            child: Padding(
              padding: AppSpacing.p16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox
                  GestureDetector(
                    onTap: onToggleComplete,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: step.completed ? AppColors.accent : Colors.transparent,
                        shape: BoxShape.circle,
                        border: step.completed
                            ? null
                            : Border.all(color: AppColors.border, width: 2),
                      ),
                      child: step.completed
                          ? const Icon(Icons.check, size: 16, color: AppColors.textPrimary)
                          : Center(
                              child: Text(
                                '$index',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  // Title and meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: AppTypography.bodyMedium.copyWith(
                            decoration: step.completed ? TextDecoration.lineThrough : null,
                            color: step.completed
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (step.estimateMinutes != null) ...[
                          const SizedBox(height: AppSpacing.s4),
                          Row(
                            children: [
                              SvgPicture.asset(
                                AppAssets.iconClock,
                                width: 12,
                                height: 12,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.textTertiary,
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s4),
                              Text(
                                '${step.estimateMinutes} min',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Expand/collapse icon
                  if (hasExpandableContent)
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: AppDurations.fast,
                      child: SvgPicture.asset(
                        AppAssets.iconChevronDown,
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          AppColors.textTertiary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Expanded content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(context, linkedMaterials),
            crossFadeState:
                isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AppDurations.normal,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, List<PlanMaterial> linkedMaterials) {
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.s16,
        right: AppSpacing.s16,
        bottom: AppSpacing.s16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2.withOpacity(0.5),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instruction
          if (step.displayInstruction.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Instructions',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              step.displayInstruction,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
          // Expected Output
          if (step.expectedOutput != null) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Expected Output',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Container(
              padding: AppSpacing.p12,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: AppRadii.br12,
                border: Border.all(
                  color: AppColors.success.withOpacity(0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    AppAssets.iconCheckCircle,
                    width: 16,
                    height: 16,
                    colorFilter: const ColorFilter.mode(
                      AppColors.success,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      step.expectedOutput!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Linked resources
          if (linkedMaterials.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Resources',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: linkedMaterials.map((material) {
                return CmpysTag(
                  label: material.title,
                  small: true,
                  color: material.isInAppLesson
                      ? AppColors.accent
                      : AppColors.info,
                  icon: material.isInAppLesson
                      ? AppAssets.iconBookOpen
                      : AppAssets.iconExternalLink,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card widget for a material/resource.
class _MaterialCard extends StatelessWidget {
  const _MaterialCard({
    required this.material,
    required this.onTap,
  });

  final PlanMaterial material;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      onTap: onTap,
      padding: AppSpacing.p16,
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _getIconBackgroundColor(),
              borderRadius: AppRadii.br12,
            ),
            child: Center(
              child: SvgPicture.asset(
                _getIcon(),
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(
                  _getIconColor(),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        material.title,
                        style: AppTypography.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    _buildKindBadge(),
                  ],
                ),
                if (material.reason != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    material.reason!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (material.durationMinutes != null) ...[
                  const SizedBox(height: AppSpacing.s6),
                  Row(
                    children: [
                      SvgPicture.asset(
                        AppAssets.iconClock,
                        width: 12,
                        height: 12,
                        colorFilter: const ColorFilter.mode(
                          AppColors.textTertiary,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      Text(
                        '${material.durationMinutes} min',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          // Arrow
          SvgPicture.asset(
            AppAssets.iconChevronRight,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              AppColors.textTertiary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKindBadge() {
    final (label, color) = switch (material.type) {
      PlanMaterialType.inAppLesson => ('Lesson', AppColors.accent),
      PlanMaterialType.search => ('Search', AppColors.info),
      PlanMaterialType.book => ('Book', AppColors.info),
      PlanMaterialType.article => ('Article', AppColors.info),
      PlanMaterialType.video => ('Video', AppColors.warning),
      PlanMaterialType.course => ('Course', AppColors.success),
      _ => ('Link', AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadii.brFull,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _getIcon() {
    return switch (material.type) {
      PlanMaterialType.inAppLesson => AppAssets.iconBookOpen,
      PlanMaterialType.search => AppAssets.iconSearch,
      PlanMaterialType.book => AppAssets.iconBookOpen,
      PlanMaterialType.video => AppAssets.iconPlay,
      PlanMaterialType.article => AppAssets.iconFileText,
      _ => AppAssets.iconExternalLink,
    };
  }

  Color _getIconColor() {
    return switch (material.type) {
      PlanMaterialType.inAppLesson => AppColors.accent,
      PlanMaterialType.search => AppColors.info,
      PlanMaterialType.book => AppColors.info,
      PlanMaterialType.video => AppColors.warning,
      PlanMaterialType.course => AppColors.success,
      _ => AppColors.textSecondary,
    };
  }

  Color _getIconBackgroundColor() {
    return switch (material.type) {
      PlanMaterialType.inAppLesson => AppColors.accent.withValues(alpha: 0.15),
      PlanMaterialType.search => AppColors.info.withValues(alpha: 0.15),
      PlanMaterialType.book => AppColors.info.withValues(alpha: 0.15),
      PlanMaterialType.video => AppColors.warning.withValues(alpha: 0.15),
      PlanMaterialType.course => AppColors.success.withValues(alpha: 0.15),
      _ => AppColors.surface2,
    };
  }
}
