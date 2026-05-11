import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/ambient_background.dart';
import '../../../core/ui/loading_state.dart';
import '../controllers/comparison_controller.dart';
import '../models/comparison_models.dart';

class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key});

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(comparisonControllerProvider);
      if (state is ComparisonInitial) {
        ref.read(comparisonControllerProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check if achievements changed while the app was in background
      ref.read(comparisonControllerProvider.notifier).checkAndRefreshIfNeeded();
    }
  }

  /// Called when the tab is re-selected (navigated back to).
  /// We check eagerly via initState + addPostFrameCallback already,
  /// but this also fires when switching between tabs.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Non-blocking check: auto-refresh if achievements changed
    ref.read(comparisonControllerProvider.notifier).checkAndRefreshIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final comparisonState = ref.watch(comparisonControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // -- HEADER --
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button (now a push route, not a tab)
                    GestureDetector(
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.arrow_back_ios_rounded,
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Back',
                              style: AppTypography.body.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      'Comparative Growth',
                      style: AppTypography.h2.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your trajectory vs. your idol',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // -- REFRESHING INDICATOR --
              if (comparisonState is ComparisonLoaded &&
                  comparisonState.isRefreshing)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: AppColors.accent.withValues(alpha: 0.08),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Updating comparison...',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // -- CONTENT --
              Expanded(
                child: switch (comparisonState) {
                  ComparisonInitial() ||
                  ComparisonLoading() => const LoadingState(
                    messages: [
                      'Analyzing your growth trajectory...',
                      'Aligning historical timelines...',
                      'Calculating category scores...',
                    ],
                  ),
                  ComparisonError(:final message) => _buildErrorState(message),
                  ComparisonLoaded(:final comparison) => _buildContent(
                    comparison,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    final needsIdol =
        message.toLowerCase().contains('idol') ||
        message.toLowerCase().contains('choose an idol');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              needsIdol ? Icons.explore_outlined : Icons.error_outline,
              color: needsIdol ? AppColors.accent : AppColors.error,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text(
              needsIdol ? 'Choose Your North Star' : 'Comparison Unavailable',
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              needsIdol
                  ? 'Pick a benchmark before comparing your trajectory.'
                  : message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: needsIdol
                  ? () => context.goToIdolSuggest()
                  : () =>
                        ref.read(comparisonControllerProvider.notifier).load(),
              child: Text(needsIdol ? 'Choose Idol' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ComparisonResponse comparison) {
    final overallScore = comparison.overallScore.clamp(0, 100);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),

            // -- OVERALL RING --
            Center(
              child: SizedBox(
                width: 192,
                height: 192,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(192, 192),
                      painter: _ProgressRingPainter(
                        progress: overallScore / 100,
                        strokeWidth: 12,
                        trackColor: AppColors.surfaceHighlight,
                        progressColor: AppColors.accent,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$overallScore%',
                          style: AppTypography.h1.copyWith(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'OVERALL SYNC',
                          style: AppTypography.captionUpper.copyWith(
                            color: AppColors.textSecondary,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // -- METRICS GRID --
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'STRENGTHS',
                    title: comparison.strengths.isNotEmpty
                        ? comparison.strengths.first.category
                        : 'Discipline',
                    progress: comparison.categoryBreakdown.isNotEmpty
                        ? comparison.categoryBreakdown.first.userScore / 100
                        : 0.9,
                    color: const Color(0xFF16A34A), // green-600
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _MetricCard(
                    label: 'GAPS',
                    title: comparison.gaps.isNotEmpty
                        ? comparison.gaps.first.category
                        : 'Social Capital',
                    progress: comparison.categoryBreakdown.length > 1
                        ? comparison.categoryBreakdown.last.userScore / 100
                        : 0.35,
                    color: const Color(0xFFF87171), // red-400
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // -- AI INTELLIGENCE SUMMARY --
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI INTELLIGENCE SUMMARY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    (comparison.overallAnalysis ?? '').isNotEmpty
                        ? comparison.overallAnalysis!
                        : 'You are showing strong potential in personal development. Focus on building your network and strategic partnerships to accelerate your trajectory.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => context.goToComparisonDetail(comparison),
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: AppRadii.br16,
                      ),
                      child: Center(
                        child: Text(
                          'VIEW DETAILED REPORT',
                          style: AppTypography.captionUpper.copyWith(
                            fontSize: 11,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Metric card for strengths/gaps.
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.title,
    required this.progress,
    required this.color,
  });

  final String label;
  final String title;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br20,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: AppRadii.brFull,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: AppColors.surfaceHighlight,
              color: color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom progress ring painter.
class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
