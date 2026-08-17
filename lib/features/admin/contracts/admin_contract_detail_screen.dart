// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Admin contract detail — read-only with edit FAB.
class AdminContractDetailScreen extends StatelessWidget {
  const AdminContractDetailScreen({super.key, required this.contract});

  final Map<String, dynamic> contract;

  @override
  Widget build(BuildContext context) {
    final name = contract['name'] as String? ?? '';
    final description = contract['description'] as String? ?? '';
    final notes = contract['notes'] as String? ?? '';
    final price = contract['price'] as num?;
    final startDate = contract['startDate'] as String?;
    final endDate = contract['endDate'] as String?;
    final frequencyValue = contract['frequencyValue'] as int? ?? 1;
    final frequencyUnit = contract['frequencyUnit'] as int? ?? 1;

    final startLabel = startDate != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(startDate))
        : '—';
    final endLabel = endDate != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(endDate))
        : 'Nessuna data fine';
    final priceLabel = price != null ? '€${price.toStringAsFixed(2)}' : '—';
    final freqLabel = '$frequencyValue ${_frequencyUnitLabel(frequencyUnit)}';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>(
              '/altro/contratti/${contract['id']}/modifica',
              extra: contract,
            );
          },
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: ScreenHeader(title: name, showBack: true)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Nome', value: name),
                  _InfoRow(label: 'Descrizione', value: description.isNotEmpty ? description : '—'),
                  _InfoRow(label: 'Data inizio', value: startLabel),
                  _InfoRow(label: 'Data fine', value: endLabel),
                  _InfoRow(label: 'Frequenza', value: freqLabel),
                  _InfoRow(label: 'Prezzo', value: priceLabel),
                  _InfoRow(
                    label: 'Note',
                    value: notes.isNotEmpty ? notes : '—',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }

  String _frequencyUnitLabel(int unit) => switch (unit) {
    0 => 'giorni',
    1 => 'mesi',
    2 => 'anni',
    _ => 'mesi',
  };
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.showDivider = true});

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: context.colors.inkMuted, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}
