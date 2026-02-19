import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for CMPYS app.
/// V3: "Executive Dark Mode" — Obsidian palette, Inter only.
abstract final class AppColors {
  // Deep Obsidian Backgrounds
  static const Color bgTrue = Color(0xFF000000);
  static const Color bg = Color(0xFF09090B);
  static const Color surface = Color(0xFF121214);
  static const Color surfaceHighlight = Color(0xFF1C1C1F); // Elevated
  static const Color surface2 = surfaceHighlight; // Compat alias
  static const Color surfaceGlass = Color(0xBF09090B); // 75% bg
  static const Color cardBorder = Color(0x14FFFFFF); // 8% White
  static const Color border = Color(0x14FFFFFF); // 8% White

  // Typography Colors
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF52525B);

  // Executive Accents
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDim = Color(0x2610B981); // 15% Emerald
  static const Color blue = Color(0xFF3B82F6);
  static const Color gold = Color(0xFFF59E0B);
  static const Color alert = Color(0xFFEF4444);

  // Semantic Aliases (for backward compatibility)
  static const Color primary = textPrimary; // White (main accent)
  static const Color secondary = emerald;
  static const Color tertiary = blue;
  static const Color accent = emerald;
  static const Color accentLight = Color(0xFF34D399); // Lighter Emerald
  static final Color accentMuted = emerald.withOpacity(0.15);

  static const Color error = alert;
  static const Color success = emerald;
  static const Color warning = gold;
  static const Color info = blue;

  // Border variants
  static const Color borderLight = Color(0x14FFFFFF); // 8% White
  static const Color borderFocus = Color(0x26FFFFFF); // 15% White

  // Lime alias removed – "lime" was V2. Keep alias pointing to primary for safety.
  static const Color lime = textPrimary;
  static const Color purple = emerald; // remap old purple references
  static const Color orange = gold; // remap old orange references
}

/// Border radii tokens
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
}

/// Typography tokens
/// V3: Inter only. Clean executive style.
abstract final class AppTypography {
  // -- HEADERS (Inter) --
  static TextStyle get h1 => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -1.0,
    color: AppColors.textPrimary,
  );

  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle get h4 => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  // -- BODY (Inter) --
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

  /// Executive caption — small, uppercase, spaced.
  static TextStyle get captionUpper => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.8,
    color: AppColors.textTertiary,
  );

  static TextStyle get tiny => captionUpper; // Alias

  // -- DATA / NUMBERS (Inter bold — replaced SpaceMono) --
  static TextStyle get monoNum => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w300, // Light weight for large numbers
    color: AppColors.textPrimary,
  );

  static TextStyle get monoLabel => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // -- UI ELEMENTS --
  static TextStyle get button => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.bgTrue, // Black text on white buttons
  );

  static TextStyle get buttonSmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.bgTrue,
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
}

/// Animation durations
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
}

/// Common shadows
abstract final class AppShadows {
  static List<BoxShadow> glowEmerald = [
    BoxShadow(
      color: AppColors.emerald.withOpacity(0.4),
      blurRadius: 12,
      offset: const Offset(0, 0),
    ),
  ];

  static List<BoxShadow> glowBlue = [
    BoxShadow(
      color: AppColors.blue.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  // Keep old names pointing to new values
  static List<BoxShadow> glowLime = glowEmerald;
  static List<BoxShadow> glowPurple = glowEmerald;

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black26,
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> pop = [
    BoxShadow(
      color: Colors.black38,
      blurRadius: 30,
      offset: Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get accent => glowEmerald;
}
