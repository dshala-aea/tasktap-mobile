// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/prodotti/${prodotto['id']}/modifica', extra: prodotto);
          },
        ),
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
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Column(
                  children: [
                    KeyVal(label: 'Nome', value: name),
                    KeyVal(label: 'Descrizione', value: description.isNotEmpty ? description : '—'),
                    KeyVal(
                      label: 'Numero di serie',
                      value: serialNumber.isNotEmpty ? serialNumber : '—',
                    ),
                    KeyVal(label: 'Scadenza garanzia', value: warrantyLabel),
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
}
