import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the CMPYS app.
///
/// v3 system: warm paper canvas, ember accent, iris / sage / gold supports and
/// a night surface for dark moments. Source of truth: `CMPYS v3.html` `:root`.
/// The accent families (ember, iris, sage, gold, danger) are the design's OKLCH
/// values converted once to gamut-clamped sRGB hex. The old v2 names (`green`,
/// `brandAccent`, `primary`, ...) stay as aliases onto the v3 tokens so every
/// existing call site keeps compiling; new code should use the v3 names.
abstract final class AppColors {
  // ═══════════════════════════════════════════════
  // CMPYS v3 palette
  // ═══════════════════════════════════════════════

  // ── Paper, ink and hairlines ──
  static const Color paper = Color(0xFFF5F2EC);
  static const Color paper2 = Color(0xFFEDE8DF);
  static const Color card = Color(0xFFFFFDF9);
  static const Color ink = Color(0xFF17151A);
  static const Color ink2 = Color(0xFF5D5962);
  static const Color ink3 = Color(0xFF7E7983);
  static const Color hair = Color(0xFFE6E0D6);
  static const Color hair2 = Color(0xFFD8D1C5);

  // ── Night (dark surfaces) ──
  static const Color night = Color(0xFF0E0C14);
  static const Color night2 = Color(0xFF191622);
  static const Color night3 = Color(0xFF252131);
  static const Color nink2 = Color(0xB8FFFFFF); // rgba(255,255,255,.72)
  static const Color nink3 = Color(0x80FFFFFF); // rgba(255,255,255,.5)

  // ── Accents (oklch -> sRGB; `2` is the accessible text/action tone) ──
  static const Color ember = Color(0xFFEC6E38); //     oklch(0.68 0.17 42)
  static const Color ember2 = Color(0xFFC94E0C); //    oklch(0.58 0.17 42)
  static const Color emberSoft = Color(0xFFFFE4D3); // oklch(0.94 0.04 52)
  static const Color iris = Color(0xFF8A81EF); //      oklch(0.66 0.16 285)
  static const Color iris2 = Color(0xFF6B5DCF); //     oklch(0.55 0.17 285)
  static const Color irisSoft = Color(0xFFE8E8FF); //  oklch(0.94 0.035 285)
  static const Color sage = Color(0xFF43A96E); //      oklch(0.66 0.13 155)
  static const Color sage2 = Color(0xFF187C49); //     oklch(0.52 0.12 155)
  static const Color sageSoft = Color(0xFFD7F4E0); //  oklch(0.94 0.04 155)
  static const Color gold = Color(0xFFE4B750); //      oklch(0.8 0.13 85)
  static const Color gold2 = Color(0xFFA97416); //     oklch(0.6 0.12 75)
  static const Color goldSoft = Color(0xFFFAEECD); //  oklch(0.95 0.045 90)
  static const Color danger = Color(0xFFD33C33); //    oklch(0.58 0.19 28)
  static const Color dangerSoft = Color(0xFFFFE7E3); // oklch(0.95 0.03 28)

  // ═══════════════════════════════════════════════
  // Legacy aliases (v2 names, re-pointed onto the v3 tokens)
  // ═══════════════════════════════════════════════

  // ── Brand (v3: ember on warm paper) ──
  // Brand maps onto the ember/paper system so the whole app — including any
  // Material widget that reads ColorScheme.primary — shares one accent.
  static const Color brandBg = paper;
  static const Color brandAccent = ember;
  static const Color brandAccentDark = ember2;
  static const Color brandAccentLight = emberSoft;
  static final Color brandAccentMuted = brandAccent.withValues(alpha: 0.12);
  static const Color peach = Color(0xFFFFC27A);
  static const Color mint = sage;

  // ── Backgrounds ──
  static const Color bg = brandBg;
  static const Color bgTrue = Color(0xFFF9FAFB);
  static const Color surface = card;
  static const Color surfaceHighlight = hair; // tracks
  static const Color surface2 = surfaceHighlight;
  static const Color surfaceGlass = Color(0xEFFFFFFF);

  // ── Dark Surfaces (Auth/Splash/Card variants) ──
  static const Color charcoal = night;
  static const Color charcoalSurface = night2;
  static const Color cardDark = night2;

