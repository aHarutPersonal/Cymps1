// Design-styled markdown rendering for LLM-generated content
// (comparison verdicts, blueprints, mentor messages).

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/design_tokens.dart';

/// Markdown body using the CMPYS type system. [onDark] flips ink → white for
/// use on color-block surfaces.
class CmpysMarkdown extends StatelessWidget {
  const CmpysMarkdown(this.data, {super.key, this.onDark = false});
  final String data;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? Colors.white : AppColors.ink;
    final ink2 = onDark ? Colors.white.withValues(alpha: 0.8) : AppColors.ink2;
    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: MarkdownStyleSheet(
        p: AppTypography.reading.copyWith(fontSize: 15.5, height: 1.6, color: ink),
        h1: AppTypography.h2.copyWith(fontSize: 24, color: ink, height: 1.25),
        h2: AppTypography.h3.copyWith(fontSize: 20, color: ink, height: 1.3),
        h3: AppTypography.h4.copyWith(fontSize: 17, color: ink, height: 1.3),
        strong: AppTypography.readingBold.copyWith(fontSize: 15.5, color: ink),
        em: AppTypography.reading.copyWith(
            fontSize: 15.5, fontStyle: FontStyle.italic, color: ink),
        listBullet:
            AppTypography.reading.copyWith(fontSize: 15.5, color: ink2),
        blockquote: AppTypography.readingQuote.copyWith(
            fontSize: 16.5, color: ink, height: 1.45),
        blockquoteDecoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.greenSoft,
          borderRadius: BorderRadius.circular(12),
          border: const Border(
              left: BorderSide(color: AppColors.green, width: 3)),
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
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hair),
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        size: 22, color: AppColors.ink),
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
                    child: Text(title,
                        style: AppTypography.h1.copyWith(
                            fontSize: 28, letterSpacing: -0.4, height: 1.3)),
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
