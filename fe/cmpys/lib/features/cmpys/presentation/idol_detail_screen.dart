import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/cmpys_ideas_provider.dart';
import '../data/cmpys_seed.dart';

/// Idol detail — color-block hero, blurb, "at your age" card, and any
/// AI-generated idea cards attributed to this mentor.
class CmpysIdolDetailScreen extends ConsumerWidget {
  const CmpysIdolDetailScreen({super.key, required this.idol});
  final CmpysIdol idol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ideas come from the AI feed; show only ones attributed to this mentor.
    final attributedIdeas = (ref.watch(cmpysIdeasProvider).valueOrNull ??
            const <CmpysIdea>[])
        .where((i) =>
            i.author.toLowerCase().contains(idol.short.toLowerCase()) ||
            i.author.toLowerCase().contains(idol.name.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _hero(context)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, AppShell.bottomNavClearance(context)),
            sliver: SliverList.list(
              children: [
                Text(
                  '"${idol.quote}"',
                  style: AppTypography.readingQuote.copyWith(
                    fontSize: 20,
                    height: 1.42,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  idol.blurb,
                  style: AppTypography.body.copyWith(
                    fontSize: 15,
                    height: 1.55,
                    color: AppColors.ink2,
                  ),
                ),
                if (idol.atYourAge != null) ...[
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: idol.tint,
                      borderRadius: AppRadii.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CmpysKicker('At your age', color: idol.color),
                        const SizedBox(height: 8),
                        Text(
                          idol.atYourAge!,
                          style: AppTypography.body.copyWith(
                            fontSize: 15,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (idol.pillars.isNotEmpty) ...[
                  const CmpysKicker('Pillars you work on together'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in idol.pillars)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.hair),
                          ),
                          child: Text(
                            p,
                            style: AppTypography.bodyMedium.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                if (attributedIdeas.isNotEmpty) ...[
                  Text(
                    'Ideas from ${idol.short}',
                    style: AppTypography.h3
                        .copyWith(fontSize: 21, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 12),
                  for (final idea in attributedIdeas) ...[
                    _ideaTile(idea),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(22, top + 12, 22, 30),
      decoration: BoxDecoration(
        // Design: linear-gradient(165deg, color, color@cc) — second stop is the
        // mentor color at ~80% opacity composited over paper (lighter, not darker).
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            idol.color,
            Color.alphaBlend(
                idol.color.withValues(alpha: 0.80), AppColors.paper),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.chevron_left_rounded,
                    size: 22, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: Colors.white,
              size: 110,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              idol.name,
              style: AppTypography.display.copyWith(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Center(
            child: Text(
              '${idol.title} · ${idol.era}',
              style: AppTypography.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // "Your active mentor" pill (design: rgba(255,255,255,0.16) bg).
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF9FD0B6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Your active mentor',
                    style: AppTypography.captionMedium.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ideaTile(CmpysIdea idea) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: idea.tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  idea.tag.toUpperCase(),
                  style: AppTypography.kicker.copyWith(
                    color: idea.tone,
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(PhosphorIconsRegular.heart,
                  size: 14, color: AppColors.ink3),
              const SizedBox(width: 4),
              Text(
                idea.likes.toString(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.ink3,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '"${idea.text}"',
            style: AppTypography.body.copyWith(
              fontSize: 15,
              height: 1.5,
              color: AppColors.ink,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
