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

import '../../core/auth/access.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/detail/detail_activity_timeline.dart';
import '../../core/widgets/detail/detail_attachment_row.dart';
import '../../core/widgets/detail/detail_facts_grid.dart';
import '../../core/widgets/detail/detail_hero.dart';
import '../../core/widgets/detail/detail_scaffold.dart';
import '../../core/widgets/detail/detail_section.dart';
import '../../core/widgets/geo_map_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/dio_client.dart';
import '../../data/attachments/attachment_content_cache.dart';
import '../../data/entitlements/entitlement_providers.dart' show cachedEntitlementProvider;
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
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RapportinoViewScreen — read-only view for submitted rapportini (D3b).
// ══════════════════════════════════════════════════════════════════════════════

/// One per-report in-flight flag shared by the hero's two PDF actions.
///
/// Scarica PDF and Condividi resolve the same cache entry — same `report-{id}.pdf.part` write — so
/// they must not run independently: a share starting while a download is still writing can read a
/// half-renamed file, and two downloads race on the same temporary path. Both actions therefore
/// take this single flag, and both disable while it is set. Keyed by report id so two open reports
/// never block each other.
final _rapportinoPdfBusyProvider = StateProvider.autoDispose.family<bool, String>(
  (ref, reportId) => false,
);

/// Per-report guard for the hero's rework action, so a double tap mints only one draft while two
/// open reports can still be reworked independently.
final _rapportinoReworkBusyProvider = StateProvider.autoDispose.family<bool, String>(
  (ref, reportId) => false,
);

/// How a resolved PDF is handed to another app (share sheet). Injected so the hero's share guard
/// can be exercised without popping a real platform sheet.
typedef ReportPdfShare = Future<void> Function(File file);

