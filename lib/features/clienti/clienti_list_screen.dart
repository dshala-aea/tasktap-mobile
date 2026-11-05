import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_freshness_provider.dart';
import 'clienti_providers.dart';

enum _CustomerStatusFilter { attivi, tutti, inattivi }

extension on _CustomerStatusFilter {
  String get label => switch (this) {
    _CustomerStatusFilter.attivi => 'Attivi',
    _CustomerStatusFilter.tutti => 'Tutti',
    _CustomerStatusFilter.inattivi => 'Inattivi',
  };
}

enum _ContractFilter { tutti, conAttivo, senzaAttivo }

extension on _ContractFilter {
  String get label => switch (this) {
    _ContractFilter.tutti => 'Tutti',
    _ContractFilter.conAttivo => 'Con contratto attivo',
    _ContractFilter.senzaAttivo => 'Senza contratto attivo',
  };
}

class _ClientiFilters {
  const _ClientiFilters({
    this.status = _CustomerStatusFilter.attivi,
    this.city,
    this.contracts = _ContractFilter.tutti,
    this.onlyWithOpenTickets = false,
  });

  final _CustomerStatusFilter status;
  final String? city;
  final _ContractFilter contracts;
  final bool onlyWithOpenTickets;

  bool get hasFacets =>
      city != null || contracts != _ContractFilter.tutti || onlyWithOpenTickets;
}

class ClientiListScreen extends StatefulWidget {
  const ClientiListScreen({super.key});

  @override
  State<ClientiListScreen> createState() => _ClientiListScreenState();
}

class _ClientiListScreenState extends State<ClientiListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  _ClientiFilters _filters = const _ClientiFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_ClientiFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ClientiFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _ClientiListBody(
          filters: _filters,
          query: _query,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
          onFiltersChanged: (f) => setState(() => _filters = f),
          onOpenFilters: _openFilters,
        ),
      ),
    );
  }
}

class _ClientiListBody extends ConsumerWidget {
  const _ClientiListBody({
    required this.filters,
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onFiltersChanged,
    required this.onOpenFilters,
  });

  final _ClientiFilters filters;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_ClientiFilters> onFiltersChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(allClientiCustomersProvider);
    final allCustomers = customersAsync.valueOrNull ?? const <Customer>[];
    final openTicketCounts = ref.watch(customerOpenTicketCountsProvider);
    final contractCounts =
        ref.watch(activeContractCountsByCustomerProvider).valueOrNull ??
        const <String, int>{};

    final filtered = allCustomers.where((c) {
      if (!_matchesStatus(c, filters.status)) return false;
      if (!_matchesQuery(c, query)) return false;
      if (filters.city != null && c.city != filters.city) return false;
      final contractCount = contractCounts[c.id] ?? 0;
      if (filters.contracts == _ContractFilter.conAttivo &&
          contractCount == 0) {
        return false;
      }
      if (filters.contracts == _ContractFilter.senzaAttivo &&
          contractCount > 0) {
        return false;
      }
      if (filters.onlyWithOpenTickets && (openTicketCounts[c.id] ?? 0) == 0) {
        return false;
      }
      return true;
    }).toList();

    final activeCount = filtered.where((c) => c.isActive).length;
    final neverSynced =
        ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;

    final groups = <ListGroupData>[
      if (filtered.any((c) => c.isActive))
        ListGroupData(
          title: 'Attivi',
          count: activeCount,
          rows: filtered
              .where((c) => c.isActive)
              .map(
                (c) => _row(
                  c,
                  openTickets: openTicketCounts[c.id] ?? 0,
                  contracts: contractCounts[c.id] ?? 0,
                  context: context,
                ),
              )
              .toList(),
        ),
      if (filtered.any((c) => !c.isActive))
        ListGroupData(
          title: 'Inattivi',
          count: filtered.length - activeCount,
          rows: filtered
              .where((c) => !c.isActive)
              .map(
                (c) => _row(
                  c,
                  openTickets: openTicketCounts[c.id] ?? 0,
                  contracts: contractCounts[c.id] ?? 0,
                  context: context,
                ),
              )
              .toList(),
        ),
    ];

