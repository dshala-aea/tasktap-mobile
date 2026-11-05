// dart format width=100
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../../presentation/providers/schedule_providers.dart' show allCustomersProvider;
import '../../ticket/ticket_providers.dart'
    show closedTicketStatusIdsProvider, ticketIsClosed, ticketsProvider;

/// All locations from Drift cache, alphabetical.
final adminLocationsProvider = StreamProvider.autoDispose<List<Location>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)..orderBy([(l) => OrderingTerm.asc(l.name)])).watch();
});

/// Open-ticket count per location id, from the local mirror.
///
/// "Open" is the ticket list's own predicate (`closedAt` or a closing status), so the
/// `Con ticket` / `Senza ticket` chips and the `Solo con ticket aperti` toggle cannot disagree
/// about what an open ticket is.
final locationOpenTicketCountsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final tickets = ref.watch(ticketsProvider).valueOrNull ?? const <Ticket>[];
  final closedStatusIds = ref.watch(closedTicketStatusIdsProvider).valueOrNull ?? const <int>{};
  final counts = <String, int>{};
  for (final ticket in tickets) {
    if (ticketIsClosed(ticket, closedStatusIds)) continue;
    counts[ticket.locationId] = (counts[ticket.locationId] ?? 0) + 1;
  }
  return counts;
});

/// The three quick-filter presets from the prototype's Sedi chip row.
enum _SedeStatusFilter { tutti, conTicket, senzaTicket }

extension on _SedeStatusFilter {
  String get id => name;

  String get label => switch (this) {
    _SedeStatusFilter.tutti => 'Tutti',
    _SedeStatusFilter.conTicket => 'Con ticket',
    _SedeStatusFilter.senzaTicket => 'Senza ticket',
  };
}

/// The quick chip plus every facet reachable from the `Filtri` sheet.
class _SediFilters {
  const _SediFilters({
    this.status = _SedeStatusFilter.tutti,
    this.customerId,
    this.city,
    this.onlyWithOpenTickets = false,
  });

  final _SedeStatusFilter status;
  final String? customerId;
  final String? city;
  final bool onlyWithOpenTickets;

  bool get hasFacets => customerId != null || city != null || onlyWithOpenTickets;

  _SediFilters copyWith({
    _SedeStatusFilter? status,
    String? customerId,
    bool clearCustomer = false,
    String? city,
    bool clearCity = false,
    bool? onlyWithOpenTickets,
  }) {
    return _SediFilters(
      status: status ?? this.status,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      city: clearCity ? null : (city ?? this.city),
      onlyWithOpenTickets: onlyWithOpenTickets ?? this.onlyWithOpenTickets,
    );
  }
}

/// Admin location list — grouped by customer, filterable through a real `Filtri` sheet.
class AdminLocationListScreen extends StatefulWidget {
  const AdminLocationListScreen({super.key});

  @override
  State<AdminLocationListScreen> createState() => _AdminLocationListScreenState();
}

class _AdminLocationListScreenState extends State<AdminLocationListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  _SediFilters _filters = const _SediFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectStatus(ListFilterChipData chip) {
    final status = _SedeStatusFilter.values.firstWhere(
      (f) => f.id == chip.id,
      orElse: () => _SedeStatusFilter.tutti,
    );
    setState(() {
      _filters = _filters.copyWith(
        status: status,
        // `Senza ticket` + `Solo con ticket aperti` is a guaranteed empty set; clear the toggle
        // rather than hide the reason the list emptied.
        onlyWithOpenTickets: status == _SedeStatusFilter.senzaTicket
            ? false
            : _filters.onlyWithOpenTickets,
      );
    });
  }

  Future<void> _openFilterSheet({
    required List<({String id, String name})> clients,
    required List<String> cities,
  }) async {
    final result = await showModalBottomSheet<_SediFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SediFilterSheet(initial: _filters, clients: clients, cities: cities),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _AdminLocationListBody(
          filters: _filters,
          query: _query,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
          onSelectStatus: _selectStatus,
          onOpenFilters: _openFilterSheet,
        ),
      ),
    );
  }
}

