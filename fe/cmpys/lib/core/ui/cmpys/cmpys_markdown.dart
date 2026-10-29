// Design-styled markdown rendering for LLM-generated content
// (comparison verdicts, blueprints, mentor messages).

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../../reading/learning_comparison.dart';
import '../../reading/learning_diagram.dart';
import '../../reading/lesson_fences.dart';
import '../../reading/markdown_code_text.dart';
import '../v3/lesson_blocks/formula_stack.dart';
import '../v3/lesson_blocks/quick_check.dart';
import '../v3/lesson_blocks/waterfall_chart.dart';
import '../v3/lesson_blocks/worked_steps.dart';
import 'learning_diagram_view.dart';
import 'cmpys_primitives.dart';
import 'learning_comparison_view.dart';

import '../../../app/design_tokens.dart';

/// Markdown body using the CMPYS type system. [onDark] flips ink → white for
/// use on color-block surfaces. [readerTheme] (the tutorial reader) takes the
/// text colours from that reading theme instead.
///
/// Code fences are routed by kind: the native lesson blocks (formula, chart,
/// steps, check, diagram, comparison) render through [LessonFenceBlock];
/// other fences keep the legacy diagram/comparison detection and otherwise
/// show as code.
class CmpysMarkdown extends StatelessWidget {
  const CmpysMarkdown(
    this.data, {
    super.key,
    this.onDark = false,
    this.fontSize = 15.5,
    this.lineHeight = 1.6,
    this.readerTheme,
  });
  final String data;
  final bool onDark;
  final double fontSize;
  final double lineHeight;
  final ReaderTheme? readerTheme;

  @override
  Widget build(BuildContext context) {
    final theme = readerTheme;
    final dark = onDark || theme == ReaderTheme.dark;
    final ink = theme?.fg ?? (onDark ? Colors.white : AppColors.ink);
    final ink2 =
        theme?.fg2 ??
        (onDark ? Colors.white.withValues(alpha: 0.8) : AppColors.ink2);
    // The tutorial reader reads in Literata (the design's `.serif`).
    final body = theme != null
        ? AppTypography.read(fontSize)
        : AppTypography.reading;
    return MarkdownBody(
      data: data,
      selectable: false,
      fitContent: false,
      builders: {
        'pre': _LearningBlockBuilder(
          fontSize: fontSize,
          dark: dark,
          theme: theme ?? (onDark ? ReaderTheme.dark : ReaderTheme.light),
        ),
      },
      styleSheet: MarkdownStyleSheet(
        codeblockDecoration: const BoxDecoration(),
        p: body.copyWith(fontSize: fontSize, height: lineHeight, color: ink),
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
        strong: (theme != null
                ? body.copyWith(fontWeight: FontWeight.w600)
                : AppTypography.readingBold)
            .copyWith(fontSize: fontSize, color: ink),
        em: body.copyWith(
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
          color: ink,
        ),
        listBullet: body.copyWith(fontSize: fontSize, color: ink2),
        blockquote: AppTypography.readingQuote.copyWith(
          fontSize: fontSize + 1,
          color: ink,
          height: 1.45,
        ),
        blockquoteDecoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : theme?.card ?? AppColors.greenSoft,
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
                child: CmpysPressable(
                  semanticLabel: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
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

/// One native lesson fence, parsed with the A6 grammar mirror
/// (lesson_fences.dart): a formula stack, a waterfall or bar chart, worked
/// steps or a quick check; the legacy diagram and comparison views; and, for
/// a body that breaks its grammar, the body as plain lines so the lesson
/// never loses its text.
class LessonFenceBlock extends StatelessWidget {
  const LessonFenceBlock({
    super.key,
    required this.kind,
    required this.body,
    this.theme = ReaderTheme.light,
    this.fontSize = 17.5,
  });

  final String kind;
  final String body;
  final ReaderTheme theme;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final dark = theme == ReaderTheme.dark;
    final block = switch (kind) {
      'formula' => switch (parseFormulaFence(body)) {
        final b? => FormulaStack(block: b, theme: theme),
        null => null,
      },
      'chart' => switch (parseChartFence(body)) {
        final b? => WaterfallChart(block: b, theme: theme),
        null => null,
      },
      'steps' => switch (parseStepsFence(body)) {
        final b? => WorkedSteps(block: b, theme: theme, fontSize: fontSize),
        null => null,
      },
      'check' => switch (parseCheckFence(body)) {
        final b? => QuickCheck(block: b, theme: theme),
        null => null,
      },
      'comparison' => switch (LearningComparison.parse(
        body,
        language: 'comparison',
      )) {
        final c? => LearningComparisonView(
          comparison: c,
          fontSize: fontSize,
          dark: dark,
        ),
        null => null,
      },
      'diagram' => switch (LearningDiagram.parse(body, language: 'diagram')) {
        final d? => LearningDiagramView(
          diagram: d,
          fontSize: fontSize,
          dark: dark,
        ),
        null => null,
      },
      _ => null,
    };
    return block ??
        _FencePlainLines(body: body, theme: theme, fontSize: fontSize);
  }
}

/// A fence body that breaks its grammar, shown line by line as reading text.
class _FencePlainLines extends StatelessWidget {
  const _FencePlainLines({
    required this.body,
    required this.theme,
    required this.fontSize,
  });

  final String body;
  final ReaderTheme theme;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final line in body.split(RegExp(r'\r\n|\r|\n')))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              style: AppTypography.read(
                fontSize,
              ).copyWith(height: 1.55, color: theme.fg),
            ),
          ),
      ],
    );
  }
}

class _LearningBlockBuilder extends MarkdownElementBuilder {
  _LearningBlockBuilder({
    required this.fontSize,
    required this.dark,
    required this.theme,
  });
  final double fontSize;
  final bool dark;
  final ReaderTheme theme;
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
    if (lessonFenceKinds.contains(language)) {
      return LessonFenceBlock(
        kind: language,
        body: source,
        theme: theme,
        fontSize: fontSize,
      );
    }
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
