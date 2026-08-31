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
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/vetro_button.dart';
import '../../core/widgets/vetro_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/dio_client.dart';
import '../../data/local/app_database.dart';
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
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              ScreenHeader(title: 'Rapportino', showBack: true),
              EmptyState(
                icon: LucideIcons.xCircle,
                title: 'Errore',
                body: 'Impossibile caricare il rapportino.',
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
    // For openAttachment below (photo grid + signature) — see its own doc comment for why an
    // authenticated client is the right one, not a bare Dio.
    final dio = ref.watch(dioProvider);

    final statusLabel = rapportinoStatusLabel(draft);
    final dateLabel = DateFormat(
      'dd/MM/yyyy',
      'it',
    ).format((draft.updatedAt ?? draft.createdAt).toLocal());

    final staff = staffAsync.valueOrNull ?? [];
    final materiali = materialiAsync.valueOrNull ?? [];

    // rapportinoAllegatiProvider mixes photo and signature rows (both are just "allegati" for
    // the report) — split them here so the photo grid never shows a signature as if it were a
    // job photo, and _SignatureBlock gets the real row instead of resolving it itself.
    final allegati = allegatiAsync.valueOrNull ?? [];
    final signatureIds = {
      draft.customerSignatureAllegatoId,
      draft.technicianSignatureAllegatoId,
    }..removeWhere((id) => id == null);
    final photoAllegati = allegati.where((a) => !signatureIds.contains(a.id)).toList();
    final customerSignatureAllegato = draft.customerSignatureAllegatoId == null
        ? null
        : allegati.where((a) => a.id == draft.customerSignatureAllegatoId).firstOrNull;

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
                    child: VetroCard(
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
                                StatusPill(stato: statusLabel, outlined: true),
                                const SizedBox(width: 8),
                                Text(
                                  dateLabel,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, thickness: 1, color: context.colors.borderLight),
                          KeyVal(label: 'Sede', value: _locationLabel(context, ref, draft)),
                          KeyVal(label: 'Tecnico', value: tecnicoLabel),
                          KeyVal(label: 'Cliente', value: _customerLabel(context, ref, draft)),
                          KeyVal(label: 'Ore', value: oreLabel, showDivider: false),
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
                      child: VetroCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Descrizione'),
                            const SizedBox(height: 4),
                            Text(
                              draft.details!,
                              style: TextStyle(
                                fontFamily: 'Inter',
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

                // ── Materiali list ────────────────────────────────────────────
                if (materiali.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: VetroCard(
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
                      child: VetroCard(
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
                      child: VetroCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Firma cliente'),
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
                        Expanded(
                          child: VetroButton(
                            label: 'Scarica PDF',
                            icon: const Icon(LucideIcons.download, size: 16),
                            onPressed: () => _openReportPdf(context, ref, draft.id),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SharePdfButton(reportId: draft.id),
                      ],
                    ),
                  ),
                ),

                SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
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
Future<File?> _fetchPdfToTempFile(
  WidgetRef ref,
  String reportId,
  BuildContext context,
) async {
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
    final v = context.vetro;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: AppTappable(
        onTap: _busy ? null : _share,
        color: v.tint.withAlpha(31),
        borderRadius: BorderRadius.circular(16),
        semanticLabel: 'Condividi PDF',
        child: Center(
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: v.tint),
                )
              : Icon(LucideIcons.share2, size: 18, color: v.tint),
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
          VetroButton(
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
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.inkMuted),
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
                  ? Image.file(File(a.storagePath), errorBuilder: (_, _, _) => const _SignatureFallbackIcon())
                  : a.url.isNotEmpty
                  ? Image.network(a.url, errorBuilder: (_, _, _) => const _SignatureFallbackIcon())
                  : const _SignatureFallbackIcon(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Firmato il $signedLabel',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.inkMuted),
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
        (MediaQuery.sizeOf(context).width - AppSpacing.pagePadding * 2 - AppSpacing.base * 2 - 8 * 2) /
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
