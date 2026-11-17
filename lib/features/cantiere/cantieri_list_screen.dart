// dart format width=100
// lib/features/cantiere/cantieri_list_screen.dart
//
// Technician-facing list of the operator's own cantieri (worksites) — the Cantieri tab.
// Deliberately not a reuse of admin_cantiere_list_screen.dart: that one is CRUD-oriented,
// office/admin-only. This one reads the local Drift mirror exactly as CantiereTimbraScreen's
// picker already does — already scoped server-side to the technician's own CantiereAssignment
// rows (falling back to all active cantieri when they have none).
//
// It reads `allCantieriProvider` rather than the timbra picker's `cantieriProvider` because the
// prototype has a `Chiusi` chip: that provider filters `status == 0` (active only), so closed
// cantieri would be unreachable. Same local table, same sync scope, no new network read — the
// timbra picker keeps using `cantieriProvider` untouched.
//
// Groups: `Da seguire oggi` (the same predicate as the sheet's `Solo da seguire oggi` toggle and
// the `N oggi` summary), `Altri cantieri attivi`, `Pianificati` (active with a future start date)
// and `Chiusi` (completed/cancelled). The prototype shows the first three; `Chiusi` exists so the
// `Chiusi` chip and the `Tutti` preset have somewhere to put their rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/time/business_time.dart' show formatWorkDate;
import '../../core/time/business_time_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_freshness_provider.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../presentation/providers/schedule_providers.dart'
    show allCantieriProvider, allCustomersProvider;
import '../timbra/cantiere_timbra_screen.dart'
    show cantiereActiveSessionProvider, formatHoursMinutes, todayCantiereEventsProvider;

/// The four quick-filter presets from `filterConfig.cantieri` / the prototype chip row.
enum _CantiereFilter { attivi, tutti, pianificati, chiusi }

extension on _CantiereFilter {
  String get id => name;

  String get label => switch (this) {
    _CantiereFilter.attivi => 'Attivi',
    _CantiereFilter.tutti => 'Tutti',
    _CantiereFilter.pianificati => 'Pianificati',
    _CantiereFilter.chiusi => 'Chiusi',
  };

  /// Only the presets that can contain a cantiere punched today. Under `Pianificati`/`Chiusi`
  /// the `Solo da seguire oggi` toggle is guaranteed to empty the list, so it is not offered.
  bool get supportsTodayFilter => this == _CantiereFilter.attivi || this == _CantiereFilter.tutti;
}

/// The quick chip plus every facet reachable from the `Filtri` sheet.
///
/// Cliente/Sede/Periodo read columns already on the local `Cantieri` mirror. `Squadra` has no
/// local column (the crew mirror holds technicians, not a squadra name), so it is not offered.
class _CantiereFilters {
  const _CantiereFilters({
    this.status = _CantiereFilter.attivi,
    this.customerId,
    this.city,
    this.periodFrom,
    this.periodTo,
    this.onlyToday = false,
  });

  final _CantiereFilter status;
  final String? customerId;
  final String? city;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final bool onlyToday;

  _CantiereFilters copyWith({
    _CantiereFilter? status,
    String? customerId,
    bool clearCustomer = false,
    String? city,
    bool clearCity = false,
    DateTime? periodFrom,
    bool clearPeriodFrom = false,
    DateTime? periodTo,
    bool clearPeriodTo = false,
    bool? onlyToday,
  }) {
    return _CantiereFilters(
      status: status ?? this.status,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      city: clearCity ? null : (city ?? this.city),
      periodFrom: clearPeriodFrom ? null : (periodFrom ?? this.periodFrom),
      periodTo: clearPeriodTo ? null : (periodTo ?? this.periodTo),
      onlyToday: onlyToday ?? this.onlyToday,
    );
  }
}

/// Crew size per cantiere from the local assignment mirror, one stream for the whole list.
///
/// Deliberately local-only: `cantiereCrewAssignmentsProvider` is online-first and would fire one
/// request per row at page open.
final _cantiereCrewCountsProvider = StreamProvider.autoDispose<Map<String, int>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.cantiereCrewAssignments).watch().map((rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row.cantiereId] = (counts[row.cantiereId] ?? 0) + 1;
    }
    return counts;
  });
});

