import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/design_tokens.dart';
import '../../../core/ui/loading_state.dart';
import '../controllers/comparison_controller.dart';
import 'widgets/mirror_card.dart';
import '../models/comparison_models.dart';

class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key});

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  double _currentAge = 28.0;

  @override
  Widget build(BuildContext context) {
    final comparisonState = ref.watch(comparisonControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // -- HEADER --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Mirror', style: AppTypography.h1),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.tune, color: AppColors.textPrimary),
                    style: IconButton.styleFrom(
                      shape: const CircleBorder(side: BorderSide.none),
                    ),
                  ),
                ],
              ),
            ),

            // -- AGE SLIDER CARD --
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.br16,
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'COMPARISON INDEX: AGE',
                        style: AppTypography.captionUpper,
                      ),
                      Text(
                        _currentAge.toInt().toString(),
                        style: AppTypography.h2.copyWith(color: AppColors.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppColors.textPrimary,
                      inactiveTrackColor: AppColors.surfaceHighlight,
                      thumbColor: AppColors.textPrimary,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                      overlayColor: AppColors.textPrimary.withOpacity(0.1),
                    ),
                    child: Slider(
                      min: 18,
                      max: 50,
                      value: _currentAge,
                      onChanged: (v) => setState(() => _currentAge = v),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // -- TIMELINE LABELS --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('YOUR TIMELINE', style: AppTypography.captionUpper),
                  Text('BENCHMARK DATA', style: AppTypography.captionUpper),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // -- TIMELINE BODY --
            Expanded(
              child: switch (comparisonState) {
                ComparisonInitial() || ComparisonLoading() => const LoadingState(
                    message: 'Aligning timelines...',
                  ),
                ComparisonError(:final message) => Center(
                    child: Text(message, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
                  ),
                ComparisonLoaded(:final comparison) => _buildTimeline(comparison),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(ComparisonResponse comparison) {
    // Build timeline data from comparison
    final allEvents = <int, Map<String, dynamic>>{};
    final sortedAges = allEvents.keys.toList()..sort();

    // If empty, show demo data
    if (sortedAges.isEmpty) {
      return _buildDemoTimeline();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: sortedAges.length,
      itemBuilder: (context, index) {
        final age = sortedAges[index];
        final data = allEvents[age]!;
        return MirrorCard(
          age: age,
          userEvent: data['user'] as String?,
          idolEvent: data['idol'] as String? ?? '',
          isMatched: data['user'] != null,
        );
      },
    );
  }

  Widget _buildDemoTimeline() {
    final demoEvents = [
      _TimelineEvent(24, 'Graduated with dual degrees in Engineering and Economics.', 'Graduated UPenn (Physics & Econ).', true),
      _TimelineEvent(25, null, 'Started PhD at Stanford, dropped out in 2 days to build Zip2.', false),
      _TimelineEvent(28, 'Scaled SaaS startup to \$10k MRR. Secured seed funding.', 'Sold Zip2 for \$307 million. Founded X.com.', true),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
      itemCount: demoEvents.length,
      itemBuilder: (context, index) {
        final event = demoEvents[index];
        final isCurrentAge = event.age == _currentAge.toInt();

        return Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline node
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: event.isMatched
                              ? AppColors.emerald
                              : isCurrentAge
                                  ? AppColors.textPrimary
                                  : AppColors.borderLight,
                        ),
                        boxShadow: event.isMatched
                            ? [BoxShadow(color: AppColors.emeraldDim, blurRadius: 12)]
                            : null,
                      ),
                      child: Text(
                        event.age.toString(),
                        style: AppTypography.captionUpper.copyWith(
                          color: event.isMatched
                              ? AppColors.emerald
                              : isCurrentAge
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (index < demoEvents.length - 1)
                      Container(
                        width: 1,
                        height: 100,
                        color: AppColors.borderFocus,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User entry
                    Text('USER', style: AppTypography.captionUpper.copyWith(color: AppColors.emerald)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: event.userEvent != null ? Colors.white.withOpacity(0.02) : Colors.transparent,
                        borderRadius: AppRadii.br12,
                        border: Border.all(
                          color: event.userEvent != null
                              ? (isCurrentAge ? AppColors.textPrimary : AppColors.borderFocus)
                              : AppColors.borderLight,
                          style: event.userEvent != null ? BorderStyle.solid : BorderStyle.none,
                        ),
                      ),
                      child: Text(
                        event.userEvent ?? 'Data gap. Awaiting entry.',
                        style: AppTypography.body.copyWith(
                          color: event.userEvent != null
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Idol entry
                    Text('BENCHMARK', style: AppTypography.captionUpper.copyWith(color: AppColors.blue)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.br12,
                        border: Border.all(
                          color: AppColors.borderFocus,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Text(
                        event.idolEvent,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineEvent {
  final int age;
  final String? userEvent;
  final String idolEvent;
  final bool isMatched;

  _TimelineEvent(this.age, this.userEvent, this.idolEvent, this.isMatched);
}