  // ── Dark Gradient (Ideas/Feed cards) ──
  static const Color darkGradientStart = Color(0xFF07080B);
  static const Color darkGradientEnd = Color(0xFF15171E);

  // ── Glass / Frosted surfaces ──
  static const Color glassBg = Color(0xEFFFFFFF);
  static const Color glassBorder = Color(0x1F1F1B16);
  static const Color glassHighlight = Color(0xFFFFFFFF);

  // ── Timeline node states ──
  static const Color timelineActive = brandAccent;
  static const Color timelineComplete = sage2;
  static const Color timelineLocked = Color(0x331F1B16);
  static const Color timelineLine = Color(0x1A1F1B16);
  static const Color timelineLineActive = brandAccent;

  // ── Typography Colors ──
  static const Color textPrimary = ink;
  static const Color textSecondary = ink2;
  static const Color textTertiary = ink3;

  // ── Typography Colors (dark backgrounds — auth/splash) ──
  static const Color textOnDarkPrimary = Color(0xFFFFFFFF);
  static const Color textOnDarkSecondary = Color(0xFF9CA3AF);

  // ── Functional Accents ──
  static const Color emerald = mint;
  static const Color blue = Color(0xFF78C7FF);
  // Semantic red is decoupled from brand: brand is ember (a warm orange), so
  // red must stay a distinct red for Compare / destructive states.
  static const Color red = danger;
  static const Color alert = danger;

  // ── Semantic Aliases ──
  static const Color primary = brandAccent;
  static const Color secondary = emerald;
  static const Color tertiary = blue;
  static const Color accent = brandAccent;
  static const Color accentLight = brandAccentLight;
  static final Color accentMuted = brandAccentMuted;

  static const Color error = alert;
  static const Color success = sage2;
  static const Color warning = Color(0xFFFFC107);
  static const Color info = blue;

  static const Color border = hair;
  static const Color borderLight = hair;
  static const Color borderFocus = hair2;
  static const Color cardBorder = hair;

  // ── Dark-mode borders (auth/splash) ──
  static const Color borderOnDark = Color(0x1AFFFFFF);
  static const Color borderOnDarkLight = Color(0x14FFFFFF);

  // ── Highlight (markdown bold bg in IdeaCards) ──
  static final Color highlightBg = brandAccent.withValues(alpha: 0.10);

  // Legacy aliases (for backwards compat during migration). `gold` itself is
  // now the real v3 gold; its old Dark/Light siblings follow it.
  static const Color goldDark = gold2;
  static const Color goldLight = goldSoft;
  static const Color coral = brandAccent;
  static const Color coralDark = brandAccentDark;
  static const Color coralLight = brandAccentLight;
  static const Color lime = mint;
  static const Color purple = emerald;
  static const Color orange = ochre;
  static const Color crimson = danger;
  static final Color crimsonDim = danger.withValues(alpha: 0.15);
  static const Color cardCream = Color(0xFFFFFCF6);
  static const Color cardPeach = Color(0x26FFC27A);
  static const Color cardMint = Color(0x242DBE82);
  static const Color cardLavender = Color(0x22A78BFA);
  static const Color cardSky = Color(0x2278C7FF);
  static const Color cardAmber = Color(0x26FFC27A);
  static const Color cardTextPrimary = textPrimary;
  static const Color cardTextSecondary = textSecondary;

  // ── CMPYS 2026 (v2) names — brand/success families follow v3 ──
  static const Color green = ember;
  // Accessible foreground/action tone; the lighter ember is a visual accent.
  static const Color green2 = ember2;
  static const Color greenSoft = emberSoft;
  static const Color ochre = Color(0xFFF59E0B);
  static const Color ochre2 = Color(0xFFB45309);
  static const Color ochreSoft = Color(0xFFFCEBC9);
  static const Color clay = Color(0xFFFF6B5E);
  static const Color claySoft = Color(0xFFFFE1DD);
  static const Color blueSoft = Color(0xFFDBE8FE);
  static const Color lilac = Color(0xFF6D5EF6);
  static const Color lilacSoft = Color(0xFFE6E3FE);
  static const Color pink = Color(0xFFFF5DA2);
  static const Color pinkSoft = Color(0xFFFFDEEC);
  static const Color mintSoft = sageSoft;
  static const Color blkInk = ink;

