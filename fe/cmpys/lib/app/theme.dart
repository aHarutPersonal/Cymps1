import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// App theme configuration.
/// V3: "Executive Dark Mode" Design.
abstract final class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.textPrimary, // White accent
        onPrimary: Colors.black,
        secondary: AppColors.emerald,
        onSecondary: Colors.black,
        tertiary: AppColors.blue,
        onTertiary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      fontFamily: 'Inter',
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
      snackBarTheme: _snackBarTheme,
      progressIndicatorTheme: _progressIndicatorTheme,
      switchTheme: _switchTheme,
      checkboxTheme: _checkboxTheme,
      radioTheme: _radioTheme,
      tabBarTheme: _tabBarTheme,
      bottomNavigationBarTheme: _bottomNavTheme,
      navigationBarTheme: _navigationBarTheme,
      splashColor: AppColors.textPrimary.withOpacity(0.08),
      highlightColor: AppColors.textPrimary.withOpacity(0.04),
    );
  }

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
    backgroundColor: AppColors.bg,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    systemOverlayStyle: const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ),
    titleTextStyle: AppTypography.h1,
    toolbarHeight: 64,
    iconTheme: const IconThemeData(
      color: AppColors.textPrimary,
      size: 24,
    ),
  );

  // Card Theme (Subtle border, compact radius)
  static CardThemeData get _cardTheme => const CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadii.br16,
      side: BorderSide(color: AppColors.borderLight),
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
      hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiary),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textSecondary),
      errorStyle: AppTypography.caption.copyWith(color: AppColors.error),
      border: OutlineInputBorder(
        borderRadius: AppRadii.br12,
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadii.br12,
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadii.br12,
        borderSide: const BorderSide(color: AppColors.textPrimary, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadii.br12,
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadii.br12,
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  // Elevated Button Theme (White pill)
  static ElevatedButtonThemeData get _elevatedButtonTheme {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.bgTrue,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s24,
          vertical: AppSpacing.s16,
        ),
        minimumSize: const Size(64, 52),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.br12,
        ),
        textStyle: AppTypography.button,
      ),
    );
  }

  // Text Button Theme
  static TextButtonThemeData get _textButtonTheme {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.br12,
        ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.br12,
        ),
        textStyle: AppTypography.button.copyWith(color: AppColors.textPrimary),
      ),
    );
  }

  // Icon Button Theme
  static IconButtonThemeData get _iconButtonTheme {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        highlightColor: AppColors.textPrimary.withOpacity(0.08),
        minimumSize: const Size(40, 40),
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.borderLight),
        ),
      ),
    );
  }

  // Bottom Sheet Theme
  static BottomSheetThemeData get _bottomSheetTheme => const BottomSheetThemeData(
    backgroundColor: AppColors.surface,
    modalBackgroundColor: AppColors.surface,
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
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.br16,
      ),
      titleTextStyle: AppTypography.h3,
      contentTextStyle: AppTypography.body.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }

  // SnackBar Theme
  static SnackBarThemeData get _snackBarTheme {
    return SnackBarThemeData(
      backgroundColor: AppColors.surfaceHighlight,
      contentTextStyle: AppTypography.body,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.br12,
      ),
      insetPadding: AppSpacing.p20,
    );
  }

  // Progress Indicator Theme
  static ProgressIndicatorThemeData get _progressIndicatorTheme =>
      const ProgressIndicatorThemeData(
    color: AppColors.textPrimary,
    linearTrackColor: AppColors.surfaceHighlight,
    circularTrackColor: AppColors.surfaceHighlight,
  );

  // Switch Theme
  static SwitchThemeData get _switchTheme {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.bgTrue;
        }
        return AppColors.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.emerald;
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
          return AppColors.textPrimary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(AppColors.bgTrue),
      side: const BorderSide(color: AppColors.borderFocus, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // Radio Theme
  static RadioThemeData get _radioTheme {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.textPrimary;
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
      indicatorColor: AppColors.textPrimary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    );
  }

  // Bottom Navigation Bar Theme (Legacy)
  static BottomNavigationBarThemeData get _bottomNavTheme {
    return BottomNavigationBarThemeData(
      backgroundColor: AppColors.surfaceGlass,
      selectedItemColor: AppColors.textPrimary,
      unselectedItemColor: AppColors.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: AppTypography.captionMedium.copyWith(fontSize: 10),
      unselectedLabelStyle: AppTypography.caption.copyWith(fontSize: 10),
    );
  }

  // Navigation Bar Theme (Material 3)
  static NavigationBarThemeData get _navigationBarTheme {
    return NavigationBarThemeData(
      backgroundColor: AppColors.surfaceGlass,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 90,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.textPrimary, size: 24);
        }
        return const IconThemeData(color: AppColors.textTertiary, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.captionMedium.copyWith(
            color: AppColors.textPrimary,
            fontSize: 10,
          );
        }
        return AppTypography.caption.copyWith(
          color: AppColors.textTertiary,
          fontSize: 10,
        );
      }),
    );
  }
}
