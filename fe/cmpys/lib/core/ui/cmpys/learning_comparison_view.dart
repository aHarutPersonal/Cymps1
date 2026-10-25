import 'package:flutter/material.dart';
import '../../../app/design_tokens.dart';
import '../../reading/learning_comparison.dart';

/// Text remains ordinary selectable Flutter text. Narration supplies spans in
/// this same semantic coordinate space instead of maintaining a second copy.
class LearningComparisonView extends StatelessWidget {
  const LearningComparisonView({
    super.key,
    required this.comparison,
    required this.fontSize,
    this.dark = false,
    this.spansForRange,
  });
  final LearningComparison comparison;
  final double fontSize;
  final bool dark;
  final List<InlineSpan> Function(int start, int end)? spansForRange;

  Widget _text(ComparisonTextRange range, TextStyle style) => Text.rich(
    TextSpan(
      children:
          spansForRange?.call(range.start, range.end) ??
          [TextSpan(text: comparison.text.substring(range.start, range.end))],
    ),
    style: style,
  );

  Widget _item(ComparisonTextRange range, Color ink, Color muted) {
    final value = comparison.text.substring(range.start, range.end);
    final detail = value.indexOf(' (');
    if (detail < 0 || !value.endsWith(')')) {
      return _text(
        range,
        AppTypography.body.copyWith(
          color: ink,
          fontSize: fontSize,
          height: 1.5,
        ),
      );
    }
    final split = range.start + detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          ComparisonTextRange(range.start, split),
          AppTypography.bodyMedium.copyWith(
            color: ink,
            fontSize: fontSize,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        _text(
          ComparisonTextRange(split, range.end),
          AppTypography.body.copyWith(
            color: muted,
            fontSize: fontSize - 2,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Colors.white : AppColors.ink;
    final muted = dark ? Colors.white70 : AppColors.ink2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < comparison.sections.length; index++) ...[
          if (index > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _text(
                  comparison.separator,
                  AppTypography.captionMedium.copyWith(
                    color: muted,
                    fontSize: fontSize - 3,
                  ),
                ),
              ),
            ),
          Container(
            key: ValueKey('learning-comparison-section-$index'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withValues(alpha: .06)
                  : index == 0
                  ? AppColors.greenSoft.withValues(alpha: .55)
                  : AppColors.paper2,
              borderRadius: AppRadii.br16,
              border: Border.all(
                color: dark
                    ? Colors.white12
                    : index == 0
                    ? AppColors.green.withValues(alpha: .18)
                    : AppColors.hair2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        index == 0
                            ? Icons.fact_check_outlined
                            : Icons.compare_arrows_rounded,
                        size: 21,
                        color: index == 0
                            ? (dark ? AppColors.mint : AppColors.green2)
                            : muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _text(
                        comparison.sections[index].heading,
                        AppTypography.h4.copyWith(
                          color: ink,
                          fontSize: fontSize - 1,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final item in comparison.sections[index].items) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _item(item, ink, muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
