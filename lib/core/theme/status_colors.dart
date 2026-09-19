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

/// The five status families this app actually distinguishes, independent of the ~15 raw Italian
/// strings that map onto them. [StatusStamp] (`status_stamp.dart`) reads this — not the raw string
/// — to pick its ring/fill/texture treatment per Il Documento's States section (frontend
/// `DESIGN.md`): [good] renders as Approvato, [bad] as Non valido, [warn] as In lavorazione,
/// [info] as Verificato, [neutral] as a ghost Draft stamp.
enum StatusFamily { neutral, info, good, warn, bad }

/// Returns the [StatusFamily] for one of the ~15 Italian UI status strings this app renders.
///
/// The single source of truth both [statusColor] (legacy pill colours) and [StatusStamp] (the
/// Il Documento stamp device) build on — see each call site's own switch arm for which raw string
/// maps to which family, and why.
StatusFamily statusFamilyOf(String stato) {
  return switch (stato.trim().toLowerCase()) {
    'aperto' => StatusFamily.info,
    // A commessa (job order) is feminine — 'Aperta', same concept as a ticket's 'Aperto'.
    'aperta' => StatusFamily.info,
    'in corso' => StatusFamily.warn,
    'in pausa' => StatusFamily.neutral,
    'in attesa' => StatusFamily.info,
    'completato' => StatusFamily.good,
    'chiuso' => StatusFamily.neutral,
    'annullato' => StatusFamily.bad,
    'bozza' => StatusFamily.neutral,
    'inviata' => StatusFamily.info,
    'pagata' => StatusFamily.good,
    'scaduta' => StatusFamily.bad,
    'sospeso' => StatusFamily.bad,
    'attivo' => StatusFamily.good,
    'inattivo' => StatusFamily.bad,
    // ── Report lifecycle, masculine ─────────────────────────────────────────
    //
    // A rapportino is masculine, so the backend sends 'Inviato' / 'Fatturato' where the invoice
    // states above are 'Inviata' / 'Pagata'. Without these three, every report state fell through
    // to the neutral default — which is exactly why `admin_report_list_screen` grew its own
    // colour table with a third set of blues and greens that matched neither this file nor the
    // StatusPill beside it. Aliases, not new colours: each returns the family its feminine or enum
    // counterpart already uses.
    'inviato' => StatusFamily.info,
    'fatturato' => StatusFamily.good,
    // Rejected rapportino (Inviato → Respinto, office sends it back for rework). Same treatment as
    // Annullato/Scaduta — both read as "this needs attention", which a rejection does too.
    'respinta' => StatusFamily.bad,
    'respinto' => StatusFamily.bad,
    // Same family as In corso — both are "actively being worked", just at a different lifecycle
    // stage.
    'controllato' => StatusFamily.warn,
    // ── Ferie/permessi (absence request) lifecycle ──────────────────────────
    //
    // 'In attesa' already matches above. Approvata/Rifiutata/Annullata read exactly like the
    // report/ticket lifecycle's own approved/rejected/cancelled states — same families, not new
    // colours.
    'approvata' => StatusFamily.good,
    'rifiutata' => StatusFamily.bad,
    'annullata' => StatusFamily.bad,
    _ => StatusFamily.neutral,
  };
}

/// Returns [StatusColorPair] for the 13 Italian UI status strings per DESIGN-SPEC.
///
/// Covers: Aperto, In corso, In pausa, In attesa, Completato, Chiuso,
/// Annullato, Bozza, Inviata, Pagata, Scaduta, Sospeso, Attivo.
///
/// Every pair comes from [context]'s theme via [statusFamilyOf] — [AppVetroPalette]'s tint (an
/// "in flight, needs eyes" state), statusGood, statusWarn, statusBad, or [AppPalette]'s neutrals.
/// Kept for callers that still need a flat colour pair ([StatusBadge]'s text-only sizes); status
/// *display* itself now goes through [StatusStamp], not this pair directly — see
/// `status_pill.dart`/`status_badge.dart`.
StatusColorPair statusColor(BuildContext context, String stato) {
  final v = context.vetro;
  final neutral = StatusColorPair(
    background: context.colors.bg3,
    foreground: context.colors.inkMuted,
  );
  final info = StatusColorPair(
    background: v.tint.withAlpha(31),
    foreground: v.tint,
  );
  final good = StatusColorPair(
    background: v.statusGoodBg,
    foreground: v.statusGood,
  );
  final warn = StatusColorPair(
    background: v.statusWarnBg,
    foreground: v.statusWarn,
  );
  final bad = StatusColorPair(
    background: v.statusBadBg,
    foreground: v.statusBad,
  );

  return switch (statusFamilyOf(stato)) {
    StatusFamily.neutral => neutral,
    StatusFamily.info => info,
    StatusFamily.good => good,
    StatusFamily.warn => warn,
    StatusFamily.bad => bad,
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
