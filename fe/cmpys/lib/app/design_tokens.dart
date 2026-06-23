import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for CMPYS app.
/// Prototype system: light grid surfaces, charcoal text, coral actions, mint signals.
abstract final class AppColors {
  // ── Brand ──
  static const Color brandBg = Color(0xFFF9FAFB);
  static const Color brandAccent = Color(0xFFFF7F6A);
  static const Color brandAccentDark = Color(0xFFE45F51);
  static const Color brandAccentLight = Color(0xFFFF9A88);
  static final Color brandAccentMuted = brandAccent.withValues(alpha: 0.12);
  static const Color peach = Color(0xFFFFC27A);
  static const Color mint = Color(0xFF10B981);

  // ── Backgrounds ──
  static const Color bg = brandBg;
  static const Color bgTrue = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHighlight = Color(0xFFF8FAFC);
  static const Color surface2 = surfaceHighlight;
  static const Color surfaceGlass = Color(0xEFFFFFFF);

  // ── Dark Surfaces (Auth/Splash/Card variants) ──
  static const Color charcoal = Color(0xFF0F172A);
  static const Color charcoalSurface = Color(0xFF1E293B);
  static const Color cardDark = Color(0xFF1E293B);

  // ── Dark Gradient (Ideas/Feed cards) ──
  static const Color darkGradientStart = Color(0xFF07080B);
  static const Color darkGradientEnd = Color(0xFF15171E);

  // ── Glass / Frosted surfaces ──
  static const Color glassBg = Color(0xEFFFFFFF);
  static const Color glassBorder = Color(0x1F1F1B16);
  static const Color glassHighlight = Color(0xFFFFFFFF);

  // ── Timeline node states ──
  static const Color timelineActive = brandAccent;
  static const Color timelineComplete = Color(0xFF16A34A);
  static const Color timelineLocked = Color(0x331F1B16);
  static const Color timelineLine = Color(0x1A1F1B16);
  static const Color timelineLineActive = brandAccent;

  // ── Typography Colors (light backgrounds) ──
  static const Color textPrimary = charcoal;
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);

  // ── Typography Colors (dark backgrounds — auth/splash) ──
  static const Color textOnDarkPrimary = Color(0xFFFFFFFF);
  static const Color textOnDarkSecondary = Color(0xFF9CA3AF);

  // ── Functional Accents ──
  static const Color emerald = mint;
  static const Color blue = Color(0xFF78C7FF);
  static const Color red = brandAccent;
  static const Color alert = Color(0xFFFF3B30);

  // ── Semantic Aliases ──
  static const Color primary = brandAccent;
  static const Color secondary = emerald;
  static const Color tertiary = blue;
  static const Color accent = brandAccent;
  static const Color accentLight = brandAccentLight;
  static final Color accentMuted = brandAccentMuted;

  static const Color error = alert;
  static const Color success = emerald;
  static const Color warning = Color(0xFFFFC107);
  static const Color info = blue;

  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);
  static const Color borderFocus = Color(0xFFCBD5E1);
  static const Color cardBorder = Color(0xFFE2E8F0);

  // ── Dark-mode borders (auth/splash) ──
  static const Color borderOnDark = Color(0x1AFFFFFF);
  static const Color borderOnDarkLight = Color(0x14FFFFFF);

  // ── Highlight (markdown bold bg in IdeaCards) ──
  static final Color highlightBg = brandAccent.withValues(alpha: 0.10);

  // Legacy aliases (for backwards compat during migration)
  static const Color gold = brandAccent;
  static const Color goldDark = brandAccentDark;
  static const Color goldLight = brandAccentLight;
  static const Color coral = brandAccent;
  static const Color coralDark = brandAccentDark;
  static const Color coralLight = brandAccentLight;
  static const Color lime = mint;
  static const Color purple = emerald;
  static const Color orange = brandAccent;
  static const Color crimson = brandAccent;
  static final Color crimsonDim = brandAccent.withValues(alpha: 0.15);
  static const Color cardCream = Color(0xFFFFFCF6);
  static const Color cardPeach = Color(0x26FFC27A);
  static const Color cardMint = Color(0x242DBE82);
  static const Color cardLavender = Color(0x22A78BFA);
  static const Color cardSky = Color(0x2278C7FF);
  static const Color cardAmber = Color(0x26FFC27A);
  static const Color cardTextPrimary = textPrimary;
  static const Color cardTextSecondary = textSecondary;
}

/// Border radii tokens.
abstract final class AppRadii {
  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;
  static const double r32 = 32.0;
  static const double rFull = 9999.0;

  static const BorderRadius br8 = BorderRadius.all(Radius.circular(r8));
  static const BorderRadius br12 = BorderRadius.all(Radius.circular(r12));
  static const BorderRadius br16 = BorderRadius.all(Radius.circular(r16));
  static const BorderRadius br20 = BorderRadius.all(Radius.circular(r20));
  static const BorderRadius br24 = BorderRadius.all(Radius.circular(r24));
  static const BorderRadius br32 = BorderRadius.all(Radius.circular(r32));
  static const BorderRadius brFull = BorderRadius.all(Radius.circular(rFull));
}

/// Spacing tokens
abstract final class AppSpacing {
  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s6 = 6.0;
  static const double s8 = 8.0;
  static const double s10 = 10.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s40 = 40.0;
  static const double s48 = 48.0;
  static const double s64 = 64.0;
  static const double s80 = 80.0;
  static const double s100 = 100.0;

