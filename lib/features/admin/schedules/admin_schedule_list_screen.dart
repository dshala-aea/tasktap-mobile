// dart format width=100
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../../features/calendario/calendario_providers.dart';
import '../../../features/calendario/views/mese_view.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../ticket/steps/step_assegnazione.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import '../squadre/admin_squadra_list_screen.dart' show adminSquadreProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? statusId;
  final String? technicianId;
  final String? squadraId;

  bool get isEmpty =>
      dateFrom == null &&
      dateTo == null &&
      statusId == null &&
      technicianId == null &&
      squadraId == null;

  int get activeCount => [
    dateFrom,
    dateTo,
    statusId,
    technicianId,
    squadraId,
  ].where((v) => v != null).length;

  AdminScheduleFilters copyWith({
    DateTime? Function()? dateFrom,
    DateTime? Function()? dateTo,
    int? Function()? statusId,
    String? Function()? technicianId,
    String? Function()? squadraId,
  }) {
    return AdminScheduleFilters(
      dateFrom: dateFrom != null ? dateFrom() : this.dateFrom,
      dateTo: dateTo != null ? dateTo() : this.dateTo,
      statusId: statusId != null ? statusId() : this.statusId,
      technicianId: technicianId != null ? technicianId() : this.technicianId,
      squadraId: squadraId != null ? squadraId() : this.squadraId,
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

/// Admin schedule list — a real calendar (month grid) plus a filterable elenco: date range,
/// status, squadra and technician, on top of the title search this screen used to be limited to.
class AdminScheduleListScreen extends StatefulWidget {
  const AdminScheduleListScreen({super.key, this.initialSquadraId});

  /// Pre-applies the squadra filter when navigated here from that squadra's detail screen (Gap 9
  /// of the feature audit) — see `admin_squadra_detail_screen.dart`'s "Pianificazioni squadra"
  /// header action and the `pianificazioni` route's builder in `app_router.dart`.
  final String? initialSquadraId;

  @override
  State<AdminScheduleListScreen> createState() => _AdminScheduleListScreenState();
}

class _AdminScheduleListScreenState extends State<AdminScheduleListScreen> {
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

  void _openFilterSheet() async {
    final result = await showModalBottomSheet<AdminScheduleFilters>(
      context: context,
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
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _AdminScheduleListBody(
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
          onOpenFilters: _openFilterSheet,
          onClearFilters: () => setState(() {
            _filters = const AdminScheduleFilters();
            _selectedDay = null;
          }),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuova pianificazione',
          onPressed: () => context.push('/altro/pianificazioni/nuova'),
        ),
      ),
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
  final VoidCallback onOpenFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(adminSchedulesProvider);
    final allSchedules = schedulesAsync.valueOrNull ?? [];
    final assigneeMap = ref.watch(scheduleAssigneeMapProvider).valueOrNull ?? const {};

    final squadraMemberIds = filters.squadraId == null
        ? null
        : ref.watch(_squadraMemberIdsProvider(filters.squadraId!)).valueOrNull;

    bool matchesFilters(Schedule s) {
      if (query.isNotEmpty && !s.title.toLowerCase().contains(query.toLowerCase())) return false;
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

    return RefreshIndicator(
      onRefresh: () => ref.read(syncProvider.notifier).performSync(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Pianificazioni',
              subtitle: '${filtered.length} totali',
              showBack: true,
            ),
          ),
          SliverToBoxAdapter(
            child: AppTabs(
              tabs: const [AppTab(label: 'Calendario'), AppTab(label: 'Elenco')],
              selectedIndex: viewMode.index,
              onSelected: (i) => onViewModeChanged(_ViewMode.values[i]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchBar(
                      controller: searchCtrl,
                      hint: 'Cerca per titolo…',
                      onChanged: onQueryChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(activeCount: filters.activeCount, onTap: onOpenFilters),
                ],
              ),
            ),
          ),
          if (!filters.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.pagePadding,
                  right: AppSpacing.pagePadding,
                  bottom: AppSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppTappable(
                    onTap: onClearFilters,
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
          if (schedulesAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxxl),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (viewMode == _ViewMode.calendario)
            _CalendarSliver(
              month: calendarMonth,
              selectedDay: selectedDay ?? DateTime.now(),
              schedules: filtered,
              onMonthChanged: onMonthChanged,
              onDayTap: onDayTap,
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.calendarDays,
                title: 'Nessuna pianificazione',
                body: 'Crea una nuova pianificazione con il pulsante +, o modifica i filtri.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final schedule = filtered[i];
                final dateLabel = DateFormat(
                  'EEE d MMM HH:mm',
                  'it',
                ).format(schedule.activityDate.toLocal());
                return _AdminScheduleRow(
                  schedule: schedule,
                  dateLabel: dateLabel,
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

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return AppTappable(
      onTap: onTap,
      color: active ? context.colors.surfaceInverse : context.colors.surface,
      border: Border.all(
        color: active ? context.colors.surfaceInverse : context.colors.borderMedium,
      ),
      borderRadius: AppRack.insetShape,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      semanticLabel: 'Filtri${active ? ' ($activeCount attivi)' : ''}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.filter,
            size: 16,
            color: active ? context.colors.inkInverse : context.colors.ink,
          ),
          if (active) ...[
            const SizedBox(width: 6),
            Text(
              '$activeCount',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.colors.inkInverse,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The month grid plus its own prev/next/today navigation — a real calendar, replacing the flat
/// title-search-only list this screen used to be limited to (the header comment used to claim
/// "filterable by date range" when nothing on this screen was).
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
                    style: TextStyle(
                      fontFamily: 'Sora',
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

  static String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
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
    final dateFmt = DateFormat('d MMM y', 'it');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom + 19,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const AdminScheduleFilters()),
                    child: const Text('Azzera'),
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

class _AdminScheduleRow extends StatelessWidget {
  const _AdminScheduleRow({required this.schedule, required this.dateLabel, required this.isLast});

  final Schedule schedule;
  final String dateLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: const RowIconTile(icon: LucideIcons.calendarDays),
      title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
      subtitle: dateLabel,
      showDivider: !isLast,
      onTap: () => context.push('/altro/pianificazioni/${schedule.id}'),
    );
  }
}
