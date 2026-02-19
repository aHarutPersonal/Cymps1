import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/progress_bar.dart';
import '../../../core/ui/thinking_stream.dart';
import '../../auth/controllers/session_controller.dart';
import '../../intake/data/intake_repository.dart';
import '../data/idols_repository.dart';
import '../data/jobs_repository.dart';
import '../models/idol_models.dart';
import '../models/job_models.dart';

class EnrichingScreen extends ConsumerStatefulWidget {
  const EnrichingScreen({
    super.key,
    this.jobId,
    this.idolId,
    this.idol,
  });

  final String? jobId;
  final String? idolId;
  final IdolCandidate? idol;

  @override
  ConsumerState<EnrichingScreen> createState() => _EnrichingScreenState();
}

class _EnrichingScreenState extends ConsumerState<EnrichingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _currentJobId = widget.jobId;
    _currentIdolId = widget.idolId;

    // Start polling job status
    _startJobPolling();
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
            _errorMessage = status.errorMessage ?? 'Import failed. Please try again.';
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
      await ref.read(sessionControllerProvider.notifier).setCurrentIdolId(_currentIdolId!);
    }

    if (!mounted) return;

    // Small delay to show completion state before navigating
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted) return;

    // Start intake flow with idol ID and user age
    try {
      final userAge = ref.read(sessionControllerProvider.notifier).userAge;
      final intakeRepository = ref.read(intakeRepositoryProvider);
      
      debugPrint('📋 Starting intake: idolId=$_currentIdolId, targetAge=$userAge');
      
      final intakeResponse = await intakeRepository.startIntake(
        idolId: _currentIdolId,
        targetAge: userAge,
      );

      debugPrint('📋 Intake started: sessionId=${intakeResponse.sessionId}, questions=${intakeResponse.questions.length}');

      if (!mounted) return;

      // Navigate to intake wizard with session and questions
      debugPrint('🚀 Navigating to IntakeWizardScreen');
      context.goToIntake(
        sessionId: intakeResponse.sessionId,
        questions: intakeResponse.questions,
        idolId: _currentIdolId,
        targetAge: userAge,
      );
    } catch (e) {
      // If intake fails, complete onboarding and go to home
      debugPrint('❌ Failed to start intake: $e');
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
      'collecting_sources' || 'fetching' || 'fetch' || 'scraping' => 'Gathering timeline data...',
      'extracting_profile' || 'parsing' || 'parse' => 'Reading profile information...',
      'extracting_achievements' || 'extracting' => 'Analyzing achievements...',
      'normalizing_timeline' || 'enriching' || 'enrich' || 'processing' => 'Building comparison model...',
      'generating_persona' || 'generating' || 'generate' || 'analyzing' => 'Generating insights...',
      'storing_data' || 'finalizing' || 'finalize' || 'completing' => 'Preparing your dashboard...',
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
    final thinkingStream = _jobStatus?.thinkingStream;
    final previewAchievements = _jobStatus?.previewAchievements;
    final previewDomains = _jobStatus?.previewDomains;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Fixed header section
            Padding(
              padding: AppSpacing.screenH,
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.s32),
                  // Header with idol name and progress
                  _HeaderSection(
                    idolName: idolName,
                    hasError: _hasError,
                    isRetrying: _isRetrying,
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  // Progress bar
                  if (!_hasError)
                    _ProgressSection(
                      progress: progress,
                      stepLabel: stepLabel,
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.s24),

            // Scrollable content section
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: AppSpacing.screenH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasError) ...[
                      // Error state
                      _ErrorSection(
                        errorMessage: _errorMessage,
                        isRetrying: _isRetrying,
                        onRetry: _onRetryImport,
                        onChooseDifferent: _onChooseDifferentIdol,
                      ),
                    ] else ...[
                      // Thinking stream (AI text)
                      if (thinkingStream != null) ...[
                        ThinkingStreamWidget(
                          stream: thinkingStream,
                          idolName: idolName,
                        ),
                        const SizedBox(height: AppSpacing.s24),
                      ] else ...[
                        // Fallback animated icon when no thinking stream
                        Center(
                          child: _AnimatedIcon(
                            animation: _pulseController,
                            hasError: false,
                            isRetrying: _isRetrying,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s24),
                      ],

                      // Preview domains (available after 25%)
                      if (previewDomains != null && previewDomains.isNotEmpty) ...[
                        PreviewDomainsWidget(domains: previewDomains),
                        const SizedBox(height: AppSpacing.s24),
                      ],

                      // Preview achievements (available after 60%)
                      if (previewAchievements != null && previewAchievements.isNotEmpty) ...[
                        PreviewAchievementsWidget(achievements: previewAchievements),
                        const SizedBox(height: AppSpacing.s24),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // Step indicators and skip button at bottom
            if (!_hasError && !_isRetrying)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s24),
                child: Column(
                  children: [
                    _StepIndicators(
                      totalSteps: 5,
                      currentStep: _calculateStep(progress),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    // Skip button - allows proceeding even if enrichment is slow
                    CmpysButton(
                      label: 'Skip for Now',
                      variant: CmpysButtonVariant.ghost,
                      onPressed: _onSkipEnrichment,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Skip enrichment and proceed directly to intake
  Future<void> _onSkipEnrichment() async {
    debugPrint('⏭️ Skipping enrichment, proceeding to intake');
    
    // Stop polling
    _stopPolling();
    
    // If we have an idol ID, proceed to intake
    if (_currentIdolId != null) {
      await ref.read(sessionControllerProvider.notifier).setCurrentIdolId(_currentIdolId!);
      
      if (!mounted) return;
      
      try {
        final userAge = ref.read(sessionControllerProvider.notifier).userAge;
        final intakeRepository = ref.read(intakeRepositoryProvider);
        
        debugPrint('📋 Starting intake (skipped enrichment): idolId=$_currentIdolId, targetAge=$userAge');
        
        final intakeResponse = await intakeRepository.startIntake(
          idolId: _currentIdolId,
          targetAge: userAge,
        );

        debugPrint('📋 Intake started: sessionId=${intakeResponse.sessionId}, questions=${intakeResponse.questions.length}');

        if (!mounted) return;

        context.goToIntake(
          sessionId: intakeResponse.sessionId,
          questions: intakeResponse.questions,
          idolId: _currentIdolId,
          targetAge: userAge,
        );
      } catch (e) {
        debugPrint('❌ Failed to start intake after skip: $e');
        // Fallback to home if intake fails
        await ref.read(sessionControllerProvider.notifier).completeOnboarding();
        
        if (!mounted) return;
        context.go(AppRoutes.home);
      }
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

/// Header section with idol name and title
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.idolName,
    required this.hasError,
    required this.isRetrying,
  });

  final String idolName;
  final bool hasError;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Subtitle
        AnimatedSwitcher(
          duration: AppDurations.normal,
          child: Text(
            hasError
                ? 'Import Failed'
                : isRetrying
                    ? 'Retrying...'
                    : 'Researching',
            key: ValueKey(hasError ? 'error' : isRetrying ? 'retry' : 'loading'),
            style: AppTypography.body.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        // Idol name
        Text(
          idolName,
          style: AppTypography.h2.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Progress section with bar and step label
class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.progress,
    required this.stepLabel,
  });

  final double progress;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Progress bar
        ProgressBar(
          progress: progress,
          height: 6,
          animated: true,
        ),
        const SizedBox(height: AppSpacing.s8),
        // Percentage and step label
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).round()}% complete',
              style: AppTypography.caption.copyWith(
                color: AppColors.accent,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            Flexible(
              child: Text(
                stepLabel,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
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
    return Center(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.s32),
          // Error icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
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
              errorMessage ?? 'An error occurred',
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
}

/// Animated icon widget (fallback when no thinking stream)
class _AnimatedIcon extends StatelessWidget {
  const _AnimatedIcon({
    required this.animation,
    required this.hasError,
    required this.isRetrying,
  });

  final Animation<double> animation;
  final bool hasError;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final color = hasError ? AppColors.error : AppColors.accent;
          final colorLight = hasError ? AppColors.error.withOpacity(0.7) : AppColors.accentLight;

          return Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, colorLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(animation.value * 6.28),
              ),
              borderRadius: AppRadii.br24,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: hasError
                  ? SvgPicture.asset(
                      AppAssets.iconAlertCircle,
                      width: 44,
                      height: 44,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    )
                  : SvgPicture.asset(
                      AppAssets.iconSparkles,
                      width: 44,
                      height: 44,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Step indicators at bottom
class _StepIndicators extends StatelessWidget {
  const _StepIndicators({
    required this.totalSteps,
    required this.currentStep,
  });

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
