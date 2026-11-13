// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/riverpod/read_future.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/auth/access.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/business_time.dart' show formatWorkDate, parseDateOnly;
import '../../../core/time/business_time_providers.dart';
import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/widgets.dart';
import '../../../data/entitlements/entitlement_providers.dart' show cachedEntitlementProvider;
import '../../../data/local/app_database.dart';
import '../../../data/reference/reference_cache_repository.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../../presentation/providers/schedule_providers.dart' show allLocationsProvider;
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';

/// The list's search text. Its own provider (not a family argument on the list provider) so the
/// form screen can keep invalidating [adminProdottiAssistenzaProvider] without knowing the query.
final adminProdottiQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// The Asset list's rows, plus where they came from.
///
/// [fromMirror] drives [MirrorNotice]: the sync payload is scoped, so a mirrored list is a partial
/// one and its "N totali" must not read as the tenant's whole asset book.
class ProdottoListRows {
  const ProdottoListRows(this.rows, {required this.fromMirror});

  final List<Map<String, dynamic>> rows;
  final bool fromMirror;
}

/// Prodotti assistenza — server-first, mirror when it cannot be reached.
///
/// Online the search term is sent as `q` and the server searches every row. Offline the mirror is
/// searched here with the fields a technician has on the row: name, codice, categoria, seriale and
/// customer name — so typing a serial number on site still gets an answer instead of a spinner.
///
/// The mirror carries fewer fields than `GET /api/prodottoassistenza`: the sync DTO has no
/// `warrantyExpiryDate`, `prossimaManutenzione` or `ultimaManutenzione`. Those read as absent on
/// mirrored rows (no line, no warranty group) instead of being invented from another column.
final adminProdottiAssistenzaProvider = FutureProvider.autoDispose<ProdottoListRows>((ref) async {
  final q = ref.watch(adminProdottiQueryProvider);

  Future<ProdottoListRows> fromMirror() async {
    final db = ref.watch(appDatabaseProvider);
    final rows = await ref.watch(referenceCacheProvider).allProdottiAssistenza();
    if (rows.isEmpty && await db.getLastSync() == null) {
      throw const TicketDetailOfflineException();
    }
    // The row shows the customer's *name*; the mirror carries only the id. Read every customer
    // (inactive ones included — an asset can belong to a customer the office has since archived,
    // and '—' there would claim the asset belongs to nobody).
    final customers = {for (final c in await db.select(db.customers).get()) c.id: c.companyName};
    final needle = q.toLowerCase();
    final matches = needle.isEmpty
        ? rows
        : rows.where((p) {
            final customerName = customers[p.customerId] ?? '';
            return p.name.toLowerCase().contains(needle) ||
                (p.codice ?? '').toLowerCase().contains(needle) ||
                (p.categoria ?? '').toLowerCase().contains(needle) ||
                (p.serialNumber ?? '').toLowerCase().contains(needle) ||
                customerName.toLowerCase().contains(needle);
          }).toList();
    return ProdottoListRows([
      for (final p in matches)
        {
          'id': p.id,
          'name': p.name,
          'customerId': p.customerId,
          'customerName': customers[p.customerId] ?? '—',
          'locationId': p.locationId,
          'isActive': p.isActive,
          'codice': p.codice,
          'categoria': p.categoria,
          'serialNumber': p.serialNumber,
          'marchio': p.marchio,
          'externalId': p.externalId,
        },
    ], fromMirror: true);
  }

  if (ref.watch(isOnlineProvider)) {
    try {
      return ProdottoListRows(
        await ref.watch(adminApiClientProvider).fetchProdottiAssistenza(q: q),
        fromMirror: false,
      );
    } catch (e) {
      if (!isTransportOrServerFault(e)) rethrow;
    }
  }
  return fromMirror();
});

/// Quick-filter presets from the prototype's chip row.
///
/// The three asset states are mutually exclusive and are the same predicate the groups and the
/// `Filtri` sheet use. `Tutti` is the list's existing default (every asset was always visible).
enum _ProdottoFilter { tutti, inGaranzia, scaduta, inattivi }

extension _ProdottoFilterX on _ProdottoFilter {
  String get label => switch (this) {
    _ProdottoFilter.tutti => 'Tutti',
    _ProdottoFilter.inGaranzia => 'In garanzia',
    _ProdottoFilter.scaduta => 'Garanzia scaduta',
    _ProdottoFilter.inattivi => 'Inattivi',
  };
}