  // Common paddings
  static const EdgeInsets p4 = EdgeInsets.all(s4);
  static const EdgeInsets p8 = EdgeInsets.all(s8);
  static const EdgeInsets p12 = EdgeInsets.all(s12);
  static const EdgeInsets p16 = EdgeInsets.all(s16);
  static const EdgeInsets p20 = EdgeInsets.all(s20);
  static const EdgeInsets p24 = EdgeInsets.all(s24);

  // Horizontal paddings
  static const EdgeInsets ph16 = EdgeInsets.symmetric(horizontal: s16);
  static const EdgeInsets ph20 = EdgeInsets.symmetric(horizontal: s20);
  static const EdgeInsets ph24 = EdgeInsets.symmetric(horizontal: s24);

  // Vertical paddings
  static const EdgeInsets pv16 = EdgeInsets.symmetric(vertical: s16);

  // Screen padding
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: s20);

  // Clearance for the floating nav bar rendered by AppShell.
  // Nav bar: 56px + gap (8px or 16px if no bottom safe area).
  // Using 96px gives comfortable clearance across all device sizes.
  static const double floatingNavBarHeight = 96.0;

  // EdgeInsets to apply as bottom padding on scrollable content inside tabs.
  static const EdgeInsets floatingNavBarBottom =
      EdgeInsets.only(bottom: floatingNavBarHeight);
}

/// Typography tokens — prototype font system.
///
/// UI font: Inter. Data labels: JetBrains Mono.
/// Reading font: Playfair Display — elegant serif for IdeaCard content.
abstract final class AppTypography {
  // ═══════════════════════════════════════════════
  // UI FONT — Inter (Nav, Headers, Labels, Buttons)
  // ═══════════════════════════════════════════════

  // -- HEADERS --
  static TextStyle get h1 => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle get h4 => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  // -- BODY (UI context — descriptions, secondary text) --
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static TextStyle get captionMedium => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static TextStyle get bodySmall => caption;

  static TextStyle get captionUpper => GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.5,
    color: AppColors.textTertiary,
  );

  static TextStyle get tiny => captionUpper;

  // -- DATA / NUMBERS --
  static TextStyle get monoNum => GoogleFonts.jetBrainsMono(
    fontSize: 24,
    fontWeight: FontWeight.w300,
    color: AppColors.textPrimary,
  );

  static TextStyle get monoLabel => GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // -- UI ELEMENTS --
  static TextStyle get button => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static TextStyle get buttonSmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static TextStyle get label => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  // ═══════════════════════════════════════════════
  // READING FONT — Playfair Display (IdeaCards, Lessons, Long Text)
  // ═══════════════════════════════════════════════

  /// Primary reading style for IdeaCard content.
  /// Size 28, height 1.6 for maximum frictionless reading.
  static TextStyle get reading => GoogleFonts.playfairDisplay(
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.textPrimary,
  );

  /// Smaller reading variant for secondary content.
  static TextStyle get readingSmall => GoogleFonts.playfairDisplay(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.textPrimary,
  );

  /// Bold reading variant for emphasis within IdeaCards.
  static TextStyle get readingBold => GoogleFonts.playfairDisplay(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.6,
    color: AppColors.textPrimary,
  );

  /// Reading quote style — italic serif for pullquotes.
  static TextStyle get readingQuote => GoogleFonts.playfairDisplay(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    height: 1.6,
    color: AppColors.textTertiary,
  );

  /// Category tag on IdeaCards — small uppercase serif.
  static TextStyle get readingTag => GoogleFonts.playfairDisplay(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    height: 1.2,
    color: AppColors.brandAccent,
  );

  /// IdeaCard body text — Playfair at 17px for card-context reading.
  static TextStyle get ideaCardBody => GoogleFonts.playfairDisplay(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.65,
    color: AppColors.textPrimary,
  );
}

/// Animation durations & curves
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration pageTransition = Duration(milliseconds: 400);
}

abstract final class AppCurves {
  /// Premium ease-out for modals and cards
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);

  /// Smooth editorial entrance
  static const Curve editorialIn = Cubic(0.65, 0, 0.35, 1);
}

/// Common shadows — Ultra-soft editorial style.
abstract final class AppShadows {
  /// Subtle card shadow — barely visible, premium feel.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x121F1B16), blurRadius: 24, offset: Offset(0, 12)),
  ];

  /// Medium elevation — floating cards.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x181F1B16), blurRadius: 42, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x26FF6F61), blurRadius: 28, offset: Offset(0, 0)),
  ];

  /// Large elevation — hero cards, modals.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x211F1B16), blurRadius: 70, offset: Offset(0, 30)),
    BoxShadow(color: Color(0x30FF6F61), blurRadius: 44, offset: Offset(0, 0)),
  ];

  static const List<BoxShadow> card = sm;
  static const List<BoxShadow> pop = md;

  static List<BoxShadow> glowAccent = [
    BoxShadow(
      color: AppColors.brandAccent.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  // Legacy aliases
  static List<BoxShadow> glowGold = glowAccent;
  static List<BoxShadow> glowCoral = glowAccent;
  static List<BoxShadow> glowEmerald = [
    BoxShadow(
      color: AppColors.emerald.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> glowBlue = [
    BoxShadow(
      color: AppColors.blue.withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> glowLime = glowEmerald;
  static List<BoxShadow> glowPurple = glowEmerald;
  static List<BoxShadow> get accent => glowAccent;

  /// Ultra-soft glow for timeline current node
  static List<BoxShadow> glowSubtle = [
    BoxShadow(
      color: AppColors.brandAccent.withValues(alpha: 0.15),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: AppColors.brandAccent.withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}
