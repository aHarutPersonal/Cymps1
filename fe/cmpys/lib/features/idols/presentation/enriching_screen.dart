import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../auth/controllers/session_controller.dart';
import '../data/idols_repository.dart';
import '../data/jobs_repository.dart';
import '../models/idol_models.dart';
import '../models/job_models.dart';
import 'idol_visuals.dart';

class EnrichingScreen extends ConsumerStatefulWidget {
  const EnrichingScreen({super.key, this.jobId, this.idolId, this.idol});

  final String? jobId;
  final String? idolId;
  final IdolCandidate? idol;

  @override
  ConsumerState<EnrichingScreen> createState() => _EnrichingScreenState();
}

class _EnrichingScreenState extends ConsumerState<EnrichingScreen> {
  final ScrollController _scrollController = ScrollController();

  JobStatus? _jobStatus;
  bool _hasError = false;
  String? _errorMessage;
  bool _isRetrying = false;
  StreamSubscription<JobStatus>? _jobSubscription;

  // Store IDs for retry
  String? _currentJobId;
  String? _currentIdolId;

  @override
  void initState() {
    super.initState();
    _currentJobId = widget.jobId;
    _currentIdolId = widget.idolId;

    // Start polling job status
    _startJobPolling();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _stopPolling();
    super.dispose();
  }

  void _stopPolling() {
    _jobSubscription?.cancel();
    _jobSubscription = null;
  }

