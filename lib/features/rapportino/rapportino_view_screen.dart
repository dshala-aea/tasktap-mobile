// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/detail/detail_hero.dart';
import '../../core/widgets/detail/detail_scaffold.dart';
import '../../core/widgets/detail/detail_section.dart';
import '../../core/widgets/geo_map_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/dio_client.dart';
import '../../data/attachments/attachment_content_cache.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/report_pdf_cache.dart';
import '../../data/reports/ticket_controls_cache_repository.dart' show cachedTicketControlsProvider;
import '../../data/sync/connectivity_provider.dart' show isOnlineProvider;
import '../../domain/reports/customer_signature_absence_reason.dart';
import '../ticket/ticket_detail_api_client.dart'
    show ControlType, FlatTicketControl, flattenTicketControls;
import 'create_draft.dart';
import 'rapportino_list_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RapportinoViewScreen — read-only view for submitted rapportini (D3b).
// ══════════════════════════════════════════════════════════════════════════════

/// Per-report in-flight flags for the hero's PDF actions.
///
/// The hero calls the PDF helpers directly (it has no local widget state to hold a spinner), so
/// these keep a second tap from starting a concurrent download (both writes target the same
/// `.part` file) or a second share sheet. Keyed by report id so two open reports never block each
/// other.
final _rapportinoPdfBusyProvider = StateProvider.autoDispose.family<bool, String>(
  (ref, reportId) => false,
);
final _rapportinoShareBusyProvider = StateProvider.autoDispose.family<bool, String>(
  (ref, reportId) => false,
);

class RapportinoViewScreen extends ConsumerWidget {
  const RapportinoViewScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(rapportinoByIdProvider(reportId));

