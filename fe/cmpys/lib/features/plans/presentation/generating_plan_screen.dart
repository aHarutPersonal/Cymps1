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
import '../../idols/data/jobs_repository.dart';
import '../../idols/models/job_models.dart';
import '../controllers/plans_controller.dart';

/// Screen shown while a plan is being generated in the background.
///
/// Polls /jobs/{jobId} every 1-2 seconds and shows animated progress.
/// On success, navigates to PlanScreen. On failure, shows retry options.
class GeneratingPlanScreen extends ConsumerStatefulWidget {
  const GeneratingPlanScreen({
    super.key,
    required this.jobId,
  });

  final String jobId;

  @override
  ConsumerState<GeneratingPlanScreen> createState() => _GeneratingPlanScreenState();
}

class _GeneratingPlanScreenState extends ConsumerState<GeneratingPlanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  JobStatus? _jobStatus;
  bool _hasError = false;
  String? _errorMessage;
  bool _isRetrying = false;
  StreamSubscription<JobStatus>? _jobSubscription;
  Timer? _timeoutTimer;

  // Timeout duration (5 minutes)
  static const _timeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Handle mock jobs (from mock intake) - simulate success after a short delay
    if (widget.jobId.startsWith('mock-job-')) {
      debugPrint('🎭 Mock job detected - simulating plan generation');
      _simulateMockJobCompletion();
    } else {
      _startJobPolling();
      _startTimeoutTimer();
    }
  }

  /// Simulate job completion for mock intake sessions
  Future<void> _simulateMockJobCompletion() async {
    // Simulate progress updates
    for (int progress = 10; progress <= 100; progress += 15) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _jobStatus = JobStatus(
          id: widget.jobId,
          status: progress < 100 ? 'running' : 'completed',
          step: progress < 100 ? 'generating' : 'done',
          progressPercent: progress,
        );
      });
    }
    
    // Navigate to home after completion
    await Future.delayed(const Duration(milliseconds: 500));
    _onJobComplete();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopPolling();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _stopPolling() {
    _jobSubscription?.cancel();
    _jobSubscription = null;
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, () {
      if (!mounted) return;
      _stopPolling();
      setState(() {
        _hasError = true;
        _errorMessage = 'Plan generation is taking longer than expected. Please try again.';
      });
    });
  }

  /// Start polling job status from GET /jobs/{jobId} every 1.5 seconds
  void _startJobPolling() {
    // Cancel any existing subscription
    _stopPolling();

    final jobsRepository = ref.read(jobsRepositoryProvider);

    // Poll every 1.5 seconds (between 1-2s as requested)
    _jobSubscription = jobsRepository
        .watchJob(
      widget.jobId,
      pollInterval: const Duration(milliseconds: 1500),
    )
        .listen(
      (status) {
        if (!mounted) return;

        setState(() => _jobStatus = status);

        // Stop polling when status is terminal (done/failed)
        if (status.isCompleted) {
          _stopPolling();
          _timeoutTimer?.cancel();
          _onJobComplete();
        } else if (status.isFailed) {
          _stopPolling();
          _timeoutTimer?.cancel();
          setState(() {
            _hasError = true;
            _errorMessage = status.errorMessage ?? 'Plan generation failed. Please try again.';
          });
        }
      },
      onError: (error) {
        if (!mounted) return;
        _stopPolling();
        _timeoutTimer?.cancel();
        setState(() {
          _hasError = true;
          _errorMessage = error.toString();
        });
      },
    );
  }

  /// Called when job completes successfully
  Future<void> _onJobComplete() async {
    if (!mounted) return;

    // Small delay to show completion state
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    // Refresh plan data before navigating
    await ref.read(plansControllerProvider.notifier).load();

    if (!mounted) return;

    // Navigate to plan screen
    context.go(AppRoutes.plan);
  }

  /// Retry plan generation
  Future<void> _onRetry() async {
    setState(() {
      _isRetrying = true;
      _hasError = false;
      _errorMessage = null;
      _jobStatus = null;
    });

    try {
      // Regenerate plan via controller
      await ref.read(plansControllerProvider.notifier).generatePlan();

      if (!mounted) return;

      // Check if plan was generated successfully
      final plansState = ref.read(plansControllerProvider);
      if (plansState is PlansLoaded) {
        // Plan generated successfully, navigate to plan screen
        context.go(AppRoutes.plan);
      } else if (plansState is PlansError) {
        setState(() {
          _isRetrying = false;
          _hasError = true;
          _errorMessage = plansState.message;
        });
      } else {
        setState(() => _isRetrying = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// Go back to previous screen
  void _onGoBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  String _getStepLabel(String? step) {
    if (step == null) return 'Preparing your plan...';

    return switch (step.toLowerCase()) {
      'analyzing' || 'analysis' => 'Analyzing your goals...',
      'comparing' || 'comparison' => 'Comparing with idol timeline...',
      'generating' || 'generate' => 'Generating personalized tasks...',
      'optimizing' || 'optimize' => 'Optimizing your schedule...',
      'finalizing' || 'finalize' => 'Finalizing your plan...',
      'pending' => 'Starting plan generation...',
      'running' || 'in_progress' => 'Creating your plan...',
      'done' => 'Plan ready!',
      _ => step,
    };
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_jobStatus?.progressPercent ?? 0) / 100;
    final stepLabel = _getStepLabel(_jobStatus?.step);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenH,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.s24),

              // Back button (only show when there's an error)
              if (_hasError)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: _onGoBack,
                    icon: SvgPicture.asset(
                      AppAssets.iconArrowLeft,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),

              const Spacer(),

              // Main content
              if (_hasError)
                _ErrorContent(
                  errorMessage: _errorMessage,
                  isRetrying: _isRetrying,
                  onRetry: _onRetry,
                  onGoBack: _onGoBack,
                )
              else
                _LoadingContent(
                  pulseController: _pulseController,
                  progress: progress,
                  stepLabel: stepLabel,
                  isRetrying: _isRetrying,
                ),

              const Spacer(),

              // Step indicators
              if (!_hasError)
                _StepIndicators(
                  totalSteps: 4,
                  currentStep: _calculateStep(progress),
                ),

              const SizedBox(height: AppSpacing.s48),
            ],
          ),
        ),
      ),
    );
  }

  int _calculateStep(double progress) {
    return (progress * 4).floor().clamp(0, 3);
  }
}

