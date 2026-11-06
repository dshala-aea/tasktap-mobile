// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/detail/detail_activity_timeline.dart';
import '../../../core/widgets/detail/detail_attachment_row.dart';
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/dio_client.dart';
import '../../../data/attachments/attachment_content_cache.dart';
import '../../../data/local/app_database.dart';
import '../../../data/reports/report_pdf_cache.dart';
import '../../../data/sync/connectivity_provider.dart' show isOnlineProvider;
import '../../../presentation/providers/schedule_providers.dart'
    show colleagueNameProvider, customerByIdProvider, locationByIdProvider, ticketByIdProvider;
import '../../cantiere/cantiere_providers.dart' show cantiereByIdProvider;
import '../../rapportino/rapportino_list_providers.dart' show rapportinoAllegatiProvider;
import '../admin_api_client.dart';
import 'admin_report_list_screen.dart' show adminReportsProvider;

/// Admin report detail — read-only with state transition actions.
///
/// Rebuilt on the wave-0 detail shell: SummaryHero with `Apri PDF` as its primary action, then
/// Documenti → Sintesi → Attività. Stateful (not just `ConsumerWidget`) because the transition
/// must keep the screen showing the report's new status (`_report` is the mutable local copy) and
/// because the Fattura action must leave its XML download reachable here.
class AdminReportDetailScreen extends ConsumerStatefulWidget {
  const AdminReportDetailScreen({super.key, required this.report});

  final Map<String, dynamic> report;

  @override
  ConsumerState<AdminReportDetailScreen> createState() => _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends ConsumerState<AdminReportDetailScreen> {
  late Map<String, dynamic> _report;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final stato = report['stato'] as String? ?? 'Bozza';
    final createdAt = _parseDate(report['createdAt']);
    final inviatoAt = _parseDate(report['inviatoAt']);
    final controllatoAt = _parseDate(report['controllatoAt']);
    final fatturatoAt = _parseDate(report['fatturatoAt']);
    final details = (report['details'] as String?)?.trim() ?? '';
    final diagnosi = (report['diagnosi'] as String?)?.trim() ?? '';
    final soluzione = (report['soluzione'] as String?)?.trim() ?? '';
    final technicianNotes = (report['technicianNotes'] as String?)?.trim() ?? '';

    final title = (report['title'] as String?)?.trim();
    final numero = (report['numero'] as String?)?.trim();
    final hasNumero = numero != null && numero.isNotEmpty;
    final entityTitle = (title != null && title.isNotEmpty)
        ? (hasNumero && !title.contains(numero) ? '$title · $numero' : title)
        : (hasNumero ? 'Rapportino $numero' : 'Rapportino');

    // Local only: a report's photos/signature images, when this device holds them. No network read
    // at open — a report synced without its allegati simply has no photo rows.
    final reportId = report['id'] as String?;
    final List<ReportAllegatiData> allegati = reportId == null
        ? const []
        : ref.watch(rapportinoAllegatiProvider(reportId)).valueOrNull ?? const [];
    final signatureIds = {
      report['customerSignatureAllegatoId'],
      report['technicianSignatureAllegatoId'],
    }..removeWhere((id) => id == null);
    final photos = allegati.where((a) => !signatureIds.contains(a.id)).toList();

    final customerId = report['customerId'] as String?;
    final locationId = report['locationId'] as String?;
    final ticketId = report['ticketId'] as String?;
    final cantiereId = report['cantiereId'] as String?;
    final insertedUserId = report['insertedUserId'] as String?;

    final customer = customerId == null
        ? null
        : ref.watch(customerByIdProvider(customerId)).valueOrNull?.companyName;
    final location = locationId == null
        ? null
        : ref.watch(locationByIdProvider(locationId)).valueOrNull?.name;
    final ticket = ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(ticketId)).valueOrNull?.title;
    final cantiere = cantiereId == null
        ? null
        : ref.watch(cantiereByIdProvider(cantiereId)).valueOrNull?.name;
    final technician = insertedUserId == null
        ? null
        : ref.watch(colleagueNameProvider(insertedUserId)).valueOrNull;

    final period = _periodLabel(report);
    final ore = _hoursLabel(report);
    final dateLabel = createdAt == null
        ? '—'
        : DateFormat('dd/MM/yyyy HH:mm', 'it').format(createdAt.toLocal());

    final heroFacts = [
      if (customer != null && customer.trim().isNotEmpty) customer,
      ?period,
      ?ore,
    ].join(' · ');

    final hasCustomerSignature = report['customerSignatureAllegatoId'] != null;
    final hasTechnicianSignature = report['technicianSignatureAllegatoId'] != null;
    final customerAbsenceReason = report['customerSignatureAbsenceReason'];
    final customerSignatureLabel = hasCustomerSignature
        ? 'Firmato'
        : (customerAbsenceReason != null ? 'Senza firma' : 'Mancante');