final reportPdfShareProvider = Provider<ReportPdfShare>((ref) {
  return (file) => SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
});

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

    final hasCronologia =
        draft.inviatoAt != null || draft.controllatoAt != null || draft.fatturatoAt != null;
    final rejected = rapportinoIsRejected(draft);
    final hasCustomerSignature = draft.customerSignatureAllegatoId != null;
    final hasCustomerAbsence = !hasCustomerSignature && customerAbsenceReason != null;
    final hasTechnicianSignature = draft.technicianSignatureAllegatoId != null;

    final techNames = staff.isNotEmpty
        ? staff
              .map((s) => ref.watch(colleagueNameProvider(s.userId)).valueOrNull ?? s.userId)
              .join(', ')
        : (ref.watch(colleagueNameProvider(draft.insertedUserId)).valueOrNull ??
              draft.insertedUserId);
    final signatureLabel = hasCustomerSignature
        ? 'Firmato'
        : hasCustomerAbsence
        ? 'Senza firma'
        : 'Non firmato';

    final facts = <DetailFact>[
      DetailFact(label: 'Cliente', value: _customerLabel(context, ref, draft)),
      DetailFact(label: 'Sede', value: _locationLabel(context, ref, draft)),
      DetailFact(label: 'Tecnico', value: techNames),
      DetailFact(label: 'Data', value: dateLabel),
      DetailFact(label: 'Stato firma', value: signatureLabel),
      DetailFact(label: 'Ore', value: oreLabel),
      if (draft.isAiAssisted) const DetailFact(label: 'Redazione', value: 'AI, poi rivista'),
      // "Serve un secondo intervento" (step_riepilogo.dart's own toggle) — local-only for a report
      // synced down from another device, so off is not proof nothing was flagged.
      if (draft.richiedeSecondoIntervento)
        const DetailFact(label: 'Follow-up', value: 'Da tornare'),
    ];

    final timeline = <DetailActivityEvent>[
      if (draft.inviatoAt != null)
        DetailActivityEvent(time: _eventTime(draft.inviatoAt!), title: 'Inviato'),
      if (draft.controllatoAt != null)
        DetailActivityEvent(time: _eventTime(draft.controllatoAt!), title: 'Controllato'),
      if (draft.fatturatoAt != null)
        DetailActivityEvent(
          time: _eventTime(draft.fatturatoAt!),
          title: 'Fatturato',
          tone: DetailEventTone.good,
        ),
    ];

    final details = draft.details ?? '';
    final diagnosi = draft.diagnosi ?? '';
    final soluzione = draft.soluzione ?? '';
    final notes = draft.technicianNotes ?? '';
    final gap = const SizedBox(height: AppSpacing.base);

    return DetailScaffold(
      screenTitle: 'Rapportino',
      onRefresh: () => refreshWithFeedback(context, ref),
      hero: _buildRapportinoHero(context, ref, draft, techNames: techNames),
      sections: [
        // ── Attività: lifecycle (Inviato → Controllato → Fatturato) and rejection ──
        //
        // Bozza → createdAt/updatedAt alone says everything; past that, the office's own review
        // trail is real content this report carries.
        DetailSectionData(
          title: 'Attività',
          isEmpty: !hasCronologia && !rejected,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasCronologia) DetailActivityTimeline(events: timeline),
              if (hasCronologia && rejected) gap,
              // The backend has no rejection-reason field (POST /api/reports/{id}/respingi takes
              // no body, Report carries none), so the banner states the fact, not a reason.
              if (rejected) const _RejectionBanner(),
            ],
          ),
        ),

        // ── Sintesi: the report's own metadata and written record ───────
        DetailSectionData(
          title: 'Sintesi',
          trailing: DetailSectionMeta('${facts.length} campi'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailFactsGrid(facts: facts),
              if (details.isNotEmpty) ...[gap, _TextBlock(label: 'Descrizione', text: details)],
              // Diagnosi names the cause and soluzione the remedy; the office searches on those
              // two, so they are not folded into Descrizione.
              if (diagnosi.isNotEmpty) ...[gap, _TextBlock(label: 'Diagnosi', text: diagnosi)],
              if (soluzione.isNotEmpty) ...[gap, _TextBlock(label: 'Soluzione', text: soluzione)],
              // Internal, not printed on the customer PDF (Report.technicianNotes) — its own block
              // so it is never mistaken for the description.
              if (notes.isNotEmpty) ...[gap, _TextBlock(label: 'Note tecnico', text: notes)],
            ],
          ),
        ),

        // ── Ore: the itemized worklog behind the total ──────────────────
        DetailSectionData(
          title: 'Ore',
          isEmpty: staff.isEmpty,
          trailing: DetailSectionMeta(oreLabel),
          child: _RuleList(
            children: [
              for (final s in staff)
                _RuleRow(
                  icon: LucideIcons.user,
                  title: ref.watch(colleagueNameProvider(s.userId)).valueOrNull ?? s.userId,
                  subtitle: [
                    if (s.kmTraveled > 0) '${s.kmTraveled.toStringAsFixed(1)} km',
                    ?s.vehicle,
                    ?s.notes,
                  ].join(' · '),
                  trailing: formatOreLabel(totalOreMinutes([s])),
                ),
            ],
          ),
        ),

        // ── Materiali list ────────────────────────────────────────────
        DetailSectionData(
          title: 'Materiali',
          isEmpty: materiali.isEmpty && !draft.materialiNotRequired,
          trailing: materiali.isEmpty ? null : DetailSectionMeta('${materiali.length} voci'),
          child: materiali.isEmpty
              ? Text(
                  'Nessun materiale utilizzato — confermato dal tecnico.',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11.5,
                    color: context.colors.inkMuted,
                  ),
                )
              : _RuleList(
                  children: [
                    for (final m in materiali)
                      () {
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
                        return _RuleRow(
                          icon: LucideIcons.package,
                          title: name,
                          trailing: ['$qty${uom != null ? ' $uom' : ''}', ?priceStr].join(' · '),
                        );
                      }(),
                  ],
                ),
        ),

        // ── Controlli (checklist) ────────────────────────────────────────
        //
        // What was recorded against the ticket's checklist on this visit (ADR-0012 §B.4) — labels
        // resolved against the cached ticket checklist when available; a raw controlId is shown
        // instead of hiding the row when the checklist hasn't been cached on this device.
        DetailSectionData(
          title: 'Controlli',
          isEmpty: controlli.isEmpty,
          trailing: DetailSectionMeta('${controlli.length} voci'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in groupControlliByAsset(controlli, controlLabels)) ...[
                if (group.assetId != null) _AssetGroupHeader(assetId: group.assetId!),
                _RuleList(
                  children: [
                    for (final c in group.rows)
                      _ControlloAnswerRow(controllo: c, flat: controlLabels[c.controlId]),
                  ],
                ),
                if (group != groupControlliByAsset(controlli, controlLabels).last)
                  const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),

        // ── Documenti & mappa: where it happened and what was attached ──
        DetailSectionData(
          title: 'Documenti & mappa',
          trailing: photoAllegati.isEmpty
              ? null
              : DetailSectionMeta('${photoAllegati.length} file'),
          isEmpty:
              locationAddress.isEmpty &&
              photoAllegati.isEmpty &&
              !hasCustomerSignature &&
              !hasCustomerAbsence &&
              !hasTechnicianSignature,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The hero states the site; this shows where it is.
              if (locationAddress.isNotEmpty) ...[
                GeoMapCard(
                  pointAsync: ref.watch(locationGeocodedLocationProvider(locationId)),
                  address: locationAddress,
                ),
                gap,
              ],

              // ── Foto: inline attachment rows with a thumbnail in the icon box ──
              if (photoAllegati.isNotEmpty) ...[
                _MonoLabel('Foto (${photoAllegati.length})'),
                const SizedBox(height: AppSpacing.xs),
                for (final a in photoAllegati)
                  _PhotoRow(dio: dio, allegato: a, isLast: a == photoAllegati.last),
                gap,
              ],

              // ── Firma cliente ─────────────────────────────────────────────
              if (hasCustomerSignature) ...[
                const _MonoLabel('Firma cliente'),
                const SizedBox(height: AppSpacing.xs),
                // The acceptance text the customer signed against (Report.customerSignoffText).
                if (draft.customerSignoffText != null && draft.customerSignoffText!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      draft.customerSignoffText!,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: context.colors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
                _SignatureBlock(
                  dio: dio,
                  allegato: customerSignatureAllegato,
                  signedAt:
                      draft.customerSignoffAt ??
                      draft.inviatoAt ??
                      draft.updatedAt ??
                      draft.createdAt,
                ),
                gap,
              ],

              // ── Senza firma cliente (motivo) ──────────────────────────────
              // Why the customer could not sign, instead of a blank as if it were forgotten.
              if (hasCustomerAbsence) ...[
                const _MonoLabel('Firma cliente'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Senza firma cliente — ${customerAbsenceReason.summaryLabel}',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                  ),
                ),
                if (draft.customerSignatureAbsenceNote?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  Text(
                    draft.customerSignatureAbsenceNote!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: context.colors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                gap,
              ],

              // ── Firma tecnico ─────────────────────────────────────────────
              if (hasTechnicianSignature) ...[
                const _MonoLabel('Firma tecnico'),
                const SizedBox(height: AppSpacing.xs),
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
            ],
          ),
        ),
      ],
    );
  }
}

