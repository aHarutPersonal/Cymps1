import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/state/reader_settings.dart';

/// The "Reading settings" sheet (design `sheet === 'aa'`) shared by the
/// tutorial reader and the book reader: text size A / A+ / A++ and the
/// light / sepia / dark theme, stored on this device through
/// [readerSettingsProvider], so both readers follow one setting.
Future<void> showReaderSettingsSheet(BuildContext context) {
  return showV3Sheet<void>(
    context,
    title: 'Reading settings',
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(readerSettingsProvider);
        final label = AppTypography.sans(
          12.5,
          FontWeight.w600,
        ).copyWith(color: AppColors.ink2);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Text size', style: label),
            const SizedBox(height: 8),
            V3Seg<int>(
              items: [
                for (var i = 0; i < ReaderSettings.sizeLabels.length; i++)
                  V3SegItem(i, ReaderSettings.sizeLabels[i]),
              ],
              value: settings.size,
              onChanged: ref.setReaderSize,
            ),
            const SizedBox(height: 18),
            Text('Theme', style: label),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final theme in ReaderTheme.values) ...[
                  if (theme != ReaderTheme.values.first)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _ThemeSwatch(
                      theme: theme,
                      selected: settings.theme == theme,
                      onTap: () => ref.setReaderTheme(theme),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReaderTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: theme.label,
      focusRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: MotionConfig.enabled(context)
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        // At least 70 pt; taller when a large text scale needs the room.
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.ember : theme.hair,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Aa',
              style: AppTypography.read(
                20,
              ).copyWith(color: theme.fg, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(
              theme.label,
              style: AppTypography.sans(
                13.5,
                FontWeight.w600,
              ).copyWith(color: theme.fg),
            ),
          ],
        ),
      ),
    );
  }
}
