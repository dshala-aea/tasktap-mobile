import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_rack.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Builds the TaskTap [ThemeData] for one [Brightness].
///
/// Brand yellow Y `#FFF10E` is primary in both themes — it is the brand, and it reads on either
/// ground. Everything else comes from [AppPalette], which is also attached as a theme extension so
/// widgets can reach tokens the Material [ColorScheme] has no slot for (four background steps,
/// three border weights, the card shadow).
///
/// Typography: Sora (display / titles) + Manrope (body / labels). The text styles carry no colour
/// of their own; it is applied here, once, from the palette's ink.
ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final p = isDark ? AppPalette.dark : AppPalette.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: AppColors.Y,
    onPrimary: p.brandOn,
    primaryContainer: AppColors.YSoft,
    onPrimaryContainer: p.ink,
    secondary: p.ink,
    onSecondary: p.inkInverse,
    secondaryContainer: p.borderMedium,
    onSecondaryContainer: p.ink,
    tertiary: p.blue,
    onTertiary: p.inkInverse,
    tertiaryContainer: Color(0x14000000), // placeholder — no spec value
    onTertiaryContainer: p.blue,
    error: p.red,
    onError: Colors.white,
    errorContainer: p.redSoft,
    onErrorContainer: p.red,
    surface: p.surface,
    onSurface: p.ink,
    surfaceContainerHighest: p.bg1,
    onSurfaceVariant: p.inkFaint,
    outline: p.borderMedium,
    outlineVariant: p.borderLight,
    shadow: p.shadow.first.color,
    scrim: Color(0x80000000),
    inverseSurface: p.surfaceInverse,
    onInverseSurface: p.inkInverse,
    inversePrimary: AppColors.Y,
  );

  // The styles carry no colour of their own (see AppTextStyles), so it is applied here in one
  // place. `bodyColor` covers body/label/title, `displayColor` the display and headline sizes.
  final textTheme = buildTextTheme().apply(bodyColor: p.ink, displayColor: p.ink);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    // Everything the ColorScheme has no slot for: the four background steps, the three border
    // weights, the card shadow, and the ink/surface pair that must not be confused for each other.
    extensions: <ThemeExtension<dynamic>>[p],
    scaffoldBackgroundColor: p.bg1,

    // ── AppBar ─────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: p.shadow.first.color,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppTextStyles.titleLarge.copyWith(color: p.ink),
      // Status-bar icons are the inverse of the bar behind them.
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),

    // ── Bottom Navigation Bar ──────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: AppColors.Y,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTextStyles.labelMedium.copyWith(
            // On the yellow indicator, so brandOn — not ink, which inverts with the theme while
            // the yellow beneath it does not.
            color: p.brandOn,
            fontWeight: FontWeight.w700,
          );
        }
        return AppTextStyles.labelMedium.copyWith(color: p.inkMuted);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: p.brandOn, size: 22);
        }
        return IconThemeData(color: p.inkDisabled, size: 22);
      }),
      height: AppSpacing.bottomNavHeight,
      elevation: 4,
      shadowColor: p.shadow.first.color,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),

    // ── Card ───────────────────────────────────────────────────────────────
    //
    // Material's own Card, for the places Flutter reaches for one on our behalf (dialogs, menus,
    // banners). Given the rack's material and corner language so a framework-supplied surface
    // does not arrive wearing the previous design system.
    cardTheme: CardThemeData(
      color: p.labelCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRack.freeShape,
        side: BorderSide(color: p.borderLight),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Elevated Button ────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.Y,
        foregroundColor: p.ink,
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
        foregroundColor: p.ink,
        side: BorderSide(color: p.borderMedium),
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
        foregroundColor: p.ink,
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
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: BorderSide(color: p.borderMedium),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: BorderSide(color: p.borderMedium),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.Y, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: BorderSide(color: p.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: BorderSide(color: p.red, width: 2),
      ),
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: p.inkFaint,
      ),
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: p.inkDisabled,
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(color: p.red),
      floatingLabelStyle: AppTextStyles.labelMedium.copyWith(
        color: p.ink,
      ),
    ),

    // ── Divider ────────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: p.divider,
      space: 1,
      thickness: 1,
    ),

    // ── Chip ───────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: p.bg3,
      selectedColor: AppColors.Y,
      labelStyle: AppTextStyles.labelMedium.copyWith(color: p.ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        side: BorderSide(color: p.borderMedium),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
    ),

    // ── FAB ────────────────────────────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.Y,
      foregroundColor: p.ink,
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
