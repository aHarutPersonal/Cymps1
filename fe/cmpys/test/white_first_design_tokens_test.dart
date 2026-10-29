import 'dart:io';
import 'dart:math' as math;

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// CMPYS v3 design tokens ("CMPYS v3.html" :root + v3/tutorial.jsx THEMES):
// warm paper canvas, ember accent, iris / sage / gold supports, Geist UI,
// Instrument Serif display and Literata reading faces. These tests pin the
// canonical values so a later screen task cannot drift from the design.

/// Independent OKLCH -> OKLab -> linear sRGB -> gamma sRGB conversion (clamped
/// to gamut). The expected hex literals below came from a separate Python
/// implementation, so agreement here proves the conversion, not just a copy.
Color _oklch(double l, double c, double hueDegrees) {
  final a = c * math.cos(hueDegrees * math.pi / 180);
  final b = c * math.sin(hueDegrees * math.pi / 180);
  final lp = math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final mp = math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final sp = math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
  final linear = [
    4.0767416621 * lp - 3.3077115913 * mp + 0.2309699292 * sp,
    -1.2684380046 * lp + 2.6097574011 * mp - 0.3413193965 * sp,
    -0.0041960863 * lp - 0.7034186147 * mp + 1.7076147010 * sp,
  ];
  int encode(double x) {
    final g = x <= 0.0031308
        ? 12.92 * x
        : 1.055 * math.pow(x, 1 / 2.4).toDouble() - 0.055;
    return (g.clamp(0.0, 1.0) * 255).round();
  }

  return Color.fromARGB(
    255,
    encode(linear[0]),
    encode(linear[1]),
    encode(linear[2]),
  );
}

