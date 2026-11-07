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
import '../../../core/time/business_time.dart' show BusinessTime, formatWorkDate;
import '../../../core/time/business_time_providers.dart' show businessTimeProvider;
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

/// Every mirrored customer — active and inactive — for naming the customer groups.
///
/// The `Cliente` filter stays on the active set ([allCustomersProvider]) to preserve the old
/// screen's behaviour. Naming is a different question: a sede whose customer was deactivated is
/// still that customer's sede, so it must not be labelled `Senza cliente`.
final _allMirroredCustomersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.customers)..orderBy([(c) => OrderingTerm.asc(c.companyName)])).watch();
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

/// The latest ticket activity per location id, from the already-watched local ticket mirror.
///
/// This is the row's second line source (`Ultima attività dd/MM` / `Nessuna attività recente`).
/// A ticket's activity is the newest of its creation, last update and closure; closed tickets
/// still count as activity. Only the synced mirror is read, same limitation as the open counts.
final locationLastActivityProvider = Provider.autoDispose<Map<String, DateTime>>((ref) {
  final tickets = ref.watch(ticketsProvider).valueOrNull ?? const <Ticket>[];
  final latest = <String, DateTime>{};
  for (final ticket in tickets) {
    final at = _ticketActivityAt(ticket);
    final current = latest[ticket.locationId];
    if (current == null || at.isAfter(current)) latest[ticket.locationId] = at;
  }
  return latest;
});

