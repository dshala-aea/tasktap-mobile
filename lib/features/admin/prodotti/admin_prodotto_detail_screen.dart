// dart format width=100
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';

/// Admin prodotto assistenza detail — read-only with edit FAB.
class AdminProdottoDetailScreen extends StatelessWidget {
  const AdminProdottoDetailScreen({super.key, required this.prodotto});

  final Map<String, dynamic> prodotto;

  @override
  Widget build(BuildContext context) {
    final name = prodotto['name'] as String? ?? '';
    final description = prodotto['description'] as String? ?? '';
    final serialNumber = prodotto['serialNumber'] as String? ?? '';
    final notes = prodotto['notes'] as String? ?? '';
    final warrantyDate = prodotto['warrantyExpiryDate'] as String?;
    final warrantyLabel = warrantyDate != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(warrantyDate))
        : '—';

    return Scaffold(
      backgroundColor: AppColors.BG2,
      floatingActionButton: AppFab(
        icon: LucideIcons.pencil,
        tooltip: 'Modifica',
        onPressed: () async {
          await context.push<bool>(
            '/altro/prodotti/${prodotto['id']}/modifica',
            extra: prodotto,
          );
        },
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: name,
              subtitle: serialNumber.isNotEmpty ? 'S/N: $serialNumber' : '',
              showBack: true,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Nome', value: name),
                  _InfoRow(
                      label: 'Descrizione',
                      value: description.isNotEmpty ? description : '—'),
                  _InfoRow(
                      label: 'Numero di serie',
                      value: serialNumber.isNotEmpty ? serialNumber : '—'),
                  _InfoRow(
                      label: 'Scadenza garanzia',
                      value: warrantyLabel),
                  _InfoRow(
                      label: 'Note',
                      value: notes.isNotEmpty ? notes : '—',
                      showDivider: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.MUTED,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
