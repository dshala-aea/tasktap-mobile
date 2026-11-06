// dart format width=100
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../../presentation/providers/schedule_providers.dart' show allCustomersProvider;
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The prototype's status presets, in the order the chip row shows them.
///
/// `Bozza` is deliberately absent from the quick chips (`Inviati · Controllati · Fatturati ·
/// Tutti`, as in `filterConfig.report`) but stays reachable in the `Filtri` sheet: a draft is a
/// report in the flow too, and the enum already had it.
enum _ReportFilter { inviato, controllato, fatturato, tutti, bozza }

extension _ReportFilterCopy on _ReportFilter {
  String get id => name;

  /// Quick-chip label (plural, as the prototype chips read).
  String get label => switch (this) {
    _ReportFilter.inviato => 'Inviati',
    _ReportFilter.controllato => 'Controllati',
    _ReportFilter.fatturato => 'Fatturati',
    _ReportFilter.tutti => 'Tutti',
    _ReportFilter.bozza => 'Bozza',
  };

  /// Group heading. Same plural vocabulary as the quick chips.
  String get groupTitle => switch (this) {
    _ReportFilter.inviato => 'Inviati',
    _ReportFilter.controllato => 'Controllati',
    _ReportFilter.fatturato => 'Fatturati',
    _ReportFilter.tutti => 'Tutti',
    _ReportFilter.bozza => 'Bozza',
  };

  /// The wire `ReportStatoEnum` name, or null for "no status filter".
  String? get statusMatch => switch (this) {
    _ReportFilter.inviato => 'Inviato',
    _ReportFilter.controllato => 'Controllato',
    _ReportFilter.fatturato => 'Fatturato',
    _ReportFilter.tutti => null,
    _ReportFilter.bozza => 'Bozza',
  };

  bool matches(String stato) => switch (this) {
    _ReportFilter.inviato => stato == 'Inviato',
    _ReportFilter.controllato => stato == 'Controllato',
    _ReportFilter.fatturato => stato == 'Fatturato',
    _ReportFilter.tutti => true,
    _ReportFilter.bozza => stato == 'Bozza',
  };

  /// The four groups the prototype renders, in order; a `Bozza` group only appears when the
  /// data has drafts in it.
  static const List<_ReportFilter> groups = [
    _ReportFilter.inviato,
    _ReportFilter.controllato,
    _ReportFilter.fatturato,
    _ReportFilter.bozza,
  ];
}

/// The quick status preset plus every combinable facet the real `Filtri` sheet offers.
///
/// Cliente/Sede/Ticket/Cantiere are ids already carried by the report row; names come from the
/// local mirrors. Periodo reads the report's own start/end dates. None of this is a new network
/// read.
class _ReportFilters {
  const _ReportFilters({
    this.status = _ReportFilter.inviato,
    this.customerId,
    this.locationId,
    this.ticketId,
    this.cantiereId,
    this.periodFrom,
    this.periodTo,
    this.onlyToControl = false,
  });

  final _ReportFilter status;
  final String? customerId;
  final String? locationId;
  final String? ticketId;
  final String? cantiereId;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final bool onlyToControl;

  _ReportFilters copyWith({
    _ReportFilter? status,
    String? customerId,
    bool clearCustomer = false,
    String? locationId,
    bool clearLocation = false,
    String? ticketId,
    bool clearTicket = false,
    String? cantiereId,
    bool clearCantiere = false,
    DateTime? periodFrom,
    bool clearPeriodFrom = false,
    DateTime? periodTo,
    bool clearPeriodTo = false,
    bool? onlyToControl,
  }) {
    return _ReportFilters(
      status: status ?? this.status,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      ticketId: clearTicket ? null : (ticketId ?? this.ticketId),
      cantiereId: clearCantiere ? null : (cantiereId ?? this.cantiereId),
      periodFrom: clearPeriodFrom ? null : (periodFrom ?? this.periodFrom),
      periodTo: clearPeriodTo ? null : (periodTo ?? this.periodTo),
      onlyToControl: onlyToControl ?? this.onlyToControl,
    );
  }
}

