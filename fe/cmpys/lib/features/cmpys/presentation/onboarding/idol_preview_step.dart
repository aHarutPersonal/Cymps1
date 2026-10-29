import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/v3/v3.dart';
import '../../data/cmpys_seed.dart';
import '../idol_timeline.dart';
import 'mentor_image.dart';

/// Mentor preview (`v3/onboard2.jsx` MentorPreview): the night page that opens
/// out of the tapped discovery card (see `V3ExpandRoute`).
///
/// - a 470 pt portrait hero with the "AI interpretation · not {short}" tag,
///   the name in display 52 and "field · era"
/// - the why / summary in Literata 17 and the domain tags
/// - the **documented timeline** from the idol catalog, with the node at the
///   user's own [age] in ember (the design shows 24)
/// - a footer button, "Begin intake with {short}", and a close button.
///
/// The step holds no navigation of its own: [onBack] closes it and [onChoose]
/// commits the mentor. The timeline loads on entry and never blocks choosing;
/// a mentor who is not in the catalog yet shows "No documented timeline yet."
class CmpysIdolPreviewStep extends ConsumerStatefulWidget {
  const CmpysIdolPreviewStep({
    super.key,
    required this.idol,
    required this.age,
    required this.onBack,
    required this.onChoose,
  });

  final CmpysIdol idol;

  /// The user's age, to highlight the matching timeline node.
  final int age;
  final VoidCallback onBack;
  final ValueChanged<CmpysIdol> onChoose;

  @override
  ConsumerState<CmpysIdolPreviewStep> createState() =>
      _CmpysIdolPreviewStepState();
}

class _CmpysIdolPreviewStepState extends ConsumerState<CmpysIdolPreviewStep> {
  CmpysIdol get _idol => widget.idol;

  /// "field · era"; a suggestion with no era carries the placeholder `—`,
  /// which is left out rather than shown.
  String get _fieldAndEra => [
    _idol.field,
    _idol.era,
  ].where((part) => part.trim().isNotEmpty && part.trim() != '—').join(' · ');

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DefaultTextStyle(
        style: AppTypography.sans(16).copyWith(color: Colors.white),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = math.max(22.0, (constraints.maxWidth - 520) / 2);
            return Stack(
              children: [
                Positioned.fill(
                  child: V3FooterScaffold(
                    background: AppColors.night,
                    footerHorizontalPadding: gutter,
                    body: (context, bottomPadding) => SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      child: _content(gutter),
                    ),
                    footer: V3Button(
                      full: true,
                      iconRight: V3Icons.arrowR,
                      onPressed: () => widget.onChoose(_idol),
                      child: Text('Begin intake with ${_idol.short}'),
                    ),
                  ),
                ),
                Positioned(
                  top: math.max(inset, 12),
                  right: 16,
                  child: V3IconButton(
                    icon: V3Icons.x,
                    dark: true,
                    label: 'Close preview',
                    onPressed: widget.onBack,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _content(double gutter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hero(gutter),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              V3Rise(
                delay: const Duration(milliseconds: 440),
                child: Text(
                  _idol.blurb,
                  style: AppTypography.read(
                    17,
                  ).copyWith(height: 1.55, color: AppColors.nink2),
                ),
              ),
              if (_idol.pillars.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: V3Rise(
                    delay: const Duration(milliseconds: 500),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final domain in _idol.pillars)
                          V3Tag(
                            background: const Color(0x14FFFFFF),
                            color: Colors.white,
                            height: 30,
                            horizontalPadding: 12,
                            fontSize: 12.5,
                            child: Text(domain),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 30, bottom: 14),
                child: Text(
                  'DOCUMENTED TIMELINE',
                  style: AppTypography.kick.copyWith(color: AppColors.nink3),
                ),
              ),
              CmpysIdolTimeline(idolName: _idol.name, age: widget.age),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero(double gutter) {
    return V3Portrait(
      image: cmpysIdolImage(_idol),
      height: 470,
      child: Positioned(
        left: gutter,
        right: gutter,
        bottom: 24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            V3Rise(
              delay: const Duration(milliseconds: 250),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: V3Tag(
                    background: const Color(0x1FFFFFFF),
                    color: Colors.white,
                    icon: V3Icons.info,
                    child: Text('AI interpretation · not ${_idol.short}'),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: V3Rise(
                delay: const Duration(milliseconds: 320),
                child: Text(
                  _idol.name,
                  style: AppTypography.display(
                    52,
                  ).copyWith(color: Colors.white),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: V3Rise(
                delay: const Duration(milliseconds: 380),
                child: Text(
                  _fieldAndEra,
                  style: AppTypography.sans(
                    14,
                  ).copyWith(color: AppColors.nink2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
