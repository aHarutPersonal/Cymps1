// Design-styled markdown rendering for LLM-generated content
// (comparison verdicts, blueprints, mentor messages).

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../../reading/learning_comparison.dart';
import '../../reading/learning_diagram.dart';
import '../../reading/markdown_code_text.dart';
import 'learning_diagram_view.dart';
import 'learning_comparison_view.dart';

import '../../../app/design_tokens.dart';

/// Markdown body using the CMPYS type system. [onDark] flips ink → white for
/// use on color-block surfaces.
class CmpysMarkdown extends StatelessWidget {
  const CmpysMarkdown(
    this.data, {
    super.key,
    this.onDark = false,
    this.fontSize = 15.5,
    this.lineHeight = 1.6,
  });
  final String data;
  final bool onDark;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? Colors.white : AppColors.ink;
    final ink2 = onDark ? Colors.white.withValues(alpha: 0.8) : AppColors.ink2;
    return MarkdownBody(
      data: data,
      selectable: false,
      fitContent: false,
      builders: {
        'pre': _LearningBlockBuilder(fontSize: fontSize, dark: onDark),
      },
      styleSheet: MarkdownStyleSheet(
        codeblockDecoration: const BoxDecoration(),
        p: AppTypography.reading.copyWith(
          fontSize: fontSize,
          height: lineHeight,
          color: ink,
        ),
        h1: AppTypography.h2.copyWith(
          fontSize: fontSize + 8.5,
          color: ink,
          height: 1.25,
        ),
        h2: AppTypography.h3.copyWith(
          fontSize: fontSize + 4.5,
          color: ink,
          height: 1.3,
        ),
        h3: AppTypography.h4.copyWith(
          fontSize: fontSize + 1.5,
          color: ink,
          height: 1.3,
        ),
        strong: AppTypography.readingBold.copyWith(
          fontSize: fontSize,
          color: ink,
        ),
        em: AppTypography.reading.copyWith(
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
          color: ink,
        ),
        listBullet: AppTypography.reading.copyWith(
          fontSize: fontSize,
          color: ink2,
        ),
        blockquote: AppTypography.readingQuote.copyWith(
          fontSize: fontSize + 1,
          color: ink,
          height: 1.45,
        ),
        blockquoteDecoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.greenSoft,
          borderRadius: BorderRadius.circular(12),
          border: const Border(
            left: BorderSide(color: AppColors.green, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        h1Padding: const EdgeInsets.only(top: 18, bottom: 4),
        h2Padding: const EdgeInsets.only(top: 16, bottom: 4),
        h3Padding: const EdgeInsets.only(top: 12, bottom: 2),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair2)),
        ),
      ),
    );
  }
}

/// Full-screen reader for a markdown document (AI verdict / blueprint).
class CmpysMarkdownScreen extends StatelessWidget {
  const CmpysMarkdownScreen({
    super.key,
    required this.kicker,
    required this.title,
    required this.markdown,
  });
  final String kicker;
  final String title;
  final String markdown;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hair),
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      size: 22,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 60),
                children: [
                  Text(kicker.toUpperCase(), style: AppTypography.kicker),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      title,
                      style: AppTypography.h1.copyWith(
                        fontSize: 28,
                        letterSpacing: -0.4,
                        height: 1.3,
                      ),
                    ),
                  ),
                  CmpysMarkdown(markdown),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningBlockBuilder extends MarkdownElementBuilder {
  _LearningBlockBuilder({required this.fontSize, required this.dark});
  final double fontSize;
  final bool dark;
  @override
  bool isBlockElement() => true;
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) =>
      const SizedBox.shrink();
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final language = (code?.attributes['class'] ?? '').replaceFirst(
      'language-',
      '',
    );
    // FlutterMarkdown already constructs Document(encodeHtml: false).
    final source = markdownCodeText(element.textContent, encoded: false);
    final comparison = LearningComparison.parse(source, language: language);
    if (comparison != null) {
      return LearningComparisonView(
        comparison: comparison,
        fontSize: fontSize,
        dark: dark,
      );
    }
    final diagram = LearningDiagram.parse(source, language: language);
    if (diagram != null) {
      return LearningDiagramView(
        diagram: diagram,
        fontSize: fontSize,
        dark: dark,
      );
    }
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: .06) : AppColors.paper2,
        borderRadius: AppRadii.br12,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          source.trimRight(),
          style: AppTypography.monoLabel.copyWith(
            color: dark ? Colors.white : AppColors.ink,
            fontSize: fontSize - 2,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}