    return draftAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Rapportino'),
      // No online/offline distinction to draw here (unlike the ticket detail tabs): this reads
      // the local Drift mirror only (rapportinoByIdProvider), never the network, so an error
      // here is a local read failure, not connectivity — and a retry re-opens that same stream.
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Rapportino',
        icon: LucideIcons.xCircle,
        title: 'Impossibile caricare il rapporto di intervento',
        reason: 'Si è verificato un errore imprevisto. Riprova.',
        onRetry: () => ref.invalidate(rapportinoByIdProvider(reportId)),
      ),
      data: (draft) {
        if (draft == null) {
          return const DetailScaffold.unavailable(
            screenTitle: 'Rapportino',
            icon: LucideIcons.fileX,
            title: 'Rapporto di intervento non trovato',
            reason: 'Il rapporto di intervento richiesto non è disponibile in cache.',
          );
        }
        return _RapportinoViewBody(draft: draft);
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Body
// ══════════════════════════════════════════════════════════════════════════════

class _RapportinoViewBody extends ConsumerWidget {
  const _RapportinoViewBody({required this.draft});

  final DraftReport draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(rapportinoStaffProvider(draft.id));
    final materialiAsync = ref.watch(rapportinoMaterialiProvider(draft.id));
    final oreLabel = ref.watch(rapportinoOreProvider(draft.id));
    final allegatiAsync = ref.watch(rapportinoAllegatiProvider(draft.id));
    final controlliAsync = ref.watch(rapportinoControlliProvider(draft.id));
    // For openAttachment below (photo grid + signature) — see its own doc comment for why an
    // authenticated client is the right one, not a bare Dio.
    final dio = ref.watch(dioProvider);

    // Resolves each recorded Controlli answer's label/group/type against the ticket's checklist
    // (same source StepControlli compiled it from). Deliberately tolerant: a report not linked to
    // a ticket, or a checklist that hasn't been cached on this device yet, still shows the
    // recorded answers below — just without a resolved label — rather than hiding the section or
    // blocking it on a network round trip the read-only view has no reason to require.
    final ticketId = draft.ticketId;
    final ticketControlsAsync = (ticketId != null && ticketId.isNotEmpty)
        ? ref.watch(cachedTicketControlsProvider(ticketId))
        : null;
    final controlLabels = <String, FlatTicketControl>{
      for (final f in flattenTicketControls(ticketControlsAsync?.valueOrNull ?? const []))
        f.control.id: f,
    };

    final statusLabel = rapportinoStatusLabel(draft);
    final dateLabel = DateFormat(
      'dd/MM/yyyy',
      'it',
    ).format((draft.updatedAt ?? draft.createdAt).toLocal());

    final staff = staffAsync.valueOrNull ?? [];
    final materiali = materialiAsync.valueOrNull ?? [];
    final controlli = controlliAsync.valueOrNull ?? [];

    // rapportinoAllegatiProvider mixes photo and signature rows (both are just "allegati" for
    // the report) — split them here so the photo grid never shows a signature as if it were a
    // job photo, and _SignatureBlock gets the real row instead of resolving it itself.
    final allegati = allegatiAsync.valueOrNull ?? [];
    final signatureIds = {draft.customerSignatureAllegatoId, draft.technicianSignatureAllegatoId}
      ..removeWhere((id) => id == null);
    final photoAllegati = allegati.where((a) => !signatureIds.contains(a.id)).toList();
    final customerSignatureAllegato = draft.customerSignatureAllegatoId == null
        ? null
        : allegati.where((a) => a.id == draft.customerSignatureAllegatoId).firstOrNull;
    final technicianSignatureAllegato = draft.technicianSignatureAllegatoId == null
        ? null
        : allegati.where((a) => a.id == draft.technicianSignatureAllegatoId).firstOrNull;
    final customerAbsenceReason = CustomerSignatureAbsenceReason.fromWire(
      draft.customerSignatureAbsenceReason,
    );

    // Sede map — only when this draft carries a real Location id: a report saved against a
    // free-text-only site (`locationFreeText` in metadataJson, no `Locations` row) has nothing to
    // geocode or cache a point against, same as `_locationLabel`'s own fallback chain above.
    final locationId = draft.locationId;
    final locationAsync = locationId.isEmpty ? null : ref.watch(locationByIdProvider(locationId));
    final location = locationAsync?.valueOrNull;
    final locationAddress = [
      location?.address,
      location?.city,
      location?.postalCode,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return DetailScaffold(
      screenTitle: 'Rapportino',
      onRefresh: () => refreshWithFeedback(context, ref),
      hero: _buildRapportinoHero(context, ref, draft),
      sections: [
        DetailSectionData(
          title: 'Documento',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header card: StatusPill + date + KeyVal metadata ──────────
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.base),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            StatusPill(stato: statusLabel),
                            const SizedBox(width: 8),
                            Text(
                              dateLabel,
                              style: TextStyle(
                                fontFamily: 'Archivo',
                                fontSize: 12,
                                color: context.colors.inkMuted,
                              ),
                            ),
                            // "Serve un secondo intervento" (step_riepilogo.dart's own toggle)
                            // — surfaced here so the office/technician sees it without opening
                            // Rilavora. Local-only for a report synced down from another
                            // device (see richiedeSecondoIntervento's own doc comment on
                            // DraftReports) — off is not proof nothing was flagged, only that
                            // this device doesn't know.
                            if (draft.richiedeSecondoIntervento) ...[
                              const SizedBox(width: 8),
                              AppBadge(
                                label: 'Da tornare',
                                bgColor: context.colors.amber.withAlpha(31),
                                fgColor: context.colors.amber,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: context.colors.borderLight),
                      // Stated on the technician's own record of what they signed, mirroring
                      // the exact same row (same label, same text) step_riepilogo.dart's
                      // summary card shows before the two signatures are collected.
                      if (draft.isAiAssisted)
                        const KeyVal(
                          label: 'Redazione',
                          value: 'Bozza generata con AI, poi rivista',
                        ),
                      KeyVal(label: 'Ore', value: oreLabel, showDivider: false),
                    ],
                  ),
                ),
              ),

              // ── Sede map ──────────────────────────────────────────────────────
              //
              // Same embedded-map treatment ticket detail and cantiere detail already give a
              // location. The hero states the site; this shows where it is.
              if (locationAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: GeoMapCard(
                    pointAsync: ref.watch(locationGeocodedLocationProvider(locationId)),
                    address: locationAddress,
                  ),
                ),

              // ── Cronologia: lifecycle dates past creation ────────────────────
              //
              // Bozza → createdAt/updatedAt alone (already in the header) says everything.
              // Past that, the office's own review trail (Inviato/Controllato/Fatturato) is
              // real content this report carries and the view never showed — only the
              // customer-facing Firma dates got surfaced before this.
              if (draft.inviatoAt != null ||
                  draft.controllatoAt != null ||
                  draft.fatturatoAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                          child: SectionTitle(title: 'Cronologia'),
                        ),
                        if (draft.inviatoAt != null)
                          KeyVal(
                            label: 'Inviato il',
                            value: DateFormat(
                              'dd/MM/yyyy HH:mm',
                              'it',
                            ).format(draft.inviatoAt!.toLocal()),
                            showDivider: draft.controllatoAt != null || draft.fatturatoAt != null,
                          ),
                        if (draft.controllatoAt != null)
                          KeyVal(
                            label: 'Controllato il',
                            value: DateFormat(
                              'dd/MM/yyyy HH:mm',
                              'it',
                            ).format(draft.controllatoAt!.toLocal()),
                            showDivider: draft.fatturatoAt != null,
                          ),
                        if (draft.fatturatoAt != null)
                          KeyVal(
                            label: 'Fatturato il',
                            value: DateFormat(
                              'dd/MM/yyyy HH:mm',
                              'it',
                            ).format(draft.fatturatoAt!.toLocal()),
                            showDivider: false,
                          ),
                      ],
                    ),
                  ),
                ),

              // ── Rejection banner + rework affordance ────────────────────────
              //
              // The office rejected this report (POST /api/reports/{id}/respingi). The
              // backend has no rejection-reason field to show (checked: ReportsController,
              // ReportService.RespingiAsync, the Report entity itself all take/carry none), so
              // this states the fact plainly instead of inventing a reason. "Rilavora" clones
              // this report's data into a brand-new local draft — see createReworkDraft's own
              // doc comment for why it can't simply reopen this same report id (the backend's
              // state machine only allows Bozza → Inviato).
              if (rapportinoIsRejected(draft))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: const _RejectionBanner(),
                ),

              // ── Descrizione ───────────────────────────────────────────────
              if (draft.details != null && draft.details!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Descrizione'),
                        const SizedBox(height: 4),
                        Text(
                          draft.details!,
                          style: TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 13,
                            color: context.colors.ink,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Diagnosi e soluzione ──────────────────────────────────────
              //
              // Two fields the technician fills in on site (step Dettagli) and that the
              // customer's PDF prints — but the read-only view, the only place a sent report
              // can be re-read, dropped them. They are not part of Descrizione: that is the
              // free-text account of the visit, while diagnosi names the cause and soluzione
              // the remedy, and the office searches on those two. One card, because they are
              // read together; each shown only when it has text, so a report with just a cause
              // does not print an empty "Soluzione".
              if ((draft.diagnosi ?? '').isNotEmpty || (draft.soluzione ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Diagnosi e soluzione'),
                        if ((draft.diagnosi ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _ReportFieldLabel(label: 'Diagnosi'),
                          const SizedBox(height: 2),
                          Text(
                            draft.diagnosi!,
                            style: TextStyle(
                              fontFamily: 'Archivo',
                              fontSize: 13,
                              color: context.colors.ink,
                              height: 1.5,
                            ),
                          ),
                        ],
                        if ((draft.soluzione ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ReportFieldLabel(label: 'Soluzione'),
                          const SizedBox(height: 2),
                          Text(
                            draft.soluzione!,
                            style: TextStyle(
                              fontFamily: 'Archivo',
                              fontSize: 13,
                              color: context.colors.ink,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // ── Note tecnico ──────────────────────────────────────────────
              //
              // A separate field from Descrizione (DraftReports.details) — internal, not
              // printed on the customer PDF (see Report.technicianNotes' own backend doc
              // comment) — so it needs its own section rather than being folded into or
              // mistaken for the description above it.
              if (draft.technicianNotes != null && draft.technicianNotes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Note tecnico'),
                        const SizedBox(height: 4),
                        Text(
                          draft.technicianNotes!,
                          style: TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 13,
                            color: context.colors.ink,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Squadra e ore ────────────────────────────────────────────────
              //
              // The header's "Ore" row is the report's aggregate total — this is the
              // itemized worklog behind it, one row per technician who contributed, with
              // whatever travel/vehicle/notes data that technician's row carries.
              if (staff.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                          child: SectionTitle(title: 'Squadra e ore'),
                        ),
                        ...staff.map((s) {
                          final name =
                              ref.watch(colleagueNameProvider(s.userId)).valueOrNull ?? s.userId;
                          final hours = formatOreLabel(totalOreMinutes([s]));
                          final metaParts = [
                            hours,
                            if (s.kmTraveled > 0) '${s.kmTraveled.toStringAsFixed(1)} km',
                            ?s.vehicle,
                            ?s.notes,
                          ];
                          return ListRow(
                            leading: const RowIconTile(icon: LucideIcons.user),
                            title: name,
                            subtitle: metaParts.join(' · '),
                            showDivider: s != staff.last,
                          );
                        }),
                      ],
                    ),
                  ),
                ),

              // ── Controlli (checklist) ────────────────────────────────────────
              //
              // What was recorded against the ticket's checklist on this visit (ADR-0012
              // §B.4) — labels/types resolved against the cached ticket checklist when
              // available (see controlLabels above); a raw controlId is shown instead of
              // hiding the row when the checklist hasn't been cached on this device.
              if (controlli.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                          child: SectionTitle(title: 'Controlli'),
                        ),
                        ...groupControlliByAsset(controlli, controlLabels).expand((group) {
                          return <Widget>[
                            if (group.assetId != null) ...[
                              _AssetGroupHeader(assetId: group.assetId!),
                              const SizedBox(height: 6),
                            ],
                            for (final c in group.rows)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ControlloAnswerRow(
                                  controllo: c,
                                  flat: controlLabels[c.controlId],
                                ),
                              ),
                          ];
                        }),
                      ],
                    ),
                  ),
                ),

              // ── Materiali list ────────────────────────────────────────────
              if (materiali.isNotEmpty || draft.materialiNotRequired)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                          child: SectionTitle(title: 'Materiali'),
                        ),
                        if (materiali.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Text(
                              'Nessun materiale utilizzato — confermato dal tecnico.',
                              style: TextStyle(
                                fontFamily: 'Archivo',
                                fontSize: 13,
                                color: context.colors.inkMuted,
                              ),
                            ),
                          ),
                        ...materiali.map((m) {
                          final name =
                              m.freeTextName ??
                              (m.materialeId != null
                                  ? (ref.watch(materialeNameProvider(m.materialeId!)).valueOrNull ??
                                        m.materialeId!)
                                  : '—');
                          final qty = m.quantity.toStringAsFixed(
                            m.quantity.truncateToDouble() == m.quantity ? 0 : 2,
                          );
                          final priceStr = m.unitPrice != null
                              ? '€${m.unitPrice!.toStringAsFixed(2)}'
                              : null;
                          final uom = m.unitOfMeasure;
                          final metaSub = [
                            '$qty${uom != null ? ' $uom' : ''}',
                            ?priceStr,
                          ].join(' · ');
                          return ListRow(
                            leading: const RowIconTile(
                              icon: LucideIcons.package,
                              size: 36,
                              iconSize: 18,
                            ),
                            title: name,
                            subtitle: metaSub,
                            showDivider: m != materiali.last,
                          );
                        }),
                      ],
                    ),
                  ),
                ),

              // ── Foto ──────────────────────────────────────────────────────
              if (photoAllegati.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Foto (${photoAllegati.length})'),
                        const SizedBox(height: 8),
                        _AllegatiPhotoGrid(dio: dio, allegati: photoAllegati),
                      ],
                    ),
                  ),
                ),

              // ── Firma cliente ─────────────────────────────────────────────
              if (draft.customerSignatureAllegatoId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Firma cliente'),
                        // The acceptance text the customer signed against
                        // (Report.customerSignoffText) — captured alongside the signature
                        // itself, and otherwise nowhere on this screen.
                        if (draft.customerSignoffText != null &&
                            draft.customerSignoffText!.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              draft.customerSignoffText!,
                              style: TextStyle(
                                fontFamily: 'Archivo',
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: context.colors.inkMuted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ] else
                          const SizedBox(height: 8),
                        _SignatureBlock(
                          dio: dio,
                          allegato: customerSignatureAllegato,
                          signedAt:
                              draft.customerSignoffAt ??
                              draft.inviatoAt ??
                              draft.updatedAt ??
                              draft.createdAt,
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Senza firma cliente (motivo) ──────────────────────────────
              // The counterpart of the block above for a report the customer could not sign:
              // show why, instead of leaving the section blank as if the signature had merely
              // been forgotten.
              if (draft.customerSignatureAllegatoId == null && customerAbsenceReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Firma cliente'),
                        const SizedBox(height: 8),
                        Text(
                          'Senza firma cliente — ${customerAbsenceReason.summaryLabel}',
                          style: TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.ink,
                          ),
                        ),
                        if (draft.customerSignatureAbsenceNote?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 6),
                          Text(
                            draft.customerSignatureAbsenceNote!,
                            style: TextStyle(
                              fontFamily: 'Archivo',
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: context.colors.inkMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // ── Firma tecnico ─────────────────────────────────────────────
              if (draft.technicianSignatureAllegatoId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(title: 'Firma tecnico'),
                        const SizedBox(height: 8),
                        _SignatureBlock(
                          dio: dio,
                          allegato: technicianSignatureAllegato,
                          signedAt:
                              draft.customerSignoffAt ??
                              draft.inviatoAt ??
                              draft.updatedAt ??
                              draft.createdAt,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens the report's PDF (`GET /api/Reports/{id}/pdf`, generated server-side) in the device's
/// default viewer, from [reportPdfCacheProvider]: online it is re-downloaded and stored, offline
/// the stored copy is served. This is the document the technician hands to the customer, so it has
/// to survive the drive to the site — it used to live in the temp directory and vanish with it.
Future<void> _openReportPdf(BuildContext context, WidgetRef ref, String reportId) async {
  final file = await _resolveReportPdf(ref, reportId, context);
  if (file == null) return;

  final result = await OpenFilex.open(file.path);
  if (result.type != ResultType.done) {
    if (!context.mounted) return;
    showAppToast(
      context,
      message: 'Impossibile aprire il PDF: ${result.message}',
      tone: ToastTone.error,
    );
  }
}

/// Shared resolve step behind [_openReportPdf] and [_shareReportPdf] — each caller decides what to
/// do with the file. Returns null (and has already said why) when there is no PDF to be had, so
/// callers check for null rather than duplicating error UI.
///
/// The three outcomes are told apart on purpose: "never downloaded" is a first-time problem the
/// technician can fix by going back online once, "download failed" is the server's, and a stale
/// copy is not an error at all.
Future<File?> _resolveReportPdf(WidgetRef ref, String reportId, BuildContext context) async {
  try {
    return await ref
        .read(reportPdfCacheProvider)
        .resolve(reportId, online: ref.read(isOnlineProvider));
  } on ReportPdfUnavailable catch (e) {
    if (!context.mounted) return null;
    showAppToast(
      context,
      message: switch (e.reason) {
        ReportPdfFailure.notDownloaded =>
          'PDF non ancora scaricato su questo telefono — serve la connessione la prima volta.',
        ReportPdfFailure.downloadFailed => 'Impossibile scaricare il PDF. Riprova più tardi.',
      },
      tone: e.reason == ReportPdfFailure.notDownloaded ? ToastTone.warning : ToastTone.error,
    );
    return null;
  } catch (_) {
    if (!context.mounted) return null;
    showAppToast(context, message: 'Impossibile scaricare il PDF.', tone: ToastTone.error);
    return null;
  }
}

/// Sends the report's PDF through the OS share sheet — same cached file [_openReportPdf] uses,
/// so a technician can hand it to the office/customer over email/WhatsApp without leaving the app.
Future<void> _shareReportPdf(BuildContext context, WidgetRef ref, String reportId) async {
  final file = await _resolveReportPdf(ref, reportId, context);
  if (file == null) return;

  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}

/// Runs the hero's Scarica PDF action with the per-report in-flight guard: the provider disables
/// the action while the download runs, and the re-entry check covers a tap that lands before the
/// rebuild.
Future<void> _downloadReportPdfFromHero(
  BuildContext context,
  WidgetRef ref,
  String reportId,
) async {
  final busy = _rapportinoPdfBusyProvider(reportId);
  if (ref.read(busy)) return;
  ref.read(busy.notifier).state = true;
  try {
    await _openReportPdf(context, ref, reportId);
  } finally {
    if (context.mounted) ref.read(busy.notifier).state = false;
  }
}

/// Runs the hero's Condividi action with the same per-report in-flight guard as
/// [_downloadReportPdfFromHero].
Future<void> _shareReportPdfFromHero(BuildContext context, WidgetRef ref, String reportId) async {
  final busy = _rapportinoShareBusyProvider(reportId);
  if (ref.read(busy)) return;
  ref.read(busy.notifier).state = true;
  try {
    await _shareReportPdf(context, ref, reportId);
  } finally {
    if (context.mounted) ref.read(busy.notifier).state = false;
  }
}

/// Guards the hero's rework action against a double tap minting two drafts.
bool _reworkInFlight = false;

/// Creates a fresh local draft from a rejected report and opens it in the editor.
///
/// A rework clones this report's data into a brand-new local draft — see createReworkDraft's own
/// doc comment for why it can't simply reopen this same report id (the backend's state machine
/// only allows Bozza → Inviato).
Future<void> _reworkReport(BuildContext context, WidgetRef ref, DraftReport draft) async {
  if (_reworkInFlight) return;
  _reworkInFlight = true;
  try {
    final newId = await createReworkDraft(ref, draft);
    if (!context.mounted) return;
    if (newId == null) {
      showAppToast(
        context,
        message: 'Accedi per rielaborare il rapporto di intervento.',
        tone: ToastTone.warning,
      );
      return;
    }
    context.push(AppRoutes.rapportiniEditor(newId));
  } finally {
    _reworkInFlight = false;
  }
}

/// Resolves [draft]'s location for display: the local mirror's name, falling back to the
/// free-text the operator typed when the site wasn't in the catalog (packed into
/// `metadataJson` — see `report_editor_providers.dart`'s `_buildMetadataJson`), falling back
/// to the raw id rather than showing nothing.
String _locationLabel(BuildContext context, WidgetRef ref, DraftReport draft) {
  if (draft.locationId.isEmpty) {
    return _metadataField(draft.metadataJson, 'locationFreeText') ?? '—';
  }
  return ref.watch(locationNameProvider(draft.locationId)).valueOrNull ??
      _metadataField(draft.metadataJson, 'locationFreeText') ??
      draft.locationId;
}

/// Resolves [draft]'s customer for display — same fallback chain as [_locationLabel].
String _customerLabel(BuildContext context, WidgetRef ref, DraftReport draft) {
  final customerId = draft.customerId;
  if (customerId == null || customerId.isEmpty) {
    return _metadataField(draft.metadataJson, 'customerFreeText') ?? '—';
  }
  return ref.watch(customerNameProvider(customerId)).valueOrNull ??
      _metadataField(draft.metadataJson, 'customerFreeText') ??
      customerId;
}

/// Builds the report's hero: identity, status, the three facts and the actions this read-only
/// document actually offers. PDF/share are the normal pair; a rejected report swaps the primary
/// for Rilavora, the one action that gives the technician a way forward.
DetailHeroData _buildRapportinoHero(BuildContext context, WidgetRef ref, DraftReport draft) {
  final staff = ref.watch(rapportinoStaffProvider(draft.id)).valueOrNull ?? const [];
  final tecnicoLabel = staff.isNotEmpty
      ? staff
            .map((s) => ref.watch(colleagueNameProvider(s.userId)).valueOrNull ?? s.userId)
            .join(', ')
      : (ref.watch(colleagueNameProvider(draft.insertedUserId)).valueOrNull ??
            draft.insertedUserId);
  final rejected = rapportinoIsRejected(draft);
  final pdfBusy = ref.watch(_rapportinoPdfBusyProvider(draft.id));
  final shareBusy = ref.watch(_rapportinoShareBusyProvider(draft.id));

  return DetailHeroData(
    variant: DetailHeroVariant.operational,
    title: draft.title,
    status: DetailStatus(label: rapportinoStatusLabel(draft)),
    facts: [
      DetailFact(label: 'Cliente', value: _customerLabel(context, ref, draft)),
      DetailFact(label: 'Sede', value: _locationLabel(context, ref, draft)),
      DetailFact(label: 'Tecnico', value: tecnicoLabel),
    ],
    primaryAction: rejected
        ? DetailAction(
            label: 'Rilavora',
            icon: const Icon(LucideIcons.penTool, size: 16),
            onPressed: () => _reworkReport(context, ref, draft),
          )
        : DetailAction(
            label: 'Scarica PDF',
            icon: const Icon(LucideIcons.download, size: 16),
            enabled: !pdfBusy,
            disabledReason: pdfBusy ? 'Download in corso…' : null,
            onPressed: pdfBusy ? null : () => _downloadReportPdfFromHero(context, ref, draft.id),
          ),
    secondaryActions: [
      DetailAction(
        label: 'Condividi',
        icon: const Icon(LucideIcons.share2, size: 16),
        enabled: !shareBusy,
        onPressed: shareBusy ? null : () => _shareReportPdfFromHero(context, ref, draft.id),
      ),
    ],
  );
}

/// Reads one string field out of the draft's packed `metadataJson` blob. Malformed/absent
/// metadata is not worth losing the rest of the display over — returns null rather than
/// throwing, same tolerance `report_editor_providers.dart`'s own parser applies.
String? _metadataField(String? json, String key) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final value = decoded[key];
    return value is String && value.isNotEmpty ? value : null;
  } catch (_) {
    return null;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Rejection banner
// ══════════════════════════════════════════════════════════════════════════════

/// Explains a rejected report. Text-only on purpose: the hero owns the single Rilavora action, so
/// this banner never duplicates it.
class _RejectionBanner extends StatelessWidget {
  const _RejectionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: context.colors.red.withValues(alpha: 0.12),
        border: Border.all(color: context.colors.red),
        borderRadius: AppRack.freeShape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.xCircle, color: context.colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "L'ufficio ha respinto questo rapporto di intervento.",
                  style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // The backend has no motivo/reason field to show here — POST
            // /api/reports/{id}/respingi takes no body and Report carries none — so this says
            // what is true instead of a reason that does not exist yet.
            "Rielaboralo per correggerlo e inviarlo di nuovo: si crea un nuovo rapporto di "
            "lavoro con gli stessi dati, quello respinto resta com'è. "
            "L'ufficio non ha registrato un motivo per questo rifiuto.",
            style: TextStyle(color: context.colors.ink, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Signature block
// ══════════════════════════════════════════════════════════════════════════════

class _SignatureBlock extends ConsumerWidget {
  const _SignatureBlock({required this.dio, required this.allegato, required this.signedAt});

  final Dio dio;

  /// Resolved by the caller against [rapportinoAllegatiProvider] — null while that stream is
  /// still loading, or if the id it points to was never found (deleted/never synced).
  final ReportAllegatiData? allegato;
  final DateTime signedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedLabel = DateFormat('dd/MM/yyyy HH:mm', 'it').format(signedAt.toLocal());

    // The placeholder this used to always show, still shown when the allegato hasn't resolved —
    // "we can't easily resolve a local path from allegatoId" no longer applies now that
    // rapportinoAllegatiProvider does exactly that, but a signature genuinely absent from the
    // local mirror (synced down without its allegati, or deleted) still needs an honest fallback
    // rather than a broken image icon.
    if (allegato == null) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 90),
        decoration: BoxDecoration(
          border: Border.all(
            color: context.colors.borderStrong,
            width: 1.5,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(10),
          color: context.colors.bg1,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.penTool, size: 28, color: context.colors.inkMuted),
            const SizedBox(height: 6),
            Text(
              'Firmato il $signedLabel',
              style: TextStyle(fontFamily: 'Archivo', fontSize: 12, color: context.colors.inkMuted),
            ),
          ],
        ),
      );
    }

    final a = allegato!;
    final hasLocal = a.storagePath.isNotEmpty && File(a.storagePath).existsSync();
    final contentRef = (
      allegatoId: a.id,
      contentHash: a.contentHash,
      sizeBytes: a.sizeBytes,
      url: a.url,
    );

    return AppTappable(
      onTap: () => openAttachment(
        context,
        dio: dio,
        fileName: a.fileName,
        contentType: a.contentType,
        url: a.url,
        localPath: hasLocal ? a.storagePath : null,
        cache: ref.read(attachmentContentCacheProvider),
        contentRef: a.url.isEmpty ? null : contentRef,
      ),
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 90),
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.borderStrong, width: 1.5),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white, // a signature is drawn in ink on white — never the theme's bg
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hasLocal
                  ? Image.file(
                      File(a.storagePath),
                      errorBuilder: (_, _, _) => const _SignatureFallbackIcon(),
                    )
                  : a.url.isNotEmpty
                  ? AttachmentThumbnail(
                      attachment: contentRef,
                      fit: BoxFit.contain,
                      placeholder: const _SignatureFallbackIcon(),
                    )
                  : const _SignatureFallbackIcon(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Firmato il $signedLabel',
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 12,
                    color: context.colors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureFallbackIcon extends StatelessWidget {
  const _SignatureFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Icon(LucideIcons.penTool, size: 28, color: context.colors.inkMuted),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Photo grid (Step 6 "Allegati")
// ══════════════════════════════════════════════════════════════════════════════

/// Thumbnails for whatever Step 6 attached, local-first (same as the editor's own
/// StepMaterialiFold grid) so an offline-captured, not-yet-uploaded photo still shows.
/// cacheWidth/cacheHeight for the same reason StepMaterialiFold's own tile has them: a camera
/// photo decodes at full sensor resolution, and this is a small square tile.
class _AllegatiPhotoGrid extends ConsumerWidget {
  const _AllegatiPhotoGrid({required this.dio, required this.allegati});

  final Dio dio;
  final List<ReportAllegatiData> allegati;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tileSize =
        (MediaQuery.sizeOf(context).width -
            AppSpacing.pagePadding * 2 -
            AppSpacing.base * 2 -
            8 * 2) /
        3;
    final cachePx = (tileSize * MediaQuery.devicePixelRatioOf(context)).round();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allegati.map((a) {
        final hasLocal = a.storagePath.isNotEmpty && File(a.storagePath).existsSync();
        final contentRef = (
          allegatoId: a.id,
          contentHash: a.contentHash,
          sizeBytes: a.sizeBytes,
          url: a.url,
        );
        return AppTappable(
          onTap: () => openAttachment(
            context,
            dio: dio,
            fileName: a.fileName,
            contentType: a.contentType,
            url: a.url,
            localPath: hasLocal ? a.storagePath : null,
            cache: ref.read(attachmentContentCacheProvider),
            contentRef: a.url.isEmpty ? null : contentRef,
          ),
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: tileSize,
              height: tileSize,
              child: hasLocal
                  ? Image.file(
                      File(a.storagePath),
                      fit: BoxFit.cover,
                      cacheWidth: cachePx,
                      cacheHeight: cachePx,
                      errorBuilder: (ctx, e, _) => _photoErrorTile(context),
                    )
                  : a.url.isNotEmpty
                  ? AttachmentThumbnail(
                      attachment: contentRef,
                      cacheWidth: cachePx,
                      cacheHeight: cachePx,
                      placeholder: _photoErrorTile(context),
                    )
                  : _photoErrorTile(context),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _photoErrorTile(BuildContext context) {
    return Container(
      color: context.colors.bg3,
      child: Icon(LucideIcons.imageOff, color: context.colors.inkMuted),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Controlli answers — one recorded checklist finding
// ══════════════════════════════════════════════════════════════════════════════

/// The Controlli answers of a report, grouped by the asset they were recorded against.
class ControlloAssetGroup {
  const ControlloAssetGroup({required this.assetId, required this.rows});

  /// Null for the ticket-level rows — the answers that belong to no asset.
  final String? assetId;
  final List<ReportControlliData> rows;
}

/// Groups recorded answers by asset, ticket-level rows first.
///
/// The asset comes from the answer's own snapshot when it has one, and from the ticket checklist
/// otherwise — the same two sources the label uses, so a report whose checklist is gone still groups
/// correctly instead of collapsing into one anonymous list. Order inside a group is the order the
/// answers were recorded in, which is the order the technician filled them in.
List<ControlloAssetGroup> groupControlliByAsset(
  List<ReportControlliData> rows,
  Map<String, FlatTicketControl> labels,
) {
  final order = <String?>[];
  final byAsset = <String?, List<ReportControlliData>>{};
  for (final row in rows) {
    final assetId = row.assetId ?? labels[row.controlId]?.control.prodottoAssistenzaId;
    if (!byAsset.containsKey(assetId)) {
      order.add(assetId);
      byAsset[assetId] = <ReportControlliData>[];
    }
    byAsset[assetId]!.add(row);
  }
  // Ticket-level answers have no asset of their own to be filed under; leading with them keeps the
  // report's own general findings above the per-asset detail, and stops a report with no assets at
  // all from starting with an empty-headed group. Filtered rather than sorted: `List.sort` is not
  // stable, and the order within each block is the technician's own.
  final ticketLevel = [
    for (final assetId in order)
      if (assetId == null) ControlloAssetGroup(assetId: null, rows: byAsset[assetId]!),
  ];
  final perAsset = [
    for (final assetId in order)
      if (assetId != null) ControlloAssetGroup(assetId: assetId, rows: byAsset[assetId]!),
  ];
  return [...ticketLevel, ...perAsset];
}

/// The heading above one asset's block of answers: the asset's name, from the synced mirror.
class _AssetGroupHeader extends ConsumerWidget {
  const _AssetGroupHeader({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(assetNameProvider(assetId)).valueOrNull;
    return Row(
      children: [
        Icon(LucideIcons.wrench, size: 14, color: context.colors.inkMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            // A device that never synced this asset still names the block honestly rather than
            // dropping the grouping or repeating the GUID.
            name ?? 'Attrezzatura',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small uppercase-ish heading inside a card that carries more than one field
/// (Diagnosi e soluzione), so the two values are not read as one run-on paragraph.
class _ReportFieldLabel extends StatelessWidget {
  const _ReportFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.inkMuted),
    );
  }
}

/// One recorded [ReportControlliData] row, read-only — the answer this report's own technician
/// gave to one item of the ticket's checklist (ADR-0012 §B.4). Mirrors ticket_detail_screen.dart's
/// `_TicketControlStatusCard` shape (icon + group path + label + value), but reads a report's own
/// recorded answer instead of the ticket's live/current one.
///
/// The label comes from the answer itself first: a sent report is a document, and it has to name its
/// own rows on a device that has never seen this ticket's checklist — otherwise the customer-facing
/// view of the job lists raw GUIDs (the bug this row used to have). The checklist resolution is
/// still the second source, for rows mirrored from the server, which carry only a control id.
class _ControlloAnswerRow extends StatelessWidget {
  const _ControlloAnswerRow({required this.controllo, required this.flat});

  final ReportControlliData controllo;
  final FlatTicketControl? flat;

  @override
  Widget build(BuildContext context) {
    final control = flat?.control;
    final label = controllo.controlLabel ?? control?.label ?? 'Controllo ${controllo.controlId}';
    final groupPath = flat?.groupPath;
    final valueLabel = _valueLabel(control?.type);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.clipboardCheck, size: 18, color: context.colors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groupPath != null && groupPath.isNotEmpty)
                  Text(groupPath, style: TextStyle(color: context.colors.inkMuted, fontSize: 11)),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: context.colors.ink,
                  ),
                ),
                if (valueLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      valueLabel,
                      style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Picks the recorded column matching [type] when it's known; falls back to "whichever column
  /// is actually populated" when the checklist item's type hasn't resolved (offline / never
  /// cached) — a report's answer is stored in exactly one of these four columns regardless of
  /// whether this device can currently say which type it is.
  String? _valueLabel(ControlType? type) {
    switch (type) {
      // Same split as the editable field — a tick is an assertion, not a choice between two
      // answers. The `null`/unknown fallback below still has to guess "whichever column is
      // populated" and cannot tell the two boolean types apart, so it keeps the neutral Sì/No
      // wording rather than inventing a tick the record may not describe.
      case ControlType.checkbox:
        if (controllo.boolValue == null) return null;
        return controllo.boolValue! ? 'Spuntato' : 'Non spuntato';
      case ControlType.trueFalse:
        if (controllo.boolValue == null) return null;
        return controllo.boolValue! ? 'Sì' : 'No';
      case ControlType.dateTime:
        if (controllo.dateValue == null) return null;
        return DateFormat('dd/MM/yyyy', 'it').format(controllo.dateValue!.toLocal());
      case ControlType.number:
        return controllo.numberValue?.toString();
      case ControlType.text:
      case ControlType.options:
      case ControlType.unknown:
      case null:
        return controllo.stringValue ??
            (controllo.boolValue != null ? (controllo.boolValue! ? 'Sì' : 'No') : null) ??
            (controllo.dateValue != null
                ? DateFormat('dd/MM/yyyy', 'it').format(controllo.dateValue!.toLocal())
                : null) ??
            controllo.numberValue?.toString();
    }
  }
}