    final signatures = <({String name, String value})>[
      (name: 'Firma cliente', value: customerSignatureLabel),
      (name: 'Firma tecnico', value: hasTechnicianSignature ? 'Firmato' : 'Mancante'),
    ];
    final documentCount = 1 + signatures.length + photos.length;

    final facts = <DetailFact>[
      if (location != null && location.trim().isNotEmpty)
        DetailFact(label: 'Sede', value: location),
      if (ticket != null && ticket.trim().isNotEmpty) DetailFact(label: 'Ticket', value: ticket),
      if (cantiere != null && cantiere.trim().isNotEmpty)
        DetailFact(label: 'Cantiere', value: cantiere),
      if (technician != null && technician.trim().isNotEmpty)
        DetailFact(label: 'Tecnico', value: technician),
      DetailFact(label: 'Creato il', value: dateLabel),
    ];

    final timeline = <DetailActivityEvent>[
      if (inviatoAt != null)
        DetailActivityEvent(
          time: _eventTime(inviatoAt),
          title: 'Inviato',
          tone: DetailEventTone.good,
        ),
      if (controllatoAt != null)
        DetailActivityEvent(
          time: _eventTime(controllatoAt),
          title: 'Controllato',
          tone: DetailEventTone.warn,
        ),
      if (fatturatoAt != null)
        DetailActivityEvent(
          time: _eventTime(fatturatoAt),
          title: 'Fatturato',
          tone: DetailEventTone.good,
        ),
    ];

