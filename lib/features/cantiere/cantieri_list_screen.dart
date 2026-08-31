// dart format width=100
// lib/features/cantiere/cantieri_list_screen.dart
//
// Technician-facing list of the operator's own cantieri (worksites) — the Cantieri tab.
// Deliberately not a reuse of admin_cantiere_list_screen.dart: that one is CRUD-oriented,
// office/admin-only. This one reads cantieriProvider exactly as CantiereTimbraScreen's picker
// already does — already scoped server-side to the technician's own CantiereAssignment rows
// (falling back to all active cantieri when they have none), so no new filtering logic here.
//
// Structured as one always-present CustomScrollView wrapped in a single RefreshIndicator —
// loading/error/empty/populated content all live as slivers inside it — mirroring
// ticket_list_screen.dart's own convention exactly. A RefreshIndicator only fires over a
// Scrollable descendant; an earlier version of this screen put it around
// `cantieriAsync.when(...)` with only the populated (ListView.builder) branch containing one, so
// pull-to-refresh silently did nothing in the loading/error/empty states despite the empty-state
// copy telling the technician to do exactly that.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/sync/sync_service.dart';
import '../timbra/cantiere_timbra_screen.dart' show cantieriProvider;

class CantieriListScreen extends ConsumerWidget {
  const CantieriListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantieriAsync = ref.watch(cantieriProvider);
    final cantieri = cantieriAsync.valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(syncProvider.notifier).performSync(),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.base,
                    AppSpacing.pagePadding,
                    AppSpacing.sm,
                  ),
                  child: ScreenHeader(title: 'Cantieri'),
                ),
              ),
              if (cantieriAsync.isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxxl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (cantieriAsync.hasError)
                const SliverToBoxAdapter(
                  child: UnavailableState(
                    icon: LucideIcons.hardHat,
                    titolo: 'Impossibile caricare i cantieri',
                    motivo: 'Trascina in basso per aggiornare, oppure riprova tra poco.',
                  ),
                )
              else if (cantieri.isEmpty)
                const SliverToBoxAdapter(
                  child: UnavailableState(
                    icon: LucideIcons.hardHat,
                    titolo: 'Nessun cantiere disponibile',
                    motivo:
                        'Non risultano cantieri sincronizzati su questo dispositivo. Trascina in '
                        'basso per aggiornare, oppure riprova tra poco.',
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final c = cantieri[i];
                    return ListRow(
                      leading: Icon(LucideIcons.hardHat, color: context.colors.inkMuted),
                      title: c.name,
                      subtitle: c.address,
                      showDivider: i != cantieri.length - 1,
                      onTap: () => context.push(AppRoutes.cantieriDetailPath(c.id)),
                    );
                  }, childCount: cantieri.length),
                ),
              SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
            ],
          ),
        ),
      ),
    );
  }
}
