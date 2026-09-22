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
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/geo_map_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/dio_client.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/ticket_controls_cache_repository.dart' show cachedTicketControlsProvider;
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

class RapportinoViewScreen extends ConsumerWidget {
  const RapportinoViewScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(rapportinoByIdProvider(reportId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // No online/offline distinction to draw here (unlike the ticket detail tabs): this reads
        // the local Drift mirror only (rapportinoByIdProvider), never the network, so an error
        // here is a local read failure, not connectivity — and a retry re-opens that same stream.
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              ScreenHeader(title: 'Rapportino', showBack: true),
              Expanded(
                child: UnavailableState(
                  icon: LucideIcons.xCircle,
                  titolo: 'Impossibile caricare il rapportino',
                  motivo: 'Si è verificato un errore imprevisto. Riprova.',
                  action: AppButton(
                    label: 'Riprova',
                    size: AppButtonSize.sm,
                    fullWidth: false,
                    onPressed: () => ref.invalidate(rapportinoByIdProvider(reportId)),
                  ),
                ),
              ),
            ],
          ),
        ),
        data: (draft) {
          if (draft == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(title: 'Rapportino', showBack: true),
                  EmptyState(
                    icon: LucideIcons.fileX,
                    title: 'Rapportino non trovato',
                    body: 'Il rapportino richiesto non è disponibile in cache.',
                  ),
                ],
              ),
            );
          }
          return _RapportinoViewBody(draft: draft);
        },
      ),
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

    // Names, not user ids. This joined raw GUIDs — on the read-only view of the document that
    // becomes an invoice, where "who did the work" is the line a customer actually reads back.
    // The colleagues mirror is synced, so this still resolves with the radio off; an id the mirror
    // does not know falls through as itself rather than vanishing from the list.
    final tecnicoLabel = staff.isNotEmpty
        ? staff
              .map((s) => ref.watch(colleagueNameProvider(s.userId)).valueOrNull ?? s.userId)
              .join(', ')
        : (ref.watch(colleagueNameProvider(draft.insertedUserId)).valueOrNull ??
              draft.insertedUserId);

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

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(title: draft.title, showBack: true),
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Header card: StatusPill + date + KeyVal metadata ──────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      AppSpacing.sm,
                      AppSpacing.pagePadding,
                      AppSpacing.base,
                    ),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.md,
                              bottom: AppSpacing.sm,
                            ),
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
                          KeyVal(label: 'Sede', value: _locationLabel(context, ref, draft)),
                          KeyVal(label: 'Tecnico', value: tecnicoLabel),
                          KeyVal(label: 'Cliente', value: _customerLabel(context, ref, draft)),
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
                ),

                // ── Sede map ──────────────────────────────────────────────────────
                //
                // Same embedded-map treatment ticket detail and cantiere detail already give a
                // location — this report's "Sede" KeyVal row above used to be the only trace of
                // where the job happened; there was no map at all.
                if (locationAddress.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: GeoMapCard(
                        pointAsync: ref.watch(locationGeocodedLocationProvider(locationId)),
                        address: locationAddress,
                      ),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                                bottom: AppSpacing.xs,
                              ),
                              child: SectionTitle(title: 'Cronologia'),
                            ),
                            if (draft.inviatoAt != null)
                              KeyVal(
                                label: 'Inviato il',
                                value: DateFormat(
                                  'dd/MM/yyyy HH:mm',
                                  'it',
                                ).format(draft.inviatoAt!.toLocal()),
                                showDivider:
                                    draft.controllatoAt != null || draft.fatturatoAt != null,
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: _RejectionBanner(draft: draft),
                    ),
                  ),

                // ── Descrizione ───────────────────────────────────────────────
                if (draft.details != null && draft.details!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
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
                  ),

                // ── Note tecnico ──────────────────────────────────────────────
                //
                // A separate field from Descrizione (DraftReports.details) — internal, not
                // printed on the customer PDF (see Report.technicianNotes' own backend doc
                // comment) — so it needs its own section rather than being folded into or
                // mistaken for the description above it.
                if (draft.technicianNotes != null && draft.technicianNotes!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
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
                  ),

                // ── Squadra e ore ────────────────────────────────────────────────
                //
                // The header's "Ore" row is the report's aggregate total — this is the
                // itemized worklog behind it, one row per technician who contributed, with
                // whatever travel/vehicle/notes data that technician's row carries.
                if (staff.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                                bottom: AppSpacing.xs,
                              ),
                              child: SectionTitle(title: 'Squadra e ore'),
                            ),
                            ...staff.map((s) {
                              final name =
                                  ref.watch(colleagueNameProvider(s.userId)).valueOrNull ??
                                  s.userId;
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
                  ),

                // ── Controlli (checklist) ────────────────────────────────────────
                //
                // What was recorded against the ticket's checklist on this visit (ADR-0012
                // §B.4) — labels/types resolved against the cached ticket checklist when
                // available (see controlLabels above); a raw controlId is shown instead of
                // hiding the row when the checklist hasn't been cached on this device.
                if (controlli.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                                bottom: AppSpacing.xs,
                              ),
                              child: SectionTitle(title: 'Controlli'),
                            ),
                            ...controlli.map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ControlloAnswerRow(
                                  controllo: c,
                                  flat: controlLabels[c.controlId],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Materiali list ────────────────────────────────────────────
                if (materiali.isNotEmpty || draft.materialiNotRequired)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                                bottom: AppSpacing.xs,
                              ),
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
                                      ? (ref
                                                .watch(materialeNameProvider(m.materialeId!))
                                                .valueOrNull ??
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
                  ),

                // ── Foto ──────────────────────────────────────────────────────
                if (photoAllegati.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
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
                  ),

                // ── Firma cliente ─────────────────────────────────────────────
                if (draft.customerSignatureAllegatoId != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
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
                  ),

                // ── Firma tecnico ─────────────────────────────────────────────
                if (draft.technicianSignatureAllegatoId != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
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
                  ),

                // ── Download PDF ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      0,
                      AppSpacing.pagePadding,
                      AppSpacing.xl,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _DownloadPdfButton(reportId: draft.id)),
                        const SizedBox(width: 8),
                        _SharePdfButton(reportId: draft.id),
                      ],
                    ),
                  ),
                ),

                SliverPadding(padding: EdgeInsets.only(bottom: context.fabSafeBottom)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Downloads the report's PDF (`GET /api/Reports/{id}/pdf`, already generated server-side —
/// this was the missing half, no client code path called it) to a temp file and opens it in
/// the device's default PDF viewer. Temp, not the app-documents directory `step_riepilogo.dart`
/// uses for a signature: a downloaded PDF is disposable cache content the OS can reclaim, not
/// something this app owns going forward.
Future<void> _openReportPdf(BuildContext context, WidgetRef ref, String reportId) async {
  final file = await _fetchPdfToTempFile(ref, reportId, context);
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

/// Shared fetch-and-save step behind [_openReportPdf] and [_SharePdfButton] — downloads once,
/// each caller decides what to do with the file. Returns null (and has already shown the
/// error) on failure, so callers can just check for null rather than duplicating error UI.
Future<File?> _fetchPdfToTempFile(WidgetRef ref, String reportId, BuildContext context) async {
  try {
    final dio = ref.read(dioProvider);
    final response = await dio.get<List<int>>(
      '/api/Reports/$reportId/pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null) throw StateError('empty PDF response');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/report-$reportId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  } on DioException catch (e) {
    final offline =
        e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout;
    if (!context.mounted) return null;
    showAppToast(
      context,
      message: offline
          ? 'Nessuna connessione — riprova quando sei online.'
          : 'Impossibile scaricare il PDF. Riprova più tardi.',
      tone: offline ? ToastTone.warning : ToastTone.error,
    );
    return null;
  } catch (_) {
    if (!context.mounted) return null;
    showAppToast(context, message: 'Impossibile scaricare il PDF.', tone: ToastTone.error);
    return null;
  }
}

/// "Scarica PDF" — downloads (via [_openReportPdf]) and opens the report's PDF in the device's
/// default viewer. Same local-`_busy` shape as its sibling [_SharePdfButton] below, so the two
/// download actions next to each other agree on what "in progress" looks like: this one drives
/// [AppButton]'s own `isLoading` state instead of a bespoke spinner, since [AppButton] (unlike the
/// icon-only [AppTappable] share button) already renders one.
class _DownloadPdfButton extends ConsumerStatefulWidget {
  const _DownloadPdfButton({required this.reportId});

  final String reportId;

  @override
  ConsumerState<_DownloadPdfButton> createState() => _DownloadPdfButtonState();
}

class _DownloadPdfButtonState extends ConsumerState<_DownloadPdfButton> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      await _openReportPdf(context, ref, widget.reportId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: _busy ? 'Download in corso...' : 'Scarica PDF',
      icon: _busy ? null : const Icon(LucideIcons.download, size: 16),
      isLoading: _busy,
      onPressed: _busy ? null : _open,
    );
  }
}

/// Square icon-only twin to the "Scarica PDF" [VetroButton] — sends the same downloaded file
/// through the OS share sheet instead of opening it, so a technician can hand the report to the
/// office/customer over email/WhatsApp without leaving the app. Not [VetroButton] itself: that
/// widget always pairs an icon with a label, and a share affordance next to a full-width primary
/// button reads better as an icon-only square than a second full-width row.
class _SharePdfButton extends ConsumerStatefulWidget {
  const _SharePdfButton({required this.reportId});

  final String reportId;

  @override
  ConsumerState<_SharePdfButton> createState() => _SharePdfButtonState();
}

class _SharePdfButtonState extends ConsumerState<_SharePdfButton> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final file = await _fetchPdfToTempFile(ref, widget.reportId, context);
    if (mounted) setState(() => _busy = false);
    if (file == null) return;

    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: AppTappable(
        onTap: _busy ? null : _share,
        color: AppColors.Y.withAlpha(31),
        borderRadius: BorderRadius.circular(16),
        semanticLabel: 'Condividi PDF',
        child: Center(
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.Y),
                )
              : Icon(LucideIcons.share2, size: 18, color: AppColors.Y),
        ),
      ),
    );
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
// Rejection banner + rework button
// ══════════════════════════════════════════════════════════════════════════════