    return Column(
      children: [
        const OfflineSyncBanner(),
        ScreenHeader(
          title: 'Clienti',
          subtitle: 'Chi sono i clienti e cosa hanno aperto con noi.',
          subtitleMaxLines: 2,
          showBack: true,
          actions: [
            CapabilityGate(
              capability: 'clienti.customer.write',
              child: ListHeaderAction(
                label: 'Nuovo',
                onPressed: () => context.push('/altro/clienti/nuovo'),
              ),
            ),
          ],
        ),
        AppSearchBar(
          controller: searchCtrl,
          hint: 'Cerca ragione sociale, città o P.IVA…',
          onChanged: onQueryChanged,
        ),
        ListFilterRow(
          filters: const [
            ListFilterChipData(label: 'Attivi'),
            ListFilterChipData(label: 'Tutti'),
            ListFilterChipData(label: 'Inattivi'),
          ],
          activeIndex: filters.status.index,
          onSelected: (chip) => onFiltersChanged(
            _ClientiFilters(
              status: _CustomerStatusFilter.values.firstWhere(
                (s) => s.label == chip.label,
              ),
              city: filters.city,
              contracts: filters.contracts,
              onlyWithOpenTickets: filters.onlyWithOpenTickets,
            ),
          ),
          onOpenFilters: onOpenFilters,
        ),
        Expanded(
          child: _body(
            context: context,
            ref: ref,
            customersAsync: customersAsync,
            groups: groups,
            filteredCount: filtered.length,
            activeCount: activeCount,
            neverSynced: neverSynced,
            hasCustomers: allCustomers.isNotEmpty,
            query: query,
            filters: filters,
          ),
        ),
      ],
    );
  }

  Widget _body({
    required BuildContext context,
    required WidgetRef ref,
    required AsyncValue<List<Customer>> customersAsync,
    required List<ListGroupData> groups,
    required int filteredCount,
    required int activeCount,
    required bool neverSynced,
    required bool hasCustomers,
    required String query,
    required _ClientiFilters filters,
  }) {
    Future<void> onRefresh() => refreshWithFeedback(context, ref);

    if (customersAsync.isLoading && !customersAsync.hasValue) {
      return _scrollable(context, const ListLoadingSkeleton(), onRefresh);
    }

    if (customersAsync.hasError && !customersAsync.hasValue) {
      return _scrollable(
        context,
        UnavailableState(
          icon: LucideIcons.alertTriangle,
          titolo: 'Clienti non disponibili',
          motivo: 'Non è stato possibile leggere i clienti da questo telefono.',
          action: AppButton(
            label: 'Riprova',
            onPressed: () => ref.invalidate(allClientiCustomersProvider),
          ),
        ),
        onRefresh,
      );
    }

    if (groups.isEmpty) {
      return _scrollable(
        context,
        _emptyState(
          query: query,
          filters: filters,
          neverSynced: neverSynced,
          hasCustomers: hasCustomers,
        ),
        onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(
              child: _framed(
                child: ListGroupHeader(title: group.title!, count: group.count),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => KeyedSubtree(
                    key: group.rows[i].rowKey,
                    child: ListDocumentRow(data: group.rows[i]),
                  ),
                  childCount: group.rows.length,
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _framed(
              child: ListSummaryFooter(
                data: ListSummaryData(
                  left: _clientiLabel(filteredCount),
                  right: _attiviLabel(activeCount),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.navClearance)),
        ],
      ),
    );
  }

  Widget _scrollable(
    BuildContext context,
    Widget child,
    Future<void> Function() onRefresh,
  ) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: child,
            ),
          ),
          SizedBox(height: context.navClearance),
        ],
      ),
    );
  }

  Widget _framed({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _emptyState({
    required String query,
    required _ClientiFilters filters,
    required bool neverSynced,
    required bool hasCustomers,
  }) {
    if (query.isNotEmpty || filters.hasFacets) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: query.isNotEmpty
            ? 'Nessun cliente corrisponde a "$query".'
            : 'Nessun cliente corrisponde ai filtri selezionati.',
      );
    }
    if (!hasCustomers && neverSynced) {
      return const EmptyState(
        icon: LucideIcons.cloudOff,
        title: 'Clienti non ancora scaricati',
        body:
            'Questo telefono non ha ancora completato una sincronizzazione: i '
            'clienti compariranno qui appena i dati saranno scaricati.',
      );
    }
    if (!hasCustomers) {
      return const EmptyState(
        icon: LucideIcons.users,
        title: 'Nessun cliente',
        body: 'Non ci sono clienti da mostrare.',
      );
    }
    return const EmptyState(
      icon: LucideIcons.users,
      title: 'Nessun cliente',
      body: 'Nessun cliente corrisponde allo stato selezionato.',
    );
  }

  static bool _matchesStatus(Customer c, _CustomerStatusFilter status) {
    return switch (status) {
      _CustomerStatusFilter.attivi => c.isActive,
      _CustomerStatusFilter.inattivi => !c.isActive,
      _CustomerStatusFilter.tutti => true,
    };
  }

  static bool _matchesQuery(Customer c, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return c.companyName.toLowerCase().contains(q) ||
        (c.city?.toLowerCase().contains(q) ?? false) ||
        (c.taxId?.toLowerCase().contains(q) ?? false) ||
        (c.fiscalCode?.toLowerCase().contains(q) ?? false);
  }

  static ListRowData _row(
    Customer customer, {
    required int openTickets,
    required int contracts,
    required BuildContext context,
  }) {
    final parts = <String>[
      if (customer.city != null && customer.city!.trim().isNotEmpty)
        customer.city!.trim(),
      _ticketLabel(openTickets),
      _contractLabel(contracts),
    ];

    return ListRowData(
      title: customer.companyName,
      meta: parts.join(' · '),
      secondary: 'Cliente dal ${customer.createdAt.toLocal().year}',
      status: customer.isActive ? 'Attivo' : 'Inattivo',
      statusTone: customer.isActive ? ListStatusTone.good : ListStatusTone.bad,
      onTap: () => context.push(AppRoutes.clientiDetail(customer.id)),
    );
  }

  static String _ticketLabel(int count) {
    if (count == 0) return 'nessun ticket';
    if (count == 1) return '1 ticket aperto';
    return '$count ticket aperti';
  }

  static String _contractLabel(int count) {
    if (count == 1) return '1 contratto';
    return '$count contratti';
  }

  static String _clientiLabel(int count) =>
      count == 1 ? '1 cliente' : '$count clienti';

  static String _attiviLabel(int count) =>
      count == 1 ? '1 attivo' : '$count attivi';
}

