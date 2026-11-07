// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/time/business_time.dart' show formatWorkDate, parseDateOnly;
import '../../../core/time/business_time_providers.dart';
import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/widgets.dart';
import '../../../data/reference/reference_cache_repository.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../../presentation/providers/schedule_providers.dart'
    show allCustomersProvider, allLocationsProvider;
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';

/// The Contratti list's rows, plus where they came from.
///
/// [fromMirror] is not diagnostic noise: a mirrored list is a *scoped* one, so the screen has to
/// say so (see [MirrorNotice]) instead of letting the summary read as the whole book of business.
class ContractListRows {
  const ContractListRows(this.rows, {required this.fromMirror});

  final List<Map<String, dynamic>> rows;
  final bool fromMirror;
}

/// The tenant's contracts — from the server when it answers, from the synced mirror otherwise.
///
/// Online the server answers, because an office edit made a minute ago only exists there. When the
/// request never arrived (the radio says online but nothing came back) or the server itself
/// faulted, the mirror answers instead; offline it answers from the start. A 4xx is never
/// second-guessed — a 401/403 is about this account, not about connectivity, and hiding it behind
/// a list of stale rows would misreport why the page is empty.
///
/// The mirror carries fewer fields than `GET /api/contracts`: `tipo` is stored as the C# ordinal
/// but the wire shape is the enum's *name* (`"Manutenzione"`), and `price`, `condizioni`,
/// `frequency*`, `autoRenewal` and `scadenzaGiorni` are not synced at all. Those read as absent on
/// the detail screen instead of being converted from a guess — an ordinal mapped through an
/// assumed ordering is a wrong value that looks right.
final adminContractsProvider = FutureProvider.autoDispose<ContractListRows>((ref) async {
  Future<ContractListRows> fromMirror() async {
    final db = ref.watch(appDatabaseProvider);
    final rows = await ref.watch(referenceCacheProvider).allContracts();
    // An empty mirror means one of two very different things: nothing was ever downloaded (say
    // so, and point at a connection), or the sync ran and this account genuinely has no contracts
    // (an empty list, with the list's own "Nessun contratto" copy).
    if (rows.isEmpty && await db.getLastSync() == null) {
      throw const TicketDetailOfflineException();
    }
    return ContractListRows([
      for (final c in rows)
        {
          'id': c.id,
          'name': c.name,
          'customerId': c.customerId,
          'locationId': c.locationId,
          // Re-stamped to UTC for the same reason contractByIdProvider does it: Drift hands a
          // DateTimeColumn back as a LOCAL-kind instant, and the detail screen parses these
          // strings as the server's own `Z`-suffixed dates.
          'startDate': c.startDate.toUtc().toIso8601String(),
          'endDate': c.endDate?.toUtc().toIso8601String(),
          'isActive': c.isActive,
          'numero': c.numero,
          'codice': c.codice,
          'externalId': c.externalId,
        },
    ], fromMirror: true);
  }

  if (ref.watch(isOnlineProvider)) {
    try {
      final rows = await ref.watch(adminApiClientProvider).fetchContracts();
      return ContractListRows(rows, fromMirror: false);
    } catch (e) {
      if (!isTransportOrServerFault(e)) rethrow;
    }
  }
  return fromMirror();
});

/// The contract's lifecycle bucket, derived exactly like the server's `Contract.Stato`
/// (`isActive` + `endDate`, today in the tenant's business zone) with the prototype's extra
/// "expiring soon" bucket from `GET /api/contracts?inScadenza=true`: `now < endDate <= now + 30
/// days`, expired and undated contracts excluded.
enum _ContractState { inScadenza, attivo, scaduto, inattivo }

extension on _ContractState {
  String get groupTitle => switch (this) {
    _ContractState.inScadenza => 'In scadenza',
    _ContractState.attivo => 'Attivi',
    _ContractState.scaduto => 'Scaduti',
    _ContractState.inattivo => 'Inattivi',
  };

  String get stampLabel => switch (this) {
    _ContractState.inScadenza => 'In scadenza',
    _ContractState.attivo => 'Attivo',
    _ContractState.scaduto => 'Scaduto',
    _ContractState.inattivo => 'Inattivo',
  };

