import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The CMPYS design system (per the referenced Deepstash/Wiser-style design)
// uses a cool off-white "paper" canvas with pure-white cards and a vibrant
// green accent — not the earlier white-first/violet system. These tests guard
// the canonical surface tokens against regression.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('route-wide design tokens use the cool-paper surface system', () {
    expect(AppColors.paper, const Color(0xFFF2F3F5));
    expect(AppColors.brandBg, AppColors.paper);
    expect(AppColors.bg, AppColors.paper);
    expect(AppColors.card, const Color(0xFFFFFFFF));
    expect(AppColors.surface, AppColors.card);
    expect(AppColors.green, const Color(0xFF10B36B));
    expect(AppColors.brandAccent, AppColors.green);
  });

  test('app theme keeps route scaffolds on the paper canvas', () {
    final theme = AppTheme.light;

    expect(theme.scaffoldBackgroundColor, AppColors.brandBg);
    expect(theme.bottomSheetTheme.backgroundColor, AppColors.brandBg);
    expect(theme.cardTheme.color, AppColors.surface);
  });
}