/// Loading content with animated icon and progress
class _LoadingContent extends StatelessWidget {
  const _LoadingContent({
    required this.pulseController,
    required this.progress,
    required this.stepLabel,
    required this.isRetrying,
  });

  final AnimationController pulseController;
  final double progress;
  final String stepLabel;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated icon
        _AnimatedPlanIcon(animation: pulseController),
        const SizedBox(height: AppSpacing.s32),

        // Title
        Text(
          isRetrying ? 'Regenerating Plan...' : 'Generating Your Plan',
          style: AppTypography.h2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s8),

        // Subtitle
        Text(
          'Creating a personalized plan based on\nyour idol\'s journey',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s32),

        // Progress bar
        Padding(
          padding: AppSpacing.ph16,
          child: Column(
            children: [
              ProgressBar(
                progress: progress,
                height: 6,
                animated: true,
              ),
              const SizedBox(height: AppSpacing.s12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(progress * 100).round()}%',
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
          ),
        ),
        const SizedBox(height: AppSpacing.s24),

        // Tips
        _PlanTip(),
      ],
    );
  }
}

/// Animated plan generation icon
class _AnimatedPlanIcon extends StatelessWidget {
  const _AnimatedPlanIcon({required this.animation});

  final Animation<double> animation;

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
          return Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent, AppColors.accentLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(animation.value * 6.28),
              ),
              borderRadius: AppRadii.br24,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Main icon
                SvgPicture.asset(
                  AppAssets.iconListChecks,
                  width: 40,
                  height: 40,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                // Sparkle overlay
                Positioned(
                  top: 12,
                  right: 12,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final scale = 0.8 + 0.4 * ((animation.value * 2) % 1);
                      return Transform.scale(
                        scale: scale,
                        child: SvgPicture.asset(
                          AppAssets.iconSparkles,
                          width: 16,
                          height: 16,
                          colorFilter: const ColorFilter.mode(
                            AppColors.textPrimary,
                            BlendMode.srcIn,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tip shown during generation
class _PlanTip extends StatefulWidget {
  @override
  State<_PlanTip> createState() => _PlanTipState();
}

class _PlanTipState extends State<_PlanTip> {
  int _tipIndex = 0;
  Timer? _tipTimer;

  static const _tips = [
    'Your plan will include weekly tasks and milestones',
    'Track your progress and stay motivated',
    'Adjust tasks to fit your schedule',
    'Complete tasks to level up your journey',
  ];

  @override
  void initState() {
    super.initState();
    _tipTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
      }
    });
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            AppAssets.iconInfo,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              AppColors.accent,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.normal,
              child: Text(
                _tips[_tipIndex],
                key: ValueKey(_tipIndex),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error content with retry options
class _ErrorContent extends StatelessWidget {
  const _ErrorContent({
    required this.errorMessage,
    required this.isRetrying,
    required this.onRetry,
    required this.onGoBack,
  });

  final String? errorMessage;
  final bool isRetrying;
  final VoidCallback onRetry;
  final VoidCallback onGoBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: AppRadii.br24,
          ),
          child: Center(
            child: SvgPicture.asset(
              AppAssets.iconAlertCircle,
              width: 40,
              height: 40,
              colorFilter: const ColorFilter.mode(
                AppColors.error,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s24),

        // Title
        Text(
          'Generation Failed',
          style: AppTypography.h2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s8),

        // Error message
        Padding(
          padding: AppSpacing.ph16,
          child: Text(
            errorMessage ?? 'An unexpected error occurred',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.s32),

        // Retry button
        CmpysButton(
          label: 'Try Again',
          onPressed: isRetrying ? null : onRetry,
          isLoading: isRetrying,
          icon: AppAssets.iconRefreshCw,
        ),
        const SizedBox(height: AppSpacing.s12),

        // Go back button
        CmpysButton(
          label: 'Go Back',
          variant: CmpysButtonVariant.ghost,
          onPressed: isRetrying ? null : onGoBack,
        ),
        const SizedBox(height: AppSpacing.s24),

        // Support message
        Container(
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br16,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                AppAssets.iconCircleHelp,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help?',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      'If the problem persists, please contact support.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