class _ClientiFilterSheet extends ConsumerStatefulWidget {
  const _ClientiFilterSheet({required this.initial});

  final _ClientiFilters initial;

  @override
  ConsumerState<_ClientiFilterSheet> createState() =>
      _ClientiFilterSheetState();
}

class _ClientiFilterSheetState extends ConsumerState<_ClientiFilterSheet> {
  late _CustomerStatusFilter _status = widget.initial.status;
  late String? _city = widget.initial.city;
  late _ContractFilter _contracts = widget.initial.contracts;
  late bool _onlyWithOpenTickets = widget.initial.onlyWithOpenTickets;

  @override
  Widget build(BuildContext context) {
    final customers =
        ref.watch(allClientiCustomersProvider).valueOrNull ?? const [];
    final cities = {
      for (final c in customers)
        if (c.city != null && c.city!.trim().isNotEmpty) c.city!.trim(),
    }.toList()..sort();
    if (_city != null && !cities.contains(_city)) cities.add(_city!);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            AppSpacing.pagePadding,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: SheetHandle(),
            ),
            Text('Filtri', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Stato',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in _CustomerStatusFilter.values)
                    _FilterChoice(
                      label: status.label,
                      active: _status == status,
                      onTap: () => setState(() => _status = status),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Città',
              child: DropdownButtonFormField<String?>(
                key: const Key('clienti-filter-city'),
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _city,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte')),
                  ...cities.map(
                    (city) => DropdownMenuItem(value: city, child: Text(city)),
                  ),
                ],
                onChanged: (v) => setState(() => _city = v),
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Contratti',
              child: DropdownButtonFormField<_ContractFilter>(
                key: const Key('clienti-filter-contracts'),
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _contracts,
                isExpanded: true,
                items: [
                  for (final filter in _ContractFilter.values)
                    DropdownMenuItem(value: filter, child: Text(filter.label)),
                ],
                onChanged: (v) =>
                    setState(() => _contracts = v ?? _ContractFilter.tutti),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Solo con ticket aperti',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                AppToggle(
                  key: const Key('clienti-filter-open-only'),
                  value: _onlyWithOpenTickets,
                  onChanged: (v) => setState(() => _onlyWithOpenTickets = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('clienti-filter-reset'),
                    label: 'Azzera',
                    onPressed: () =>
                        Navigator.pop(context, const _ClientiFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('clienti-filter-apply'),
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _ClientiFilters(
                        status: _status,
                        city: _city,
                        contracts: _contracts,
                        onlyWithOpenTickets: _onlyWithOpenTickets,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AppTappable(
            onTap: onTap,
            borderRadius: AppRack.freeShape,
            color: active ? colors.ink : colors.surface,
            border: Border.all(color: active ? colors.ink : colors.borderLight),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.docCode.copyWith(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.32,
                color: active ? colors.surface : colors.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
