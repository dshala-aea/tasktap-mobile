// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';

/// All locations from Drift cache, alphabetical.
final adminLocationsProvider =
    StreamProvider.autoDispose<List<Location>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)
        ..orderBy([(l) => OrderingTerm.asc(l.name)]))
      .watch();
});

/// Admin location list — filterable by customer, with FAB to create.
class AdminLocationListScreen extends StatefulWidget {
  const AdminLocationListScreen({super.key});

  @override
  State<AdminLocationListScreen> createState() =>
      _AdminLocationListScreenState();
}

class _AdminLocationListScreenState extends State<AdminLocationListScreen> {
  String _query = '';
  String? _selectedCustomerId;
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
        child: _AdminLocationListBody(
          query: _query,
          selectedCustomerId: _selectedCustomerId,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
          onCustomerChanged: (id) =>
              setState(() => _selectedCustomerId = id),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuova sede',
        onPressed: () => context.push('/altro/sedi/nuova'),
      ),
    );
  }
}

class _AdminLocationListBody extends ConsumerWidget {
  const _AdminLocationListBody({
    required this.query,
    required this.selectedCustomerId,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onCustomerChanged,
  });

  final String query;
  final String? selectedCustomerId;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onCustomerChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(adminLocationsProvider);
    final customersAsync = ref.watch(allCustomersProvider);
    final allLocations = locationsAsync.valueOrNull ?? [];
    final customers = customersAsync.valueOrNull ?? [];

    final customerMap = {for (final c in customers) c.id: c.companyName};

    final filtered = allLocations.where((l) {
      final matchCustomer =
          selectedCustomerId == null || l.customerId == selectedCustomerId;
      final matchQuery = query.isEmpty ||
          l.name.toLowerCase().contains(query.toLowerCase()) ||
          (l.city?.toLowerCase().contains(query.toLowerCase()) ?? false);
      return matchCustomer && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Sedi',
            subtitle: '${filtered.length} totali',
            showBack: true,
          ),
        ),
        SliverToBoxAdapter(
          child: AppSearchBar(
            controller: searchCtrl,
            hint: 'Cerca per nome o città…',
            onChanged: onQueryChanged,
          ),
        ),
        // ── Customer filter ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  AppChip(
                    label: 'Tutti',
                    active: selectedCustomerId == null,
                    onTap: () => onCustomerChanged(null),
                  ),
                  const SizedBox(width: 8),
                  for (final c in customers) ...[
                    AppChip(
                      label: c.companyName,
                      active: selectedCustomerId == c.id,
                      onTap: () => onCustomerChanged(c.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (locationsAsync.isLoading)
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
              icon: LucideIcons.mapPin,
              title: 'Nessuna sede',
              body: 'Crea una nuova sede con il pulsante +.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final location = filtered[i];
                final customerName =
                    customerMap[location.customerId] ?? '—';
                return _AdminLocationRow(
                  location: location,
                  customerName: customerName,
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

class _AdminLocationRow extends StatelessWidget {
  const _AdminLocationRow({
    required this.location,
    required this.customerName,
    required this.isLast,
  });

  final Location location;
  final String customerName;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cityLabel = location.city ?? '—';

    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.BG3,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(LucideIcons.mapPin, size: 20, color: AppColors.MUTED),
      ),
      title: location.name,
      subtitle: '$customerName · $cityLabel',
      meta: const Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: AppColors.MUTED,
      ),
      showDivider: !isLast,
      onTap: () => context.push('/altro/sedi/${location.id}'),
    );
  }
}