/// Admin report list — server-first, mirror when the server cannot be reached.
class AdminReportListScreen extends StatefulWidget {
  const AdminReportListScreen({super.key});

  @override
  State<AdminReportListScreen> createState() => _AdminReportListScreenState();
}

class _AdminReportListScreenState extends State<AdminReportListScreen> {
  String _query = '';
  _ReportFilters _filters = const _ReportFilters();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters(List<Map<String, dynamic>> reports) async {
    final result = await showModalBottomSheet<_ReportFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ReportFilterSheet(initial: _filters, reports: reports),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _AdminReportListBody(
          filter: _filters,
          query: _query,
          searchCtrl: _searchCtrl,
          onFiltersChanged: (f) => setState(() => _filters = f),
          onQueryChanged: (q) => setState(() => _query = q),
          onOpenFilters: _openFilters,
        ),
      ),
    );
  }
}

class _AdminReportListBody extends ConsumerWidget {
  const _AdminReportListBody({
    required this.filter,
    required this.query,
    required this.searchCtrl,
    required this.onFiltersChanged,
    required this.onQueryChanged,
    required this.onOpenFilters,
  });

  final _ReportFilters filter;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<_ReportFilters> onFiltersChanged;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function(List<Map<String, dynamic>> reports) onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statoFilter = StatoFilter(filter.status.statusMatch);
    final reportsAsync = ref.watch(adminReportsProvider(statoFilter));
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const [];
    final customerNames = {for (final c in customers) c.id: c.companyName};

    final data = reportsAsync.valueOrNull;
    final rawRows = data?.rows ?? const <Map<String, dynamic>>[];
    final fromMirror = data?.fromMirror ?? false;

    final filtered = rawRows.where((row) {
      final stato = row['stato'] as String? ?? 'Bozza';
      if (!filter.status.matches(stato)) return false;
      if (filter.onlyToControl && stato != 'Inviato') return false;
      if (filter.customerId != null && row['customerId'] != filter.customerId) {
        return false;
      }
      if (filter.locationId != null && row['locationId'] != filter.locationId) {
        return false;
      }
      if (filter.ticketId != null && row['ticketId'] != filter.ticketId) return false;
      if (filter.cantiereId != null && row['cantiereId'] != filter.cantiereId) {
        return false;
      }
      if (!_matchesPeriod(row, filter.periodFrom, filter.periodTo)) return false;
      final customer = customerNames[row['customerId']];
      return _matchesQuery(row, customer, query);
    }).toList();

    final groups = <ListGroupData>[
      for (final state in _ReportFilterCopy.groups)
        if (filtered.any((r) => state.matches(r['stato'] as String? ?? 'Bozza')))
          ListGroupData(
            title: state.groupTitle,
            count: filtered.where((r) => state.matches(r['stato'] as String? ?? 'Bozza')).length,
            rows: [
              for (final row in filtered.where(
                (r) => state.matches(r['stato'] as String? ?? 'Bozza'),
              ))
                _rowData(context, row, customerNames),
            ],
          ),
    ];

    final toControl = filtered.where((r) => (r['stato'] as String? ?? 'Bozza') == 'Inviato').length;

    final isLoading = reportsAsync.isLoading && !reportsAsync.hasValue;
    final empty = rawRows.isEmpty
        ? const EmptyState(
            icon: LucideIcons.fileText,
            title: 'Nessun rapporto di intervento',
            body: 'Non ci sono rapporti di intervento per questo filtro.',
          )
        : EmptyState(
            icon: LucideIcons.searchX,
            title: 'Nessun risultato',
            body: query.trim().isNotEmpty
                ? 'Nessun report corrisponde a "$query".'
                : 'Nessun report corrisponde ai filtri selezionati.',
          );

    Future<void> onRefresh() => ref.refresh(adminReportsProvider(statoFilter).future);