  /// Start polling job status from GET /jobs/{jobId} every 1.5 seconds
  void _startJobPolling() {
    // If we have an idol ID but no job ID, it means the import was instant
    if (_currentJobId == null && _currentIdolId != null) {
      _onJobComplete();
      return;
    }

    if (_currentJobId == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'No job ID provided';
      });
      return;
    }

    // Cancel any existing subscription
    _stopPolling();

    final jobsRepository = ref.read(jobsRepositoryProvider);

    // Poll every 1.5 seconds (between 1-2s as requested)
    _jobSubscription = jobsRepository
        .watchJob(
          _currentJobId!,
          pollInterval: const Duration(milliseconds: 1500),
        )
        .listen(
          (status) {
            if (!mounted) return;

            setState(() => _jobStatus = status);
            _scrollToBottom();

            // Store idol ID from job status if available
            if (status.idolId != null) {
              _currentIdolId = status.idolId;
            }

            // Stop polling when status is terminal (done/failed)
            if (status.isCompleted) {
              _stopPolling();
              _onJobComplete();
            } else if (status.isFailed) {
              _stopPolling();
              setState(() {
                _hasError = true;
                _errorMessage =
                    status.errorMessage ?? 'Import failed. Please try again.';
              });
            }
          },
          onError: (error) {
            if (!mounted) return;
            _stopPolling();
            setState(() {
              _hasError = true;
              _errorMessage = error.toString();
            });
          },
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Called when job completes successfully (status = done)
  Future<void> _onJobComplete() async {
    debugPrint('✅ _onJobComplete called, idolId: $_currentIdolId');

    // Store idol ID in session
    if (_currentIdolId != null) {
      await ref
          .read(sessionControllerProvider.notifier)
          .setCurrentIdolId(_currentIdolId!);
    }

    if (!mounted) return;

    // Small delay to show completion state before navigating
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    // Navigate to achievement intake first (before general intake)
    if (_currentIdolId != null) {
      final userAge = ref.read(sessionControllerProvider.notifier).userAge;
      context.goToAchievementIntake(
        idolId: _currentIdolId!,
        targetAge: userAge,
        mentorName: widget.idol?.name,
        mentorImageUrl: widget.idol != null
            ? imageUrlForIdolCandidate(widget.idol!)
            : null,
      );
    } else {
      // Fallback: skip to home
      await ref.read(sessionControllerProvider.notifier).completeOnboarding();
      if (!mounted) return;
      context.go(AppRoutes.home);
    }
  }

  /// Re-run import for the same idol (POST /idols/import again)
  Future<void> _onRetryImport() async {
    if (widget.idol == null) {
      // No idol info, go back to selection
      _onChooseDifferentIdol();
      return;
    }

    setState(() {
      _isRetrying = true;
      _hasError = false;
      _errorMessage = null;
      _jobStatus = null;
    });

    try {
      // Re-call POST /idols/import
      final idolsRepository = ref.read(idolsRepositoryProvider);
      final importResponse = await idolsRepository.importIdol(
        provider: widget.idol!.provider,
        externalId: widget.idol!.externalId,
      );

      if (!mounted) return;

      // Update IDs and restart polling
      setState(() {
        _currentJobId = importResponse.jobId;
        _currentIdolId = importResponse.idolId;
        _isRetrying = false;
      });

      _startJobPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// Go back to idol selection
  void _onChooseDifferentIdol() {
    context.go(AppRoutes.idolSuggest);
  }

  String _getStepLabel(String? step) {
    if (step == null) return 'Preparing...';

    return switch (step.toLowerCase()) {
      'collecting_sources' ||
      'fetching' ||
      'fetch' ||
      'scraping' => 'Gathering timeline data...',
      'extracting_profile' ||
      'parsing' ||
      'parse' => 'Reading profile information...',
      'extracting_achievements' || 'extracting' => 'Analyzing achievements...',
      'normalizing_timeline' ||
      'enriching' ||
      'enrich' ||
      'processing' => 'Building comparison model...',
      'generating_persona' ||
      'generating' ||
      'generate' ||
      'analyzing' => 'Generating insights...',
      'storing_data' ||
      'finalizing' ||
      'finalize' ||
      'completing' => 'Preparing your dashboard...',
      'pending' => 'Starting import...',
      'running' || 'in_progress' => 'Processing...',
      'done' => 'Complete!',
      _ => step,
    };
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_jobStatus?.progressPercent ?? 0) / 100;
    final stepLabel = _getStepLabel(_jobStatus?.step);
    // Prefer idol name from job status, fallback to widget idol
    final idolName = _jobStatus?.idolName ?? widget.idol?.name ?? 'your idol';
    final previewDomains = _jobStatus?.previewDomains;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: PrototypeGridBackground(
        color: AppColors.surface,
        child: SafeArea(
          child: _hasError
              ? SingleChildScrollView(
                  padding: AppSpacing.p24,
                  child: _ErrorSection(
                    errorMessage: _errorMessage,
                    isRetrying: _isRetrying,
                    onRetry: _onRetryImport,
                    onChooseDifferent: _onChooseDifferentIdol,
                  ),
                )
              : Padding(
                  padding: AppSpacing.p24,
                  child: Column(
                    children: [
                      const Spacer(),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _ThinkingRing(inset: 0, opacity: 0.10),
                            _ThinkingRing(inset: 40, opacity: 0.20),
                            _ThinkingRing(inset: 80, opacity: 0.40),
                            Container(
                              width: 192,
                              height: 192,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.mint,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.mint.withValues(
                                      alpha: 0.20,
                                    ),
                                    blurRadius: 40,
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.network(
                                widget.idol != null
                                    ? imageUrlForIdolCandidate(widget.idol!)
                                    : kPrototypeThinkingAsset,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.mint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Engine.Reasoning_Active',
                            style: AppTypography.captionUpper.copyWith(
                              color: AppColors.mint,
                              fontSize: 10,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Text(
                        'Synthesizing\n$idolName...',
                        style: AppTypography.h2.copyWith(height: 1.2),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.s24),
                      Container(
                        width: double.infinity,
                        padding: AppSpacing.p20,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight,
                          border: Border.all(color: AppColors.borderLight),
                          borderRadius: AppRadii.br12,
                        ),
                        child: Column(
                          children: [
                            _ThinkingLogRow(
                              label: 'COLLECTING_SOURCE_GRAPH',
                              complete: progress >= 0.20,
                            ),
                            _ThinkingLogRow(
                              label: 'READING_PROFILE_INFORMATION',
                              active: stepLabel.contains('Reading'),
                              complete: progress >= 0.35,
                            ),
                            _ThinkingLogRow(
                              label: 'EXTRACTING_ACHIEVEMENT_NODES',
                              active:
                                  stepLabel.contains('achievement') ||
                                  stepLabel.contains('Analyzing'),
                              complete: progress >= 0.60,
                            ),
                            _ThinkingLogRow(
                              label: 'ALIGNING_COMPARISON_PROTOCOL',
                              active: progress > 0.60,
                              complete: progress >= 1.0,
                            ),
                          ],
                        ),
                      ),
                      if (previewDomains != null &&
                          previewDomains.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: previewDomains
                              .map(
                                (domain) => Chip(
                                  label: Text(domain),
                                  backgroundColor: AppColors.surface,
                                  side: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const Spacer(),
                      _StepIndicators(
                        totalSteps: 5,
                        currentStep: _calculateStep(progress),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      CmpysButton(
                        label: 'Skip for Now',
                        variant: CmpysButtonVariant.ghost,
                        onPressed: _onSkipEnrichment,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Skip enrichment and proceed directly to achievement intake
  Future<void> _onSkipEnrichment() async {
    debugPrint('⏭️ Skipping enrichment, proceeding to achievement intake');

    // Stop polling
    _stopPolling();

    // If we have an idol ID, proceed to achievement intake
    if (_currentIdolId != null) {
      await ref
          .read(sessionControllerProvider.notifier)
          .setCurrentIdolId(_currentIdolId!);

      if (!mounted) return;

      final userAge = ref.read(sessionControllerProvider.notifier).userAge;
      context.goToAchievementIntake(
        idolId: _currentIdolId!,
        targetAge: userAge,
        mentorName: widget.idol?.name,
        mentorImageUrl: widget.idol != null
            ? imageUrlForIdolCandidate(widget.idol!)
            : null,
      );
    } else {
      // No idol ID available, complete onboarding and go home
      await ref.read(sessionControllerProvider.notifier).completeOnboarding();

      if (!mounted) return;
      context.go(AppRoutes.home);
    }
  }

  int _calculateStep(double progress) {
    return (progress * 5).floor().clamp(0, 4);
  }
}

class _ThinkingRing extends StatelessWidget {
  const _ThinkingRing({required this.inset, required this.opacity});

  final double inset;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      left: inset,
      right: inset,
      top: inset,
      bottom: inset,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.mint.withValues(alpha: opacity)),
        ),
      ),
    );
  }
}

class _ThinkingLogRow extends StatelessWidget {
  const _ThinkingLogRow({
    required this.label,
    this.active = false,
    this.complete = false,
  });

  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: active || complete ? 1 : 0.30,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.captionUpper.copyWith(
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontSize: 9,
                ),
              ),
            ),
            if (complete)
              const Icon(Icons.check_rounded, color: AppColors.mint, size: 14)
            else if (active)
              Container(width: 12, height: 2, color: AppColors.mint),
          ],
        ),
      ),
    );
  }
}

/// Error section with retry buttons
class _ErrorSection extends StatelessWidget {
  const _ErrorSection({
    required this.errorMessage,
    required this.isRetrying,
    required this.onRetry,
    required this.onChooseDifferent,
  });

  final String? errorMessage;
  final bool isRetrying;
  final VoidCallback onRetry;
  final VoidCallback onChooseDifferent;

  @override
  Widget build(BuildContext context) {
    final displayMessage = _friendlyError(errorMessage);
    return Center(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.s32),
          // Error icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: AppRadii.br16,
            ),
            child: Center(
              child: SvgPicture.asset(
                AppAssets.iconAlertCircle,
                width: 32,
                height: 32,
                colorFilter: const ColorFilter.mode(
                  AppColors.error,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
          // Error message
          Padding(
            padding: AppSpacing.ph16,
            child: Text(
              displayMessage,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.s32),
          // Retry buttons
          CmpysButton(
            label: 'Try Again',
            onPressed: isRetrying ? null : onRetry,
            isLoading: isRetrying,
          ),
          const SizedBox(height: AppSpacing.s12),
          CmpysButton(
            label: 'Choose Different Idol',
            variant: CmpysButtonVariant.ghost,
            onPressed: isRetrying ? null : onChooseDifferent,
          ),
        ],
      ),
    );
  }

  String _friendlyError(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'We could not finish importing this idol. Please try again.';
    }

    if (raw.contains('user_id') || raw.contains('IdolImportJob')) {
      return 'We could not finish preparing personalized materials for this idol. The import can be retried safely.';
    }

    return raw;
  }
}

/// Step indicators at bottom
class _StepIndicators extends StatelessWidget {
  const _StepIndicators({required this.totalSteps, required this.currentStep});

  final int totalSteps;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final isActive = index <= currentStep;
        final isCurrent = index == currentStep;
        return AnimatedContainer(
          duration: AppDurations.fast,
          width: isCurrent ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accent : AppColors.surface2,
            borderRadius: AppRadii.brFull,
          ),
        );
      }),
    );
  }
}