  ListStatusTone get tone => switch (this) {
    _ContractState.inScadenza => ListStatusTone.warn,
    _ContractState.attivo => ListStatusTone.good,
    _ContractState.scaduto => ListStatusTone.bad,
    _ContractState.inattivo => ListStatusTone.bad,
  };
}

/// Quick chips and the filter sheet's state picker share this one value.
enum _ContractStatusFilter { tutti, attivi, inScadenza, scaduti }

extension on _ContractStatusFilter {
  String get label => switch (this) {
    _ContractStatusFilter.tutti => 'Tutti',
    _ContractStatusFilter.attivi => 'Attivi',
    _ContractStatusFilter.inScadenza => 'In scadenza',
    _ContractStatusFilter.scaduti => 'Scaduti',
  };

  String get id => switch (this) {
    _ContractStatusFilter.tutti => 'tutti',
    _ContractStatusFilter.attivi => 'attivi',
    _ContractStatusFilter.inScadenza => 'inScadenza',
    _ContractStatusFilter.scaduti => 'scaduti',
  };

  bool matches(_ContractState state) => switch (this) {
    _ContractStatusFilter.tutti => true,
    _ContractStatusFilter.attivi => state == _ContractState.attivo,
    _ContractStatusFilter.inScadenza => state == _ContractState.inScadenza,
    _ContractStatusFilter.scaduti => state == _ContractState.scaduto,
  };
}

class _ContractFilters {
  const _ContractFilters({
    this.status = _ContractStatusFilter.tutti,
    this.customerId,
    this.locationId,
    this.scadenzaFrom,
    this.scadenzaTo,
    this.onlyAutoRenewal = false,
  });

  final _ContractStatusFilter status;
  final String? customerId;
  final String? locationId;

  /// Civil dates (`DateTime.utc(y, m, d)`) matched against the contract's end-date label.
  final DateTime? scadenzaFrom;
  final DateTime? scadenzaTo;
  final bool onlyAutoRenewal;

  bool get hasFacets =>
      customerId != null ||
      locationId != null ||
      scadenzaFrom != null ||
      scadenzaTo != null ||
      onlyAutoRenewal;

  bool get isActive => status != _ContractStatusFilter.tutti || hasFacets;

  _ContractFilters withStatus(_ContractStatusFilter next) => _ContractFilters(
    status: next,
    customerId: customerId,
    locationId: locationId,
    scadenzaFrom: scadenzaFrom,
    scadenzaTo: scadenzaTo,
    onlyAutoRenewal: onlyAutoRenewal,
  );
}

/// One row normalized from either the server payload or the mirror.
class _ContractItem {
  const _ContractItem({
    required this.raw,
    required this.id,
    required this.name,
    required this.customerId,
    required this.locationId,
    required this.endDate,
    required this.isActive,
    required this.autoRenewal,
    required this.scadenzaGiorni,
    required this.numero,
    required this.codice,
    required this.externalId,
  });

  factory _ContractItem.fromRow(Map<String, dynamic> raw) {
    final autoRenewal = raw['autoRenewal'];
    final scadenzaGiorni = raw['scadenzaGiorni'];
    return _ContractItem(
      raw: raw,
      id: raw['id'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      customerId: raw['customerId'] as String?,
      locationId: raw['locationId'] as String?,
      endDate: parseDateOnly(raw['endDate']),
      isActive: raw['isActive'] as bool? ?? true,
      autoRenewal: autoRenewal is bool ? autoRenewal : null,
      scadenzaGiorni: scadenzaGiorni is num
          ? scadenzaGiorni.toInt()
          : (scadenzaGiorni is String ? int.tryParse(scadenzaGiorni) : null),
      numero: raw['numero'] as String?,
      codice: raw['codice'] as String?,
      externalId: raw['externalId'] as String?,
    );
  }

  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final String? customerId;
  final String? locationId;

  /// Civil date (`DateTime.utc(y, m, d)`) of the contract's end date, if any.
  final DateTime? endDate;
  final bool isActive;

  /// Null on a mirrored row: the sync payload does not carry it.
  final bool? autoRenewal;
  final int? scadenzaGiorni;
  final String? numero;
  final String? codice;
  final String? externalId;
}

class _ContractEntry {
  const _ContractEntry({required this.item, required this.state});