/// One asset's warranty state, derived from the row's own `warrantyExpiryDate`.
///
/// The single source shared by the chips, the groups, the summary and the row stamp. A civil date
/// is valid through its own day; it is only expired from the following day (the same convention
/// the ticket list uses for a due date). A row without the field is *not* claimed to be under
/// warranty: the local mirror does not carry it.
enum _WarrantyState { inGaranzia, scaduta, nonRegistrata }

bool _isActiveProdotto(Map<String, dynamic> row) => row['isActive'] as bool? ?? true;

_WarrantyState _warrantyStateOf(Map<String, dynamic> row, DateTime today) {
  final expiry = parseDateOnly(row['warrantyExpiryDate']);
  if (expiry == null) return _WarrantyState.nonRegistrata;
  return expiry.isBefore(today) ? _WarrantyState.scaduta : _WarrantyState.inGaranzia;
}

DateTime? _nextMaintenanceOf(Map<String, dynamic> row) =>
    parseDateOnly(row['prossimaManutenzione']);

DateTime? _lastMaintenanceOf(Map<String, dynamic> row) => parseDateOnly(row['ultimaManutenzione']);

/// The only maintenance predicate on this screen: the next maintenance is due today or overdue.
///
/// There is no local lead-time window (the app has no such rule; the server's reminder is not
/// mirrored), so no future threshold is invented. Mirrored rows have no date and never match.
bool _isMaintenanceDue(Map<String, dynamic> row, DateTime today) {
  final next = _nextMaintenanceOf(row);
  return next != null && !next.isAfter(today);
}

/// The groups shown in the prototype's order. `Senza garanzia registrata` hosts active assets the
/// mirror cannot classify (or a server row without an expiry date) — dropping them would hide real
/// assets; claiming a warranty would invent one.
const _groupOrder = ['In garanzia', 'Garanzia scaduta', 'Senza garanzia registrata', 'Inattivi'];

/// Every facet the `Filtri` sheet owns. Quick chips only change [status].
class _ProdottoFilters {
  const _ProdottoFilters({
    this.status = _ProdottoFilter.tutti,
    this.customerId,
    this.locationId,
    this.categoria,
    this.onlyMaintenanceDue = false,
  });

  final _ProdottoFilter status;
  final String? customerId;
  final String? locationId;
  final String? categoria;
  final bool onlyMaintenanceDue;

  bool get isActive =>
      status != _ProdottoFilter.tutti ||
      customerId != null ||
      locationId != null ||
      categoria != null ||
      onlyMaintenanceDue;

  _ProdottoFilters withStatus(_ProdottoFilter next) => _ProdottoFilters(
    status: next,
    customerId: customerId,
    locationId: locationId,
    categoria: categoria,
    onlyMaintenanceDue: onlyMaintenanceDue,
  );
}

/// Admin prodotto assistenza list — server-first, mirror when it cannot be reached.
class AdminProdottoListScreen extends ConsumerStatefulWidget {
  const AdminProdottoListScreen({super.key});

  @override
  ConsumerState<AdminProdottoListScreen> createState() => _AdminProdottoListScreenState();
}

