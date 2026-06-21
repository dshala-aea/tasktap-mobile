import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Rapportino workflow states — exactly matching backend `StatoRapportino` enum.
enum ReportStato {
  bozza,
  inviato,
  controllato,
  fatturato,
  annullato,
}

/// Color descriptor for a [ReportStato] — background + foreground pair.
class StatusColorPair {
  const StatusColorPair({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

/// Returns the brand-defined [StatusColorPair] for a given [ReportStato].
///
/// Usage:
/// ```dart
/// final pair = statusColor(ReportStato.fatturato);
/// Container(color: pair.background, child: Text('Fatturato', style: TextStyle(color: pair.foreground)));
/// ```
StatusColorPair statusColor(ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => const StatusColorPair(
        background: AppColors.statusBozza,
        foreground: AppColors.onStatusBozza,
      ),
    ReportStato.inviato => const StatusColorPair(
        background: AppColors.statusInviato,
        foreground: AppColors.onStatusInviato,
      ),
    ReportStato.controllato => const StatusColorPair(
        background: AppColors.statusControllato,
        foreground: AppColors.onStatusControllato,
      ),
    ReportStato.fatturato => const StatusColorPair(
        background: AppColors.statusFatturato,
        foreground: AppColors.onStatusFatturato,
      ),
    ReportStato.annullato => const StatusColorPair(
        background: AppColors.statusAnnullato,
        foreground: AppColors.onStatusAnnullato,
      ),
  };
}

/// Convenience: Italian label for each [ReportStato].
String statoLabel(ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => 'Bozza',
    ReportStato.inviato => 'Inviato',
    ReportStato.controllato => 'Controllato',
    ReportStato.fatturato => 'Fatturato',
    ReportStato.annullato => 'Annullato',
  };
}