  // Deep end of [gradGreen]: oklch(0.50 0.15 42), derived (not a design
  // token) so white text on the gradient stays above 4.5:1.
  static const Color _emberDeep = Color(0xFFA63D02);

  /// Brand gradient (name kept from v2; it is ember now).
  static const LinearGradient gradGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ember2, _emberDeep],
  );
  static const LinearGradient gradViolet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [iris, iris2],
  );
  static const LinearGradient gradInk = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [night3, night2],
  );
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

  // ── CMPYS v3 radii (--r / --r2) ──
  /// Cards, tiles and inputs.
  static const double r = 22.0;

  /// Hero cards, sheets and large surfaces.
  static const double r2 = 28.0;

  static const BorderRadius brR = BorderRadius.all(Radius.circular(r));
  static const BorderRadius brR2 = BorderRadius.all(Radius.circular(r2));

  // ── CMPYS 2026 (v2) radii (--r-btn / --r-card / --r-lg) ──
  static const BorderRadius button = BorderRadius.all(Radius.circular(999));
  static const BorderRadius card = BorderRadius.all(Radius.circular(26));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(32));
}

/// Spacing tokens
abstract final class AppSpacing {
  /// Keep reading and task lists comfortable on tablets and landscape screens.
  static double pageGutter(double width) =>
      ((width - 720) / 2).clamp(18.0, double.infinity);

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
  static const EdgeInsets floatingNavBarBottom = EdgeInsets.only(
    bottom: floatingNavBarHeight,
  );
}

/// A [TextStyle] that can also be called with a size: `AppTypography.display`
/// is the legacy 34 pt headline style (about 30 call sites use
/// `AppTypography.display.copyWith(...)`), and `AppTypography.display(26)` is
/// the v3 `display(size)` helper. Everything else behaves as a plain [TextStyle].
class AppDisplayStyle extends TextStyle {
  AppDisplayStyle._(TextStyle base)
    : super(
        inherit: base.inherit,
        color: base.color,
        backgroundColor: base.backgroundColor,
        fontSize: base.fontSize,
        fontWeight: base.fontWeight,
        fontStyle: base.fontStyle,
        letterSpacing: base.letterSpacing,
        wordSpacing: base.wordSpacing,
        textBaseline: base.textBaseline,
        height: base.height,
        leadingDistribution: base.leadingDistribution,
        locale: base.locale,
        foreground: base.foreground,
        background: base.background,
        shadows: base.shadows,
        fontFeatures: base.fontFeatures,
        fontVariations: base.fontVariations,
        decoration: base.decoration,
        decorationColor: base.decorationColor,
        decorationStyle: base.decorationStyle,
        decorationThickness: base.decorationThickness,
        debugLabel: base.debugLabel,
        fontFamily: base.fontFamily,
        fontFamilyFallback: base.fontFamilyFallback,
        overflow: base.overflow,
      );

  /// v3 `display(size)`: Instrument Serif, -0.01em, line height 1.02.
  TextStyle call(double size) => AppTypography._instrumentSerif(size);
}

/// Typography tokens — CMPYS v3 type system.
///
/// UI font: Geist (bundled, `assets/fonts/geist`). Display: Instrument Serif.
/// Reading: Literata. The last two come from google_fonts. v3 helpers
/// ([display], [displayItalic], [read], [sans], [kick], [tnum]) carry no colour
/// (except [kick]) so they follow the surrounding text colour, as the design's
/// CSS does. The members below the "legacy" headings keep their v2 names and
/// now map onto Geist / Instrument Serif; the Playfair Display and JetBrains
/// Mono members have no v3 counterpart yet and are unchanged.
abstract final class AppTypography {
  /// Bundled UI family (pubspec `fonts:`); weights 400, 500, 600 and 700.
  static const String geist = 'Geist';

  // ═══════════════════════════════════════════════
  // v3 helpers
  // ═══════════════════════════════════════════════

  static TextStyle _instrumentSerif(
    double size, {
    FontStyle fontStyle = FontStyle.normal,
  }) => GoogleFonts.instrumentSerif(
    fontSize: size,
    fontWeight: FontWeight.w400,
    fontStyle: fontStyle,
    letterSpacing: -0.01 * size,
    height: 1.02,
  );

