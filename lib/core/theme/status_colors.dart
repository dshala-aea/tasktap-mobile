import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Legacy rapportino workflow states — kept for backward compat with StatusBadge.
enum ReportStato {
  bozza,
  inviato,
  controllato,
  fatturato,
  annullato,
}

/// Color descriptor for a status — background + foreground pair.
class StatusColorPair {
  const StatusColorPair({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

/// Returns [StatusColorPair] for the 13 Italian UI status strings per DESIGN-SPEC.
///
/// Covers: Aperto, In corso, In pausa, In attesa, Completato, Chiuso,
/// Annullato, Bozza, Inviata, Pagata, Scaduta, Sospeso, Attivo.
///
/// Unknown strings fall back to [ReportStato.bozza] styling.
StatusColorPair statusColor(String stato) {
  return switch (stato.trim().toLowerCase()) {
    'aperto' => const StatusColorPair(
        background: Color(0xFFDCE8FF),
        foreground: Color(0xFF1D4ED8),
      ),
    'in corso' => const StatusColorPair(
        background: AppColors.AMBER,
        foreground: Color(0xFF000000),
      ),
    'in pausa' => const StatusColorPair(
        background: Color(0xFFE8E8E8),
        foreground: Color(0xFF555555),
      ),
    'in attesa' => const StatusColorPair(
        background: Color(0xFFDCF0FF),
        foreground: AppColors.CYAN,
      ),
    'completato' => const StatusColorPair(
        background: Color(0xFFDAF2E0),
        foreground: Color(0xFF1E7A3A),
      ),
    'chiuso' => const StatusColorPair(
        background: Color(0xFFE8E8E8),
        foreground: AppColors.DARK,
      ),
    'annullato' => const StatusColorPair(
        background: Color(0xFFFFDCDC),
        foreground: Color(0xFFAA0000),
      ),
    'bozza' => const StatusColorPair(
        background: Color(0xFFF5F5F5),
        foreground: Color(0xFF666666),
      ),
    'inviata' => const StatusColorPair(
        background: Color(0xFFDCE8FF),
        foreground: Color(0xFF1D4ED8),
      ),
    'pagata' => const StatusColorPair(
        background: Color(0xFFDAF2E0),
        foreground: Color(0xFF1E7A3A),
      ),
    'scaduta' => const StatusColorPair(
        background: Color(0xFFFFDCDC),
        foreground: Color(0xFFAA0000),
      ),
    'sospeso' => const StatusColorPair(
        background: Color(0xFFFFDCDC),
        foreground: Color(0xFFAA0000),
      ),
    'attivo' => const StatusColorPair(
        background: Color(0xFFDAF2E0),
        foreground: Color(0xFF1E7A3A),
      ),
    _ => const StatusColorPair(
        background: Color(0xFFF5F5F5),
        foreground: Color(0xFF666666),
      ),
  };
}

/// Returns [StatusColorPair] for a legacy [ReportStato] enum value.
///
/// Delegates to the string-based [statusColor] for a single source of truth.
StatusColorPair statusColorFromStato(ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => statusColor('Bozza'),
    ReportStato.inviato => statusColor('Inviata'),
    ReportStato.controllato => StatusColorPair(
        background: AppColors.statusControllato,
        foreground: AppColors.onStatusControllato,
      ),
    ReportStato.fatturato => statusColor('Pagata'),
    ReportStato.annullato => statusColor('Annullato'),
  };
}

/// Convenience: Italian label for each [ReportStato].
String statoLabel(ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => 'Bozza',
    ReportStato.inviato => 'Inviata',
    ReportStato.controllato => 'Controllato',
    ReportStato.fatturato => 'Pagata',
    ReportStato.annullato => 'Annullato',
  };
}