  final _ContractItem item;
  final _ContractState state;
}

/// Admin contract list — server-first, mirror when it cannot be reached.
class AdminContractListScreen extends ConsumerStatefulWidget {
  const AdminContractListScreen({super.key});

  @override
  ConsumerState<AdminContractListScreen> createState() => _AdminContractListScreenState();
}

class _AdminContractListScreenState extends ConsumerState<AdminContractListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  _ContractFilters _filters = const _ContractFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_ContractFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ContractFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final contractsAsync = ref.watch(adminContractsProvider);

    return contractsAsync.when(
      loading: () => _shell(state: ListShellState.loading),
      error: (e, _) => _shell(
        state: ListShellState.unavailable,
        unavailable: e is TicketDetailOfflineException
            ? const UnavailableState(
                icon: LucideIcons.fileSignature,
                titolo: 'Contratti non disponibili offline',
                motivo:
                    'Questo dispositivo non ha ancora scaricato i contratti. Apri questa '
                    'lista con una connessione attiva per averli anche offline.',
              )
            : ErrorState(onRetry: () => ref.invalidate(adminContractsProvider)),
      ),
      data: (data) => _content(data),
    );
  }

  Widget _shell({
    required ListShellState state,
    List<ListGroupData> groups = const [],
    ListSummaryData? summary,
    Widget? empty,
    Widget? unavailable,
    Widget? bodyHeader,
  }) {
    return ListShell(
      title: 'Contratti',
      subtitle: 'Cosa scade, cosa si rinnova, cosa è coperto.',
      showBack: true,
      action: CapabilityGate(
        capability: 'contratti.contract.write',
        child: ListHeaderAction(
          label: 'Nuovo',
          onPressed: () => context.push('/altro/contratti/nuovo'),
        ),
      ),
      banner: const OfflineSyncBanner(),
      searchController: _searchCtrl,
      searchHint: 'Cerca contratto, cliente o codice…',
      onSearchChanged: (q) => setState(() => _query = q),
      filters: const [
        ListFilterChipData(label: 'Attivi', id: 'attivi'),
        ListFilterChipData(label: 'In scadenza', id: 'inScadenza'),
        ListFilterChipData(label: 'Scaduti', id: 'scaduti'),
        ListFilterChipData(label: 'Tutti', id: 'tutti'),
      ],
      activeFilterId: _filters.status.id,
      onFilterSelected: (chip) {
        final next = _ContractStatusFilter.values.firstWhere((s) => s.id == chip.id);
        setState(() => _filters = _filters.withStatus(next));
      },
      onOpenFilters: _openFilters,
      groups: groups,
      summary: summary,
      state: state,
      empty: empty,
      unavailable: unavailable,
      bodyHeader: bodyHeader,
      onRefresh: () => ref.refresh(adminContractsProvider.future),
    );
  }

  Widget _content(ContractListRows data) {
    final today = ref.watch(businessTimeProvider).businessToday();
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const [];
    final customerNames = {for (final c in customers) c.id: c.companyName};

    final entries = data.rows.map((raw) {
      final item = _ContractItem.fromRow(raw);
      return _ContractEntry(item: item, state: _stateFor(item, today));
    }).toList();

    final filtered = entries.where((e) {
      if (!_filters.status.matches(e.state)) return false;
      if (_filters.customerId != null && e.item.customerId != _filters.customerId) {
        return false;
      }
      if (_filters.locationId != null && e.item.locationId != _filters.locationId) {
        return false;
      }
      if (_filters.scadenzaFrom != null &&
          (e.item.endDate == null || e.item.endDate!.isBefore(_filters.scadenzaFrom!))) {
        return false;
      }
      if (_filters.scadenzaTo != null &&
          (e.item.endDate == null || e.item.endDate!.isAfter(_filters.scadenzaTo!))) {
        return false;
      }
      if (_filters.onlyAutoRenewal && e.item.autoRenewal != true) return false;
      return _matchesQuery(e.item, customerNames[e.item.customerId], _query);
    }).toList();

    final groups = <ListGroupData>[
      for (final contractState in _ContractState.values)
        if (filtered.any((e) => e.state == contractState))
          ListGroupData(
            title: contractState.groupTitle,
            count: filtered.where((e) => e.state == contractState).length,
            rows: [
              for (final entry in filtered.where((e) => e.state == contractState))
                _rowData(context, entry, customerNames[entry.item.customerId], today),
            ],
          ),
    ];

    final inScadenzaCount = filtered.where((e) => e.state == _ContractState.inScadenza).length;

    // A mirrored list is scoped, so the notice stays even when the filters empty it.
    final mirrorNotice = data.fromMirror && data.rows.isNotEmpty
        ? const MirrorNotice(what: 'contratti')
        : null;

    if (groups.isEmpty) {
      return _shell(
        state: ListShellState.content,
        bodyHeader: mirrorNotice,
        empty: _emptyState(data.rows.isNotEmpty),
      );
    }

    return _shell(
      state: ListShellState.content,
      groups: groups,
      bodyHeader: mirrorNotice,
      summary: ListSummaryData(
        left: _contractCountLabel(filtered.length),
        right: '$inScadenzaCount in scadenza',
      ),
    );
  }

  Widget _emptyState(bool hasContracts) {
    if (!hasContracts) {
      return const EmptyState(
        icon: LucideIcons.fileSignature,
        title: 'Nessun contratto',
        body: 'Non ci sono contratti da mostrare.',
      );
    }
    if (_query.isNotEmpty) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: 'Nessun contratto corrisponde a "$_query".',
      );
    }
    return EmptyState(
      icon: LucideIcons.searchX,
      title: 'Nessun risultato',
      body: _filters.isActive
          ? 'Nessun contratto corrisponde ai filtri selezionati.'
          : 'Nessun contratto corrisponde allo stato selezionato.',
    );
  }

  static _ContractState _stateFor(_ContractItem item, DateTime today) {
    final end = item.endDate;
    if (end != null && end.isBefore(today)) return _ContractState.scaduto;
    if (!item.isActive) return _ContractState.inattivo;
    // The server's own `inScadenza` rule: now < endDate <= now + 30 days.
    if (end != null && end.isAfter(today) && !end.isAfter(today.add(const Duration(days: 30)))) {
      return _ContractState.inScadenza;
    }
    return _ContractState.attivo;
  }

  static bool _matchesQuery(_ContractItem item, String? customerName, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return item.name.toLowerCase().contains(q) ||
        (customerName?.toLowerCase().contains(q) ?? false) ||
        (item.numero?.toLowerCase().contains(q) ?? false) ||
        (item.codice?.toLowerCase().contains(q) ?? false) ||
        (item.externalId?.toLowerCase().contains(q) ?? false);
  }

  static ListRowData _rowData(
    BuildContext context,
    _ContractEntry entry,
    String? customerName,
    DateTime today,
  ) {
    final item = entry.item;
    final metaParts = <String>[
      if (customerName != null && customerName.trim().isNotEmpty) customerName,
      if (item.endDate == null)
        'nessuna scadenza'
      else
        'scade ${formatWorkDate(item.endDate!, item.endDate!.year == today.year ? 'dd/MM' : 'dd/MM/yyyy')}',
    ];

    final renewalParts = <String>[
      if (item.autoRenewal == true)
        'Rinnovo automatico'
      else if (item.autoRenewal == false)
        'Rinnovo manuale',
      if (item.scadenzaGiorni != null) 'preavviso ${item.scadenzaGiorni}gg',
    ];

    return ListRowData(
      title: item.name,
      meta: metaParts.join(' · '),
      secondary: renewalParts.isEmpty ? null : renewalParts.join(' · '),
      status: entry.state.stampLabel,
      statusTone: entry.state.tone,
      rowKey: ValueKey('contract-${item.id}'),
      onTap: item.id.isEmpty
          ? null
          : () => context.push('/altro/contratti/${item.id}', extra: item.raw),
    );
  }

  static String _contractCountLabel(int count) => count == 1 ? '1 contratto' : '$count contratti';
}

