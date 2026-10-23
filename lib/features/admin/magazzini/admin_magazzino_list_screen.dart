// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../magazzino/magazzino_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AdminMagazzinoListScreen — Gap 2 of the feature audit.
//
// Warehouse (Magazzino: Sede/Furgone) admin CRUD. Distinct from the materiali *catalogue* CRUD at
// `admin_materiale_*` — this manages the warehouses themselves (name, type, assigned technician,
// address), which had no mobile screen at all before this.
//
// The warehouse *catalogue* is mirrored: the sync payload carries `magazzini` (a whole-tenant
// replace, not a technician-scoped slice) and `magazziniProvider` reads it offline, so this list
// opens with no signal. What is deliberately live-only is anything stock-adjacent — giacenze and
// movimenti — see magazzino_api_client.dart's header comment for why.
// ══════════════════════════════════════════════════════════════════════════════

class AdminMagazzinoListScreen extends ConsumerWidget {
  const AdminMagazzinoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(magazziniProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(magazziniProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ScreenHeader(
                  title: 'Magazzini',
                  subtitle: async.valueOrNull != null
                      ? '${async.valueOrNull!.length} totali'
                      : null,
                  showBack: true,
                ),
              ),
              async.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xxxl),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  // A device that never synced has no mirror to fall back on — a retry button
                  // there asks for something the user cannot do until they are back online.
                  child: e is MagazziniOfflineException
                      ? const UnavailableState(
                          icon: LucideIcons.warehouse,
                          titolo: 'Magazzini non disponibili offline',
                          motivo:
                              'Questo dispositivo non ha ancora scaricato i magazzini. Apri '
                              'questa lista con una connessione attiva per averli anche offline.',
                        )
                      : ErrorState(onRetry: () => ref.invalidate(magazziniProvider)),
                ),
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter(
                        child: UnavailableState(
                          icon: LucideIcons.warehouse,
                          titolo: 'Nessun magazzino',
                          motivo:
                              'Non è ancora stato creato nessun magazzino. Usa il pulsante + per crearne uno.',
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) =>
                              _MagazzinoRow(magazzino: list[i], isLast: i == list.length - 1),
                          childCount: list.length,
                        ),
                      ),
              ),
              SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
            ],
          ),
        ),
      ),
      floatingActionButton: CapabilityGate(
        capability: 'magazzino.warehouse.write',
        child: Padding(
          // navClearance alone, not minus navGap — see admin_cantiere_list_screen.dart's comment
          // on this same change.
          padding: EdgeInsets.only(bottom: context.navClearance),
          child: AppFab(
            tooltip: 'Nuovo magazzino',
            onPressed: () => context.push('/altro/magazzino/magazzini/nuovo'),
          ),
        ),
      ),
    );
  }
}

class _MagazzinoRow extends StatelessWidget {
  const _MagazzinoRow({required this.magazzino, required this.isLast});

  final MagazzinoDto magazzino;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: const RowIconTile(icon: LucideIcons.warehouse),
      title: magazzino.nome,
      subtitle: magazzino.tipo,
      meta: !magazzino.isActive ? const StatusPill(stato: 'Inattivo', small: true) : null,
      showDivider: !isLast,
      onTap: () => context.push('/altro/magazzino/magazzini/${magazzino.id}', extra: magazzino),
    );
  }
}
