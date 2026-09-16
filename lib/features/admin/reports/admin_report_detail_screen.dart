// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../admin_api_client.dart';
import 'admin_report_list_screen.dart' show adminReportsProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin report detail — read-only with state transition actions.
///
/// Stateful (not just `ConsumerWidget`) because the "Fattura" action must stay on this screen
/// showing the report's new Fatturato status and an XML download action, rather than popping
/// back to the list the moment it succeeds — `_report` is the mutable local copy that lets the
/// transition update what's on screen without a full re-fetch.
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
    final title = report['title'] as String? ?? '—';
    final stato = report['stato'] as String? ?? 'Bozza';
    final createdAt = report['createdAt'] as String?;
    final details = report['details'] as String? ?? '';
    final technicianNotes = report['technicianNotes'] as String? ?? '';
    final inviatoAt = report['inviatoAt'] as String?;
    final controllatoAt = report['controllatoAt'] as String?;
    final fatturatoAt = report['fatturatoAt'] as String?;

    final dateLabel = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'it').format(DateTime.parse(createdAt).toLocal())
        : '—';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(title: title, showBack: true),
      body: CustomScrollView(
        slivers: [
          // ── Status header ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.base,
              ),
              child: Row(
                children: [
                  StatusPill(stato: stato),
                  const Spacer(),
                  Text(
                    dateLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: context.colors.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          // ── Info card ───────────────────────────────────────────────
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
                  children: [
                    KeyVal(label: 'Stato', value: stato),
                    KeyVal(label: 'Data creazione', value: dateLabel),
                    if (inviatoAt != null)
                      KeyVal(
                        label: 'Inviato il',
                        value: DateFormat(
                          'dd/MM/yyyy HH:mm',
                          'it',
                        ).format(DateTime.parse(inviatoAt).toLocal()),
                      ),
                    if (controllatoAt != null)
                      KeyVal(
                        label: 'Controllato il',
                        value: DateFormat(
                          'dd/MM/yyyy HH:mm',
                          'it',
                        ).format(DateTime.parse(controllatoAt).toLocal()),
                      ),
                    if (fatturatoAt != null)
                      KeyVal(
                        label: 'Fatturato il',
                        value: DateFormat(
                          'dd/MM/yyyy HH:mm',
                          'it',
                        ).format(DateTime.parse(fatturatoAt).toLocal()),
                        showDivider: false,
                      ),
                  ],
                ),
              ),
            ),
          ),
          // ── Details ─────────────────────────────────────────────────
          if (details.isNotEmpty)
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
                      const SectionTitle(title: 'Dettagli'),
                      const SizedBox(height: 4),
                      Text(details, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
          // ── Technician notes ────────────────────────────────────────
          if (technicianNotes.isNotEmpty)
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
                      const SectionTitle(title: 'Note tecnico'),
                      const SizedBox(height: 4),
                      Text(technicianNotes, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
          // ── State transition buttons ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                children: [
                  _StateTransitionButtons(stato: stato, busy: _busy, onTransition: _handleAction),
                  // Fatturato reports keep an XML re-download available, not just the moment
                  // right after the transition — an office user coming back to this screen
                  // later still needs a copy of the invoice.
                  if (stato == 'Fatturato') ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: _busy ? 'Download in corso...' : 'Scarica XML fattura',
                      icon: _busy ? null : const Icon(LucideIcons.download, size: 18),
                      isLoading: _busy,
                      onPressed: _busy ? null : _downloadFatturaXml,
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
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
            setState(() => _report = {..._report, 'stato': 'Controllato'});
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
      return AppButton(
        label: 'Segna come controllato',
        icon: const Icon(LucideIcons.checkCircle, size: 18),
        onPressed: busy ? null : () => onTransition('controlla'),
      );
    }
    if (stato == 'Controllato') {
      return AppButton(
        label: 'Segna come fatturato',
        icon: const Icon(LucideIcons.receipt, size: 18),
        onPressed: busy ? null : () => onTransition('fattura'),
      );
    }
    return const SizedBox.shrink();
  }
}