class _ContractFilterSheet extends ConsumerStatefulWidget {
  const _ContractFilterSheet({required this.initial});

  final _ContractFilters initial;

  @override
  ConsumerState<_ContractFilterSheet> createState() => _ContractFilterSheetState();
}

class _ContractFilterSheetState extends ConsumerState<_ContractFilterSheet> {
  late _ContractStatusFilter _status = widget.initial.status;
  late String? _customerId = widget.initial.customerId;
  late String? _locationId = widget.initial.locationId;
  late DateTime? _scadenzaFrom = widget.initial.scadenzaFrom;
  late DateTime? _scadenzaTo = widget.initial.scadenzaTo;
  late bool _onlyAutoRenewal = widget.initial.onlyAutoRenewal;

  static const _statusOptions = [
    _ContractStatusFilter.attivi,
    _ContractStatusFilter.inScadenza,
    _ContractStatusFilter.scaduti,
  ];

  Future<void> _pickDate({required bool isFrom}) async {
    final current = isFrom ? _scadenzaFrom : _scadenzaTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1825)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final civil = DateTime.utc(picked.year, picked.month, picked.day);
      if (isFrom) {
        _scadenzaFrom = civil;
      } else {
        _scadenzaTo = civil;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const [];
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? const [];
    final rows = ref.watch(adminContractsProvider).valueOrNull?.rows ?? const [];
    final hasAutoRenewalData = rows.any((r) => r['autoRenewal'] is bool);

    final visibleLocations = _customerId == null
        ? locations
        : locations.where((l) => l.customerId == _customerId).toList();

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
              child: Center(child: SheetHandle()),
            ),
            Text('Filtri', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Restringi per stato, contesto e periodo. Nessun identificativo interno.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            const AppFieldLabel(label: 'Stato', enabled: true),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in _statusOptions)
                  AppChip(
                    key: Key('contratti-filter-status-${option.id}'),
                    label: option.label,
                    active: _status == option,
                    onTap: () => setState(() => _status = option),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppFieldShell(
              label: 'Cliente',
              child: DropdownButtonFormField<String?>(
                key: const Key('contratti-filter-customer'),
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _customerId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti i clienti')),
                  ...customers.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)),
                  ),
                  if (_customerId != null && !customers.any((c) => c.id == _customerId))
                    const DropdownMenuItem(
                      value: '__selected__',
                      child: Text('Cliente selezionato'),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _customerId = v == '__selected__' ? _customerId : v;
                  if (_customerId != null &&
                      _locationId != null &&
                      !locations.any((l) => l.id == _locationId && l.customerId == _customerId)) {
                    _locationId = null;
                  }
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFieldShell(
              label: 'Sede',
              child: DropdownButtonFormField<String?>(
                key: const Key('contratti-filter-location'),
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _locationId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte le sedi')),
                  ...visibleLocations.map(
                    (l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(
                        [l.name, l.city].where((p) => p != null && p.trim().isNotEmpty).join(' · '),
                      ),
                    ),
                  ),
                  if (_locationId != null && !visibleLocations.any((l) => l.id == _locationId))
                    const DropdownMenuItem(value: '__selected__', child: Text('Sede selezionata')),
                ],
                onChanged: (v) =>
                    setState(() => _locationId = v == '__selected__' ? _locationId : v),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const AppFieldLabel(label: 'Scadenza', enabled: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    key: const Key('contratti-filter-from'),
                    label: 'Da',
                    value: _scadenzaFrom,
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    key: const Key('contratti-filter-to'),
                    label: 'A',
                    value: _scadenzaTo,
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              key: const Key('contratti-filter-auto-renewal'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo rinnovo automatico'),
              subtitle: hasAutoRenewalData
                  ? null
                  : const Text('Disponibile quando i contratti sono stati aggiornati online.'),
              value: _onlyAutoRenewal,
              onChanged: hasAutoRenewalData ? (v) => setState(() => _onlyAutoRenewal = v) : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('contratti-filter-reset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _ContractFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('contratti-filter-apply'),
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _ContractFilters(
                        status: _status,
                        customerId: _customerId,
                        locationId: _locationId,
                        scadenzaFrom: _scadenzaFrom,
                        scadenzaTo: _scadenzaTo,
                        onlyAutoRenewal: _onlyAutoRenewal,
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

class _DateField extends StatelessWidget {
  const _DateField({super.key, required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? 'Qualsiasi' : formatWorkDate(value!, 'dd/MM/yyyy', locale: 'it');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: AppFieldShell(
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const Icon(LucideIcons.calendarDays, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
