import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../data/cmpys_seed.dart';

/// Full-bleed idol preview — color-block header, quote, blurb, "at your age",
/// pillars chips. Sticky footer to commit selection.
class CmpysIdolPreviewStep extends StatelessWidget {
  const CmpysIdolPreviewStep({
    super.key,
    required this.idol,
    required this.onBack,
    required this.onChoose,
  });

  final CmpysIdol idol;
  final VoidCallback onBack;
  final ValueChanged<CmpysIdol> onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _scroll(context)),
        _footer(),
      ],
    );
  }

  Widget _scroll(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: idol.tint,
                      borderRadius: AppRadii.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CmpysKicker('At your age', color: idol.color),
                        const SizedBox(height: 6),
                        Text(
                          idol.atYourAge!,
                          style: AppTypography.body.copyWith(
                            fontSize: 14.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (idol.pillars.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const CmpysKicker('What you’ll work on together'),
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
                            border:
                                Border.all(color: AppColors.hair, width: 1),
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
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(22, top + 14, 22, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            idol.color,
            Color.alphaBlend(Colors.black.withValues(alpha: 0.18), idol.color),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_left_rounded,
                    size: 22, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: Colors.white,
              size: 92,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              idol.name,
              style: AppTypography.h1.copyWith(
                color: Colors.white,
                fontSize: 28,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '${idol.title} · ${idol.era} · ${idol.tag}',
              style: AppTypography.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          top: BorderSide(color: AppColors.hair, width: 1),
        ),
      ),
      child: CmpysButton(
        variant: CmpysBtnVariant.primary,
        size: CmpysBtnSize.lg,
        full: true,
        trailingIcon: Icons.arrow_forward_rounded,
        onTap: () => onChoose(idol),
        child: Text('Choose ${idol.short} as my mentor'),
      ),
    );
  }
}
