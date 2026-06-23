import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/ambient_background.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../idols/data/jobs_repository.dart';
import '../../idols/models/job_models.dart';
import '../controllers/plans_controller.dart';
import 'widgets/path_design_helpers.dart';

/// Screen shown while a plan is being generated in the background.
///
/// Polls /jobs/{jobId} every 1-2 seconds and shows animated progress.
/// On success, navigates to PlanScreen. On failure, shows retry options.
class GeneratingPlanScreen extends ConsumerStatefulWidget {
  const GeneratingPlanScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<GeneratingPlanScreen> createState() =>
      _GeneratingPlanScreenState();
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
        _errorMessage =
            'Plan generation is taking longer than expected. Please try again.';
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
                _errorMessage =
                    status.errorMessage ??
                    'Plan generation failed. Please try again.';
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
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          child: Padding(
            padding: AppSpacing.screenH,
            child: _hasError
                ? _GenerationErrorContent(
                    errorMessage: _errorMessage,
                    isRetrying: _isRetrying,
                    onRetry: _onRetry,
                    onGoBack: _onGoBack,
                  )
                : _GenerationPathContent(
                    pulseController: _pulseController,
                    progress: progress,
                    stepLabel: stepLabel,
                    isRetrying: _isRetrying,
                    currentStep: _calculateStep(progress),
                  ),
          ),
        ),
      ),
    );
  }

  int _calculateStep(double progress) {
    return (progress * 4).floor().clamp(0, 3);
  }
}

class _GenerationPathContent extends StatelessWidget {
  const _GenerationPathContent({
    required this.pulseController,
    required this.progress,
    required this.stepLabel,
    required this.isRetrying,
    required this.currentStep,
  });

  final AnimationController pulseController;
  final double progress;
  final String stepLabel;
  final bool isRetrying;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final stages = ['Weeks', 'Plan items', 'Steps', 'Materials'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.s32),
        Text(
          isRetrying ? 'Rebuilding Plan' : 'Building Plan',
          style: AppTypography.h1,
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Opening the 12-week plan down into learning sections.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const Spacer(),
        Center(
          child: AnimatedBuilder(
            animation: pulseController,
            builder: (context, child) {
              final scale = 0.96 + (pulseController.value * 0.08);
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: 0.16),
                borderRadius: AppRadii.br32,
                border: Border.all(
                  color: AppColors.brandAccent.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandAccent.withValues(alpha: 0.25),
                    blurRadius: 48,
                  ),
                ],
              ),
              child: const Icon(
                Icons.route_rounded,
                size: 48,
                color: AppColors.brandAccent,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s32),
        PathGlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PathPill(label: '${(progress * 100).round()}%'),
                  const Spacer(),
                  Text(
                    stepLabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              PathProgressStrip(progress: progress),
              const SizedBox(height: AppSpacing.s20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: stages.asMap().entries.map((entry) {
                  final active = entry.key <= currentStep;
                  return Column(
                    children: [
                      AnimatedContainer(
                        duration: AppDurations.fast,
                        width: active ? 28 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.brandAccent
                              : AppColors.textTertiary.withValues(alpha: 0.35),
                          borderRadius: AppRadii.brFull,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        entry.value,
                        style: AppTypography.caption.copyWith(
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _GenerationErrorContent extends StatelessWidget {
  const _GenerationErrorContent({
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
      children: [
        const SizedBox(height: AppSpacing.s24),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: 'Back',
            onPressed: onGoBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: PathEmptyState(
            title: 'Plan Generation Failed',
            message:
                errorMessage ??
                'The plan could not be generated. Try again when ready.',
            action: CmpysButton(
              label: isRetrying ? 'Retrying...' : 'Try Again',
              onPressed: isRetrying ? null : onRetry,
            ),
          ),
        ),
      ],
    );
  }
}
