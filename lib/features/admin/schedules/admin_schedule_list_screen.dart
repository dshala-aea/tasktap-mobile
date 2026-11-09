// dart format width=100
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/time/business_time.dart' show formatWorkDate;
import '../../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../../../features/calendario/calendario_providers.dart';
import '../../../features/calendario/views/mese_view.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../ticket/steps/step_assegnazione.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import '../squadre/admin_squadra_list_screen.dart' show adminSquadreProvider;

/// All schedules from Drift cache, ordered by date desc.
final adminSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)..orderBy([(s) => OrderingTerm.desc(s.activityDate)])).watch();
});

/// The admin schedule list's filters, beyond the title search.
///
/// `squadraId` is not itself a filterable field anywhere on-device (no squadra id is synced to a
/// schedule row — see `teamAssignedScheduleIdsProvider`'s doc comment in `schedule_providers.dart`),
/// so filtering by squadra means fetching that squadra's *members* once
/// (`AdminApiClient.fetchSquadraDetail`) and matching schedules whose `ScheduleAssignees` intersect
/// them — see `_squadraMemberIdsProvider` below.
///
/// `GET /api/schedules` only accepts `userId`/`dateFrom`/`dateTo`/`statusId` as of this pass — the
/// `squadraId`/`ticketId` query params this screen's filters were originally scoped against had
/// not landed on `SchedulesController` yet when this was built (checked directly against
/// `SchedulesController.cs` in the backend repo). Every filter here is therefore applied
/// client-side, over the already-synced local mirror, rather than as a live query — which is also
/// the offline-first pattern every other list in this app already follows
/// (`schedulesInRangeProvider`, `adminSchedulesProvider` itself).
class AdminScheduleFilters {
  const AdminScheduleFilters({
    this.dateFrom,
    this.dateTo,
    this.statusId,
    this.technicianId,
    this.squadraId,
    this.ticketId,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? statusId;
  final String? technicianId;
  final String? squadraId;
  final String? ticketId;

  bool get isEmpty =>
      dateFrom == null &&
      dateTo == null &&
      statusId == null &&
      technicianId == null &&
      squadraId == null &&
      ticketId == null;

  /// One active *facet*, not one active bound: a date range is one filter even though it carries
  /// two dates. The old code counted both, so `Oggi` (from = to = today) read as "2 filtri".
  int get activeCount =>
      (dateFrom != null || dateTo != null ? 1 : 0) +
      (statusId != null ? 1 : 0) +
      (technicianId != null ? 1 : 0) +
      (squadraId != null ? 1 : 0) +
      (ticketId != null ? 1 : 0);

  AdminScheduleFilters copyWith({
    DateTime? Function()? dateFrom,
    DateTime? Function()? dateTo,
    int? Function()? statusId,
    String? Function()? technicianId,
    String? Function()? squadraId,
    String? Function()? ticketId,
  }) {
    return AdminScheduleFilters(
      dateFrom: dateFrom != null ? dateFrom() : this.dateFrom,
      dateTo: dateTo != null ? dateTo() : this.dateTo,
      statusId: statusId != null ? statusId() : this.statusId,
      technicianId: technicianId != null ? technicianId() : this.technicianId,
      squadraId: squadraId != null ? squadraId() : this.squadraId,
      ticketId: ticketId != null ? ticketId() : this.ticketId,
    );
  }
}

/// Members of the given squadra, fetched live — used only while a squadra filter is active.
final _squadraMemberIdsProvider = FutureProvider.autoDispose.family<Set<String>, String>((
  ref,
  squadraId,
) async {
  final api = ref.watch(adminApiClientProvider);
  final detail = await api.fetchSquadraDetail(squadraId);
  final membri = (detail?['membri'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  return membri.map((m) => m['userId'] as String).toSet();
});

enum _ViewMode { calendario, elenco }

/// The prototype's quick date presets. Each is the same date-range facet the `Filtri` sheet
/// already edits — no new date rule, just a shortcut to a range.
enum _DatePreset { oggi, settimana, futuro, tutte }

extension on _DatePreset {
  String get id => name;

  String get label => switch (this) {
    _DatePreset.oggi => 'Oggi',
    _DatePreset.settimana => 'Settimana',
    _DatePreset.futuro => 'Futuro',
    _DatePreset.tutte => 'Tutte',
  };
}

/// The three sections the prototype's elenco is grouped into, plus `Passato`.
///
/// `Passato` is not in the mockup, but the old elenco showed every mirrored schedule; dropping
/// past work from `Tutte` would have removed rows. It stays last and hidden while empty.
enum _DateBucket { oggi, settimana, futuro, passato }

extension on _DateBucket {
  String get title => switch (this) {
    _DateBucket.oggi => 'Oggi',
    _DateBucket.settimana => 'Questa settimana',
    _DateBucket.futuro => 'Futuro',
    _DateBucket.passato => 'Passato',
  };
}

DateTime _civilDate(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime _weekStart(DateTime civilDay) => civilDay.subtract(Duration(days: civilDay.weekday - 1));

bool _sameDay(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

_DatePresetMatch _presetOf(AdminScheduleFilters filters, DateTime today) {
  final weekStart = _weekStart(today);
  final weekEnd = weekStart.add(const Duration(days: 6));
  final nextWeek = weekStart.add(const Duration(days: 7));

  if (filters.dateFrom == null && filters.dateTo == null) return _DatePresetMatch.tutte;
  if (_sameDay(filters.dateFrom, today) && _sameDay(filters.dateTo, today)) {
    return _DatePresetMatch.oggi;
  }
  if (_sameDay(filters.dateFrom, weekStart) && _sameDay(filters.dateTo, weekEnd)) {
    return _DatePresetMatch.settimana;
  }
  if (_sameDay(filters.dateFrom, nextWeek) && filters.dateTo == null) {
    return _DatePresetMatch.futuro;
  }
  return _DatePresetMatch.custom;
}

/// `null` when the active date range came from the sheet rather than from a chip.
enum _DatePresetMatch { oggi, settimana, futuro, tutte, custom }

/// Admin schedule list — a real calendar (month grid) plus the prototype's grouped `elenco`.
///
/// The calendar/elenco toggle, the filter bottom sheet and every facet it carries (date range,
/// status, technician, squadra, ticket) are the existing ones; only the elenco's presentation and
/// the quick date chips are new.
class AdminScheduleListScreen extends ConsumerStatefulWidget {
  const AdminScheduleListScreen({super.key, this.initialSquadraId});

  /// Pre-applies the squadra filter when navigated here from that squadra's detail screen (Gap 9
  /// of the feature audit) — see `admin_squadra_detail_screen.dart`'s "Pianificazioni squadra"
  /// header action and the `pianificazioni` route's builder in `app_router.dart`.
  final String? initialSquadraId;

  @override
  ConsumerState<AdminScheduleListScreen> createState() => _AdminScheduleListScreenState();
}

class _AdminScheduleListScreenState extends ConsumerState<AdminScheduleListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  _ViewMode _viewMode = _ViewMode.calendario;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  AdminScheduleFilters _filters = const AdminScheduleFilters();

  @override
  void initState() {
    super.initState();
    if (widget.initialSquadraId != null) {
      _filters = AdminScheduleFilters(squadraId: widget.initialSquadraId);
      // The calendar tab still respects the filter (it just highlights matching days), but arriving
      // here to look at *this squadra's* schedule reads better landing straight on the filtered
      // elenco than on an unfiltered month grid the admin then has to interpret against a filter
      // they can't see applied.
      _viewMode = _ViewMode.elenco;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(ListFilterChipData chip) {
    final preset = _DatePreset.values.firstWhere(
      (p) => p.id == chip.id,
      orElse: () => _DatePreset.tutte,
    );
    final today = ref.read(businessTimeProvider).businessToday();
    final weekStart = _weekStart(today);
    final (DateTime? from, DateTime? to) = switch (preset) {
      _DatePreset.oggi => (today, today),
      _DatePreset.settimana => (weekStart, weekStart.add(const Duration(days: 6))),
      _DatePreset.futuro => (weekStart.add(const Duration(days: 7)), null),
      _DatePreset.tutte => (null, null),
    };
    setState(() {
      _filters = _filters.copyWith(dateFrom: () => from, dateTo: () => to);
      _selectedDay = null;
    });
  }

  void _openFilterSheet() async {
    final result = await showModalBottomSheet<AdminScheduleFilters>(
      context: context,
      // Same exposure as the Calendario schedule sheet: this list is the `pianificazioni` route in
      // the "altro" StatefulShellBranch (no `parentNavigatorKey: rootNavigatorKey`), so its context
      // resolves to the branch navigator and — under HomeShell's `extendBody: true` Scaffold — the
      // sheet would be painted under the floating AppBottomNav. Push on the root navigator instead.
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FilterSheet(initial: _filters),
    );
    if (result != null) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(businessTimeProvider).businessToday();
    final preset = _presetOf(_filters, today);

    return _AdminScheduleListBody(
      query: _query,
      searchCtrl: _searchCtrl,
      onQueryChanged: (q) => setState(() => _query = q),
      viewMode: _viewMode,
      onViewModeChanged: (v) => setState(() => _viewMode = v),
      calendarMonth: _calendarMonth,
      onMonthChanged: (m) => setState(() => _calendarMonth = m),
      selectedDay: _selectedDay,
      onDayTap: (d) => setState(() {
        _selectedDay = d;
        _filters = _filters.copyWith(dateFrom: () => d, dateTo: () => d);
        _viewMode = _ViewMode.elenco;
      }),
      filters: _filters,
      activePresetId: preset == _DatePresetMatch.custom ? null : preset.name,
      onSelectPreset: _selectPreset,
      onOpenFilters: _openFilterSheet,
      onClearFilters: () => setState(() {
        _filters = const AdminScheduleFilters();
        _selectedDay = null;
      }),
    );
  }
}

class _AdminScheduleListBody extends ConsumerWidget {
  const _AdminScheduleListBody({
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.calendarMonth,
    required this.onMonthChanged,
    required this.selectedDay,
    required this.onDayTap,
    required this.filters,
    required this.activePresetId,
    required this.onSelectPreset,
    required this.onOpenFilters,
    required this.onClearFilters,
  });

  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final DateTime calendarMonth;
  final ValueChanged<DateTime> onMonthChanged;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDayTap;
  final AdminScheduleFilters filters;
  final String? activePresetId;
  final ValueChanged<ListFilterChipData> onSelectPreset;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(adminSchedulesProvider);
    final allSchedules = schedulesAsync.valueOrNull ?? [];
    final assigneeMap = ref.watch(scheduleAssigneeMapProvider).valueOrNull ?? const {};
    final colleagues = ref.watch(allColleaguesProvider).valueOrNull ?? const [];
    final colleaguesById = {for (final c in colleagues) c.id: c.displayName};
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? const [];
    final locationsById = {for (final l in locations) l.id: l.name};

    final squadraMemberIds = filters.squadraId == null
        ? null
        : ref.watch(_squadraMemberIdsProvider(filters.squadraId!)).valueOrNull;

    final businessToday = ref.watch(businessTimeProvider).businessToday();

    String? technicianNameFor(Schedule s) {
      final direct = colleaguesById[s.userId];
      if (direct != null) return direct;
      final assignees = assigneeMap[s.id] ?? const <String>{};
      final names = <String>[
        for (final id in assignees)
          if (colleaguesById[id] != null) colleaguesById[id]!,
      ];
      return names.isEmpty ? null : names.join(', ');
    }

    final search = query.trim().toLowerCase();

    bool matchesQuery(Schedule s) {
      if (search.isEmpty) return true;
      final date = _civilDate(s.activityDate);
      final dateLabel = formatWorkDate(date, 'EEE d MMM y', locale: 'it');
      final numeric =
          '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/${date.year}';
      final iso =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final relative = date == businessToday
          ? 'oggi'
          : date == businessToday.add(const Duration(days: 1))
          ? 'domani'
          : '';
      final haystack = [
        s.title,
        locationsById[s.locationId] ?? '',
        technicianNameFor(s) ?? '',
        dateLabel,
        numeric,
        iso,
        relative,
      ].join(' ').toLowerCase();
      return haystack.contains(search);
    }

    bool matchesFilters(Schedule s) {
      if (!matchesQuery(s)) return false;
      if (filters.dateFrom != null) {
        final from = DateTime.utc(
          filters.dateFrom!.year,
          filters.dateFrom!.month,
          filters.dateFrom!.day,
        );
        if (s.activityDate.toUtc().isBefore(from)) return false;
      }
      if (filters.dateTo != null) {
        final to = DateTime.utc(
          filters.dateTo!.year,
          filters.dateTo!.month,
          filters.dateTo!.day,
        ).add(const Duration(days: 1));
        if (!s.activityDate.toUtc().isBefore(to)) return false;
      }
      if (filters.statusId != null && s.statusId != filters.statusId) return false;
      if (filters.ticketId != null && s.ticketId != filters.ticketId) return false;
      if (filters.technicianId != null) {
        final assignees = assigneeMap[s.id] ?? const <String>{};
        if (s.userId != filters.technicianId && !assignees.contains(filters.technicianId)) {
          return false;
        }
      }
      if (filters.squadraId != null) {
        final assignees = assigneeMap[s.id] ?? const <String>{};
        if (squadraMemberIds == null || assignees.intersection(squadraMemberIds).isEmpty) {
          return false;
        }
      }
      return true;
    }

    final filtered = allSchedules.where(matchesFilters).toList();

    final bucketOf = _bucketOf(businessToday);
    final buckets = {for (final bucket in _DateBucket.values) bucket: <Schedule>[]};
    for (final schedule in filtered) {
      buckets[bucketOf(schedule)]!.add(schedule);
    }
    for (final rows in buckets.values) {
      rows.sort((a, b) {
        final byDate = a.activityDate.compareTo(b.activityDate);
        if (byDate != 0) return byDate;
        return a.timeStartMinutes.compareTo(b.timeStartMinutes);
      });
    }

    String metaLine(Schedule s) {
      final date = _civilDate(s.activityDate);
      final time = s.allDay
          ? 'Tutto il giorno'
          : '${_fmtTime(s.timeStartMinutes)} – ${_fmtTime(s.timeEndMinutes)}';
      final dayPrefix = date == businessToday
          ? null
          : date == businessToday.add(const Duration(days: 1))
          ? 'Domani'
          : formatWorkDate(date, 'EEE d MMM', locale: 'it');
      final parts = <String>[
        if (dayPrefix == null) time else '$dayPrefix $time',
        if (technicianNameFor(s) != null) technicianNameFor(s)!,
        if (locationsById[s.locationId] != null) locationsById[s.locationId]!,
      ];
      return parts.join(' · ');
    }

    final groups = <ListGroupData>[
      for (final bucket in _DateBucket.values)
        if (buckets[bucket]!.isNotEmpty)
          ListGroupData(
            title: bucket.title,
            count: buckets[bucket]!.length,
            rows: [
              for (final s in buckets[bucket]!)
                ListRowData(
                  rowKey: ValueKey('schedule-${s.id}'),
                  title: s.title.isNotEmpty ? s.title : 'Intervento',
                  meta: metaLine(s),
                  status: scheduleStatusName(s.statusId),
                  // The prototype's `Pianificato` stamp is amber; the shared vocabulary maps that
                  // label to neutral, so the list states the tone it means.
                  statusTone: scheduleStatusName(s.statusId) == 'Pianificato'
                      ? ListStatusTone.warn
                      : null,
                  onTap: () => context.push('/altro/pianificazioni/${s.id}'),
                ),
            ],
          ),
    ];

    final todayCount = filtered.where((s) => _civilDate(s.activityDate) == businessToday).length;

    // Every filter here is client-side over the local mirror, so an empty result has the same 3
    // possible causes as the other admin lists: no match, no sync yet, or genuinely none.
    final hasActiveFilter = query.trim().isNotEmpty || !filters.isEmpty;
    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;

    final isLoading = schedulesAsync.isLoading && !schedulesAsync.hasValue;
    final isUnavailable = schedulesAsync.hasError && !schedulesAsync.hasValue;

    final summary = ListSummaryData(
      left: _impegniLabel(filtered.length),
      right: '$todayCount oggi',
    );
    final state = isLoading
        ? ListShellState.loading
        : isUnavailable
        ? ListShellState.unavailable
        : ListShellState.content;

    final tabs = AppTabs(
      tabs: const [
        AppTab(label: 'Calendario'),
        AppTab(label: 'Elenco'),
      ],
      selectedIndex: viewMode.index,
      onSelected: (i) => onViewModeChanged(_ViewMode.values[i]),
    );

    final clearFilters = filters.activeCount == 0
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppTappable(
                onTap: onClearFilters,
                child: ConstrainedBox(
                  key: const Key('clear-schedule-filters'),
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.x, size: 12, color: context.colors.inkMuted),
                        const SizedBox(width: 4),
                        Text(
                          'Rimuovi filtri (${filters.activeCount})',
                          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

    final filterChips = [
      for (final preset in _DatePreset.values)
        ListFilterChipData(label: preset.label, id: preset.id),
    ];

    // The calendar keeps its own chrome: it renders a scrollable month sliver, not the shell's
    // group/row model. The elenco is a normal grouped list and uses `ListShell`; both modes share
    // the same header, search, chips, tabs and clear-filters block.
    if (viewMode == _ViewMode.calendario) {
      return Scaffold(
        backgroundColor: context.colors.bg2,
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              AppSearchBar(
                controller: searchCtrl,
                hint: 'Cerca titolo, sede, tecnico o data…',
                onChanged: onQueryChanged,
              ),
              ListFilterRow(
                filters: filterChips,
                activeId: activePresetId,
                onSelected: onSelectPreset,
                onOpenFilters: onOpenFilters,
              ),
              tabs,
              ?clearFilters,
              Expanded(
                child: _calendarBody(
                  context: context,
                  ref: ref,
                  calendarMonth: calendarMonth,
                  onMonthChanged: onMonthChanged,
                  selectedDay: selectedDay,
                  onDayTap: onDayTap,
                  filtered: filtered,
                  isLoading: isLoading,
                  isUnavailable: isUnavailable,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListShell(
      title: 'Pianificazioni',
      subtitle: 'Gli impegni nel tempo, non i cantieri.',
      showBack: true,
      action: CapabilityGate(
        capability: 'pianificazione.schedule.write',
        child: ListHeaderAction(
          label: 'Nuovo',
          onPressed: () => context.push('/altro/pianificazioni/nuova'),
        ),
      ),
      searchController: searchCtrl,
      searchHint: 'Cerca titolo, sede, tecnico o data…',
      onSearchChanged: onQueryChanged,
      filters: filterChips,
      activeFilterId: activePresetId,
      onFilterSelected: onSelectPreset,
      onOpenFilters: onOpenFilters,
      bodyHeader: Column(mainAxisSize: MainAxisSize.min, children: [tabs, ?clearFilters]),
      groups: groups,
      summary: filtered.isEmpty ? null : summary,
      state: state,
      empty: _emptyState(
        query: query,
        hasActiveFilter: hasActiveFilter,
        hasSchedules: allSchedules.isNotEmpty,
        neverSynced: neverSynced,
      ),
      unavailable: UnavailableState(
        icon: LucideIcons.alertTriangle,
        titolo: 'Pianificazioni non disponibili',
        motivo: 'Non è stato possibile leggere le pianificazioni salvate su questo telefono.',
        action: AppButton(
          label: 'Riprova',
          onPressed: () => ref.invalidate(adminSchedulesProvider),
        ),
      ),
      onRefresh: () => refreshWithFeedback(context, ref),
    );
  }

  Widget _header(BuildContext context) {
    return ScreenHeader(
      title: 'Pianificazioni',
      subtitle: 'Gli impegni nel tempo, non i cantieri.',
      subtitleMaxLines: 2,
      showBack: true,
      actions: [
        CapabilityGate(
          capability: 'pianificazione.schedule.write',
          child: ListHeaderAction(
            label: 'Nuovo',
            onPressed: () => context.push('/altro/pianificazioni/nuova'),
          ),
        ),
      ],
    );
  }

  _DateBucket Function(Schedule) _bucketOf(DateTime today) {
    final weekStart = _weekStart(today);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return (schedule) {
      final date = _civilDate(schedule.activityDate);
      // `Settimana` is the whole business week (Mon–Sun), so Monday/Tuesday rows stay in
      // `Questa settimana` even when today is later in the week. `Passato` is previous weeks.
      if (date.isBefore(weekStart)) return _DateBucket.passato;
      if (date == today) return _DateBucket.oggi;
      if (!date.isAfter(weekEnd)) return _DateBucket.settimana;
      return _DateBucket.futuro;
    };
  }

  Widget _calendarBody({
    required BuildContext context,
    required WidgetRef ref,
    required DateTime calendarMonth,
    required ValueChanged<DateTime> onMonthChanged,
    required DateTime? selectedDay,
    required ValueChanged<DateTime> onDayTap,
    required List<Schedule> filtered,
    required bool isLoading,
    required bool isUnavailable,
  }) {
    Future<void> onRefresh() => refreshWithFeedback(context, ref);

    if (isLoading) {
      return _scrollable(context, const ListLoadingSkeleton(), onRefresh);
    }

    if (isUnavailable) {
      return _scrollable(
        context,
        UnavailableState(
          icon: LucideIcons.alertTriangle,
          titolo: 'Pianificazioni non disponibili',
          motivo: 'Non è stato possibile leggere le pianificazioni salvate su questo telefono.',
          action: AppButton(
            label: 'Riprova',
            onPressed: () => ref.invalidate(adminSchedulesProvider),
          ),
        ),
        onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _CalendarSliver(
            month: calendarMonth,
            selectedDay: selectedDay ?? DateTime.now(),
            schedules: filtered,
            onMonthChanged: onMonthChanged,
            onDayTap: onDayTap,
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
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

  Widget _emptyState({
    required String query,
    required bool hasActiveFilter,
    required bool hasSchedules,
    required bool neverSynced,
  }) {
    if (hasActiveFilter) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: query.trim().isNotEmpty
            ? 'Nessuna pianificazione corrisponde a "${query.trim()}".'
            : 'Nessuna pianificazione corrisponde ai filtri selezionati.',
      );
    }
    if (!hasSchedules && neverSynced) {
      return const UnavailableState(
        icon: LucideIcons.cloudOff,
        titolo: 'Pianificazioni non ancora scaricate',
        motivo:
            'Questo telefono non ha ancora completato una sincronizzazione. '
            'Le pianificazioni compariranno qui dopo la prossima: trascina in basso '
            'per aggiornare.',
      );
    }
    return const EmptyState(
      icon: LucideIcons.calendarDays,
      title: 'Nessuna pianificazione',
      body: 'Crea una nuova pianificazione con Nuovo in alto.',
    );
  }
}

String _impegniLabel(int count) => '$count ${count == 1 ? 'impegno' : 'impegni'}';

String _fmtTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// The month grid plus its own prev/next/today navigation — a real calendar, replacing the flat
/// title-search-only list this screen used to be limited to.
class _CalendarSliver extends StatelessWidget {
  const _CalendarSliver({
    required this.month,
    required this.selectedDay,
    required this.schedules,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<Schedule> schedules;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final monthLabel = _capitalise(DateFormat('MMMM y', 'it').format(month));

    return SliverToBoxAdapter(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1)),
                  icon: const Icon(LucideIcons.chevronLeft, size: 20),
                  tooltip: 'Mese precedente',
                ),
                Expanded(
                  child: Text(
                    monthLabel,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMedium.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1)),
                  icon: const Icon(LucideIcons.chevronRight, size: 20),
                  tooltip: 'Mese successivo',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 320,
            child: MeseView(
              month: month,
              selectedDate: selectedDay,
              schedules: schedules,
              onDayTap: onDayTap,
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalise(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final AdminScheduleFilters initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late DateTime? _dateFrom = widget.initial.dateFrom;
  late DateTime? _dateTo = widget.initial.dateTo;
  late int? _statusId = widget.initial.statusId;
  late String? _technicianId = widget.initial.technicianId;
  late String? _squadraId = widget.initial.squadraId;
  late String? _ticketId = widget.initial.ticketId;

  static const _statusIds = [1, 2, 3, 4, 5, 6, 7];

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final techniciansAsync = ref.watch(techniciansProvider);
    final technicians = techniciansAsync.valueOrNull ?? [];
    final squadreAsync = ref.watch(adminSquadreProvider);
    final squadre = squadreAsync.valueOrNull ?? [];
    final ticketsAsync = ref.watch(allTicketsProvider);
    final tickets = ticketsAsync.valueOrNull ?? [];
    final dateFmt = DateFormat('d MMM y', 'it');

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
            Row(
              children: [
                Expanded(
                  child: AdminDateField(
                    label: 'Da',
                    value: _dateFrom == null ? 'Qualsiasi' : dateFmt.format(_dateFrom!),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminDateField(
                    label: 'A',
                    value: _dateTo == null ? 'Qualsiasi' : dateFmt.format(_dateTo!),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Stato',
              child: DropdownButtonFormField<int?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _statusId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti')),
                  ..._statusIds.map(
                    (id) => DropdownMenuItem(value: id, child: Text(scheduleStatusName(id))),
                  ),
                ],
                onChanged: (v) => setState(() => _statusId = v),
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Tecnico',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _technicianId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti')),
                  ...technicians.map(
                    (t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _technicianId = v),
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Squadra',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _squadraId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte')),
                  ...squadre.map(
                    (s) => DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text(s['nome'] as String? ?? ''),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _squadraId = v),
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Ticket',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _ticketId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti')),
                  ...tickets.map(
                    (t) => DropdownMenuItem(
                      value: t.id,
                      child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _ticketId = v),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const AdminScheduleFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      AdminScheduleFilters(
                        dateFrom: _dateFrom,
                        dateTo: _dateTo,
                        statusId: _statusId,
                        technicianId: _technicianId,
                        squadraId: _squadraId,
                        ticketId: _ticketId,
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
