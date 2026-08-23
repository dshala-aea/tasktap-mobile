// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Column(
                  children: [
                    KeyVal(label: 'Nome', value: name),
                    KeyVal(label: 'Descrizione', value: description.isNotEmpty ? description : '—'),
                    KeyVal(label: 'Data inizio', value: startLabel),
                    KeyVal(label: 'Data fine', value: endLabel),
                    KeyVal(label: 'Frequenza', value: freqLabel),
                    KeyVal(label: 'Prezzo', value: priceLabel),
                    KeyVal(label: 'Note', value: notes.isNotEmpty ? notes : '—', showDivider: false),
                  ],
                ),
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