class _RejectionBanner extends ConsumerStatefulWidget {
  const _RejectionBanner({required this.draft});

  final DraftReport draft;

  @override
  ConsumerState<_RejectionBanner> createState() => _RejectionBannerState();
}

class _RejectionBannerState extends ConsumerState<_RejectionBanner> {
  bool _busy = false;

  Future<void> _rilavora() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final newId = await createReworkDraft(ref, widget.draft);
      if (!mounted) return;
      if (newId == null) {
        showAppToast(
          context,
          message: 'Accedi per rilavorare il rapportino.',
          tone: ToastTone.warning,
        );
        return;
      }
      context.push(AppRoutes.rapportiniEditor(newId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                  "L'ufficio ha respinto questo rapportino.",
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
            "Rilavoralo per correggerlo e inviarlo di nuovo. L'ufficio non ha registrato "
            'un motivo per questo rifiuto.',
            style: TextStyle(color: context.colors.ink, fontSize: 13),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Rilavora',
            icon: const Icon(LucideIcons.penTool),
            onPressed: _busy ? null : _rilavora,
            isLoading: _busy,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Signature block
// ══════════════════════════════════════════════════════════════════════════════

class _SignatureBlock extends StatelessWidget {
  const _SignatureBlock({required this.dio, required this.allegato, required this.signedAt});

  final Dio dio;

  /// Resolved by the caller against [rapportinoAllegatiProvider] — null while that stream is
  /// still loading, or if the id it points to was never found (deleted/never synced).
  final ReportAllegatiData? allegato;
  final DateTime signedAt;

  @override
  Widget build(BuildContext context) {
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

    return AppTappable(
      onTap: () => openAttachment(
        context,
        dio: dio,
        fileName: a.fileName,
        contentType: a.contentType,
        url: a.url,
        localPath: hasLocal ? a.storagePath : null,
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
                  ? Image.network(a.url, errorBuilder: (_, _, _) => const _SignatureFallbackIcon())
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
class _AllegatiPhotoGrid extends StatelessWidget {
  const _AllegatiPhotoGrid({required this.dio, required this.allegati});

  final Dio dio;
  final List<ReportAllegatiData> allegati;

  @override
  Widget build(BuildContext context) {
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
        return AppTappable(
          onTap: () => openAttachment(
            context,
            dio: dio,
            fileName: a.fileName,
            contentType: a.contentType,
            url: a.url,
            localPath: hasLocal ? a.storagePath : null,
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
                  ? Image.network(
                      a.url,
                      fit: BoxFit.cover,
                      cacheWidth: cachePx,
                      cacheHeight: cachePx,
                      errorBuilder: (ctx, e, _) => _photoErrorTile(context),
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

/// One recorded [ReportControlliData] row, read-only — the answer this report's own technician
/// gave to one item of the ticket's checklist (ADR-0012 §B.4). Mirrors ticket_detail_screen.dart's
/// `_TicketControlStatusCard` shape (icon + group path + label + value), but reads a report's own
/// recorded answer instead of the ticket's live/current one, and tolerates [flat] being null (the
/// checklist hasn't been cached on this device) by falling back to the raw control id rather than
/// hiding the row — the answer itself is still real, recorded data worth showing.
class _ControlloAnswerRow extends StatelessWidget {
  const _ControlloAnswerRow({required this.controllo, required this.flat});

  final ReportControlliData controllo;
  final FlatTicketControl? flat;

  @override
  Widget build(BuildContext context) {
    final control = flat?.control;
    final label = control?.label ?? 'Controllo ${controllo.controlId}';
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
      case ControlType.checkbox:
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