    final canTransition = stato == 'Inviato' || stato == 'Controllato';
    final canDownloadXml = stato == 'Fatturato';
    return DetailScaffold(
      screenTitle: 'Report admin',
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · documento',
        kicker: 'Summary · documento',
        title: entityTitle,
        status: DetailStatus(label: stato),
        subtitle: heroFacts.isEmpty ? null : heroFacts,
        primaryAction: DetailAction(
          label: 'Apri PDF',
          icon: const Icon(LucideIcons.fileText, size: 14),
          enabled: !_busy,
          onPressed: _openPdf,
        ),
      ),
      sections: [
        DetailSectionData(
          title: 'Documenti',
          trailing: DetailSectionMeta(
            documentCount == 1 ? '1 documento' : '$documentCount documenti',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailAttachmentRow(
                name: 'PDF rapporto',
                icon: const Icon(LucideIcons.fileText, size: 14),
                size: 'PDF',
                onTap: _busy ? null : _openPdf,
              ),
              for (var i = 0; i < signatures.length; i++)
                DetailAttachmentRow(
                  name: signatures[i].name,
                  icon: const Icon(LucideIcons.pencil, size: 14),
                  size: signatures[i].value,
                  isLast: 1 + i == documentCount - 1,
                ),
              for (var i = 0; i < photos.length; i++)
                _PhotoRow(
                  photo: photos[i],
                  isLast: 1 + signatures.length + i == documentCount - 1,
                  onOpen: () => _openPhoto(photos[i]),
                ),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Sintesi',
          trailing: DetailSectionMeta(facts.length == 1 ? '1 campo' : '${facts.length} campi'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailFactsGrid(facts: facts),
              if (details.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.base),
                _TextBlock(label: 'Descrizione', text: details),
              ],
              if (diagnosi.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.base),
                _TextBlock(label: 'Diagnosi', text: diagnosi),
              ],
              if (soluzione.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.base),
                _TextBlock(label: 'Soluzione', text: soluzione),
              ],
              if (technicianNotes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.base),
                _TextBlock(label: 'Note tecnico', text: technicianNotes),
              ],
            ],
          ),
        ),
        DetailSectionData(
          title: 'Attività',
          trailing: timeline.isEmpty ? null : DetailSectionMeta('storico'),
          isEmpty: timeline.isEmpty && !canTransition && !canDownloadXml,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (timeline.isNotEmpty) DetailActivityTimeline(events: timeline),
              if (canTransition) ...[
                if (timeline.isNotEmpty) const SizedBox(height: AppSpacing.base),
                _StateTransitionButtons(stato: stato, busy: _busy, onTransition: _handleAction),
              ],
              // Fatturato reports keep an XML re-download available, not just the moment
              // right after the transition — an office user coming back to this screen
              // later still needs a copy of the invoice.
              if (canDownloadXml) ...[
                if (timeline.isNotEmpty) const SizedBox(height: AppSpacing.base),
                DetailHeroButton(
                  label: _busy ? 'Download in corso...' : 'Scarica XML fattura',
                  icon: _busy ? null : const Icon(LucideIcons.download, size: 14),
                  variant: DetailHeroButtonVariant.secondary,
                  onPressed: _busy ? null : _downloadFatturaXml,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref
          .read(reportPdfCacheProvider)
          .resolve(_report['id'] as String, online: ref.read(isOnlineProvider));
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        showAppToast(
          context,
          message: 'Impossibile aprire il PDF: ${result.message}',
          tone: ToastTone.error,
        );
      }
    } on ReportPdfUnavailable catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: switch (e.reason) {
          ReportPdfFailure.notDownloaded =>
            'PDF non ancora scaricato su questo telefono — serve la connessione la prima volta.',
          ReportPdfFailure.downloadFailed => 'Impossibile scaricare il PDF. Riprova più tardi.',
        },
        tone: e.reason == ReportPdfFailure.notDownloaded ? ToastTone.warning : ToastTone.error,
      );
    } catch (_) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile scaricare il PDF.', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPhoto(ReportAllegatiData photo) async {
    final hasLocal = photo.storagePath.isNotEmpty && File(photo.storagePath).existsSync();
    await openAttachment(
      context,
      dio: ref.read(dioProvider),
      fileName: photo.fileName,
      contentType: photo.contentType,
      url: photo.url,
      localPath: hasLocal ? photo.storagePath : null,
      cache: ref.read(attachmentContentCacheProvider),
      contentRef: photo.url.isEmpty
          ? null
          : (
              allegatoId: photo.id,
              contentHash: photo.contentHash,
              sizeBytes: photo.sizeBytes,
              url: photo.url,
            ),
    );
  }

  Future<void> _handleAction(String action) async {
    final api = ref.read(adminApiClientProvider);
    final reportId = _report['id'] as String;

    setState(() => _busy = true);
    try {
      switch (action) {
        case 'controlla':
          await api.controllaReport(reportId);
          if (mounted) {
            setState(
              () => _report = {
                ..._report,
                'stato': 'Controllato',
                'controllatoAt': DateTime.now().toUtc().toIso8601String(),
              },
            );
          }
          break;
        case 'fattura':
          await api.fatturaReport(reportId);
          if (mounted) {
            setState(
              () => _report = {
                ..._report,
                'stato': 'Fatturato',
                'fatturatoAt': DateTime.now().toUtc().toIso8601String(),
              },
            );
          }
          break;
      }
      // The list screen underneath stays mounted with its already-fetched data, so it kept
      // showing the pre-transition stato until a manual pull-to-refresh. Invalidate the whole
      // family: this screen doesn't know which stato filter the list currently has applied, and
      // the affected report could match any of them (or none, if the transition just moved it
      // out of the current filter). Deliberately does NOT pop back to the list anymore — for
      // 'fattura' specifically, the office user's very next action is usually downloading the
      // XML this same screen now offers; popping away first only to navigate back in was the
      // reported bug.
      ref.invalidate(adminReportsProvider);
      if (mounted) {
        showAppToast(context, message: 'Stato aggiornato', tone: ToastTone.success);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadFatturaXml() async {
    final api = ref.read(adminApiClientProvider);
    final reportId = _report['id'] as String;
    final numero = _report['numero'] as String? ?? reportId;

    setState(() => _busy = true);
    try {
      final bytes = await api.fatturaXml(reportId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fattura-$numero.xml');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile scaricare l\'XML.', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _eventTime(DateTime value) =>
      DateFormat('dd/MM/yyyy HH:mm', 'it').format(value.toLocal());

  static String? _periodLabel(Map<String, dynamic> report) {
    final date = _parseDate(report['startedAt']) ?? _parseDate(report['createdAt']);
    if (date == null) return null;
    final month = DateFormat('MMMM', 'it').format(date.toLocal());
    return month.isEmpty ? null : '${month[0].toUpperCase()}${month.substring(1)}';
  }

  static String? _hoursLabel(Map<String, dynamic> report) {
    final start = _parseDate(report['startedAt']);
    final end = _parseDate(report['endedAt']);
    if (start == null || end == null || end.isBefore(start)) return null;
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return null;
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '$hours ${hours == 1 ? 'ora' : 'ore'}';
    return '${hours}h ${rest}m';
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8,
            letterSpacing: 0.64,
            color: context.colors.inkMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 11.5,
            height: 1.45,
            color: context.colors.ink,
          ),
        ),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.photo, required this.isLast, required this.onOpen});

  final ReportAllegatiData photo;
  final bool isLast;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return DetailAttachmentRow(
      name: photo.fileName,
      icon: const Icon(LucideIcons.camera, size: 14),
      size: _formatBytes(photo.sizeBytes),
      isLast: isLast,
      onTap: onOpen,
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
}

class _StateTransitionButtons extends StatelessWidget {
  const _StateTransitionButtons({
    required this.stato,
    required this.busy,
    required this.onTransition,
  });

  final String stato;
  final bool busy;
  final ValueChanged<String> onTransition;

  @override
  Widget build(BuildContext context) {
    if (stato == 'Inviato') {
      return DetailHeroButton(
        label: 'Segna come controllato',
        icon: const Icon(LucideIcons.checkCircle, size: 14),
        onPressed: busy ? null : () => onTransition('controlla'),
      );
    }
    if (stato == 'Controllato') {
      return DetailHeroButton(
        label: 'Segna come fatturato',
        icon: const Icon(LucideIcons.receipt, size: 14),
        onPressed: busy ? null : () => onTransition('fattura'),
      );
    }
    return const SizedBox.shrink();
  }
}
