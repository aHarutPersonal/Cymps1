import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';

abstract final class _IdeaPalette {
  static const paper = AppColors.surface;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
}

/// Prototype-style IdeaCard — grid-system card with serif insight text.
///
/// Renders `**bold**` markdown fragments with Playfair Display.
/// Used by the Ideas tab (vertical swipe) and Library tab (list).
class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.contentMarkdown,
    required this.category,
    this.idolName,
    this.onPlayAudio,
    this.onStash,
    this.isStashed = false,
    this.isPlaying = false,
    this.isCompact = false,
  });

  final String contentMarkdown;
  final String category;
  final String? idolName;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onStash;
  final bool isStashed;
  final bool isPlaying;
  final bool isCompact; // compact mode for Library list items

  /// Accent bar color per category.
  Color _accentColor() {
    final accents = [
      AppColors.brandAccent,
      const Color(0xFFE67E22),
      AppColors.emerald,
      const Color(0xFF8B5CF6),
      AppColors.blue,
      const Color(0xFFF59E0B),
    ];
    return accents[category.hashCode.abs() % accents.length];
  }

  @override
  Widget build(BuildContext context) {
    if (isCompact) return _buildCompact(context);
    return _buildFullScreen(context);
  }

  /// Full-screen vertical swipe card (Ideas tab).
  Widget _buildFullScreen(BuildContext context) {
    final accent = _accentColor();
    final parsed = _ParsedIdea.fromMarkdown(contentMarkdown);

    return Center(
      child: Container(
        height: (MediaQuery.sizeOf(context).height * 0.58).clamp(460.0, 520.0),
        margin: const EdgeInsets.fromLTRB(24, 116, 24, 104),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.br16,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category: ${category.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.captionUpper.copyWith(
                          color: AppColors.mint,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (idolName != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Source: $idolName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.captionUpper.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tooltip(
                  message: isStashed ? 'Remove from stash' : 'Save to stash',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onStash?.call();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        isStashed
                            ? PhosphorIconsFill.bookmarkSimple
                            : PhosphorIconsRegular.bookmarkSimple,
                        color: isStashed ? accent : AppColors.textTertiary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      parsed.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.h3.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '"${parsed.quote}"',
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.readingQuote.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                    if (parsed.body.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        parsed.body,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.48,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: isPlaying ? 'Stop' : 'Listen',
                    child: _FooterIconAction(
                      icon: isPlaying
                          ? PhosphorIconsBold.stop
                          : PhosphorIconsRegular.headphones,
                      color: isPlaying ? accent : AppColors.textTertiary,
                      onTap: onPlayAudio,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _FooterIconAction(
                    icon: PhosphorIconsRegular.shareNetwork,
                    color: AppColors.textTertiary,
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: contentMarkdown)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: AppRadii.br8,
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Text(
                      'DETAILS',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
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

  /// Compact card for Library list.
  Widget _buildCompact(BuildContext context) {
    final accent = _accentColor();

    return Container(
      decoration: BoxDecoration(
        color: _IdeaPalette.paper,
        borderRadius: AppRadii.br16,
        border: Border.all(color: _IdeaPalette.line),
      ),
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category + stash icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: AppRadii.brFull,
                ),
                child: Text(
                  category.toUpperCase(),
                  style: AppTypography.captionUpper.copyWith(
                    color: accent,
                    fontSize: 10,
                  ),
                ),
              ),
              const Spacer(),
              // 44px touch target for accessibility
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onStash?.call();
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: AppDurations.fast,
                      child: Icon(
                        isStashed
                            ? PhosphorIconsFill.bookmarkSimple
                            : PhosphorIconsRegular.bookmarkSimple,
                        key: ValueKey(isStashed),
                        size: 20,
                        color: isStashed
                            ? AppColors.brandAccent
                            : _IdeaPalette.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),

          // Content (UI font at body size for compact)
          _MarkdownBoldText(
            text: contentMarkdown,
            baseStyle: AppTypography.body.copyWith(
              color: _IdeaPalette.muted,
              height: 1.5,
            ),
            boldStyle: AppTypography.bodyMedium.copyWith(
              color: _IdeaPalette.ink,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
            maxLines: 4,
          ),

          // Attribution
          if (idolName != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              "— $idolName",
              style: AppTypography.caption.copyWith(
                color: _IdeaPalette.muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParsedIdea {
  const _ParsedIdea({
    required this.title,
    required this.quote,
    required this.body,
  });

  final String title;
  final String quote;
  final String body;

  static _ParsedIdea fromMarkdown(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    final titleMatch = RegExp(r'^\*\*(.+?)\*\*').firstMatch(input.trim());
    final title = titleMatch?.group(1)?.trim() ?? 'Strategic Insight';
    final withoutTitle = titleMatch == null
        ? normalized
        : input
              .substring(titleMatch.end)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final quote = _quoteFrom(withoutTitle.isEmpty ? normalized : withoutTitle);
    final body = _bodyFrom(withoutTitle, quote);
    return _ParsedIdea(title: title, quote: quote, body: body);
  }

  static String _quoteFrom(String value) {
    if (value.isEmpty) return 'Study the pattern, then act with precision.';
    final match = RegExp(r'^(.{32,180}?[.!?])\s+').firstMatch(value);
    if (match != null) return match.group(1)!.trim();
    return value.length > 180 ? '${value.substring(0, 177).trim()}...' : value;
  }

  static String _bodyFrom(String value, String quote) {
    if (value.isEmpty || quote.isEmpty) return '';
    if (value == quote || !value.startsWith(quote)) return '';
    return value.substring(quote.length).trim();
  }
}

// =============================================================================
// Markdown Bold Text — parses **bold** and renders with alternate style
// =============================================================================

class _MarkdownBoldText extends StatelessWidget {
  const _MarkdownBoldText({
    required this.text,
    required this.baseStyle,
    required this.boldStyle,
    this.maxLines,
  });

  final String text;
  final TextStyle baseStyle;
  final TextStyle boldStyle;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
      text: TextSpan(children: _parse(text)),
    );
  }

  /// Parse **bold** markdown fragments into TextSpans.
  List<TextSpan> _parse(String input) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*([\s\S]+?)\*\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(input)) {
      // Text before the bold
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: input.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      // Bold text
      spans.add(TextSpan(text: match.group(1), style: boldStyle));
      lastEnd = match.end;
    }

    // Remaining text after last bold
    if (lastEnd < input.length) {
      spans.add(TextSpan(text: input.substring(lastEnd), style: baseStyle));
    }

    // If no spans were added (no bold), use full text as base
    if (spans.isEmpty) {
      spans.add(TextSpan(text: input, style: baseStyle));
    }

    return spans;
  }
}

// =============================================================================
// Action Circle — headphones/stop icon with 44px touch target
// =============================================================================

class _FooterIconAction extends StatelessWidget {
  const _FooterIconAction({
    required this.icon,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        color: Colors.transparent,
        child: Center(
          child: AnimatedSwitcher(
            duration: AppDurations.fast,
            child: Icon(icon, key: ValueKey(icon), size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
