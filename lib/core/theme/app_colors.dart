import 'package:flutter/material.dart';

/// TaskTap brand color palette.
abstract final class AppColors {
  /// Brand yellow — primary action color. Always pair with [onBrand].
  static const Color brand = Color(0xFFFFF10E);

  /// Foreground on brand yellow — near-black for high contrast.
  static const Color onBrand = Color(0xFF111111);

  /// Surface — white.
  static const Color surface = Color(0xFFFFFFFF);

  /// Background — very light grey, not pure white.
  static const Color background = Color(0xFFF5F5F7);

  /// Surface variant — card / elevated surface.
  static const Color surfaceVariant = Color(0xFFFFFFFF);

  /// Border / divider.
  static const Color outline = Color(0xFFE0E0E0);

  /// Primary text.
  static const Color textPrimary = Color(0xFF111111);

  /// Secondary text.
  static const Color textSecondary = Color(0xFF6B7280);

  /// Disabled text / icon.
  static const Color textDisabled = Color(0xFFBDBDBD);

  // ── Status colours ──────────────────────────────────────────────────────

  static const Color statusBozza = Color(0xFF9E9E9E); // grey
  static const Color onStatusBozza = Color(0xFFFFFFFF);

  static const Color statusInviato = Color(0xFF2196F3); // blue
  static const Color onStatusInviato = Color(0xFFFFFFFF);

  static const Color statusControllato = Color(0xFFFFA726); // amber
  static const Color onStatusControllato = Color(0xFF111111);

  static const Color statusFatturato = Color(0xFF4CAF50); // green
  static const Color onStatusFatturato = Color(0xFFFFFFFF);

  static const Color statusAnnullato = Color(0xFFF44336); // red
  static const Color onStatusAnnullato = Color(0xFFFFFFFF);

  // ── Semantic ────────────────────────────────────────────────────────────

  static const Color error = Color(0xFFD32F2F);
  static const Color onError = Color(0xFFFFFFFF);

  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57C00);
  static const Color info = Color(0xFF1976D2);
}