  /// Instrument Serif at [size], letter-spacing -0.01em, line height 1.02
  /// (`.disp`). Also the legacy 34 pt headline style: see [AppDisplayStyle].
  static final AppDisplayStyle display = AppDisplayStyle._(
    _instrumentSerif(34).copyWith(color: AppColors.ink),
  );

  /// Italic Instrument Serif at [size] (`.disp` + italic).
  static TextStyle displayItalic(double size) =>
      _instrumentSerif(size, fontStyle: FontStyle.italic);

  /// Literata at [size] for long-form reading (`.serif`).
  static TextStyle read(double size) => GoogleFonts.literata(fontSize: size);

  /// Geist at [size] and [weight] (the design's `--sans`).
  static TextStyle sans(double size, [FontWeight weight = FontWeight.w400]) =>
      TextStyle(fontFamily: geist, fontSize: size, fontWeight: weight);

  /// `.kick`: 11 / w600 / 0.12em / ink3. CSS also uppercases it; Flutter text
  /// styles cannot, so callers pass `label.toUpperCase()`.
  static const TextStyle kick = TextStyle(
    fontFamily: geist,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 11 * 0.12,
    color: AppColors.ink3,
  );

  /// `.tnum`: tabular figures. Merge it onto a number's style:
  /// `AppTypography.sans(15).merge(AppTypography.tnum)`.
  static const TextStyle tnum = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ═══════════════════════════════════════════════
  // Legacy UI styles — now Geist (were Inter)
  // ═══════════════════════════════════════════════

  // -- HEADERS --
  static const TextStyle h1 = TextStyle(
    fontFamily: geist,
    fontSize: 32,
    fontWeight: FontWeight.w700, // Geist tops out at w700 (Inter was w800)
    height: 1.1,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: geist,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: geist,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle h4 = TextStyle(
    fontFamily: geist,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  // -- BODY (UI context — descriptions, secondary text) --
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: geist,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: geist,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle captionMedium = TextStyle(
    fontFamily: geist,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodySmall = caption;

  static final TextStyle captionUpper = GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.5,
    color: AppColors.textTertiary,
  );

  static final TextStyle tiny = captionUpper;

  // -- DATA / NUMBERS --
  static final TextStyle monoNum = GoogleFonts.jetBrainsMono(
    fontSize: 24,
    fontWeight: FontWeight.w300,
    color: AppColors.textPrimary,
  );

  static final TextStyle monoLabel = GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // -- UI ELEMENTS --
  static const TextStyle button = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontFamily: geist,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const TextStyle label = TextStyle(
    fontFamily: geist,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: geist,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  // ═══════════════════════════════════════════════
  // Legacy READING FONT — Playfair Display (IdeaCards, Lessons, Long Text).
  // Unchanged until the v3 reader screens move to [read].
  // ═══════════════════════════════════════════════

  /// Primary reading style for IdeaCard content.
  /// Size 28, height 1.6 for maximum frictionless reading.
  static final TextStyle reading = GoogleFonts.playfairDisplay(
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.textPrimary,
  );

  /// Smaller reading variant for secondary content.
  static final TextStyle readingSmall = GoogleFonts.playfairDisplay(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.textPrimary,
  );

  /// Bold reading variant for emphasis within IdeaCards.
  static final TextStyle readingBold = GoogleFonts.playfairDisplay(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.6,
    color: AppColors.textPrimary,
  );

  /// Reading quote style — italic serif for pullquotes.
  static final TextStyle readingQuote = GoogleFonts.playfairDisplay(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    height: 1.6,
    color: AppColors.textTertiary,
  );

  /// Category tag on IdeaCards — small uppercase serif.
  static final TextStyle readingTag = GoogleFonts.playfairDisplay(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    height: 1.2,
    color: AppColors.brandAccent,
  );

  /// IdeaCard body text — Playfair at 17px for card-context reading.
  static final TextStyle ideaCardBody = GoogleFonts.playfairDisplay(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.65,
    color: AppColors.textPrimary,
  );

  // ═══════════════════════════════════════════════
  // Legacy CMPYS 2026 members
  // ═══════════════════════════════════════════════

  /// Small uppercase mono label above sections (letter-spacing 0.14em).
  /// The v3 equivalent is [kick] (Geist).
  static final TextStyle kicker = GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
    height: 1.2,
    color: AppColors.ink3,
  );

  /// Dimmed body copy (secondary ink); was Plus Jakarta Sans, now Geist.
  static const TextStyle bodyDim = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.ink2,
  );
}

/// Animation durations & curves
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);

  /// Deprecated in practice: page transitions actually use [normal] via
  /// `CmpysPageTransition.duration`, not this token. Kept for backwards
  /// compatibility with any existing call sites — don't "fix" the motion
  /// kit to consume this instead; that would change the shipped timing.
  static const Duration pageTransition = Duration(milliseconds: 400);

  /// Per-item delay for staggered list entrances (motion kit).
  static const Duration stagger = Duration(milliseconds: 50);
}

