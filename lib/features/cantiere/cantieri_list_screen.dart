// dart format width=100
// lib/features/cantiere/cantieri_list_screen.dart
//
// Technician-facing list of the operator's own cantieri (worksites) — the Cantieri tab.
// Deliberately not a reuse of admin_cantiere_list_screen.dart: that one is CRUD-oriented,
// office/admin-only. This one reads cantieriProvider exactly as CantiereTimbraScreen's picker
// already does — already scoped server-side to the technician's own CantiereAssignment rows
// (falling back to all active cantieri when they have none), so no new filtering logic here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/sync/sync_service.dart';
import '../timbra/cantiere_timbra_screen.dart' show cantieriProvider;

class CantieriListScreen extends ConsumerWidget {
  const CantieriListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantieriAsync = ref.watch(cantieriProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.base,
                AppSpacing.pagePadding,
                AppSpacing.sm,
              ),
              child: ScreenHeader(title: 'Cantieri'),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(syncProvider.notifier).performSync(),
                child: cantieriAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => const UnavailableState(
                    icon: LucideIcons.hardHat,
                    titolo: 'Impossibile caricare i cantieri',
                    motivo: 'Trascina in basso per aggiornare, oppure riprova tra poco.',
                  ),
                  data: (cantieri) {
                    if (cantieri.isEmpty) {
                      return const UnavailableState(
                        icon: LucideIcons.hardHat,
                        titolo: 'Nessun cantiere disponibile',
                        motivo:
                            'Non risultano cantieri sincronizzati su questo dispositivo. Trascina '
                            'in basso per aggiornare, oppure riprova tra poco.',
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                      itemCount: cantieri.length,
                      itemBuilder: (context, i) {
                        final c = cantieri[i];
                        return ListRow(
                          leading: Icon(LucideIcons.hardHat, color: context.colors.inkMuted),
                          title: c.name,
                          subtitle: c.address,
                          showDivider: i != cantieri.length - 1,
                          onTap: () => context.push(AppRoutes.cantieriDetailPath(c.id)),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
