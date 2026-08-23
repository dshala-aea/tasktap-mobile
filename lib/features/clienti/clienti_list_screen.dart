import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
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
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuovo cliente',
          onPressed: () => context.push('/altro/clienti/nuovo'),
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

    return CustomScrollView(
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
            child: EmptyState(
              icon: LucideIcons.users,
              title: 'Nessun cliente',
              body: 'I clienti sincronizzati appariranno qui.',
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
      meta: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: context.colors.inkMuted,
      ),
      showDivider: !isLast,
      onTap: () => context.push(AppRoutes.clientiDetail(customer.id)),
    );
  }
}