/// `dd/MM/yyyy HH:mm` for a timeline event.
String _eventTime(DateTime t) => DateFormat('dd/MM/yyyy HH:mm', 'it').format(t.toLocal());

/// The muted part of the hero's kicker: `Oggi` for a report touched today, else its date.
String _kickerContext(DateTime d) {
  final t = d.toLocal();
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) return 'Oggi';
  return DateFormat('dd/MM/yyyy', 'it').format(t);
}

/// Mono 8px uppercase label — the mockup's small caps for a group inside a section.
class _MonoLabel extends StatelessWidget {
  const _MonoLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: AppTextStyles.docCode.copyWith(
      fontSize: 8,
      letterSpacing: 0.64,
      color: context.colors.inkMuted,
    ),
  );
}

/// A written field (Descrizione, Diagnosi…): mono label over 12px body text, no card.
class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonoLabel(label),
        const SizedBox(height: 4),
        Text(
          text,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 12,
            height: 1.5,
            color: context.colors.ink,
          ),
        ),
      ],
    );
  }
}

/// A list ruled top and bottom with rows separated by 1px rules — rules, not cards.
class _RuleList extends StatelessWidget {
  const _RuleList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rule = BorderSide(color: context.colors.borderLight);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: rule, bottom: rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.borderLight),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row of a [_RuleList]: muted icon, 11.5/600 title, optional 10.5 muted subtitle and a mono