DateTime _ticketActivityAt(Ticket ticket) {
  var at = ticket.createdAt;
  final updated = ticket.updatedAt;
  if (updated != null && updated.isAfter(at)) at = updated;
  final closed = ticket.closedAt;
  if (closed != null && closed.isAfter(at)) at = closed;
  return at;
}

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

  /// Drops a facet whose option disappeared from the current local data.
  ///
  /// A selected customer can be deactivated, and a selected city can lose its last sede, while the
  /// screen stays open. Keeping such a value would filter the list invisibly (and the sheet's
  /// dropdown would receive a value that is not among its items).
  _SediFilters reconciled({
    required bool Function(String id) hasCustomer,
    required bool Function(String city) hasCity,
  }) {
    final customer = customerId;
    final selectedCity = city;
    return _SediFilters(
      status: status,
      customerId: customer != null && hasCustomer(customer) ? customer : null,
      city: selectedCity != null && hasCity(selectedCity) ? selectedCity : null,
      onlyWithOpenTickets: onlyWithOpenTickets,
    );
  }

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

  @override
  bool operator ==(Object other) =>
      other is _SediFilters &&
      other.status == status &&
      other.customerId == customerId &&
      other.city == city &&
      other.onlyWithOpenTickets == onlyWithOpenTickets;

  @override
  int get hashCode => Object.hash(status, customerId, city, onlyWithOpenTickets);
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
    final reconciled = _filters.reconciled(
      hasCustomer: (id) => clients.any((client) => client.id == id),
      hasCity: cities.contains,
    );
    if (reconciled != _filters && mounted) setState(() => _filters = reconciled);

    final result = await showModalBottomSheet<_SediFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRack.cellRadius)),
      ),
      builder: (_) => _SediFilterSheet(initial: reconciled, clients: clients, cities: cities),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    return _AdminLocationListBody(
      filters: _filters,
      query: _query,
      searchCtrl: _searchCtrl,
      onQueryChanged: (q) => setState(() => _query = q),
      onSelectStatus: _selectStatus,
      onOpenFilters: _openFilterSheet,
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
    final mirroredCustomersAsync = ref.watch(_allMirroredCustomersProvider);
    final allLocations = locationsAsync.valueOrNull ?? const <Location>[];
    final customers = customersAsync.valueOrNull ?? const <Customer>[];
    final mirroredCustomers = mirroredCustomersAsync.valueOrNull ?? customers;
    final customersById = {for (final c in mirroredCustomers) c.id: c};
    final openTicketCounts = ref.watch(locationOpenTicketCountsProvider);
    final lastActivityByLocation = ref.watch(locationLastActivityProvider);
    final businessTime = ref.watch(businessTimeProvider);

    bool hasOpenTickets(Location location) => _hasOpenTickets(openTicketCounts[location.id] ?? 0);

    // The `Cliente` filter stays on the active set (the old screen's source); the group names above
    // come from every mirrored customer so an inactive customer keeps its name.
    List<({String id, String name})> clients = [
      for (final c in customers) (id: c.id, name: c.companyName),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final cities = <String>{
      for (final l in allLocations)
        if (l.city != null && l.city!.trim().isNotEmpty) l.city!.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Drop a facet whose option disappeared while the screen was open (a deactivated customer, a
    // city whose last sede was deleted). The raw [_filters] state keeps it for the sheet's initial
    // value only; behaviour always uses the reconciled set.
    final activeFilters = filters.reconciled(
      hasCustomer: (id) => clients.any((client) => client.id == id),
      hasCity: cities.contains,
    );

    final q = query.trim().toLowerCase();
    final filtered = allLocations.where((location) {
      if (!_matchesStatus(location, activeFilters.status, openTicketCounts)) return false;
      if (activeFilters.onlyWithOpenTickets && !hasOpenTickets(location)) return false;
      if (activeFilters.customerId != null && location.customerId != activeFilters.customerId) {
        return false;
      }
      if (_cityKey(activeFilters.city) != null &&
          _cityKey(location.city) != _cityKey(activeFilters.city)) {
        return false;
      }
      if (q.isEmpty) return true;
      final customerName = customersById[location.customerId]?.companyName;
      return location.name.toLowerCase().contains(q) ||
          (location.address?.toLowerCase().contains(q) ?? false) ||
          (location.city?.toLowerCase().contains(q) ?? false) ||
          (customerName?.toLowerCase().contains(q) ?? false);
    }).toList();

    final groups = _groupByCustomer(
      context,
      filtered,
      customersById,
      openTicketCounts,
      lastActivityByLocation,
      businessTime,
    );
    final withTickets = filtered.where(hasOpenTickets).length;

    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
    final hasActiveFilter =
        q.isNotEmpty || activeFilters.status != _SedeStatusFilter.tutti || activeFilters.hasFacets;

    final isLoading =
        locationsAsync.isLoading && !locationsAsync.hasValue && !locationsAsync.hasError;
    final state = locationsAsync.hasError && !locationsAsync.hasValue
        ? _ListBodyState.unavailable
        : isLoading
        ? _ListBodyState.loading
        : _ListBodyState.content;

    final shellState = switch (state) {
      _ListBodyState.loading => ListShellState.loading,
      _ListBodyState.unavailable => ListShellState.unavailable,
      _ListBodyState.content => ListShellState.content,
    };

    return ListShell(
      title: 'Sedi',
      subtitle: 'Dove andare, per quale cliente, con cosa è aperto.',
      showBack: true,
      action: CapabilityGate(
        capability: 'clienti.location.write',
        child: ListHeaderAction(label: 'Nuovo', onPressed: () => context.push('/altro/sedi/nuova')),
      ),
      banner: const OfflineSyncBanner(),
      searchController: searchCtrl,
      searchHint: 'Cerca sede, cliente, indirizzo o città…',
      onSearchChanged: onQueryChanged,
      filters: [
        for (final status in _SedeStatusFilter.values)
          ListFilterChipData(label: status.label, id: status.id),
      ],
      activeFilterId: activeFilters.status.id,
      onFilterSelected: onSelectStatus,
      onOpenFilters: () {
        onOpenFilters(clients: clients, cities: cities);
      },
      groups: groups,
      summary: groups.isEmpty
          ? null
          : ListSummaryData(left: _sediLabel(filtered.length), right: '$withTickets con ticket'),
      state: shellState,
      empty: _emptyState(
        query: query,
        hasLocations: allLocations.isNotEmpty,
        hasActiveFilter: hasActiveFilter,
        neverSynced: neverSynced,
      ),
      unavailable: UnavailableState(
        icon: LucideIcons.alertTriangle,
        titolo: 'Sedi non disponibili',
        motivo: 'Non è stato possibile leggere le sedi salvate su questo telefono.',
        action: AppButton(
          label: 'Riprova',
          onPressed: () => ref.invalidate(adminLocationsProvider),
        ),
      ),
      onRefresh: () => refreshWithFeedback(context, ref),
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
    Map<String, DateTime> lastActivityByLocation,
    BusinessTime businessTime,
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
              _row(
                context,
                location,
                openTickets: openTicketCounts[location.id] ?? 0,
                lastActivity: lastActivityByLocation[location.id],
                businessTime: businessTime,
              ),
          ],
        ),
    ];
  }

  static ListRowData _row(
    BuildContext context,
    Location location, {
    required int openTickets,
    required DateTime? lastActivity,
    required BusinessTime businessTime,
  }) {
    final address = _text(location.address);
    final city = _text(location.city);
    final place = address ?? city;
    final activity = lastActivity;

    return ListRowData(
      title: location.name,
      meta: [?place, _ticketLabel(openTickets)].join(' · '),
      secondary: activity == null
          ? 'Nessuna attività recente'
          : 'Ultima attività ${formatWorkDate(businessTime.businessDateOf(activity), 'dd/MM')}',
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
    final colors = context.colors;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'Filtri',
                    style: AppTextStyles.headlineLarge.copyWith(color: colors.ink),
                  ),
                ),
                Text(
                  'SEDI',
                  style: AppTextStyles.docCode.copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: colors.accentInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Restringi per stato, cliente e città.',
              style: AppTextStyles.caption.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: 16),
            _SediSheetField(
              label: 'Stato',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in _SedeStatusFilter.values)
                    _SediFilterChoice(
                      key: ValueKey('sediFilterStatus-${status.id}'),
                      label: status.label,
                      active: _draft.status == status,
                      onTap: () => _setStatus(status),
                    ),
                ],
              ),
            ),
            if (widget.clients.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SediSheetField(
                label: 'Cliente',
                child: DropdownButtonFormField<String?>(
                  key: const Key('sediFilterCliente'),
                  initialValue: widget.clients.any((c) => c.id == _draft.customerId)
                      ? _draft.customerId
                      : null,
                  isExpanded: true,
                  decoration: _sheetFieldDecoration(context),
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
              _SediSheetField(
                label: 'Città',
                child: DropdownButtonFormField<String?>(
                  key: const Key('sediFilterCitta'),
                  initialValue: widget.cities.contains(_draft.city) ? _draft.city : null,
                  isExpanded: true,
                  decoration: _sheetFieldDecoration(context),
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
                    label: 'Applica filtri',
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

/// The prototype's mono micro-label above a sheet field (`.filter-label`).
class _SediSheetField extends StatelessWidget {
  const _SediSheetField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.docCode.copyWith(
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: context.colors.inkMuted,
          ),
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

InputDecoration _sheetFieldDecoration(BuildContext context) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: context.colors.bg2,
  contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
  border: OutlineInputBorder(
    borderRadius: AppRack.freeShape,
    borderSide: BorderSide(color: context.colors.borderLight),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: AppRack.freeShape,
    borderSide: BorderSide(color: context.colors.borderLight),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: AppRack.freeShape,
    borderSide: BorderSide(color: context.colors.ink),
  ),
);

class _SediFilterChoice extends StatelessWidget {
  const _SediFilterChoice({
    super.key,
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
