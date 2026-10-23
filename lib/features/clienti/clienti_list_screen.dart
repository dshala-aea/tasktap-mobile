import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_freshness_provider.dart';
import 'clienti_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

class ClientiListScreen extends StatefulWidget {
  const ClientiListScreen({super.key});

  @override
  State<ClientiListScreen> createState() => _ClientiListScreenState();
}

class _ClientiListScreenState extends State<ClientiListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _ClientiListBody(
          query: _query,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
      // The only entry point to `/altro/clienti/nuovo` in the whole app: that route has
      // resolved to a working AdminCustomerFormScreen since before this pass, but nothing
      // rendered a control that pushed it — the FAB that did lived on AdminCustomerListScreen,
      // a second, unrouted "Clienti" list screen that this shell never builds. An office user
      // reaching Clienti from the Altro hub had no way to add a customer from the phone at all.
      floatingActionButton: CapabilityGate(
        capability: 'clienti.customer.write',
        child: Padding(
          // navClearance alone, not minus navGap — see admin_cantiere_list_screen.dart's comment
          // on this same change.
          padding: EdgeInsets.only(bottom: context.navClearance),
          child: AppFab(
            tooltip: 'Nuovo cliente',
            onPressed: () => context.push('/altro/clienti/nuovo'),
          ),
        ),
      ),
    );
  }
}

class _ClientiListBody extends ConsumerWidget {
  const _ClientiListBody({
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
  });

  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);
    final allCustomers = customersAsync.valueOrNull ?? [];

    final filtered = allCustomers.where((c) {
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return c.companyName.toLowerCase().contains(q) ||
          (c.city?.toLowerCase().contains(q) ?? false);
    }).toList();

    // A search that matches nothing is an answer to the technician's own question; an empty mirror
    // on a phone that has never synced is a missing download; only the third case is a fact about
    // the tenant. One message for all three let a typo read as "this company has no customers".
    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;

    // Pull-to-refresh: this list *is* the synced mirror (`customersProvider`), so a sync is the
    // whole refresh — there is no separate server read backing the screen. Added because the
    // Cliente screens were the one list in the app with no way to ask for newer data at all: a
    // technician whose customer had just been created in the office had to wait for the next
    // background sync, with nothing on screen saying so.
    return RefreshIndicator(
      onRefresh: () => refreshWithFeedback(context, ref),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Clienti',
              subtitle: '${allCustomers.length} totali',
              showBack: true,
            ),
          ),
          SliverToBoxAdapter(
            child: AppSearchBar(
              controller: searchCtrl,
              hint: 'Cerca per ragione sociale o città…',
              onChanged: onQueryChanged,
            ),
          ),
          if (customersAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxxl),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: query.isNotEmpty
                  ? EmptyState(
                      icon: LucideIcons.searchX,
                      title: 'Nessun risultato',
                      body: 'Nessun cliente corrisponde a "$query".',
                    )
                  : neverSynced
                  ? const EmptyState(
                      icon: LucideIcons.cloudOff,
                      title: 'Clienti non ancora scaricati',
                      body:
                          'Questo telefono non ha ancora completato una sincronizzazione: i '
                          'clienti compariranno qui appena i dati saranno scaricati.',
                    )
                  : const EmptyState(
                      icon: LucideIcons.users,
                      title: 'Nessun cliente',
                      body: 'Non ci sono clienti da mostrare.',
                    ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final customer = filtered[i];
                return _ClienteRow(
                  customer: customer,
                  isLast: i == filtered.length - 1,
                );
              }, childCount: filtered.length),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _ClienteRow extends ConsumerWidget {
  const _ClienteRow({required this.customer, required this.isLast});

  final Customer customer;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(ticketCountForCustomerProvider(customer.id));
    final ticketCount = countAsync.valueOrNull ?? 0;

    final cityLabel = customer.city ?? '—';
    final subLabel = '$cityLabel · $ticketCount ticket';

    return ListRow(
      leading: AppAvatar(name: customer.companyName, size: 40),
      title: customer.companyName,
      subtitle: subLabel,
      showDivider: !isLast,
      onTap: () => context.push(AppRoutes.clientiDetail(customer.id)),
    );
  }
}
