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
// Read live, not from Drift: `Magazzino` has no local mirror (nothing syncs it), same as giacenze
// and movimenti — see magazzino_api_client.dart's header comment for why that split is
// deliberate for anything stock-adjacent.
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
                  child: ErrorState(onRetry: () => ref.invalidate(magazziniProvider)),
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
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuovo magazzino',
          onPressed: () => context.push('/altro/magazzino/magazzini/nuovo'),
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
      meta: !magazzino.isActive
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Inattivo', style: TextStyle(fontSize: 10, color: context.colors.red)),
            )
          : null,
      showDivider: !isLast,
      onTap: () => context.push('/altro/magazzino/magazzini/${magazzino.id}', extra: magazzino),
    );
  }
}