    final Widget content;
    if (reportsAsync.hasError) {
      content = _scrollable(
        context,
        onRefresh: onRefresh,
        reportsAsync.error is TicketDetailOfflineException
            ? const UnavailableState(
                icon: LucideIcons.fileText,
                titolo: 'Rapporti di intervento non disponibili offline',
                motivo:
                    'Questo dispositivo non ha ancora scaricato i rapporti di intervento. Apri '
                    'questa lista con una connessione attiva per averli anche offline.',
              )
            : UnavailableState(
                icon: LucideIcons.alertTriangle,
                titolo: 'Impossibile caricare i report',
                motivo: 'Non è stato possibile leggere i rapporti di intervento.',
                action: AppButton(
                  label: 'Riprova',
                  onPressed: () => ref.invalidate(adminReportsProvider(statoFilter)),
                ),
              ),
      );
    } else if (isLoading) {
      content = _scrollable(context, const ListLoadingSkeleton(), onRefresh: onRefresh);
    } else if (groups.isEmpty) {
      content = _scrollable(
        context,
        onRefresh: onRefresh,
        empty,
        showMirror: fromMirror && rawRows.isNotEmpty,
      );
    } else {
      content = RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (fromMirror)
              const SliverToBoxAdapter(child: MirrorNotice(what: 'rapporti di intervento')),
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
            if (filtered.isNotEmpty)
              SliverToBoxAdapter(
                child: _framed(
                  child: ListSummaryFooter(
                    data: ListSummaryData(
                      left: '${filtered.length} report',
                      right: '$toControl da controllare',
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: context.navClearance)),
          ],
        ),
      );
    }

    return Column(
      children: [
        const OfflineSyncBanner(),
        ScreenHeader(
          title: 'Report admin',
          subtitle: 'Il documento ufficio e il suo stato nel flusso.',
          subtitleMaxLines: 2,
          showBack: true,
        ),
        AppSearchBar(
          controller: searchCtrl,
          hint: 'Cerca report, cliente o periodo…',
          onChanged: onQueryChanged,
        ),
        ListFilterRow(
          filters: [
            for (final f in _ReportFilter.values)
              if (f != _ReportFilter.bozza) ListFilterChipData(label: f.label, id: f.id),
          ],
          activeId: filter.status.id,
          onSelected: (chip) {
            final next = _ReportFilter.values.firstWhere((f) => f.id == chip.id);
            onFiltersChanged(filter.copyWith(status: next));
          },
          onOpenFilters: () => onOpenFilters(rawRows),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _scrollable(
    BuildContext context,
    Widget child, {
    required Future<void> Function() onRefresh,
    bool showMirror = false,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (showMirror) const MirrorNotice(what: 'rapporti di intervento'),
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

  static bool _matchesPeriod(Map<String, dynamic> row, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    final date = _parseDate(row['startedAt']) ?? _parseDate(row['createdAt']);
    if (date == null) return false;
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (from != null && day.isBefore(DateTime(from.year, from.month, from.day))) {
      return false;
    }
    if (to != null && day.isAfter(DateTime(to.year, to.month, to.day))) {
      return false;
    }
    return true;
  }

  static bool _matchesQuery(Map<String, dynamic> row, String? customerName, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      row['title'],
      row['numero'],
      customerName,
      _periodLabel(row),
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(q);
  }

  static ListRowData _rowData(
    BuildContext context,
    Map<String, dynamic> report,
    Map<String, String> customerNames,
  ) {
    final stato = report['stato'] as String? ?? 'Bozza';
    final title = (report['title'] as String?)?.trim();
    final numero = report['numero'] as String?;
    final displayTitle = (title != null && title.isNotEmpty)
        ? title
        : (numero != null && numero.isNotEmpty ? 'Rapportino $numero' : 'Rapportino');

    final customer = customerNames[report['customerId']];
    final meta = [
      if (customer != null && customer.trim().isNotEmpty) customer,
      ?_periodLabel(report),
      ?_hoursLabel(report),
    ].join(' · ');

    return ListRowData(
      title: displayTitle,
      meta: meta.isEmpty ? null : meta,
      secondary: _stateLine(stato),
      status: stato,
      onTap: () => context.push('/altro/rapportini-admin/${report['id']}', extra: report),
      rowKey: ValueKey('report-row-${report['id']}'),
    );
  }

  static String _stateLine(String stato) => switch (stato) {
    'Inviato' => 'In attesa di controllo',
    'Controllato' => 'Pronto per fatturazione',
    'Fatturato' => 'Fatturato',
    'Bozza' => 'Da inviare',
    _ => stato,
  };

  static String? _periodLabel(Map<String, dynamic> report) {
    final date = _parseDate(report['startedAt']) ?? _parseDate(report['createdAt']);
    if (date == null) return null;
    final month = DateFormat('MMMM', 'it').format(date.toLocal());
    return month.isEmpty ? null : '${month[0].toUpperCase()}${month.substring(1)}';
  }

  static String? _hoursLabel(Map<String, dynamic> report) {
    final start = _parseDate(report['startedAt']);
    final end = _parseDate(report['endedAt']);
    if (start == null || end == null || end.isBefore(start)) return null;
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return null;
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '${hours}h';
    return '${hours}h ${rest}m';
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// The report's real `Filtri` sheet. Status, Cliente, Sede, Ticket, Cantiere, Periodo and
/// `Solo da controllare`, all reading ids already on the report rows and names already in the
/// local mirrors. Facet filtering applies to the loaded page (the provider fetches one page at a
/// time); status stays the server/mirror-level filter.
class _ReportFilterSheet extends ConsumerStatefulWidget {
  const _ReportFilterSheet({required this.initial, required this.reports});

  final _ReportFilters initial;
  final List<Map<String, dynamic>> reports;

  @override
  ConsumerState<_ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends ConsumerState<_ReportFilterSheet> {
  late _ReportFilters _draft = widget.initial;

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
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const [];
    final customerNames = {for (final c in customers) c.id: c.companyName};

    final customerIds = <String>[];
    for (final r in widget.reports) {
      final id = r['customerId'] as String?;
      if (id != null) customerIds.add(id);
    }
    customerIds.sort(
      (a, b) =>
          (customerNames[a] ?? a).toLowerCase().compareTo((customerNames[b] ?? b).toLowerCase()),
    );
    // A facet applied on a previous page must still be a valid dropdown value, even when the
    // current page has no row carrying that id.
    if (_draft.customerId != null && !customerIds.contains(_draft.customerId)) {
      customerIds.add(_draft.customerId!);
    }

    // The sheet resolves only the ids this page of reports actually carries.
    final locations =
        ref
            .watch(_locationsForReportsProvider(_idsKey(widget.reports, 'locationId')))
            .valueOrNull ??
        const <Location>[];
    final tickets =
        ref.watch(_ticketsForReportsProvider(_idsKey(widget.reports, 'ticketId'))).valueOrNull ??
        const <Ticket>[];
    final cantieri =
        ref.watch(_cantieriForReportsProvider(_idsKey(widget.reports, 'cantiereId'))).valueOrNull ??
        const <CantieriData>[];

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
              'Restringi per stato, contesto e periodo.',
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
                  for (final state in [
                    _ReportFilter.tutti,
                    _ReportFilter.bozza,
                    _ReportFilter.inviato,
                    _ReportFilter.controllato,
                    _ReportFilter.fatturato,
                  ])
                    _FilterChoice(
                      key: Key('report-filter-status-${state.name}'),
                      label: state.label,
                      active: _draft.status == state,
                      onTap: () => setState(() => _draft = _draft.copyWith(status: state)),
                    ),
                ],
              ),
            ),
            if (customerIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Cliente',
                child: DropdownButtonFormField<String?>(
                  key: const Key('report-filter-cliente'),
                  initialValue: _draft.customerId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutti')),
                    for (final id in customerIds)
                      DropdownMenuItem(value: id, child: Text(customerNames[id] ?? id)),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearCustomer: true)
                        : _draft.copyWith(customerId: v);
                  }),
                ),
              ),
            ],
            if (locations.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Sede',
                child: DropdownButtonFormField<String?>(
                  key: const Key('report-filter-sede'),
                  initialValue: _draft.locationId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutte')),
                    for (final location in locations)
                      DropdownMenuItem(value: location.id, child: Text(location.name)),
                    if (_draft.locationId != null &&
                        !locations.any((l) => l.id == _draft.locationId))
                      DropdownMenuItem(value: _draft.locationId, child: Text(_draft.locationId!)),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearLocation: true)
                        : _draft.copyWith(locationId: v);
                  }),
                ),
              ),
            ],
            if (tickets.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Ticket',
                child: DropdownButtonFormField<String?>(
                  key: const Key('report-filter-ticket'),
                  initialValue: _draft.ticketId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutti')),
                    for (final ticket in tickets)
                      DropdownMenuItem(value: ticket.id, child: Text(ticket.title)),
                    if (_draft.ticketId != null && !tickets.any((t) => t.id == _draft.ticketId))
                      DropdownMenuItem(value: _draft.ticketId, child: Text(_draft.ticketId!)),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearTicket: true)
                        : _draft.copyWith(ticketId: v);
                  }),
                ),
              ),
            ],
            if (cantieri.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Cantiere',
                child: DropdownButtonFormField<String?>(
                  key: const Key('report-filter-cantiere'),
                  initialValue: _draft.cantiereId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tutti')),
                    for (final cantiere in cantieri)
                      DropdownMenuItem(value: cantiere.id, child: Text(cantiere.name)),
                    if (_draft.cantiereId != null &&
                        !cantieri.any((c) => c.id == _draft.cantiereId))
                      DropdownMenuItem(value: _draft.cantiereId, child: Text(_draft.cantiereId!)),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = v == null
                        ? _draft.copyWith(clearCantiere: true)
                        : _draft.copyWith(cantiereId: v);
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
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('report-filter-only-control'),
              contentPadding: EdgeInsets.zero,
              value: _draft.onlyToControl,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(onlyToControl: v)),
              title: const Text('Solo da controllare'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('report-filter-reset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _ReportFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('report-filter-apply'),
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

/// Comma-joined ids of one report-row key, used as a stable provider family key.
String _idsKey(List<Map<String, dynamic>> reports, String field) {
  final ids = {
    for (final r in reports)
      if (r[field] is String) r[field] as String,
  }.toList()..sort();
  return ids.join(',');
}

/// Locations on this page of reports, from the local mirror.
final _locationsForReportsProvider = StreamProvider.autoDispose.family<List<Location>, String>((
  ref,
  idsKey,
) {
  final db = ref.watch(appDatabaseProvider);
  final ids = idsKey.isEmpty ? const <String>[] : idsKey.split(',');
  if (ids.isEmpty) return Stream.value(const []);
  return (db.select(db.locations)..where((l) => l.id.isIn(ids))).watch();
});

/// Tickets on this page of reports, from the local mirror.
final _ticketsForReportsProvider = StreamProvider.autoDispose.family<List<Ticket>, String>((
  ref,
  idsKey,
) {
  final db = ref.watch(appDatabaseProvider);
  final ids = idsKey.isEmpty ? const <String>[] : idsKey.split(',');
  if (ids.isEmpty) return Stream.value(const []);
  return (db.select(db.tickets)..where((t) => t.id.isIn(ids))).watch();
});

/// Cantieri on this page of reports, from the local mirror.
final _cantieriForReportsProvider = StreamProvider.autoDispose.family<List<CantieriData>, String>((
  ref,
  idsKey,
) {
  final db = ref.watch(appDatabaseProvider);
  final ids = idsKey.isEmpty ? const <String>[] : idsKey.split(',');
  if (ids.isEmpty) return Stream.value(const []);
  return (db.select(db.cantieri)..where((c) => c.id.isIn(ids))).watch();
});

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRack.freeShape,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? context.colors.ink : context.colors.surface,
            border: Border.all(color: active ? context.colors.ink : context.colors.borderLight),
            borderRadius: AppRack.freeShape,
          ),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? context.colors.surface : context.colors.inkMuted,
            ),
          ),
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
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: context.colors.inkMuted),
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

