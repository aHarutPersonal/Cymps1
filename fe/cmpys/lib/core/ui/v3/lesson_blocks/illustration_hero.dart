import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../motion/motion_config.dart';

/// The tutorial's AI illustration as a hero under its title (owner decision
/// D2): a paper2 placeholder at the image's [aspectRatio] that the image
/// fades into, and the caption "Illustration · AI-generated". The image is
/// decorative; screen readers get [alt] and the caption. A failed load
/// collapses the whole hero, so a broken image never shows and nothing
/// retries.
class IllustrationHero extends StatefulWidget {
  const IllustrationHero({
    super.key,
    required this.url,
    required this.alt,
    this.aspectRatio = 16 / 9,
    this.theme = ReaderTheme.light,
  });

  final String url;
  final String alt;
  final double aspectRatio;
  final ReaderTheme theme;

  /// The image frame (placeholder plus image).
  static const frameKey = ValueKey('illustration-hero-frame');

  static const caption = 'Illustration · AI-generated';

  @override
  State<IllustrationHero> createState() => _IllustrationHeroState();
}

class _IllustrationHeroState extends State<IllustrationHero> {
  bool _failed = false;

  @override
  void didUpdateWidget(IllustrationHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _failed = false;
  }

  void _fail() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_failed) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final animate = MotionConfig.enabled(context);
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          image: true,
          // The caption itself is excluded, so its words join the label.
          label: '${widget.alt}. ${IllustrationHero.caption}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              key: IllustrationHero.frameKey,
              aspectRatio: widget.aspectRatio,
              child: ColoredBox(
                color: theme == ReaderTheme.dark
                    ? theme.card
                    : AppColors.paper2,
                child: Image.network(
                  widget.url,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  frameBuilder: (context, child, frame, synchronous) {
                    if (synchronous) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: animate
                          ? const Duration(milliseconds: 450)
                          : Duration.zero,
                      curve: AppMotion.out,
                      child: child,
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    _fail();
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Text(
            IllustrationHero.caption,
            style: AppTypography.sans(11.5).copyWith(color: theme.fg2),
          ),
        ),
      ],
    );
  }
}
