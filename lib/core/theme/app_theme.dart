import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Builds the TaskTap [ThemeData].
///
/// Brand yellow Y `#FFF10E` as primary, DARK `#363636` as foreground.
/// Typography: Sora (display / titles) + Manrope (body / labels).
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.Y,
    onPrimary: AppColors.DARK,
    primaryContainer: AppColors.YSoft,
    onPrimaryContainer: AppColors.DARK,
    secondary: AppColors.DARK,
    onSecondary: AppColors.WHITE,
    secondaryContainer: AppColors.BM,
    onSecondaryContainer: AppColors.DARK,
    tertiary: AppColors.BLUE,
    onTertiary: AppColors.WHITE,
    tertiaryContainer: Color(0x14000000), // placeholder — no spec value
    onTertiaryContainer: AppColors.BLUE,
    error: AppColors.error,
    onError: AppColors.WHITE,
    errorContainer: AppColors.REDSOFT,
    onErrorContainer: AppColors.error,
    surface: AppColors.WHITE,
    onSurface: AppColors.DARK,
    surfaceContainerHighest: AppColors.BG1,
    onSurfaceVariant: AppColors.FG2,
    outline: AppColors.BM,
    outlineVariant: AppColors.BL,
    shadow: Color(0x1A000000),
    scrim: Color(0x80000000),
    inverseSurface: AppColors.DARK,
    onInverseSurface: AppColors.WHITE,
    inversePrimary: AppColors.Y,
  );

  final textTheme = buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.BG1,

    // ── AppBar ─────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.WHITE,
      foregroundColor: AppColors.DARK,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x0F000000),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppTextStyles.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),

    // ── Bottom Navigation Bar ──────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.WHITE,
      indicatorColor: AppColors.Y,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTextStyles.labelMedium.copyWith(
            color: AppColors.DARK,
            fontWeight: FontWeight.w700,
          );
        }
        return AppTextStyles.labelMedium;
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.DARK, size: 22);
        }
        return const IconThemeData(color: AppColors.DIS, size: 22);
      }),
      height: AppSpacing.bottomNavHeight,
      elevation: 4,
      shadowColor: const Color(0x1A000000),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),

    // ── Card ───────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.BG1,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: const BorderSide(color: AppColors.BL),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Elevated Button ────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.Y,
        foregroundColor: AppColors.DARK,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: AppTextStyles.labelLarge,
        minimumSize: const Size(double.infinity, 48),
      ),
    ),

    // ── Outlined Button ────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.DARK,
        side: const BorderSide(color: AppColors.BM),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: AppTextStyles.labelLarge,
        minimumSize: const Size(double.infinity, 48),
      ),
    ),

    // ── Text Button ────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.DARK,
        textStyle: AppTextStyles.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
      ),
    ),

    // ── Input Decoration ───────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.WHITE,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.BM),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.BM),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.Y, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.FG2,
      ),
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.DIS,
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
      floatingLabelStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.DARK,
      ),
    ),

    // ── Divider ────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.DIV,
      space: 1,
      thickness: 1,
    ),

    // ── Chip ───────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.BG3,
      selectedColor: AppColors.Y,
      labelStyle: AppTextStyles.labelMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        side: const BorderSide(color: AppColors.BM),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
    ),

    // ── FAB ────────────────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.Y,
      foregroundColor: AppColors.DARK,
      elevation: 2,
    ),

    // ── List Tile ──────────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
    ),
  );
}
