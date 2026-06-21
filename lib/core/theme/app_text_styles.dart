import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// TaskTap typography.
///
/// Display / titles → Sora (FD).
/// Body / labels → Manrope (FB).
/// Fallback → Inter (FA, system).
abstract final class AppTextStyles {
  // ── Sora — display / headings ──────────────────────────────────────────

  static TextStyle get displayLarge => GoogleFonts.sora(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.DARK,
      );

  static TextStyle get displayMedium => GoogleFonts.sora(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.DARK,
      );

  static TextStyle get headlineLarge => GoogleFonts.sora(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.DARK,
      );

  static TextStyle get headlineMedium => GoogleFonts.sora(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: AppColors.DARK,
      );

  static TextStyle get titleLarge => GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.DARK,
      );

  static TextStyle get titleMedium => GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.DARK,
      );

  // ── Manrope — body / labels ────────────────────────────────────────────

  static TextStyle get bodyLarge => GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.DARK,
      );

  static TextStyle get bodyMedium => GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.DARK,
      );

  static TextStyle get bodySmall => GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.FG2,
      );

  static TextStyle get labelLarge => GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: AppColors.DARK,
      );

  static TextStyle get labelMedium => GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: AppColors.FG2,
      );

  static TextStyle get labelSmall => GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        color: AppColors.MUTED,
      );

  // ── Convenience ────────────────────────────────────────────────────────

  /// KPI figure — large Sora number for dashboards (Manrope 500/36 DARK per spec).
  static TextStyle get kpi => GoogleFonts.manrope(
        fontSize: 36,
        fontWeight: FontWeight.w500,
        letterSpacing: -1,
        color: AppColors.DARK,
      );

  static TextStyle get caption => GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.MUTED,
      );
}

/// Returns a [TextTheme] fully populated with Sora/Manrope styles.
TextTheme buildTextTheme() {
  return TextTheme(
    displayLarge: AppTextStyles.displayLarge,
    displayMedium: AppTextStyles.displayMedium,
    displaySmall: AppTextStyles.headlineLarge,
    headlineLarge: AppTextStyles.headlineLarge,
    headlineMedium: AppTextStyles.headlineMedium,
    headlineSmall: AppTextStyles.titleLarge,
    titleLarge: AppTextStyles.titleLarge,
    titleMedium: AppTextStyles.titleMedium,
    titleSmall: AppTextStyles.bodyMedium,
    bodyLarge: AppTextStyles.bodyLarge,
    bodyMedium: AppTextStyles.bodyMedium,
    bodySmall: AppTextStyles.bodySmall,
    labelLarge: AppTextStyles.labelLarge,
    labelMedium: AppTextStyles.labelMedium,
    labelSmall: AppTextStyles.labelSmall,
  );
}
