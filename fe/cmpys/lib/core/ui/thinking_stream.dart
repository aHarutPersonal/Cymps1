import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/assets.dart';
import '../../app/design_tokens.dart';
import '../../features/idols/models/job_models.dart';
import 'typewriter_text.dart';

/// Widget that displays the AI thinking stream during idol import.
/// Shows completed lines with checkmarks and the current line with typewriter effect.
class ThinkingStreamWidget extends StatelessWidget {
  const ThinkingStreamWidget({super.key, required this.stream, this.idolName});

  final ThinkingStream stream;
  final String? idolName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Completed lines with checkmarks
        ...stream.completedLines
            .where((line) => line.trim().isNotEmpty)
            .map((line) => _CompletedLineWidget(line: line)),

        // Current line with typewriter effect
        if (stream.currentLine.isNotEmpty)
          _CurrentLineWidget(line: stream.currentLine),

        // Insight (if available)
        if (stream.insight != null && stream.insight!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          _InsightWidget(insight: stream.insight!),
        ],
      ],
    );
  }
}

/// A completed line with checkmark icon
class _CompletedLineWidget extends StatelessWidget {
  const _CompletedLineWidget({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            AppAssets.iconCheckCircle,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              AppColors.accent.withValues(alpha: 0.7),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: MarkdownBody(
              data: line,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: AppTypography.body.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    strong: AppTypography.body.copyWith(
                      fontWeight: FontWeight.bold,
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

/// Current line being typed with typewriter effect and spinner
class _CurrentLineWidget extends StatelessWidget {
  const _CurrentLineWidget({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Animated thinking indicator
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: TypewriterText(
              text: line,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              charDuration: const Duration(milliseconds: 10),
              cursor: true,
              cursorColor: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Insight/tip shown as subtle aside
class _InsightWidget extends StatelessWidget {
  const _InsightWidget({required this.insight});

  final String insight;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        padding: AppSpacing.p12,
        decoration: BoxDecoration(
          color: AppColors.accentMuted,
          borderRadius: AppRadii.br8,
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SvgPicture.asset(
              AppAssets.iconSparkles,
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                AppColors.accent,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                insight,
                style: AppTypography.caption.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preview achievements widget shown after 60% progress
class PreviewAchievementsWidget extends StatelessWidget {
  const PreviewAchievementsWidget({
    super.key,
    required this.achievements,
    this.maxItems = 3,
  });

  final List<String> achievements;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discovered so far:',
          style: AppTypography.labelSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        ...achievements
            .take(maxItems)
            .map(
              (achievement) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        achievement,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// Domain tags widget shown after 25% progress
class PreviewDomainsWidget extends StatelessWidget {
  const PreviewDomainsWidget({super.key, required this.domains});

  final List<String> domains;

  @override
  Widget build(BuildContext context) {
    if (domains.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: domains.map((domain) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: AppRadii.brFull,
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Text(
            domain,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        );
      }).toList(),
    );
  }
}
