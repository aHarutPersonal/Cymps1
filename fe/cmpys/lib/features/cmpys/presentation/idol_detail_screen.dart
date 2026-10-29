import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/cmpys_ideas_provider.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'idol_timeline.dart';
import 'onboarding/mentor_image.dart';
import 'onboarding/mentor_video.dart';
import 'reels_screen.dart' show IdeaProvenance, ideaProvenanceOf;

/// Mentor context (`v3/you.jsx` MentorScreen): the night page with the
/// portrait hero and its "AI interpretation · not {short}" tag, the
/// disclaimer that Chat replies are generated, and the documented timeline
/// with the event at the user's own age highlighted. Below it, the mentor's
/// "at your age" note, quote, blurb, pillars and any AI-generated idea cards
/// attributed to this mentor.
class CmpysIdolDetailScreen extends ConsumerWidget {
  const CmpysIdolDetailScreen({super.key, required this.idol});
  final CmpysIdol idol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ideas come from the AI feed; show only ones attributed to this mentor.
    final attributedIdeas =
        (ref.watch(cmpysIdeasProvider).valueOrNull ?? const <CmpysIdea>[])
            .where(
              (i) =>
                  i.author.toLowerCase().contains(idol.short.toLowerCase()) ||
                  i.author.toLowerCase().contains(idol.name.toLowerCase()),
            )
            .toList();
    final age = ref.watch(cmpysStoreProvider.select((s) => s.user.age));
    final inset = MediaQuery.paddingOf(context).top;
    final field = idol.field.trim().isNotEmpty ? idol.field : idol.title;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: DefaultTextStyle(
          style: AppTypography.sans(16).copyWith(color: Colors.white),
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: 60 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _hero(field),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replies in Chat are generated from '
                              '${idol.short}’s documented writing, interviews '
                              'and biographies. They are not messages from '
                              '${idol.short}.',
                              style: AppTypography.read(
                                16.5,
                              ).copyWith(height: 1.6, color: AppColors.nink2),
                            ),
                            _kick('Timeline', top: 26),
                            CmpysIdolTimeline(
                              idolName: idol.name,
                              age: age > 0 ? age : null,
                              layout: CmpysIdolTimelineLayout.rows,
                            ),
                            ..._more(attributedIdeas),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: math.max(inset, 12),
                left: 16,
                child: V3IconButton(
                  icon: V3Icons.left,
                  dark: true,
                  label: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(String field) {
    // Buffett's lamp-lit study plays behind the hero (ringed medallion over
    // it); every other mentor keeps the duotone portrait.
    return V3VideoPortrait(
      image: cmpysIdolImage(idol),
      video: cmpysIdolVideo(idol),
      height: 420,
      tone: idol.color,
      child: Positioned(
        left: 22,
        right: 22,
        bottom: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: V3Tag(
                  background: const Color(0x1FFFFFFF),
                  color: Colors.white,
                  icon: V3Icons.info,
                  child: Text('AI interpretation · not ${idol.short}'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              idol.name,
              style: AppTypography.display(48).copyWith(color: Colors.white),
            ),
            if (field.trim().isNotEmpty)
              Text(
                field,
                style: AppTypography.sans(14).copyWith(color: AppColors.nink2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kick(String label, {double top = 30}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 12),
    child: Text(
      label.toUpperCase(),
      style: AppTypography.kick.copyWith(color: AppColors.nink3),
    ),
  );

  /// The data this screen showed before the v3 restyle, on the night ground.
  List<Widget> _more(List<CmpysIdea> ideas) {
    final atYourAge = idol.atYourAge?.trim() ?? '';
    final quote = idol.quote.trim();
    final blurb = idol.blurb.trim();
    return [
      if (atYourAge.isNotEmpty) ...[
        _kick('At your age'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.night2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            atYourAge,
            style: AppTypography.sans(
              14.5,
            ).copyWith(height: 1.5, color: Colors.white),
          ),
        ),
      ],
      if (quote.isNotEmpty || blurb.isNotEmpty) const SizedBox(height: 30),
      if (quote.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '“$quote”',
            style: AppTypography.displayItalic(
              24,
            ).copyWith(height: 1.2, color: Colors.white),
          ),
        ),
      if (blurb.isNotEmpty)
        Text(
          blurb,
          style: AppTypography.read(
            16,
          ).copyWith(height: 1.55, color: AppColors.nink2),
        ),
      if (idol.pillars.isNotEmpty) ...[
        _kick('Pillars you work on together'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in idol.pillars)
              V3Tag(
                background: const Color(0x14FFFFFF),
                color: Colors.white,
                height: 30,
                horizontalPadding: 12,
                fontSize: 12.5,
                child: Text(p),
              ),
          ],
        ),
      ],
      if (ideas.isNotEmpty) ...[
        _kick('Ideas from ${idol.short}'),
        for (var i = 0; i < ideas.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ideaCard(ideas[i]),
        ],
      ],
    ];
  }

  /// One idea, with the reels' provenance rule: only a verified or exact
  /// quotation is put in quotation marks; anything else is plain text, and
  /// every card names its provenance ([ideaProvenanceOf]).
  Widget _ideaCard(CmpysIdea idea) {
    final prov = ideaProvenanceOf(idea);
    final quoted =
        prov == IdeaProvenance.verified || prov == IdeaProvenance.exact;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.night2,
        borderRadius: BorderRadius.circular(AppRadii.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  idea.tag.toUpperCase(),
                  style: AppTypography.kick.copyWith(color: AppColors.nink3),
                ),
              ),
              const V3Icon(V3Icons.heart, size: 14, color: AppColors.nink3),
              const SizedBox(width: 4),
              Text(
                idea.likes.toString(),
                style: AppTypography.sans(
                  11.5,
                ).merge(AppTypography.tnum).copyWith(color: AppColors.nink3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            quoted ? '“${idea.text}”' : idea.text,
            style: AppTypography.read(
              15.5,
            ).copyWith(height: 1.55, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              V3Icon(prov.icon, size: 13, color: AppColors.nink3),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  prov.label,
                  style: AppTypography.sans(
                    11.5,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.nink3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