class CantieriListScreen extends ConsumerStatefulWidget {
  const CantieriListScreen({super.key});

  @override
  ConsumerState<CantieriListScreen> createState() => _CantieriListScreenState();
}

class _CantieriListScreenState extends ConsumerState<CantieriListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  _CantiereFilters _filters = const _CantiereFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectFilter(ListFilterChipData chip) {
    final status = _CantiereFilter.values.firstWhere(
      (f) => f.id == chip.id,
      orElse: () => _CantiereFilter.attivi,
    );
    setState(() {
      _filters = _filters.copyWith(
        status: status,
        // A today-only restriction cannot be met by a planned/closed-only set; clear it rather
        // than leave the quick chip showing an empty list for a reason the user cannot see.
        onlyToday: status.supportsTodayFilter ? _filters.onlyToday : false,
      );
    });
  }

  Future<void> _openFilterSheet({
    required List<({String id, String name})> clients,
    required List<String> cities,
  }) async {
    final result = await showModalBottomSheet<_CantiereFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CantiereFilterSheet(initial: _filters, clients: clients, cities: cities),
    );
    if (result != null && mounted) {
      setState(() => _filters = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cantieriAsync = ref.watch(allCantieriProvider);
    final allCantieri = cantieriAsync.value ?? const [];
    final customers = ref.watch(allCustomersProvider).value ?? const [];
    final customersById = {for (final c in customers) c.id: c};
    final crewCounts = ref.watch(_cantiereCrewCountsProvider).value ?? const {};
    final businessTime = ref.watch(businessTimeProvider);
    final activeSession = ref.watch(cantiereActiveSessionProvider);
    final activeCantiereId = activeSession?.cantiereId;

    // Today's punches already come from one local stream. Pair them ingresso→uscita sequentially
    // (exactly like `cantiereTodayHoursProvider`) so multiple visits to the same cantiere stay
    // separate intervals; a min-start/max-end envelope would include time spent elsewhere.
    final todayEvents = ref.watch(todayCantiereEventsProvider).value ?? const [];
    final todayIntervals = <String, List<({DateTime start, DateTime end})>>{};
    final todayHoursById = <String, Duration>{};
    CantierePunche? opener;
    for (final event in todayEvents) {
      switch (event.eventType) {
        case 'ingresso':
          opener = event;
        case 'uscita':
          final open = opener;
          final cantiereId = open?.cantiereId;
          if (open != null && cantiereId != null && !event.eventTime.isBefore(open.eventTime)) {
            (todayIntervals[cantiereId] ??= []).add((start: open.eventTime, end: event.eventTime));
            todayHoursById[cantiereId] =
                (todayHoursById[cantiereId] ?? Duration.zero) +
                event.eventTime.difference(open.eventTime);
          }
          opener = null;
      }
    }

    bool isPlanned(CantieriData c) =>
        c.status == 0 && c.startDate != null && c.startDate!.isAfter(businessTime.businessToday());

    bool isToday(CantieriData c) =>
        c.status == 0 &&
        ((todayHoursById[c.id] ?? Duration.zero) > Duration.zero || activeCantiereId == c.id);

    bool matchesStatus(CantieriData c) => switch (_filters.status) {
      _CantiereFilter.attivi => c.status == 0,
      _CantiereFilter.pianificati => isPlanned(c),
      _CantiereFilter.chiusi => c.status != 0,
      _CantiereFilter.tutti => true,
    };

    bool matchesPeriod(CantieriData c) {
      final from = _filters.periodFrom;
      final to = _filters.periodTo;
      if (from == null && to == null) return true;
      final start = c.startDate;
      final end = c.endDate;
      if (start == null && end == null) return false;
      final fromStart = from == null ? null : businessTime.utcRangeForBusinessDate(from).$1;
      final toEnd = to == null ? null : businessTime.utcRangeForBusinessDate(to).$2;
      if (fromStart != null && end != null && end.isBefore(fromStart)) return false;
      if (toEnd != null && start != null && !start.isBefore(toEnd)) return false;
      return true;
    }

    final q = _query.trim().toLowerCase();
    final filtered = allCantieri.where((c) {
      if (!matchesStatus(c)) return false;
      if (_filters.onlyToday && !isToday(c)) return false;
      if (_filters.customerId != null && c.customerId != _filters.customerId) return false;
      if (_filters.city != null && c.city != _filters.city) return false;
      if (!matchesPeriod(c)) return false;
      if (q.isEmpty) return true;
      final customerName = c.customerId == null ? null : customersById[c.customerId]?.companyName;
      return c.name.toLowerCase().contains(q) ||
          (customerName?.toLowerCase().contains(q) ?? false) ||
          (c.address?.toLowerCase().contains(q) ?? false) ||
          (c.city?.toLowerCase().contains(q) ?? false);
    }).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final todayLabel = activeSession == null
        ? null
        : businessTime.formatInZone(activeSession.startTime, 'HH:mm');

    ListRowData rowFor(CantieriData c, {required bool isToday, required bool isPlanned}) {
      final customerName = c.customerId == null ? null : customersById[c.customerId]?.companyName;
      final place = c.city ?? c.address;
      final crew = crewCounts[c.id] ?? 0;
      final meta = [
        if (customerName != null && customerName.trim().isNotEmpty) customerName,
        if (place != null && place.trim().isNotEmpty) place,
        if (crew > 0) '$crew ${crew == 1 ? 'operatore' : 'operatori'}',
      ].join(' · ');

      final String secondary;
      if (isToday) {
        if (activeCantiereId == c.id && todayLabel != null) {
          secondary = 'In corso · dalle $todayLabel';
        } else {
          final intervals = todayIntervals[c.id] ?? const [];
          // One visit keeps the prototype's `08:30–12:30` range. Two or more visits cannot be
          // collapsed into one range without claiming time spent on another cantiere, so show
          // the day's summed duration instead.
          final rangeLabel = intervals.length == 1
              ? '${businessTime.formatInZone(intervals.single.start, 'HH:mm')}–'
                    '${businessTime.formatInZone(intervals.single.end, 'HH:mm')}'
              : null;
          secondary = rangeLabel == null
              ? 'Timbrato oggi · ${formatHoursMinutes(todayHoursById[c.id] ?? Duration.zero)}'
              : 'Timbrato oggi · $rangeLabel';
        }
      } else if (isPlanned) {
        secondary = 'Inizio · ${formatWorkDate(c.startDate!, 'dd/MM')}';
      } else if (c.status == 0) {
        secondary = 'Nessuna attività oggi';
      } else if (c.status == 1) {
        secondary = c.endDate == null
            ? 'Completato'
            : 'Completato · ${formatWorkDate(c.endDate!, 'dd/MM')}';
      } else {
        secondary = 'Annullato';
      }

      final (statusLabel, statusTone) = switch ((c.status, isPlanned)) {
        (0, true) => ('Pianificato', ListStatusTone.info),
        (0, false) => ('Attivo', ListStatusTone.good),
        (1, _) => ('Completato', ListStatusTone.neutral),
        _ => ('Annullato', ListStatusTone.bad),
      };

      return ListRowData(
        title: c.name,
        meta: meta.isEmpty ? null : meta,
        secondary: secondary,
        status: statusLabel,
        statusTone: statusTone,
        onTap: () => context.push(AppRoutes.cantieriDetailPath(c.id)),
        rowKey: ValueKey('cantiere-row-${c.id}'),
      );
    }

    final today = <CantieriData>[];
    final otherActive = <CantieriData>[];
    final planned = <CantieriData>[];
    final closed = <CantieriData>[];
    for (final c in filtered) {
      if (isToday(c)) {
        today.add(c);
      } else if (isPlanned(c)) {
        planned.add(c);
      } else if (c.status == 0) {
        otherActive.add(c);
      } else {
        closed.add(c);
      }
    }

    // "Da seguire oggi" reads as the day's sequence, not as an alphabet: order it by the first
    // check-in. Other groups stay alphabetical, matching the list's existing order.
    today.sort((a, b) {
      final intervalsA = todayIntervals[a.id];
      final intervalsB = todayIntervals[b.id];
      final startA = intervalsA == null || intervalsA.isEmpty ? null : intervalsA.first.start;
      final startB = intervalsB == null || intervalsB.isEmpty ? null : intervalsB.first.start;
      if (startA == null && startB == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (startA == null) return 1;
      if (startB == null) return -1;
      return startA.compareTo(startB);
    });

    final groups = <ListGroupData>[
      if (today.isNotEmpty)
        ListGroupData(
          title: 'Da seguire oggi',
          count: today.length,
          rows: [for (final c in today) rowFor(c, isToday: true, isPlanned: false)],
        ),
      if (otherActive.isNotEmpty)
        ListGroupData(
          title: 'Altri cantieri attivi',
          count: otherActive.length,
          rows: [for (final c in otherActive) rowFor(c, isToday: false, isPlanned: false)],
        ),
      if (planned.isNotEmpty)
        ListGroupData(
          title: 'Pianificati',
          count: planned.length,
          rows: [for (final c in planned) rowFor(c, isToday: false, isPlanned: true)],
        ),
      if (closed.isNotEmpty)
        ListGroupData(
          title: 'Chiusi',
          count: closed.length,
          rows: [for (final c in closed) rowFor(c, isToday: false, isPlanned: false)],
        ),
    ];

    final activeCount = filtered.where((c) => c.status == 0).length;
    final closedCount = filtered.length - activeCount;
    final todayCount = filtered.where(isToday).length;

    // The prototype's `8 cantieri attivi · 2 oggi` line, kept honest about what is on screen:
    // under the `Chiusi` chip the left half reports closed cantieri instead of a misleading
    // "0 cantieri attivi", and singular counts read as Italian (1 cantiere, not 1 cantieri).
    final (summaryLeft, summaryNoun) = switch (_filters.status) {
      _CantiereFilter.chiusi => (
        closedCount,
        closedCount == 1 ? 'cantiere chiuso' : 'cantieri chiusi',
      ),
      _CantiereFilter.pianificati => (
        activeCount,
        activeCount == 1 ? 'cantiere pianificato' : 'cantieri pianificati',
      ),
      _ => (activeCount, activeCount == 1 ? 'cantiere attivo' : 'cantieri attivi'),
    };

    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).value == false;

    final isLoading = cantieriAsync.isLoading && !cantieriAsync.hasValue && !cantieriAsync.hasError;
    final state = cantieriAsync.hasError
        ? ListShellState.unavailable
        : isLoading
        ? ListShellState.loading
        : ListShellState.content;

    final empty = allCantieri.isEmpty
        ? (neverSynced
              ? const UnavailableState(
                  icon: LucideIcons.cloudOff,
                  titolo: 'Cantieri non ancora scaricati',
                  motivo:
                      'Questo telefono non ha ancora completato una sincronizzazione: i '
                      'cantieri compariranno qui appena i dati saranno scaricati.',
                )
              : const UnavailableState(
                  icon: LucideIcons.hardHat,
                  titolo: 'Nessun cantiere in corso',
                  motivo:
                      'Non risultano cantieri attivi tra quelli che ti sono assegnati. '
                      'Trascina in basso per aggiornare.',
                ))
        : const EmptyState(
            icon: LucideIcons.searchX,
            title: 'Nessun risultato',
            body: 'Nessun cantiere corrisponde a ricerca e filtri selezionati.',
          );

    // The sheet's Cliente options are only customers that actually appear on a cantiere this
    // device holds; Sede is the cantiere's own city column (there is no separate location link).
    final clientOptions = <({String id, String name})>[];
    for (final c in allCantieri) {
      final id = c.customerId;
      if (id == null) continue;
      final name = customersById[id]?.companyName;
      if (name == null) continue;
      if (clientOptions.any((o) => o.id == id)) continue;
      clientOptions.add((id: id, name: name));
    }
    clientOptions.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final cities = <String>{
      for (final c in allCantieri)
        if (c.city != null && c.city!.trim().isNotEmpty) c.city!.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListShell(
      title: 'Cantieri',
      subtitle: 'Cosa devo seguire oggi, e quali cantieri sono ancora attivi.',
      banner: const OfflineSyncBanner(),
      searchHint: 'Cerca cantiere, cliente, indirizzo o codice…',
      searchController: _searchCtrl,
      onSearchChanged: (v) => setState(() => _query = v),
      filters: [
        for (final f in _CantiereFilter.values) ListFilterChipData(label: f.label, id: f.id),
      ],
      activeFilterId: _filters.status.id,
      onFilterSelected: _selectFilter,
      onOpenFilters: () => _openFilterSheet(clients: clientOptions, cities: cities),
      groups: groups,
      summary: filtered.isEmpty
          ? null
          : ListSummaryData(left: '$summaryLeft $summaryNoun', right: '$todayCount oggi'),
      state: state,
      empty: empty,
      unavailable: UnavailableState(
        icon: LucideIcons.hardHat,
        titolo: 'Impossibile caricare i cantieri',
        motivo: 'Non è stato possibile leggere i cantieri salvati su questo telefono.',
        action: AppButton(label: 'Riprova', onPressed: () => ref.invalidate(allCantieriProvider)),
      ),
      onRefresh: () => refreshWithFeedback(context, ref),
    );
  }
}

/// The real `Filtri` sheet behind the red chip. Status, Cliente, Sede, Periodo and the same
/// `Solo da seguire oggi` predicate the groups/summary use. `Squadra` is omitted: there is no
/// squadra column on the local cantiere mirror (only a list of assigned technicians).
class _CantiereFilterSheet extends StatefulWidget {
  const _CantiereFilterSheet({required this.initial, required this.clients, required this.cities});

  final _CantiereFilters initial;
  final List<({String id, String name})> clients;
  final List<String> cities;

  @override
  State<_CantiereFilterSheet> createState() => _CantiereFilterSheetState();
}

class _CantiereFilterSheetState extends State<_CantiereFilterSheet> {
  late _CantiereFilters _draft = widget.initial;

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _draft.periodFrom : _draft.periodTo) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      helpText: isFrom ? 'Periodo · da' : 'Periodo · a',
    );
    if (picked == null) return;
    if (!mounted) return;
    final civil = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      _draft = isFrom ? _draft.copyWith(periodFrom: civil) : _draft.copyWith(periodTo: civil);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');

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
              'Restringi per stato, cliente, sede e periodo.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Stato',
              child: DropdownButtonFormField<_CantiereFilter>(
                key: const Key('cantieriFilterStato'),
                initialValue: _draft.status,
                items: [
                  for (final f in _CantiereFilter.values)
                    DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _draft = _draft.copyWith(
                      status: v,
                      onlyToday: v.supportsTodayFilter ? _draft.onlyToday : false,
                    );
                  });
                },
              ),
            ),
            if (widget.clients.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Cliente',
                child: DropdownButtonFormField<String?>(
                  key: const Key('cantieriFilterCliente'),
                  initialValue: _draft.customerId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutti')),
                    for (final c in widget.clients)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
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
                label: 'Sede',
                child: DropdownButtonFormField<String?>(
                  key: const Key('cantieriFilterSede'),
                  initialValue: _draft.city,
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
            AppFieldShell(
              label: 'Periodo',
              child: Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Da',
                      value: _draft.periodFrom == null
                          ? 'Qualsiasi'
                          : dateFmt.format(_draft.periodFrom!),
                      onTap: () => _pickDate(isFrom: true),
                      onClear: _draft.periodFrom == null
                          ? null
                          : () => setState(() => _draft = _draft.copyWith(clearPeriodFrom: true)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'A',
                      value: _draft.periodTo == null
                          ? 'Qualsiasi'
                          : dateFmt.format(_draft.periodTo!),
                      onTap: () => _pickDate(isFrom: false),
                      onClear: _draft.periodTo == null
                          ? null
                          : () => setState(() => _draft = _draft.copyWith(clearPeriodTo: true)),
                    ),
                  ),
                ],
              ),
            ),
            if (_draft.status.supportsTodayFilter) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('cantieriFilterOnlyToday'),
                contentPadding: EdgeInsets.zero,
                value: _draft.onlyToday,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(onlyToday: v)),
                title: const Text('Solo da seguire oggi'),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('cantieriFilterReset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _CantiereFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('cantieriFilterApply'),
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

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.onClear});

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRack.freeShape,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.borderMedium),
          borderRadius: AppRack.freeShape,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: context.colors.inkMuted),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Rimuovi data',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              )
            else
              Icon(LucideIcons.calendarDays, size: 18, color: context.colors.inkMuted),
          ],
        ),
      ),
    );
  }
}
