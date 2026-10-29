import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/v3/v3.dart';
import '../models/plan_models.dart';

/// `MaterialRow` (v3): an access-coloured icon tile, the title, the author
/// and a [V3AccessBadge]; .75 opacity when nothing can be read. While a
/// guide is [preparing] it shows "Preparing…" and a spinner (as does an
/// access [checking]), and a null [onTap] disables it (single flight).
///
/// Shared by the mission screen and the tutorial reader's References. A
/// [theme] recolours the card for the reader's sepia and dark themes; null is
/// the mission screen's paper look.
class MaterialRow extends StatelessWidget {
  const MaterialRow({
    super.key,
    required this.material,
    required this.type,
    required this.onTap,
    this.preparing = false,
    this.checking = false,
    this.theme,
  });

  final PlanMaterialDetail material;
  final AccessType type;
  final VoidCallback? onTap;
  final bool preparing;
  final bool checking;
  final ReaderTheme? theme;

  @override
  Widget build(BuildContext context) {
    final copy = accessCopy(type);
    final author = material.authorOrCreator?.trim() ?? '';
    final title = theme?.fg ?? AppColors.ink;
    final sub = theme?.fg2 ?? AppColors.ink3;
    return V3Pressable(
      onTap: onTap,
      focusRadius: AppRadii.brR,
      semanticLabel: [
        material.title,
        if (author.isNotEmpty) author,
        copy.label,
        if (preparing) 'Preparing…',
      ].join(', '),
      child: Opacity(
        opacity: type == AccessType.none ? .75 : 1,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: theme == null
              ? v3Card()
              : v3Card(color: theme!.card, borderColor: theme!.hair),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: copy.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: V3Icon(copy.icon, size: 18, color: copy.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      style: AppTypography.sans(
                        14.5,
                        FontWeight.w600,
                      ).copyWith(color: title, height: 1.3),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        author,
                        style: AppTypography.sans(12).copyWith(color: sub),
                      ),
                    ],
                    const SizedBox(height: 7),
                    // A long label under a large text scale shrinks rather
                    // than overflowing the row.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: V3AccessBadge(type: type),
                    ),
                    if (preparing) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Preparing…',
                        style: AppTypography.sans(12).copyWith(color: sub),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              preparing || checking
                  ? V3Spinner(color: sub, size: 16)
                  : V3Icon(V3Icons.right, size: 16, color: sub),
            ],
          ),
        ),
      ),
    );
  }
}

/// `MaterialSheet` (v3) body: the badge, title and author, "Why it’s here"
/// (hidden when the material has no reason), the access note, then the
/// access CTA, which calls [onOpen], or a disabled "Not available to read".
class MaterialSheetBody extends StatelessWidget {
  const MaterialSheetBody({
    super.key,
    required this.material,
    required this.type,
    required this.onOpen,
  });

  final PlanMaterialDetail material;
  final AccessType type;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final copy = accessCopy(type);
    final author = material.authorOrCreator?.trim() ?? '';
    final reason = material.reason?.trim() ?? '';
    final cta = copy.cta;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: V3AccessBadge(type: type),
        ),
        const SizedBox(height: 12),
        Text(
          material.title,
          style: AppTypography.sans(21, FontWeight.w600).copyWith(
            color: AppColors.ink,
            letterSpacing: -0.015 * 21,
            height: 1.25,
          ),
        ),
        if (author.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            author,
            style: AppTypography.sans(13.5).copyWith(color: AppColors.ink3),
          ),
        ],
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why it’s here',
                  style: AppTypography.sans(
                    12,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink2),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: AppTypography.sans(
                    14,
                  ).copyWith(color: AppColors.ink, height: 1.5),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: V3Icon(V3Icons.info, size: 15, color: AppColors.ink3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                copy.note,
                style: AppTypography.sans(
                  13,
                ).copyWith(color: AppColors.ink2, height: 1.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (cta != null)
          V3Button(
            full: true,
            iconRight: V3Icons.arrowR,
            onPressed: onOpen,
            child: Text(cta),
          )
        else
          const V3Button(
            kind: V3ButtonKind.soft,
            full: true,
            disabled: true,
            onPressed: null,
            child: Text('Not available to read'),
          ),
      ],
    );
  }
}
