// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../admin_providers.dart';

/// Admin customer list — shows all customers (active + inactive) with FAB to
/// create new ones.  Tapping a row navigates to the detail/edit screen.
class AdminCustomerListScreen extends StatefulWidget {
  const AdminCustomerListScreen({super.key});

  @override
  State<AdminCustomerListScreen> createState() =>
      _AdminCustomerListScreenState();
}

class _AdminCustomerListScreenState extends State<AdminCustomerListScreen> {
  String _query = '';
  bool _showInactive = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: _AdminCustomerListBody(
          query: _query,
          showInactive: _showInactive,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
          onToggleInactive: (v) => setState(() => _showInactive = v),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuovo cliente',
        onPressed: () => context.push('/altro/clienti/nuovo'),
      ),
    );
  }
}

class _AdminCustomerListBody extends ConsumerWidget {
  const _AdminCustomerListBody({
    required this.query,
    required this.showInactive,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onToggleInactive,
  });

  final String query;
  final bool showInactive;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onToggleInactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(adminCustomersProvider);
    final allCustomers = customersAsync.valueOrNull ?? [];

    final filtered = allCustomers.where((c) {
      final matchActive = showInactive || c.isActive;
      final matchQuery = query.isEmpty ||
          c.companyName.toLowerCase().contains(query.toLowerCase()) ||
          (c.city?.toLowerCase().contains(query.toLowerCase()) ?? false);
      return matchActive && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Clienti',
            subtitle: '${filtered.length} totali',
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
        // ── Filter toggle ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: Row(
              children: [
                AppChip(
                  label: 'Attivi',
                  active: !showInactive,
                  onTap: () => onToggleInactive(false),
                ),
                const SizedBox(width: 8),
                AppChip(
                  label: 'Tutti',
                  active: showInactive,
                  onTap: () => onToggleInactive(true),
                ),
              ],
            ),
          ),
        ),
        if (customersAsync.isLoading)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.users,
              title: 'Nessun cliente',
              body: 'Crea un nuovo cliente con il pulsante +.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final customer = filtered[i];
                return _AdminCustomerRow(
                  customer: customer,
                  isLast: i == filtered.length - 1,
                );
              },
              childCount: filtered.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

class _AdminCustomerRow extends StatelessWidget {
  const _AdminCustomerRow({
    required this.customer,
    required this.isLast,
  });

  final Customer customer;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cityLabel = customer.city ?? '—';
    final statusLabel = customer.isActive ? '' : ' (inattivo)';

    return ListRow(
      leading: AppAvatar(name: customer.companyName, size: 40),
      title: '${customer.companyName}$statusLabel',
      subtitle: cityLabel,
      meta: const Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: AppColors.MUTED,
      ),
      showDivider: !isLast,
      onTap: () => context.push('/altro/clienti/${customer.id}'),
    );
  }
}
