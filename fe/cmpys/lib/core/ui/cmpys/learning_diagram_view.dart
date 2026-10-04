import 'package:flutter/material.dart';
import '../../../app/design_tokens.dart';
import '../../reading/learning_comparison.dart';
import '../../reading/learning_diagram.dart';

class LearningDiagramView extends StatelessWidget {
  const LearningDiagramView({
    super.key,
    required this.diagram,
    required this.fontSize,
    this.dark = false,
    this.spansForRange,
  });
  final LearningDiagram diagram;
  final double fontSize;
  final bool dark;
  final List<InlineSpan> Function(int start, int end)? spansForRange;

  Widget _text(ComparisonTextRange range, {bool strong = false}) => Text.rich(
    TextSpan(
      children:
          spansForRange?.call(range.start, range.end) ??
          [TextSpan(text: diagram.text.substring(range.start, range.end))],
    ),
    style: AppTypography.body.copyWith(
      color: dark ? Colors.white : AppColors.ink,
      fontSize: fontSize,
      height: 1.5,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('learning-diagram'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: .06)
          : AppColors.greenSoft.withValues(alpha: .42),
      borderRadius: AppRadii.br16,
      border: Border.all(
        color: dark ? Colors.white12 : AppColors.green.withValues(alpha: .18),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (diagram.heading case final heading?) ...[
          _text(heading, strong: true),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              height: 1,
              color: dark
                  ? Colors.white24
                  : AppColors.green.withValues(alpha: .18),
            ),
          ),
        ],
        for (var index = 0; index < diagram.lines.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.only(
              left: diagram.lines[index].branch ? 16 : 0,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: diagram.lines[index].branch
                    ? const Border(
                        left: BorderSide(color: AppColors.green, width: 2),
                      )
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: diagram.lines[index].branch ? 12 : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_line(diagram.lines[index], index)],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _incoming(LearningDiagramLine line, int index) {
    final parent = diagram.lines[line.parentLineIndex!];
    final source = parent.parts[line.parentPartIndex];
    final target = line.parts[line.entryPartIndex];
    final sourceText = diagram.text.substring(source.start, source.end);
    final targetText = diagram.text.substring(target.start, target.end);
    final adjacent =
        !line.branch &&
        line.parentLineIndex == index - 1 &&
        line.parentPartIndex == parent.parts.length - 1 &&
        line.entryPartIndex == 0;
    return SelectionContainer.disabled(
      child: Semantics(
        label:
            '$sourceText ${line.directed ? "leads to" : "connects to"} $targetText',
        child: ExcludeSemantics(
          child: Padding(
            key: ValueKey('diagram-incoming-$index-${line.entryPartIndex}'),
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  line.directed
                      ? Icons.subdirectory_arrow_right_rounded
                      : Icons.height_rounded,
                  size: 18,
                  color: dark ? AppColors.mint : AppColors.green2,
                ),
                if (!adjacent) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${line.directed ? "From" : "Connected to"} $sourceText',
                      style: AppTypography.caption.copyWith(
                        fontSize: fontSize - 2,
                        color: dark ? Colors.white70 : AppColors.ink2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(LearningDiagramLine line, int index) {
    if (line.columns) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < line.parts.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: _text(line.parts[i])),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < line.parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ExcludeSemantics(
                child: Icon(
                  line.reverseLinks[i - 1] == 0
                      ? Icons.swap_vert_rounded
                      : line.reverseLinks[i - 1] < 0
                      ? Icons.north_rounded
                      : Icons.south_rounded,
                  size: 18,
                  color: dark ? AppColors.mint : AppColors.green2,
                ),
              ),
            ),
          if (line.parentLineIndex != null && i == line.entryPartIndex)
            _incoming(line, index),
          KeyedSubtree(
            key: ValueKey('diagram-node-$index-$i'),
            child: _text(
              line.parts[i],
              strong: i == 0 && line.parts.length > 1,
            ),
          ),
        ],
      ],
    );
  }
}