/// The report list's rows, plus where they came from.
///
/// [fromMirror] drives [MirrorNotice]. It matters more here than on the other lists: the mirror
/// holds what *this device* synced, which for a technician is their own rapportini, so a mirrored
/// list under an "administrator view" header is a narrower set than the header suggests.
class ReportListRows {
  const ReportListRows(this.rows, {required this.fromMirror});

  final List<Map<String, dynamic>> rows;
  final bool fromMirror;
}

String? _isoDate(DateTime? value) => value?.toUtc().toIso8601String();

/// Provider that fetches reports from backend API, falling back to the synced mirror.
///
/// Same shape as the contract and asset lists: server-first when online, mirror on transport /
/// 5xx / 408 / 429, 4xx rethrown. The stato filter applies in both paths — the mirror stores the
/// `ReportStatoEnum` *name* in `DraftReports.stato`, which is what the server sends on the wire,
/// so the same chip value filters both.
final adminReportsProvider = FutureProvider.autoDispose.family<ReportListRows, StatoFilter>((
  ref,
  filter,
) async {
  Future<ReportListRows> fromMirror() async {
    final db = ref.watch(appDatabaseProvider);
    final query = db.select(db.draftReports);
    final stato = filter.value;
    if (stato != null) {
      query.where((r) => r.stato.equals(stato));
    }
    query.orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    final rows = await query.get();
    if (rows.isEmpty && await db.getLastSync() == null) {
      throw const TicketDetailOfflineException();
    }
    return ReportListRows([
      for (final r in rows)
        {
          'id': r.id,
          'title': r.title,
          'numero': r.numero,
          'ticketId': r.ticketId,
          'cantiereId': r.cantiereId,
          'customerId': r.customerId,
          'locationId': r.locationId,
          'stato': r.stato,
          // Re-stamped to UTC: the row formats these into local time, and Drift hands a
          // DateTimeColumn back as a LOCAL-kind instant.
          'createdAt': _isoDate(r.createdAt),
          'startedAt': _isoDate(r.startedAt),
          'endedAt': _isoDate(r.endedAt),
          'inviatoAt': _isoDate(r.inviatoAt),
          'controllatoAt': _isoDate(r.controllatoAt),
          'fatturatoAt': _isoDate(r.fatturatoAt),
          'customerSignatureAllegatoId': r.customerSignatureAllegatoId,
          'technicianSignatureAllegatoId': r.technicianSignatureAllegatoId,
          'customerSignatureAbsenceReason': r.customerSignatureAbsenceReason,
          'technicianNotes': r.technicianNotes,
          'details': r.details,
          'isAiAssisted': r.isAiAssisted,
        },
    ], fromMirror: true);
  }

  if (ref.watch(isOnlineProvider)) {
    try {
      return ReportListRows(
        await ref.watch(adminApiClientProvider).fetchReports(stato: filter.value),
        fromMirror: false,
      );
    } catch (e) {
      if (!isTransportOrServerFault(e)) rethrow;
    }
  }
  return fromMirror();
});

/// Simple wrapper for the stato filter value.
///
/// Value equality is load-bearing, not tidiness: this is a Riverpod *family key*, and the list
/// screen constructs a fresh one on every build (`StatoFilter(filter.statusMatch)`). Without `==`
/// each rebuild is a new provider instance, which re-runs it, which rebuilds — an endless
/// reload that never settles (`pumpAndSettle` times out, and on a device the list just spins).
class StatoFilter {
  const StatoFilter(this.value);
  final String? value;

  @override
  bool operator ==(Object other) => other is StatoFilter && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