class _AdminLocationListBody extends ConsumerWidget {
  const _AdminLocationListBody({
    required this.filters,
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onSelectStatus,
    required this.onOpenFilters,
  });

  final _SediFilters filters;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ListFilterChipData> onSelectStatus;
  final Future<void> Function({
    required List<({String id, String name})> clients,
    required List<String> cities,
  })
  onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(adminLocationsProvider);
    final customersAsync = ref.watch(allCustomersProvider);
    final allLocations = locationsAsync.valueOrNull ?? const <Location>[];
    final customers = customersAsync.valueOrNull ?? const <Customer>[];
    final customersById = {for (final c in customers) c.id: c};
    final openTicketCounts = ref.watch(locationOpenTicketCountsProvider);

    bool hasOpenTickets(Location location) => _hasOpenTickets(openTicketCounts[location.id] ?? 0);

    final q = query.trim().toLowerCase();
    final filtered = allLocations.where((location) {
      if (!_matchesStatus(location, filters.status, openTicketCounts)) return false;
      if (filters.onlyWithOpenTickets && !hasOpenTickets(location)) return false;
      if (filters.customerId != null && location.customerId != filters.customerId) {
        return false;
      }
      if (_cityKey(filters.city) != null && _cityKey(location.city) != _cityKey(filters.city)) {
        return false;
      }
      if (q.isEmpty) return true;
      final customerName = customersById[location.customerId]?.companyName;
      return location.name.toLowerCase().contains(q) ||
          (location.address?.toLowerCase().contains(q) ?? false) ||
          (location.city?.toLowerCase().contains(q) ?? false) ||
          (customerName?.toLowerCase().contains(q) ?? false);
    }).toList();

    final groups = _groupByCustomer(context, filtered, customersById, openTicketCounts);
    final withTickets = filtered.where(hasOpenTickets).length;

    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
    final hasActiveFilter =
        query.isNotEmpty || filters.status != _SedeStatusFilter.tutti || filters.hasFacets;

    final isLoading =
        locationsAsync.isLoading && !locationsAsync.hasValue && !locationsAsync.hasError;
    final state = locationsAsync.hasError && !locationsAsync.hasValue
        ? _ListBodyState.unavailable
        : isLoading
        ? _ListBodyState.loading
        : _ListBodyState.content;

    List<({String id, String name})> clients = [
      for (final c in customers) (id: c.id, name: c.companyName),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final cities = <String>{
      for (final l in allLocations)
        if (l.city != null && l.city!.trim().isNotEmpty) l.city!.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      children: [
        const OfflineSyncBanner(),
        ScreenHeader(
          title: 'Sedi',
          subtitle: 'Dove andare, per quale cliente, con cosa è aperto.',
          subtitleMaxLines: 2,
          showBack: true,
          actions: [
            CapabilityGate(
              capability: 'clienti.location.write',
              child: ListHeaderAction(
                label: 'Nuovo',
                onPressed: () => context.push('/altro/sedi/nuova'),
              ),
            ),
          ],
        ),
        AppSearchBar(
          controller: searchCtrl,
          hint: 'Cerca sede, cliente, indirizzo o città…',
          onChanged: onQueryChanged,
        ),
        ListFilterRow(
          filters: [
            for (final status in _SedeStatusFilter.values)
              ListFilterChipData(label: status.label, id: status.id),
          ],
          activeId: filters.status.id,
          onSelected: onSelectStatus,
          onOpenFilters: () {
            onOpenFilters(clients: clients, cities: cities);
          },
        ),
        Expanded(
          child: _body(
            context: context,
            ref: ref,
            state: state,
            groups: groups,
            filteredCount: filtered.length,
            withTickets: withTickets,
            neverSynced: neverSynced,
            hasLocations: allLocations.isNotEmpty,
            hasActiveFilter: hasActiveFilter,
            query: query,
          ),
        ),
      ],
    );
  }