/// trailing value.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.icon, required this.title, this.subtitle, this.trailing});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 10.5,
                      height: 1.35,
                      color: colors.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null && trailing!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              trailing!,
              style: AppTextStyles.docCode.copyWith(fontSize: 8.5, color: colors.inkMuted),
            ),
          ],
        ],
      ),
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

  await ref.read(reportPdfShareProvider)(file);
}

/// Runs the hero's Scarica PDF action behind the shared per-report guard: the provider disables
/// both PDF actions while either runs, and the re-entry check covers a tap that lands before the
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

/// Runs the hero's Condividi action behind the same shared per-report guard as
/// [_downloadReportPdfFromHero], because both resolve the same cached file.
Future<void> _shareReportPdfFromHero(BuildContext context, WidgetRef ref, String reportId) async {
  final busy = _rapportinoPdfBusyProvider(reportId);
  if (ref.read(busy)) return;
  ref.read(busy.notifier).state = true;
  try {
    await _shareReportPdf(context, ref, reportId);
  } finally {
    if (context.mounted) ref.read(busy.notifier).state = false;
  }
}

/// Creates a fresh local draft from a rejected report and opens it in the editor.
///
/// A rework clones this report's data into a brand-new local draft — see createReworkDraft's own
/// doc comment for why it can't simply reopen this same report id (the backend's state machine
/// only allows Bozza → Inviato).
Future<void> _reworkReport(BuildContext context, WidgetRef ref, DraftReport draft) async {
  final busy = _rapportinoReworkBusyProvider(draft.id);
  if (ref.read(busy)) return;
  ref.read(busy.notifier).state = true;
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
    if (context.mounted) ref.read(busy.notifier).state = false;
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

/// Builds the report's hero: kicker, title and subtitle above the card, then the card's state label,
/// hours, copy line and the actions this read-only document actually offers. PDF/share are the
/// normal pair; a rejected report swaps the primary for Rilavora, the one action that gives the
/// technician a way forward. Cliente/Sede/Tecnico live in the Sintesi facts grid.
DetailHeroData _buildRapportinoHero(
  BuildContext context,
  WidgetRef ref,
  DraftReport draft, {
  required String techNames,
}) {
  final rejected = rapportinoIsRejected(draft);
  final pdfBusy = ref.watch(_rapportinoPdfBusyProvider(draft.id));
  final reworkBusy = ref.watch(_rapportinoReworkBusyProvider(draft.id));
  // Rielabora mints a new editable draft, so it is a report write. A read-only seat still sees
  // the rejected report and keeps the PDF action; it just cannot start the rework.
  final canWriteReport = capabilityHeld(
    ref.watch(cachedEntitlementProvider).value,
    'rapportini.report.write',
  );
  final oreLabel = ref.watch(rapportinoOreProvider(draft.id));
  final numero = draft.numero;
  final touched = draft.updatedAt ?? draft.createdAt;
  final emphasis = TextStyle(fontWeight: FontWeight.w700, color: context.colors.ink);
  final site = _locationLabel(context, ref, draft);

  return DetailHeroData(
    variant: DetailHeroVariant.operational,
    title: draft.title,
    kicker: numero == null || numero.isEmpty ? 'Rapportino' : 'Rapportino · $numero',
    kickerContext: _kickerContext(touched),
    subtitle: '${_customerLabel(context, ref, draft)} · $site\n$techNames',
    status: DetailStatus(label: rapportinoStatusLabel(draft)),
    liveValue: oreLabel == '—' ? null : Text(oreLabel),
    heroCopy: Text.rich(
      TextSpan(
        children: rejected
            ? [
                const TextSpan(text: 'Respinto '),
                TextSpan(text: "dall'ufficio", style: emphasis),
                const TextSpan(text: '. Rilavora per correggerlo e reinviarlo.'),
              ]
            : [
                const TextSpan(text: 'Aggiornato il '),
                TextSpan(text: _eventTime(touched), style: emphasis),
              ],
      ),
    ),
    primaryAction: rejected && canWriteReport
        ? DetailAction(
            label: 'Rilavora',
            icon: const Icon(LucideIcons.penTool, size: 16),
            enabled: !reworkBusy,
            disabledReason: reworkBusy ? 'Rielaborazione in corso…' : null,
            onPressed: reworkBusy ? null : () => _reworkReport(context, ref, draft),
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
        enabled: !pdfBusy,
        disabledReason: pdfBusy ? 'Download in corso…' : null,
        onPressed: pdfBusy ? null : () => _shareReportPdfFromHero(context, ref, draft.id),
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
// Photo rows (Step 6 "Allegati")
// ══════════════════════════════════════════════════════════════════════════════

/// One photo as an inline attachment row, local-first (same as the editor's own StepMaterialiFold
/// grid) so an offline-captured, not-yet-uploaded photo still shows its thumbnail in the 28px icon
/// box. cacheWidth/cacheHeight because a camera photo decodes at full sensor resolution.
class _PhotoRow extends ConsumerWidget {
  const _PhotoRow({required this.dio, required this.allegato, required this.isLast});

  final Dio dio;
  final ReportAllegatiData allegato;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = allegato;
    final hasLocal = a.storagePath.isNotEmpty && File(a.storagePath).existsSync();
    final contentRef = (
      allegatoId: a.id,
      contentHash: a.contentHash,
      sizeBytes: a.sizeBytes,
      url: a.url,
    );
    final cachePx = (28 * MediaQuery.devicePixelRatioOf(context)).round();
    const fallback = Icon(LucideIcons.imageOff);

    return DetailAttachmentRow(
      name: a.fileName,
      size: _formatBytes(a.sizeBytes),
      isLast: isLast,
      icon: hasLocal
          ? Image.file(
              File(a.storagePath),
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              cacheWidth: cachePx,
              cacheHeight: cachePx,
              errorBuilder: (_, _, _) => fallback,
            )
          : a.url.isNotEmpty
          ? AttachmentThumbnail(
              attachment: contentRef,
              cacheWidth: cachePx,
              cacheHeight: cachePx,
              placeholder: fallback,
            )
          : fallback,
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
    );
  }
}

String? _formatBytes(int bytes) {
  if (bytes <= 0) return null;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    // A device that never synced this asset still names the block honestly rather than dropping
    // the grouping or repeating the GUID.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _MonoLabel(name ?? 'Attrezzatura'),
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

    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(LucideIcons.clipboardCheck, size: 14, color: colors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groupPath != null && groupPath.isNotEmpty)
                  Text(
                    groupPath,
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 10.5, color: colors.inkMuted),
                  ),
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (valueLabel != null) ...[
            const SizedBox(width: 10),
            Text(
              valueLabel,
              style: AppTextStyles.docCode.copyWith(fontSize: 8.5, color: colors.inkMuted),
            ),
          ],
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
