import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

/// App theme configuration.
/// CMPYS 2026: cool-paper canvas, vibrant-green accent, Plus Jakarta Sans body
/// (Bricolage Grotesque display + JetBrains Mono labels live in AppTypography).
abstract final class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.brandBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandAccent,
        onPrimary: Colors.white,
        secondary: AppColors.emerald,
        onSecondary: AppColors.charcoal,
        tertiary: AppColors.blue,
        onTertiary: AppColors.charcoal,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      textTheme: _textTheme,
      appBarTheme: _appBarTheme,
      cardTheme: _cardTheme,
      dividerTheme: _dividerTheme,
      inputDecorationTheme: _inputDecorationTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      textButtonTheme: _textButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      iconButtonTheme: _iconButtonTheme,
      bottomSheetTheme: _bottomSheetTheme,
      dialogTheme: _dialogTheme,
      datePickerTheme: _datePickerTheme,
      snackBarTheme: _snackBarTheme,
      progressIndicatorTheme: _progressIndicatorTheme,
      switchTheme: _switchTheme,
      checkboxTheme: _checkboxTheme,
      radioTheme: _radioTheme,
      tabBarTheme: _tabBarTheme,
      bottomNavigationBarTheme: _bottomNavTheme,
      navigationBarTheme: _navigationBarTheme,
      splashColor: AppColors.brandAccent.withValues(alpha: 0.08),
      highlightColor: AppColors.brandAccent.withValues(alpha: 0.04),
    );
  }

  // Keep `dark` as alias for backward compat (router/app references)
  static ThemeData get dark => light;

  // Text Theme
  static TextTheme get _textTheme => TextTheme(
    displayLarge: AppTypography.h1,
    displayMedium: AppTypography.h2,
    displaySmall: AppTypography.h3,
    headlineLarge: AppTypography.h1,
    headlineMedium: AppTypography.h2,
    headlineSmall: AppTypography.h3,
    titleLarge: AppTypography.h3,
    titleMedium: AppTypography.h4,
    titleSmall: AppTypography.label,
    bodyLarge: AppTypography.bodyLarge,
    bodyMedium: AppTypography.body,
    bodySmall: AppTypography.caption,
    labelLarge: AppTypography.button,
    labelMedium: AppTypography.label,
    labelSmall: AppTypography.labelSmall,
  );

  // AppBar Theme
  static AppBarTheme get _appBarTheme => AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    systemOverlayStyle: const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
    ),
    titleTextStyle: AppTypography.h3.copyWith(fontWeight: FontWeight.bold),
    toolbarHeight: 64,
    iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 24),
  );

  // Card Theme — translucent glass surface
  static CardThemeData get _cardTheme => const CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadii.br24,
      side: BorderSide(color: AppColors.cardBorder),
    ),
  );

  // Divider Theme
  static DividerThemeData get _dividerTheme => const DividerThemeData(
    color: AppColors.borderLight,
    thickness: 1,
    space: 1,
  );

  // Input Decoration Theme
  static InputDecorationTheme get _inputDecorationTheme {
    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s16,
      ),
      hintStyle: AppTypography.body.copyWith(color: AppColors.textSecondary),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textSecondary),
      errorStyle: AppTypography.caption.copyWith(color: AppColors.error),
      border: OutlineInputBorder(
        borderRadius: AppRadii.br16,
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadii.br16,
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadii.br16,
        borderSide: const BorderSide(color: AppColors.brandAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadii.br16,
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadii.br16,
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  // Elevated Button Theme — coral capsule
  static ElevatedButtonThemeData get _elevatedButtonTheme {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s32,
          vertical: AppSpacing.s16,
        ),
        minimumSize: const Size(64, 56),
        shape: const StadiumBorder(),
        textStyle: AppTypography.button.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Text Button Theme
  static TextButtonThemeData get _textButtonTheme {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandAccent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.br12),
        textStyle: AppTypography.buttonSmall,
      ),
    );
  }

  // Outlined Button Theme
  static OutlinedButtonThemeData get _outlinedButtonTheme {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.borderFocus),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s24,
          vertical: AppSpacing.s16,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.br16),
        textStyle: AppTypography.button.copyWith(color: AppColors.textPrimary),
      ),
    );
  }

  // Icon Button Theme
  static IconButtonThemeData get _iconButtonTheme {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        highlightColor: AppColors.brandAccent.withValues(alpha: 0.08),
        minimumSize: const Size(40, 40),
        shape: const CircleBorder(),
      ),
    );
  }

  // Bottom Sheet Theme
  static BottomSheetThemeData get _bottomSheetTheme =>
      const BottomSheetThemeData(
        backgroundColor: AppColors.brandBg,
        modalBackgroundColor: AppColors.brandBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.r24),
          ),
        ),
        dragHandleColor: AppColors.surfaceHighlight,
        dragHandleSize: Size(48, 5),
        showDragHandle: true,
      );

  // Dialog Theme
  static DialogThemeData get _dialogTheme {
    return DialogThemeData(
      backgroundColor: AppColors.brandBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.br24),
      titleTextStyle: AppTypography.h3,
      contentTextStyle: AppTypography.body.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }

  static DatePickerThemeData get _datePickerTheme {
    return DatePickerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.br32),
      headerBackgroundColor: AppColors.surfaceHighlight,
      headerForegroundColor: AppColors.textPrimary,
      dividerColor: AppColors.glassBorder,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textTertiary;
        }
        return AppColors.textPrimary;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.brandAccent;
        return Colors.transparent;
      }),
      todayForegroundColor: WidgetStateProperty.all(AppColors.peach),
      todayBorder: const BorderSide(color: AppColors.peach),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textTertiary;
        }
        return AppColors.textPrimary;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.brandAccent;
        return Colors.transparent;
      }),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.peach),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: AppColors.brandAccent,
      ),
    );
  }

  // SnackBar Theme
  static SnackBarThemeData get _snackBarTheme {
    return SnackBarThemeData(
      backgroundColor: AppColors.charcoalSurface,
      contentTextStyle: AppTypography.body.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.br16),
      insetPadding: AppSpacing.p20,
    );
  }

  // Progress Indicator Theme
  static ProgressIndicatorThemeData get _progressIndicatorTheme =>
      const ProgressIndicatorThemeData(
        color: AppColors.brandAccent,
        linearTrackColor: AppColors.surfaceHighlight,
        circularTrackColor: AppColors.surfaceHighlight,
      );

  // Switch Theme
  static SwitchThemeData get _switchTheme {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return AppColors.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.brandAccent;
        }
        return AppColors.surfaceHighlight;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    );
  }

  // Checkbox Theme
  static CheckboxThemeData get _checkboxTheme {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.brandAccent;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: AppColors.borderFocus, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );
  }

  // Radio Theme
  static RadioThemeData get _radioTheme {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.brandAccent;
        }
        return AppColors.textSecondary;
      }),
    );
  }

  // Tab Bar Theme
  static TabBarThemeData get _tabBarTheme {
    return TabBarThemeData(
      labelColor: AppColors.textPrimary,
      unselectedLabelColor: AppColors.textSecondary,
      labelStyle: AppTypography.buttonSmall,
      unselectedLabelStyle: AppTypography.buttonSmall,
      indicatorColor: AppColors.brandAccent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    );
  }

  // Bottom Navigation Bar Theme
  static BottomNavigationBarThemeData get _bottomNavTheme {
    return BottomNavigationBarThemeData(
      backgroundColor: AppColors.brandBg,
      selectedItemColor: AppColors.brandAccent,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: AppTypography.captionMedium.copyWith(fontSize: 10),
      unselectedLabelStyle: AppTypography.caption.copyWith(fontSize: 10),
    );
  }

  // Navigation Bar Theme — Glassmorphism bottom bar
  static NavigationBarThemeData get _navigationBarTheme {
    return NavigationBarThemeData(
      backgroundColor: AppColors.brandBg,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.brandAccent, size: 26);
        }
        return const IconThemeData(color: AppColors.textSecondary, size: 26);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.captionMedium.copyWith(
            color: AppColors.brandAccent,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          );
        }
        return AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontSize: 10,
        );
      }),
    );
  }
}