  Widget _body({
    required BuildContext context,
    required WidgetRef ref,
    required _ListBodyState state,
    required List<ListGroupData> groups,
    required int filteredCount,
    required int withTickets,
    required bool neverSynced,
    required bool hasLocations,
    required bool hasActiveFilter,
    required String query,
  }) {
    Future<void> onRefresh() => refreshWithFeedback(context, ref);

    if (state == _ListBodyState.loading) {
      return _scrollable(context, const ListLoadingSkeleton(), onRefresh);
    }

    if (state == _ListBodyState.unavailable) {
      return _scrollable(
        context,
        UnavailableState(
          icon: LucideIcons.alertTriangle,
          titolo: 'Sedi non disponibili',
          motivo: 'Non è stato possibile leggere le sedi salvate su questo telefono.',
          action: AppButton(
            label: 'Riprova',
            onPressed: () => ref.invalidate(adminLocationsProvider),
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
          hasLocations: hasLocations,
          hasActiveFilter: hasActiveFilter,
          neverSynced: neverSynced,
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
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
                  left: _sediLabel(filteredCount),
                  right: '$withTickets con ticket',
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.navClearance)),
        ],
      ),
    );
  }

  Widget _scrollable(BuildContext context, Widget child, Future<void> Function() onRefresh) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child),
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: child,
        ),
      ),
    );
  }

  Widget _emptyState({
    required String query,
    required bool hasLocations,
    required bool hasActiveFilter,
    required bool neverSynced,
  }) {
    if (hasActiveFilter) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: query.isNotEmpty
            ? 'Nessuna sede corrisponde a "$query".'
            : 'Nessuna sede corrisponde ai filtri selezionati.',
      );
    }
    if (!hasLocations && neverSynced) {
      return const UnavailableState(
        icon: LucideIcons.cloudOff,
        titolo: 'Sedi non ancora scaricate',
        motivo:
            'Questo telefono non ha ancora completato una sincronizzazione. '
            'Le sedi compariranno qui dopo la prossima: trascina in basso per aggiornare.',
      );
    }
    if (!hasLocations) {
      return const EmptyState(
        icon: LucideIcons.mapPin,
        title: 'Nessuna sede',
        body: 'Crea una nuova sede con il pulsante Nuovo.',
      );
    }
    return const EmptyState(
      icon: LucideIcons.searchX,
      title: 'Nessun risultato',
      body: 'Nessuna sede da mostrare.',
    );
  }

  static List<ListGroupData> _groupByCustomer(
    BuildContext context,
    List<Location> locations,
    Map<String, Customer> customersById,
    Map<String, int> openTicketCounts,
  ) {
    final grouped = <String, ({String title, List<Location> rows})>{};
    for (final location in locations) {
      final name = _customerName(customersById[location.customerId]?.companyName);
      final key = name == null ? 'unknown' : 'customer:${location.customerId}';
      final group = grouped[key];
      if (group == null) {
        grouped[key] = (title: name ?? 'Senza cliente', rows: [location]);
      } else {
        group.rows.add(location);
      }
    }

    final entries = grouped.values.toList()
      ..sort((a, b) {
        if (a.title == 'Senza cliente') return 1;
        if (b.title == 'Senza cliente') return -1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return [
      for (final group in entries)
        ListGroupData(
          title: group.title,
          count: group.rows.length,
          rows: [
            for (final location in group.rows)
              _row(context, location, openTickets: openTicketCounts[location.id] ?? 0),
          ],
        ),
    ];
  }

  static ListRowData _row(BuildContext context, Location location, {required int openTickets}) {
    final address = _text(location.address);
    final city = _text(location.city);
    final place = address ?? city;

    return ListRowData(
      title: location.name,
      meta: [?place, _ticketLabel(openTickets)].join(' · '),
      status: location.isActive ? 'Attiva' : 'Inattiva',
      statusTone: location.isActive ? ListStatusTone.good : ListStatusTone.bad,
      onTap: () => context.push('/altro/sedi/${location.id}'),
      rowKey: ValueKey('sede-row-${location.id}'),
    );
  }

  static bool _matchesStatus(
    Location location,
    _SedeStatusFilter status,
    Map<String, int> openTicketCounts,
  ) {
    final open = _hasOpenTickets(openTicketCounts[location.id] ?? 0);
    return switch (status) {
      _SedeStatusFilter.tutti => true,
      _SedeStatusFilter.conTicket => open,
      _SedeStatusFilter.senzaTicket => !open,
    };
  }

  static bool _hasOpenTickets(int count) => count > 0;

  static String _ticketLabel(int count) {
    if (count == 0) return '0 ticket';
    if (count == 1) return '1 ticket aperto';
    return '$count ticket aperti';
  }

  static String _sediLabel(int count) => count == 1 ? '1 sede' : '$count sedi';

  static String? _customerName(String? name) {
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _text(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _cityKey(String? city) => _text(city);
}

enum _ListBodyState { loading, content, unavailable }

class _SediFilterSheet extends StatefulWidget {
  const _SediFilterSheet({required this.initial, required this.clients, required this.cities});

  final _SediFilters initial;
  final List<({String id, String name})> clients;
  final List<String> cities;

  @override
  State<_SediFilterSheet> createState() => _SediFilterSheetState();
}

class _SediFilterSheetState extends State<_SediFilterSheet> {
  late _SediFilters _draft = widget.initial;

  void _setStatus(_SedeStatusFilter status) {
    setState(() {
      _draft = _draft.copyWith(
        status: status,
        onlyWithOpenTickets: status == _SedeStatusFilter.senzaTicket
            ? false
            : _draft.onlyWithOpenTickets,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 4),
            Text(
              'Restringi per stato, cliente e città.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Stato',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in _SedeStatusFilter.values)
                    _SediFilterChoice(
                      label: status.label,
                      active: _draft.status == status,
                      onTap: () => _setStatus(status),
                    ),
                ],
              ),
            ),
            if (widget.clients.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Cliente',
                child: DropdownButtonFormField<String?>(
                  key: const Key('sediFilterCliente'),
                  initialValue: _draft.customerId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutti')),
                    for (final client in widget.clients)
                      DropdownMenuItem(value: client.id, child: Text(client.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearCustomer: true)
                        : _draft.copyWith(customerId: v);
                  }),
                ),
              ),
            ],
            if (widget.cities.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Città',
                child: DropdownButtonFormField<String?>(
                  key: const Key('sediFilterCitta'),
                  initialValue: _draft.city,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutte')),
                    for (final city in widget.cities)
                      DropdownMenuItem(value: city, child: Text(city)),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearCity: true)
                        : _draft.copyWith(city: v);
                  }),
                ),
              ),
            ],
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
                  key: const Key('sediFilterOpenOnly'),
                  value: _draft.onlyWithOpenTickets,
                  onChanged: (v) => setState(() {
                    _draft = _draft.copyWith(
                      onlyWithOpenTickets: v,
                      // Requiring an open ticket can never be met under `Senza ticket`;
                      // move the status to the preset that expresses the same intent.
                      status: v && _draft.status == _SedeStatusFilter.senzaTicket
                          ? _SedeStatusFilter.conTicket
                          : _draft.status,
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('sediFilterReset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _SediFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('sediFilterApply'),
                    label: 'Applica',
                    onPressed: () => Navigator.pop(context, _draft),
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

class _SediFilterChoice extends StatelessWidget {
  const _SediFilterChoice({required this.label, required this.active, required this.onTap});

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
