import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_vetro_palette.dart';

/// Legacy rapportino workflow states — kept for backward compat with StatusBadge.
enum ReportStato { bozza, inviato, controllato, fatturato, annullato }

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
/// Every pair now comes from [context]'s theme — [AppVetroPalette]'s tint (an "in flight, needs
/// eyes" state — Aperto/In attesa/Inviata), statusGood (Completato/Pagata/Attivo), statusWarn
/// (In corso/Controllato — actively being worked), statusBad (Annullato/Scaduta/Sospeso/Respinta),
/// or [AppPalette]'s neutrals (In pausa/Chiuso/Bozza — no state that needs colour). Previously a
/// flat table of ~13 hardcoded hex pairs that could not flip with the app's theme at all — this
/// file didn't even take a [BuildContext]. Unknown strings fall back to the neutral pairing.
StatusColorPair statusColor(BuildContext context, String stato) {
  final v = context.vetro;
  final neutral = StatusColorPair(background: context.colors.bg3, foreground: context.colors.inkMuted);
  final info = StatusColorPair(background: v.tint.withAlpha(31), foreground: v.tint);
  final good = StatusColorPair(background: v.statusGoodBg, foreground: v.statusGood);
  final warn = StatusColorPair(background: v.statusWarnBg, foreground: v.statusWarn);
  final bad = StatusColorPair(background: v.statusBadBg, foreground: v.statusBad);

  return switch (stato.trim().toLowerCase()) {
    'aperto' => info,
    'in corso' => warn,
    'in pausa' => neutral,
    'in attesa' => info,
    'completato' => good,
    'chiuso' => neutral,
    'annullato' => bad,
    'bozza' => neutral,
    'inviata' => info,
    'pagata' => good,
    'scaduta' => bad,
    'sospeso' => bad,
    'attivo' => good,
    'inattivo' => bad,
    // ── Report lifecycle, masculine ─────────────────────────────────────────
    //
    // A rapportino is masculine, so the backend sends 'Inviato' / 'Fatturato' where the invoice
    // states above are 'Inviata' / 'Pagata'. Without these three, every report state fell through
    // to the neutral default — which is exactly why `admin_report_list_screen` grew its own
    // colour table with a third set of blues and greens that matched neither this file nor the
    // StatusPill beside it. Aliases, not new colours: each returns the pair its feminine or enum
    // counterpart already uses.
    'inviato' => info,
    'fatturato' => good,
    // Rejected rapportino (Inviato → Respinto, office sends it back for rework). Same treatment as
    // Annullato/Scaduta — both read as "this needs attention", which a rejection does too.
    'respinta' => bad,
    'respinto' => bad,
    // Same family as In corso — both are "actively being worked", just at a different lifecycle
    // stage.
    'controllato' => warn,
    _ => neutral,
  };
}

/// Returns [StatusColorPair] for a legacy [ReportStato] enum value.
///
/// Delegates to the string-based [statusColor] for a single source of truth.
StatusColorPair statusColorFromStato(BuildContext context, ReportStato stato) {
  return switch (stato) {
    ReportStato.bozza => statusColor(context, 'Bozza'),
    ReportStato.inviato => statusColor(context, 'Inviata'),
    ReportStato.controllato => statusColor(context, 'Controllato'),
    ReportStato.fatturato => statusColor(context, 'Pagata'),
    ReportStato.annullato => statusColor(context, 'Annullato'),
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