int _channelDelta(Color a, Color b) {
  int ch(double v) => (v * 255).round();
  return [
    (ch(a.r) - ch(b.r)).abs(),
    (ch(a.g) - ch(b.g)).abs(),
    (ch(a.b) - ch(b.b)).abs(),
  ].reduce(math.max);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v3 paper, ink, hair and night tokens use the exact design hex', () {
    expect(AppColors.paper, const Color(0xFFF5F2EC));
    expect(AppColors.paper2, const Color(0xFFEDE8DF));
    expect(AppColors.card, const Color(0xFFFFFDF9));
    expect(AppColors.ink, const Color(0xFF17151A));
    expect(AppColors.ink2, const Color(0xFF5D5962));
    expect(AppColors.ink3, const Color(0xFF7E7983));
    expect(AppColors.hair, const Color(0xFFE6E0D6));
    expect(AppColors.hair2, const Color(0xFFD8D1C5));
    expect(AppColors.night, const Color(0xFF0E0C14));
    expect(AppColors.night2, const Color(0xFF191622));
    expect(AppColors.night3, const Color(0xFF252131));
  });

  test('night ink tokens are white at 72% and 50% alpha', () {
    expect(AppColors.nink2, const Color(0xB8FFFFFF));
    expect(AppColors.nink3, const Color(0x80FFFFFF));
    expect(AppColors.nink2.a, closeTo(0.72, 0.005));
    expect(AppColors.nink3.a, closeTo(0.50, 0.005));
  });

  group('v3 accent tokens', () {
    // name, token, expected hex, oklch(L C h) from CMPYS v3.html :root.
    final cases = <(String, Color, int, List<double>)>[
      ('ember', AppColors.ember, 0xFFEC6E38, [0.68, 0.17, 42]),
      ('ember2', AppColors.ember2, 0xFFC94E0C, [0.58, 0.17, 42]),
      ('emberSoft', AppColors.emberSoft, 0xFFFFE4D3, [0.94, 0.04, 52]),
      ('iris', AppColors.iris, 0xFF8A81EF, [0.66, 0.16, 285]),
      ('iris2', AppColors.iris2, 0xFF6B5DCF, [0.55, 0.17, 285]),
      ('irisSoft', AppColors.irisSoft, 0xFFE8E8FF, [0.94, 0.035, 285]),
      ('sage', AppColors.sage, 0xFF43A96E, [0.66, 0.13, 155]),
      ('sage2', AppColors.sage2, 0xFF187C49, [0.52, 0.12, 155]),
      ('sageSoft', AppColors.sageSoft, 0xFFD7F4E0, [0.94, 0.04, 155]),
      ('gold', AppColors.gold, 0xFFE4B750, [0.80, 0.13, 85]),
      ('gold2', AppColors.gold2, 0xFFA97416, [0.60, 0.12, 75]),
      ('goldSoft', AppColors.goldSoft, 0xFFFAEECD, [0.95, 0.045, 90]),
      ('danger', AppColors.danger, 0xFFD33C33, [0.58, 0.19, 28]),
      ('dangerSoft', AppColors.dangerSoft, 0xFFFFE7E3, [0.95, 0.03, 28]),
    ];

    for (final (name, token, hex, lch) in cases) {
      test('$name is the converted oklch(${lch.join(' ')})', () {
        expect(token, Color(hex));
        // Cross-check with the in-test converter (rounding slack of 1/255).
        expect(
          _channelDelta(token, _oklch(lch[0], lch[1], lch[2])),
          lessThanOrEqualTo(1),
        );
      });
    }
  });

  test('legacy brand aliases are re-pointed to ember', () {
    expect(AppColors.brandAccent, AppColors.ember);
    expect(AppColors.brandAccentDark, AppColors.ember2);
    expect(AppColors.brandAccentLight, AppColors.emberSoft);
    expect(AppColors.brandAccentMuted, AppColors.ember.withValues(alpha: 0.12));
    expect(AppColors.primary, AppColors.ember);
    expect(AppColors.accent, AppColors.ember);
    expect(AppColors.accentLight, AppColors.emberSoft);
    expect(AppColors.accentMuted, AppColors.brandAccentMuted);
    expect(AppColors.green, AppColors.ember);
    expect(AppColors.green2, AppColors.ember2);
    expect(AppColors.greenSoft, AppColors.emberSoft);
    expect(AppColors.timelineActive, AppColors.ember);
  });

  test('legacy success aliases are re-pointed to sage', () {
    expect(AppColors.success, AppColors.sage2);
    expect(AppColors.mint, AppColors.sage);
    expect(AppColors.emerald, AppColors.sage);
    expect(AppColors.secondary, AppColors.sage);
    expect(AppColors.mintSoft, AppColors.sageSoft);
    expect(AppColors.timelineComplete, AppColors.sage2);
  });

  test('legacy surface, ink, hair and danger aliases take the v3 values', () {
    expect(AppColors.brandBg, AppColors.paper);
    expect(AppColors.bg, AppColors.paper);
    expect(AppColors.surface, AppColors.card);
    expect(AppColors.surfaceHighlight, AppColors.hair);
    expect(AppColors.surface2, AppColors.hair);
    expect(AppColors.textPrimary, AppColors.ink);
    expect(AppColors.textSecondary, AppColors.ink2);
    expect(AppColors.textTertiary, AppColors.ink3);
    expect(AppColors.border, AppColors.hair);
    expect(AppColors.borderLight, AppColors.hair);
    expect(AppColors.cardBorder, AppColors.hair);
    expect(AppColors.borderFocus, AppColors.hair2);
    expect(AppColors.blkInk, AppColors.ink);
    expect(AppColors.charcoal, AppColors.night);
    expect(AppColors.charcoalSurface, AppColors.night2);
    expect(AppColors.red, AppColors.danger);
    expect(AppColors.crimson, AppColors.danger);
    expect(AppColors.error, AppColors.danger);
  });

  test('radii and motion curves match the v3 tokens', () {
    expect(AppRadii.r, 22);
    expect(AppRadii.r2, 28);
    expect(AppRadii.brR.topLeft, const Radius.circular(22));
    expect(AppRadii.brR2.topLeft, const Radius.circular(28));

    expect(
      [AppMotion.out.a, AppMotion.out.b, AppMotion.out.c, AppMotion.out.d],
      [0.16, 1, 0.3, 1],
    );
    expect(
      [
        AppMotion.spring.a,
        AppMotion.spring.b,
        AppMotion.spring.c,
        AppMotion.spring.d,
      ],
      [0.34, 1.42, 0.5, 1],
    );
    expect(
      [AppMotion.io.a, AppMotion.io.b, AppMotion.io.c, AppMotion.io.d],
      [0.65, 0, 0.35, 1],
    );
    // The existing motion kit keeps using the same ease-out.
    expect(AppCurves.easeOut, AppMotion.out);
  });

  // google_fonts starts a (network) font load whenever it builds a style. The
  // widget-test zone never lets that load complete, which keeps these tests
  // offline and silent; the same way every other test in this repo touches
  // AppTypography. Plain `test()` would let the failed fetch surface.
  group('v3 typography helpers', () {
    testWidgets('display is Instrument Serif, -0.01em, height 1.02', (
      tester,
    ) async {
      final style = AppTypography.display(40);
      expect(style.fontFamily, startsWith('InstrumentSerif'));
      expect(style.fontSize, 40);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.fontStyle, isNot(FontStyle.italic));
      expect(style.letterSpacing, closeTo(-0.4, 1e-9));
      expect(style.height, 1.02);
    });

    testWidgets('displayItalic is the italic Instrument Serif', (tester) async {
      final style = AppTypography.displayItalic(28);
      expect(style.fontFamily, startsWith('InstrumentSerif'));
      expect(style.fontStyle, FontStyle.italic);
      expect(style.fontSize, 28);
      expect(style.letterSpacing, closeTo(-0.28, 1e-9));
      expect(style.height, 1.02);
    });

    testWidgets('read is Literata', (tester) async {
      final style = AppTypography.read(17);
      expect(style.fontFamily, startsWith('Literata'));
      expect(style.fontSize, 17);
    });

    test('sans is the bundled Geist at the requested weight', () {
      final regular = AppTypography.sans(15);
      expect(regular.fontFamily, 'Geist');
      expect(regular.fontSize, 15);
      expect(regular.fontWeight, FontWeight.w400);

      final semi = AppTypography.sans(13, FontWeight.w600);
      expect(semi.fontFamily, 'Geist');
      expect(semi.fontSize, 13);
      expect(semi.fontWeight, FontWeight.w600);
    });

    test('kick is 11 / w600 / 0.12em / ink3', () {
      final style = AppTypography.kick;
      expect(style.fontFamily, 'Geist');
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, closeTo(1.32, 1e-9));
      expect(style.color, AppColors.ink3);
    });

    test('tnum asks for tabular figures', () {
      expect(AppTypography.tnum.fontFeatures, [
        const FontFeature.tabularFigures(),
      ]);
    });
  });

  testWidgets('legacy typography members keep working on the v3 faces', (
    tester,
  ) async {
    // `display` is both the legacy TextStyle (copyWith call sites) and the v3
    // size helper.
    expect(AppTypography.display.fontSize, 34);
    expect(AppTypography.display.fontFamily, startsWith('InstrumentSerif'));
    expect(AppTypography.display.copyWith(fontSize: 20).fontSize, 20);
    expect(AppTypography.display(30).fontSize, 30);

    for (final style in [
      AppTypography.h1,
      AppTypography.h2,
      AppTypography.h3,
      AppTypography.h4,
      AppTypography.bodyLarge,
      AppTypography.body,
      AppTypography.bodyMedium,
      AppTypography.caption,
      AppTypography.captionMedium,
      AppTypography.bodySmall,
      AppTypography.button,
      AppTypography.buttonSmall,
      AppTypography.label,
      AppTypography.labelSmall,
      AppTypography.bodyDim,
    ]) {
      expect(style.fontFamily, 'Geist');
    }
    // Heaviest bundled Geist weight is w700.
    expect(AppTypography.h1.fontWeight, FontWeight.w700);
  });

  test('reader themes carry the design THEMES values', () {
    expect(ReaderTheme.values, [
      ReaderTheme.light,
      ReaderTheme.sepia,
      ReaderTheme.dark,
    ]);

    // light resolves to the v3 paper / ink tokens.
    expect(ReaderTheme.light.bg, AppColors.paper);
    expect(ReaderTheme.light.fg, AppColors.ink);
    expect(ReaderTheme.light.fg2, AppColors.ink2);
    expect(ReaderTheme.light.card, AppColors.card);
    expect(ReaderTheme.light.hair, AppColors.hair);

    expect(ReaderTheme.sepia.bg, const Color(0xFFF1E7D3));
    expect(ReaderTheme.sepia.fg, const Color(0xFF3B2F22));
    expect(ReaderTheme.sepia.fg2, const Color(0xFF6B5A45));
    expect(ReaderTheme.sepia.card, const Color(0xFFF8F0E0));
    expect(ReaderTheme.sepia.hair, const Color(0xFFE2D4BA));

    expect(ReaderTheme.dark.bg, const Color(0xFF141219));
    expect(ReaderTheme.dark.fg, const Color(0xFFECE8F0));
    expect(ReaderTheme.dark.fg2, const Color(0xFFA9A3B0));
    expect(ReaderTheme.dark.card, const Color(0xFF1E1B25));
    expect(ReaderTheme.dark.hair, const Color(0xFF2C2834));

    expect(ReaderTheme.fromName('sepia'), ReaderTheme.sepia);
    expect(ReaderTheme.fromName('dark'), ReaderTheme.dark);
    expect(ReaderTheme.fromName(null), ReaderTheme.light);
    expect(ReaderTheme.fromName('neon'), ReaderTheme.light);
    expect(ReaderTheme.sepia.label, 'Sepia');
  });

  test('app theme keeps route scaffolds on the paper canvas', () {
    final theme = AppTheme.light;

    expect(theme.scaffoldBackgroundColor, AppColors.brandBg);
    expect(theme.bottomSheetTheme.backgroundColor, AppColors.brandBg);
    expect(theme.cardTheme.color, AppColors.surface);
  });

  test('app theme uses Geist as its base font and ember as primary', () {
    final theme = AppTheme.light;

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Geist');
    expect(theme.textTheme.titleLarge?.fontFamily, 'Geist');
    expect(theme.colorScheme.primary, AppColors.ember2);
    expect(theme.colorScheme.secondary, AppColors.sage);
    expect(theme.colorScheme.error, AppColors.danger);
    expect(theme.progressIndicatorTheme.color, AppColors.ember);
  });

  test('Geist 400/500/600/700 are bundled and declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: Geist'));

    const weights = {
      400: 'Regular',
      500: 'Medium',
      600: 'SemiBold',
      700: 'Bold',
    };
    weights.forEach((weight, name) {
      final path = 'assets/fonts/geist/Geist-$name.ttf';
      expect(
        pubspec,
        contains('asset: $path'),
        reason: 'pubspec declares $path',
      );
      expect(
        pubspec,
        matches(
          RegExp('asset: ${RegExp.escape(path)}\\s*\\n\\s*weight: $weight\\b'),
        ),
        reason: '$path is declared as weight $weight',
      );
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path exists');
      expect(file.lengthSync(), greaterThan(50 * 1024));
    });
  });
}