/// CMPYS v3 motion curves (`--out`, `--spring`, `--io` in `CMPYS v3.html`).
abstract final class AppMotion {
  /// Calm ease-out for entrances and most transitions.
  static const Cubic out = Cubic(0.16, 1, 0.3, 1);

  /// Springy overshoot. Use only where the design uses `--spring`.
  static const Cubic spring = Cubic(0.34, 1.42, 0.5, 1);

  /// Symmetric ease-in-out.
  static const Cubic io = Cubic(0.65, 0, 0.35, 1);
}

/// Earlier curve names; the values now come from [AppMotion].
abstract final class AppCurves {
  /// Premium ease-out for modals and cards
  static const Curve easeOut = AppMotion.out;

  /// Smooth editorial entrance
  static const Curve editorialIn = AppMotion.io;

  /// Springy overshoot for the active nav pill (v3 `--spring`).
  static const Curve spring = AppMotion.spring;
}

/// Common shadows — Ultra-soft editorial style.
abstract final class AppShadows {
  /// Subtle card shadow — barely visible, premium feel.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x121F1B16), blurRadius: 24, offset: Offset(0, 12)),
  ];

  /// Medium elevation — floating cards. Neutral ink shadow only (the old
  /// coral glow warmed every raised green card — removed).
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x181F1B16), blurRadius: 42, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x0F16161C), blurRadius: 14, offset: Offset(0, 4)),
  ];

  /// Large elevation — hero cards, modals.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x211F1B16), blurRadius: 70, offset: Offset(0, 30)),
    BoxShadow(color: Color(0x1416161C), blurRadius: 22, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> card = sm;
  static const List<BoxShadow> pop = md;

  /// Floating five-tab nav pill shadow (CMPYS 2026 dock).
  static const List<BoxShadow> tabPill = [
    BoxShadow(color: Color(0x1A16161C), blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0F16161C), blurRadius: 6, offset: Offset(0, 2)),
  ];

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

/// Reading surfaces for the lesson and book readers (`THEMES` in
/// `v3/tutorial.jsx`). `light` resolves to the v3 paper / ink tokens.
enum ReaderTheme {
  light(
    bg: AppColors.paper,
    fg: AppColors.ink,
    fg2: AppColors.ink2,
    card: AppColors.card,
    hair: AppColors.hair,
  ),
  sepia(
    bg: Color(0xFFF1E7D3),
    fg: Color(0xFF3B2F22),
    fg2: Color(0xFF6B5A45),
    card: Color(0xFFF8F0E0),
    hair: Color(0xFFE2D4BA),
  ),
  dark(
    bg: Color(0xFF141219),
    fg: Color(0xFFECE8F0),
    fg2: Color(0xFFA9A3B0),
    card: Color(0xFF1E1B25),
    hair: Color(0xFF2C2834),
  );

  const ReaderTheme({
    required this.bg,
    required this.fg,
    required this.fg2,
    required this.card,
    required this.hair,
  });

  /// Page background.
  final Color bg;

  /// Body text.
  final Color fg;

  /// Secondary text.
  final Color fg2;

  /// Raised surface (callouts, cards).
  final Color card;

  /// Hairline dividers and borders.
  final Color hair;

  /// Display name, as the design's picker shows it ("Light", "Sepia", "Dark").
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';

  /// Parses a stored name; unknown or missing names fall back to [light]
  /// (the design's `st.readTheme || 'light'`).
  static ReaderTheme fromName(String? value) {
    for (final theme in values) {
      if (theme.name == value) return theme;
    }
    return light;
  }
}
