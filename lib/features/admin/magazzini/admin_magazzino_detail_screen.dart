// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../ticket/steps/step_assegnazione.dart' show techniciansProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin magazzino detail — read-only with edit FAB. Gap 2 of the feature audit.
///
/// Travels the warehouse as `extra` from the list row that pushed here (same convention as
/// `AdminSquadraDetailScreen`/`AdminContractDetailScreen`) rather than re-fetching by id: there is
/// no `GET /api/magazzino/{id}` call site needed elsewhere, and the list already has the full
/// entity in hand.
class AdminMagazzinoDetailScreen extends ConsumerWidget {
  const AdminMagazzinoDetailScreen({super.key, required this.magazzino});

  final MagazzinoDto? magazzino;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mag = magazzino;
    if (mag == null) {
      return Scaffold(
        backgroundColor: context.colors.bg2,
        appBar: ScreenHeaderBar(title: 'Magazzino', showBack: true),
        body: const UnavailableState(
          titolo: 'Magazzino non disponibile',
          motivo: 'Torna all\'elenco e riapri questo magazzino.',
        ),
      );
    }

    final techniciansAsync = ref.watch(techniciansProvider);
    final assegnatoNome = mag.assegnatoUserId == null
        ? null
        : techniciansAsync.valueOrNull
              ?.cast<Map<String, dynamic>>()
              .where((t) => t['id'] == mag.assegnatoUserId)
              .map(
                (t) => t['displayName'] as String? ?? t['email'] as String? ?? mag.assegnatoUserId!,
              )
              .firstOrNull;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.fabSafeBottom),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/magazzino/magazzini/${mag.id}/modifica', extra: mag);
          },
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(title: mag.nome, subtitle: mag.tipo, showBack: true),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mag.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(bottom: AppSpacing.base),
                      decoration: BoxDecoration(
                        color: context.colors.red.withValues(alpha: 0.1),
                        borderRadius: AppRack.insetShape,
                      ),
                      child: Text(
                        'INATTIVO',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.colors.red,
                        ),
                      ),
                    ),
                  VetroCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    child: Column(
                      children: [
                        KeyVal(label: 'Nome', value: mag.nome),
                        KeyVal(label: 'Tipo', value: mag.tipo),
                        if (mag.isFurgone)
                          KeyVal(
                            label: 'Assegnato a',
                            value: assegnatoNome ?? mag.assegnatoUserId ?? '—',
                          ),
                        KeyVal(label: 'Indirizzo', value: mag.indirizzo ?? '—'),
                        KeyVal(label: 'Note', value: mag.note ?? '—', showDivider: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.fabSafeBottom)),
        ],
      ),
    );
  }
}
