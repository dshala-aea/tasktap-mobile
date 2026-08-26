// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin report detail — read-only with state transition actions.
class AdminReportDetailScreen extends ConsumerWidget {
  const AdminReportDetailScreen({super.key, required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  StatusPill(stato: stato, outlined: true),
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
              child: VetroCard(
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
                child: VetroCard(
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
                child: VetroCard(
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
              child: _StateTransitionButtons(
                stato: stato,
                onTransition: (action) => _handleAction(context, ref, action),
              ),
            ),
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    final api = ref.read(adminApiClientProvider);
    final reportId = report['id'] as String;

    try {
      switch (action) {
        case 'controlla':
          await api.controllaReport(reportId);
          break;
        case 'fattura':
          await api.fatturaReport(reportId);
          break;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stato aggiornato')));
        // Pop to refresh list
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile salvare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    }
  }
}

class _StateTransitionButtons extends StatelessWidget {
  const _StateTransitionButtons({required this.stato, required this.onTransition});

  final String stato;
  final ValueChanged<String> onTransition;

  @override
  Widget build(BuildContext context) {
    if (stato == 'Inviato') {
      return VetroButton(
        label: 'Segna come controllato',
        icon: const Icon(LucideIcons.checkCircle, size: 18),
        onPressed: () => onTransition('controlla'),
      );
    }
    if (stato == 'Controllato') {
      return VetroButton(
        label: 'Segna come fatturato',
        icon: const Icon(LucideIcons.receipt, size: 18),
        onPressed: () => onTransition('fattura'),
      );
    }
    return const SizedBox.shrink();
  }
}
