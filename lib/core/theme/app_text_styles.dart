import 'package:flutter/material.dart';

/// TaskTap typography.
///
/// Display / titles → Archivo Narrow.
/// Body / labels → Archivo.
/// Fallback → Inter (FA, system).
///
/// **These carry no colour.** They used to bake `AppColors.DARK` (and `MUTED` for the two
/// secondary styles), which made every heading and caption in the app a fixed near-black — fine
/// under one theme, invisible under the other. Colour is applied once, in `buildAppTheme`, by
/// running the whole [TextTheme] through `apply(bodyColor:, displayColor:)` with the palette's
/// ink. A call site that needs something other than ink still says so with `copyWith`, exactly as
/// before.
abstract final class AppTextStyles {
  // ── Archivo Narrow — display / headings ──────────────────────────────────

  static TextStyle get displayLarge => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static TextStyle get displayMedium => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle get headlineLarge => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle get headlineMedium => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static TextStyle get titleLarge => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get titleMedium => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // ── Archivo — body / labels ───────────────────────────────────────────

  static TextStyle get bodyLarge => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get bodyMedium => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get bodySmall => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get labelLarge => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static TextStyle get labelMedium => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static TextStyle get labelSmall => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );

  // ── Convenience ────────────────────────────────────────────────────────

  /// KPI figure — large Archivo Narrow number for dashboards (500/36 ink per spec).
  static TextStyle get kpi => TextStyle(
    fontFamily: 'Archivo Narrow',
    fontSize: 36,
    fontWeight: FontWeight.w500,
    letterSpacing: -1,
  );

  static TextStyle get caption => TextStyle(
    fontFamily: 'Archivo',
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  // ── IBM Plex Mono — document codes, timestamps ────────────────────────────
  //
  // Il Documento's own rule (frontend DESIGN.md: "Mono marks identity. Document numbers, form
  // codes, timestamps and inline data run in IBM Plex Mono — the carbon-copy impression."). Scoped
  // to exactly that — a running clock's HH:MM:SS, a punch timestamp, a report/ticket reference
  // number — never body text or labels; see craft-floor's own ban on monospace as a costume.

  /// A live-running elapsed-time readout (timbratura/cantiere/worklog timers). Tabular figures so
  /// the digits don't visibly shift width as seconds tick.
  static TextStyle get timerMono => const TextStyle(
    fontFamily: 'IBM Plex Mono',
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w500,
  );

  /// A document/reference code (ticket number, report number, punch timestamp) inline in body
  /// copy — smaller and lighter than [timerMono], which is a standalone readout.
  static TextStyle get docCode => const TextStyle(
    fontFamily: 'IBM Plex Mono',
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w500,
  );
}

/// Returns a [TextTheme] fully populated with Archivo Narrow/Archivo styles.
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
