import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../features/session/models/content_resource.dart';

class ResourceNotesPanel extends StatelessWidget {
  const ResourceNotesPanel({
    super.key,
    required this.title,
    required this.hintText,
    required this.controller,
    required this.highlights,
    required this.onSave,
    required this.onDelete,
    this.isLoading = false,
    this.isSaving = false,
    this.dark = false,
    this.timestampBuilder,
    this.padding,
  });

  final String title;
  final String hintText;
  final TextEditingController controller;
  final List<ContentHighlight> highlights;
  final VoidCallback onSave;
  final ValueChanged<ContentHighlight> onDelete;
  final bool isLoading;
  final bool isSaving;
  final bool dark;
  final String? Function(ContentHighlight highlight)? timestampBuilder;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final primaryText = dark ? Colors.white : AppColors.textPrimary;
    final secondaryText = dark
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.textSecondary;
    final tertiaryText = dark ? Colors.white38 : AppColors.textTertiary;
    final panelColor = dark
        ? Colors.white.withValues(alpha: 0.06)
        : AppColors.surface.withValues(alpha: 0.45);
    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.12)
        : AppColors.border.withValues(alpha: 0.6);
    final fieldColor = dark
        ? Colors.black.withValues(alpha: 0.22)
        : AppColors.bg.withValues(alpha: 0.55);

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: AppRadii.br16,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: AppRadii.br12,
                  ),
                  child: const Icon(
                    Icons.edit_note_rounded,
                    size: 22,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.h4.copyWith(color: primaryText),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: AppTypography.body.copyWith(color: primaryText),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: AppTypography.caption.copyWith(color: tertiaryText),
                filled: true,
                fillColor: fieldColor,
                border: OutlineInputBorder(
                  borderRadius: AppRadii.br12,
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.br12,
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.br12,
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: const Text('Save note'),
              ),
            ),
            if (highlights.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Divider(color: borderColor),
              const SizedBox(height: AppSpacing.s4),
              ...highlights
                  .take(4)
                  .map(
                    (highlight) => _ResourceNoteItem(
                      highlight: highlight,
                      textColor: secondaryText,
                      iconColor: tertiaryText,
                      timestamp: timestampBuilder?.call(highlight),
                      onDelete: () => onDelete(highlight),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourceNoteItem extends StatelessWidget {
  const _ResourceNoteItem({
    required this.highlight,
    required this.textColor,
    required this.iconColor,
    required this.onDelete,
    this.timestamp,
  });

  final ContentHighlight highlight;
  final Color textColor;
  final Color iconColor;
  final VoidCallback onDelete;
  final String? timestamp;

  @override
  Widget build(BuildContext context) {
    final text = highlight.displayText;
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timestamp != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.brFull,
              ),
              child: Text(
                timestamp!,
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.accent,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s10),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 9),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.s10),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete note',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: iconColor,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