class _AdminProdottoListScreenState extends ConsumerState<AdminProdottoListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  _ProdottoFilters _filters = const _ProdottoFilters();

  /// The last list that arrived. A new search term reloads the provider; keeping the last rows
  /// here means the field's text, its focus and the list stay on screen instead of a skeleton
  /// flashing on every keystroke (the old `skipLoadingOnReload` behaviour).
  ProdottoListRows? _lastData;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(adminProdottiQueryProvider.notifier).state = q.trim();
    });
  }

  Future<void> _openFilters({
    required List<Map<String, dynamic>> rows,
    required bool maintenanceAvailable,
  }) async {
    final result = await showModalBottomSheet<_ProdottoFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ProdottoFilterSheet(
        initial: _filters,
        rows: rows,
        maintenanceAvailable: maintenanceAvailable,
      ),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final prodottiAsync = ref.watch(adminProdottiAssistenzaProvider);
    final fresh = prodottiAsync.value;
    if (fresh != null) _lastData = fresh;
    final data = fresh ?? _lastData;
    final allRows = data?.rows ?? const <Map<String, dynamic>>[];
    final fromMirror = data?.fromMirror ?? false;
    final search = ref.watch(adminProdottiQueryProvider);
    final businessToday = ref.watch(businessTimeProvider).businessToday();
    final canWrite = capabilityHeld(
      ref.watch(cachedEntitlementProvider).value,
      'contratti.contract.write',
    );

    bool matchesStatus(Map<String, dynamic> row) => switch (_filters.status) {
      _ProdottoFilter.tutti => true,
      _ProdottoFilter.inGaranzia =>
        _isActiveProdotto(row) && _warrantyStateOf(row, businessToday) == _WarrantyState.inGaranzia,
      _ProdottoFilter.scaduta =>
        _isActiveProdotto(row) && _warrantyStateOf(row, businessToday) == _WarrantyState.scaduta,
      _ProdottoFilter.inattivi => !_isActiveProdotto(row),
    };

    final filtered =
        allRows.where((row) {
          if (!matchesStatus(row)) return false;
          if (_filters.customerId != null && row['customerId'] != _filters.customerId) {
            return false;
          }
          if (_filters.locationId != null && row['locationId'] != _filters.locationId) {
            return false;
          }
          if (_filters.categoria != null &&
              (row['categoria'] as String?)?.trim() != _filters.categoria) {
            return false;
          }
          if (_filters.onlyMaintenanceDue && !_isMaintenanceDue(row, businessToday)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) {
          final an = (a['name'] as String? ?? '').toLowerCase();
          final bn = (b['name'] as String? ?? '').toLowerCase();
          return an.compareTo(bn);
        });

    final buckets = <String, List<Map<String, dynamic>>>{
      for (final name in _groupOrder) name: <Map<String, dynamic>>[],
    };
    for (final row in filtered) {
      final key = !_isActiveProdotto(row)
          ? 'Inattivi'
          : switch (_warrantyStateOf(row, businessToday)) {
              _WarrantyState.inGaranzia => 'In garanzia',
              _WarrantyState.scaduta => 'Garanzia scaduta',
              _WarrantyState.nonRegistrata => 'Senza garanzia registrata',
            };
      buckets[key]!.add(row);
    }

    final groups = [
      for (final name in _groupOrder)
        if (buckets[name]!.isNotEmpty)
          ListGroupData(
            title: name,
            count: buckets[name]!.length,
            rows: [for (final row in buckets[name]!) _rowFor(context, row, businessToday)],
          ),
    ];

    final inactiveCount = filtered.where((row) => !_isActiveProdotto(row)).length;
    final dueCount = filtered.where((row) => _isMaintenanceDue(row, businessToday)).length;
    final hasActiveFilter = _filters.isActive || search.isNotEmpty;

    Widget empty = hasActiveFilter
        ? const EmptyState(
            icon: LucideIcons.searchX,
            title: 'Nessun risultato',
            body: 'Nessun prodotto corrisponde a ricerca e filtri selezionati.',
          )
        : const EmptyState(
            icon: LucideIcons.wrench,
            title: 'Nessun prodotto',
            body: 'Non ci sono prodotti in assistenza da mostrare.',
          );

    final isLoading = data == null && prodottiAsync.isLoading;
    final isUnavailable = prodottiAsync.hasError;

    final unavailable = prodottiAsync.error is TicketDetailOfflineException
        ? const UnavailableState(
            icon: LucideIcons.wrench,
            titolo: 'Asset non disponibili offline',
            motivo:
                'Questo dispositivo non ha ancora scaricato gli asset. Apri questa lista '
                'con una connessione attiva per averli anche offline.',
          )
        : ErrorState(onRetry: () => ref.invalidate(adminProdottiAssistenzaProvider));

    final state = isUnavailable
        ? ListShellState.unavailable
        : isLoading
        ? ListShellState.loading
        : ListShellState.content;

    final summary = filtered.isEmpty
        ? null
        : ListSummaryData(
            left: '${filtered.length} ${filtered.length == 1 ? 'prodotto' : 'prodotti'}',
            // The maintenance date is absent from the local mirror, so offline the right half
            // reports a count the rows can actually support (inactive assets) instead of a
            // misleading "0 in scadenza".
            right: fromMirror
                ? '$inactiveCount ${inactiveCount == 1 ? 'inattivo' : 'inattivi'}'
                : '$dueCount in scadenza',
          );

    return ListShell(
      title: 'Prodotti in assistenza',
      subtitle: 'Gli asset del cliente e la loro prossima manutenzione.',
      showBack: true,
      action: canWrite
          ? ListHeaderAction(label: 'Nuovo', onPressed: () => context.push('/altro/prodotti/nuovo'))
          : null,
      searchController: _searchCtrl,
      searchHint: 'Cerca prodotto, seriale, cliente…',
      onSearchChanged: _onQueryChanged,
      filters: const [
        ListFilterChipData(label: 'Tutti', id: 'tutti'),
        ListFilterChipData(label: 'In garanzia', id: 'inGaranzia'),
        ListFilterChipData(label: 'Garanzia scaduta', id: 'scaduta'),
        ListFilterChipData(label: 'Inattivi', id: 'inattivi'),
      ],
      activeFilterId: _filters.status.name,
      onFilterSelected: (chip) {
        final next = _ProdottoFilter.values.firstWhere((f) => f.name == chip.id);
        setState(() => _filters = _filters.withStatus(next));
      },
      onOpenFilters: () => _openFilters(rows: allRows, maintenanceAvailable: !fromMirror),
      groups: groups,
      summary: summary,
      state: state,
      empty: empty,
      unavailable: unavailable,
      bodyHeader: state == ListShellState.content && fromMirror
          ? const MirrorNotice(what: 'asset')
          : null,
      onRefresh: _refresh,
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(adminProdottiAssistenzaProvider);
    try {
      await ref.readFuture(adminProdottiAssistenzaProvider.future);
    } catch (_) {
      // The provider's error is already rendered by the unavailable/error branch. A refresh
      // future that completes with an error would be reported by RefreshIndicator as an
      // uncaught exception (and Sentry noise), so the spinner stops here instead.
    }
  }

  ListRowData _rowFor(BuildContext context, Map<String, dynamic> row, DateTime today) {
    final name = row['name'] as String? ?? '';
    final customerName = row['customerName'] as String? ?? '';
    final serial = row['serialNumber'] as String? ?? '';
    final meta = [customerName, serial].where((part) => part.trim().isNotEmpty).join(' · ');

    final next = _nextMaintenanceOf(row);
    final last = _lastMaintenanceOf(row);
    String? secondary;
    if (next != null) {
      secondary = 'Prossima manutenzione ${formatWorkDate(next, 'dd/MM/yyyy', locale: 'it')}';
    } else if (last != null) {
      secondary = 'Ultima manutenzione ${formatWorkDate(last, 'dd/MM/yyyy', locale: 'it')}';
    }

    final (status, tone) = !_isActiveProdotto(row)
        ? ('Inattivo', ListStatusTone.bad)
        : switch (_warrantyStateOf(row, today)) {
            _WarrantyState.inGaranzia => ('In garanzia', ListStatusTone.good),
            // The prototype stamps an expired warranty amber, while the shared vocabulary maps
            // `Scaduta` to red. The prototype wins for this one label.
            _WarrantyState.scaduta => ('Scaduta', ListStatusTone.warn),
            _WarrantyState.nonRegistrata => ('Attivo', ListStatusTone.good),
          };

    return ListRowData(
      title: name.isEmpty ? 'Senza nome' : name,
      meta: meta.isEmpty ? null : meta,
      secondary: secondary,
      status: status,
      statusTone: tone,
      rowKey: ValueKey('prodotto-row-${row['id']}'),
      onTap: () => context.push('/altro/prodotti/${row['id']}', extra: row),
    );
  }
}

// ── Filter sheet ────────────────────────────────────────────────────────────

class _ProdottoFilterSheet extends ConsumerStatefulWidget {
  const _ProdottoFilterSheet({
    required this.initial,
    required this.rows,
    required this.maintenanceAvailable,
  });

  final _ProdottoFilters initial;
  final List<Map<String, dynamic>> rows;

  /// False when the rows came from the mirror: the sync DTO has no maintenance date, so the
  /// toggle would be a control that can only ever filter to nothing.
  final bool maintenanceAvailable;

  @override
  ConsumerState<_ProdottoFilterSheet> createState() => _ProdottoFilterSheetState();
}

class _ProdottoFilterSheetState extends ConsumerState<_ProdottoFilterSheet> {
  late _ProdottoFilter _status = widget.initial.status;
  late String? _customerId = widget.initial.customerId;
  late String? _locationId = widget.initial.locationId;
  late String? _categoria = widget.initial.categoria;
  // A filter carried over from an online session cannot be honoured against mirrored rows: it is
  // cleared when the sheet is applied rather than left active behind a disabled switch.
  late bool _onlyMaintenanceDue = widget.initial.onlyMaintenanceDue && widget.maintenanceAvailable;

  static const _statusOptions = [
    _ProdottoFilter.inGaranzia,
    _ProdottoFilter.scaduta,
    _ProdottoFilter.inattivi,
  ];

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(allLocationsProvider).value ?? const <Location>[];
    final locationsById = {for (final l in locations) l.id: l};
    final customers = _customerOptions(widget.rows);
    // A facet chosen before the search term changed can point at a value the current rows no
    // longer contain. The dropdown would assert on a value missing from its items, so the sheet
    // clears it: a stale filter is dropped rather than left behind an invisible option.
    final customerId = customers.any((c) => c.id == _customerId) ? _customerId : null;
    final visibleLocations = _locationOptions(widget.rows, locationsById, customerId: customerId);
    final locationId = visibleLocations.any((l) => l.id == _locationId) ? _locationId : null;
    final categorie = _categoriaOptions(widget.rows);
    final categoria = categorie.contains(_categoria) ? _categoria : null;

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
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: customerId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti i clienti')),
                  ...customers.map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _customerId = v;
                  if (v != null &&
                      _locationId != null &&
                      !widget.rows.any(
                        (r) => r['locationId'] == _locationId && r['customerId'] == v,
                      )) {
                    _locationId = null;
                  }
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFieldShell(
              label: 'Sede',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: locationId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte le sedi')),
                  ...visibleLocations.map(
                    (l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _locationId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFieldShell(
              label: 'Categoria',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: categoria,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte le categorie')),
                  ...categorie.map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _categoria = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Manutenzione in scadenza'),
              subtitle: widget.maintenanceAvailable
                  ? null
                  : const Text('Non disponibile sui dati salvati sul dispositivo'),
              value: _onlyMaintenanceDue,
              onChanged: widget.maintenanceAvailable
                  ? (v) => setState(() => _onlyMaintenanceDue = v)
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _ProdottoFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _ProdottoFilters(
                        status: _status,
                        customerId: customerId,
                        locationId: locationId,
                        categoria: categoria,
                        onlyMaintenanceDue: _onlyMaintenanceDue,
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

/// Customer options restricted to customers that actually appear on a row, so an unloaded customer
/// never produces a facet that filters to nothing.
List<({String id, String name})> _customerOptions(List<Map<String, dynamic>> rows) {
  final byId = <String, String>{};
  for (final row in rows) {
    final id = row['customerId'] as String?;
    final name = (row['customerName'] as String?)?.trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
    byId[id] = name;
  }
  final options = [for (final e in byId.entries) (id: e.key, name: e.value)];
  options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return options;
}

/// Sede options restricted to locations linked to a row (and to [customerId], when given). The
/// name is resolved from the local locations mirror; an id with no mirror row is skipped rather
/// than printed as an internal identifier.
List<({String id, String name})> _locationOptions(
  List<Map<String, dynamic>> rows,
  Map<String, Location> locationsById, {
  String? customerId,
}) {
  final byId = <String, String>{};
  for (final row in rows) {
    if (customerId != null && row['customerId'] != customerId) continue;
    final id = row['locationId'] as String?;
    if (id == null || id.isEmpty) continue;
    final location = locationsById[id];
    if (location == null) continue;
    final name = [
      location.name,
      location.city,
    ].where((part) => part != null && part.trim().isNotEmpty).cast<String>().join(' · ');
    if (name.isEmpty) continue;
    byId[id] = name;
  }
  final options = [for (final e in byId.entries) (id: e.key, name: e.value)];
  options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return options;
}

List<String> _categoriaOptions(List<Map<String, dynamic>> rows) {
  final values = {
    for (final row in rows)
      if ((row['categoria'] as String?)?.trim().isNotEmpty ?? false)
        (row['categoria'] as String).trim(),
  }.toList();
  values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return values;
}
