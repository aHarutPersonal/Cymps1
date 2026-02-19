import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/design_tokens.dart';

/// Selectable chip component.
class CmpysChip extends StatelessWidget {
  const CmpysChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.icon,
    this.selectedColor,
    this.enabled = true,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? icon;
  final Color? selectedColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accentColor = selectedColor ?? AppColors.accent;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.15)
              : AppColors.surface,
          borderRadius: AppRadii.brFull,
          border: Border.all(
            color: isSelected ? accentColor : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              SvgPicture.asset(
                icon!,
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(
                  isSelected ? accentColor : AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
            ],
            Text(
              label,
              style: AppTypography.captionMedium.copyWith(
                color: isSelected ? accentColor : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip group for multiple selection.
class CmpysChipGroup extends StatelessWidget {
  const CmpysChipGroup({
    super.key,
    required this.chips,
    required this.selectedIndices,
    this.onSelectionChanged,
    this.allowMultiple = true,
    this.wrap = true,
    this.spacing = AppSpacing.s8,
  });

  final List<String> chips;
  final Set<int> selectedIndices;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final bool allowMultiple;
  final bool wrap;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final children = chips.asMap().entries.map((entry) {
      final index = entry.key;
      final label = entry.value;
      final isSelected = selectedIndices.contains(index);

      return CmpysChip(
        label: label,
        isSelected: isSelected,
        enabled: onSelectionChanged != null,
        onTap: onSelectionChanged == null
            ? null
            : () {
                final newSelection = Set<int>.from(selectedIndices);
                if (isSelected) {
                  newSelection.remove(index);
                } else {
                  if (!allowMultiple) newSelection.clear();
                  newSelection.add(index);
                }
                onSelectionChanged!(newSelection);
              },
      );
    }).toList();

    if (wrap) {
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: children,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: children
            .map((chip) => Padding(
                  padding: EdgeInsets.only(right: spacing),
                  child: chip,
                ))
            .toList(),
      ),
    );
  }
}

/// Tag chip (non-interactive, for display).
class CmpysTag extends StatelessWidget {
  const CmpysTag({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.small = false,
  });

  final String label;
  final Color? color;
  final String? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tagColor = color ?? AppColors.accent;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? AppSpacing.s8 : AppSpacing.s12,
        vertical: small ? AppSpacing.s4 : AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: tagColor.withOpacity(0.15),
        borderRadius: AppRadii.brFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SvgPicture.asset(
              icon!,
              width: small ? 12 : 14,
              height: small ? 12 : 14,
              colorFilter: ColorFilter.mode(tagColor, BlendMode.srcIn),
            ),
            SizedBox(width: small ? AppSpacing.s4 : AppSpacing.s6),
          ],
          Text(
            label,
            style: (small ? AppTypography.tiny : AppTypography.caption)
                .copyWith(color: tagColor, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
