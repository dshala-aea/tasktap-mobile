// dart format width=100
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/time/business_time.dart' show BusinessTime, formatWorkDate;
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/utils/error_message.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/dio_client.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/import_server_report.dart' show ServerReportNotEditableException;
import '../../data/sync/connectivity_provider.dart' show connectivityProvider;
import '../../data/sync/sync_freshness_provider.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/reports/customer_signature_absence_reason.dart';
import '../../presentation/providers/report_editor_providers.dart';
import '../../presentation/providers/schedule_providers.dart'
    show allColleaguesProvider, allCustomersProvider, allLocationsProvider;
import '../admin/admin_providers.dart' show adminCustomersProvider;
import '../admin/locations/admin_location_list_screen.dart' show adminLocationsProvider;
import '../ticket/ticket_label.dart' show ticketReference;
import 'create_draft.dart';
import 'import_server_report_action.dart';
import 'rapportino_list_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Filter model
// ══════════════════════════════════════════════════════════════════════════════

/// Status filters for the rapportini list.
///
/// Every one of these reflects the real server lifecycle — SyncService's `submittedReports`
/// upsert keeps `stato` current, including Respinto/Fatturato/Annullato.
///
/// The prototype's quick chips use a different workflow vocabulary (`Da inviare`,
/// `In revisione`, `Firmati`, `Fatturati`). Only labels with a clear local status are mapped:
/// `Da inviare → bozza`, `In revisione → inviata`, `Fatturati → pagata`. `Firmati` is signature
/// state, not a status, so it is dropped (see the task report). The prototype's old names stay
/// reachable as status chips in the `Filtri` sheet, so no existing status filter is removed.
enum _RapportinoFilter { tutti, bozza, inviata, respinta, pagata, annullato }

extension _FilterLabel on _RapportinoFilter {
  String get label => switch (this) {
    _RapportinoFilter.tutti => 'Tutti',
    _RapportinoFilter.bozza => 'Bozza',
    _RapportinoFilter.inviata => 'Inviata',
    _RapportinoFilter.respinta => 'Respinta',
    _RapportinoFilter.pagata => 'Pagata',
    _RapportinoFilter.annullato => 'Annullato',
  };
}

/// The prototype's quick chips: a single-facet preset over [status].
const List<ListFilterChipData> _quickFilters = [
  ListFilterChipData(label: 'Tutti', id: 'tutti'),
  ListFilterChipData(label: 'Da inviare', id: 'bozza'),
  ListFilterChipData(label: 'In revisione', id: 'inviata'),
  ListFilterChipData(label: 'Fatturati', id: 'pagata'),
];

/// Everything the list can filter on, beyond the title search.
class _RapportinoFilters {
  const _RapportinoFilters({
    this.status = _RapportinoFilter.tutti,
    this.customerId,
    this.locationId,
    this.technicianId,
    this.dateFrom,
    this.dateTo,
    this.onlyToSend = false,
  });

  final _RapportinoFilter status;
  final String? customerId;
  final String? locationId;
  final String? technicianId;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Prototype `Solo da inviare`: reports that have not left this device yet.
  final bool onlyToSend;

  bool get isEmpty =>
      status == _RapportinoFilter.tutti &&
      customerId == null &&
      locationId == null &&
      technicianId == null &&
      dateFrom == null &&
      dateTo == null &&
      !onlyToSend;

  _RapportinoFilters withStatus(_RapportinoFilter value) => _RapportinoFilters(
    status: value,
    customerId: customerId,
    locationId: locationId,
    technicianId: technicianId,
    dateFrom: dateFrom,
    dateTo: dateTo,
    onlyToSend: onlyToSend,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Screen
// ══════════════════════════════════════════════════════════════════════════════

class RapportiniListScreen extends ConsumerStatefulWidget {
  const RapportiniListScreen({super.key});

  @override
  ConsumerState<RapportiniListScreen> createState() => _RapportiniListScreenState();
}

class _RapportiniListScreenState extends ConsumerState<RapportiniListScreen> {
  _RapportinoFilters _filters = const _RapportinoFilters();
  String _query = '';
  final _searchCtrl = TextEditingController();

  /// Guards against a rapid double-tap firing two overlapping `createLocalDraft` calls.
  bool _creating = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_RapportinoFilters>(
      context: context,
      // This list lives inside the "altro" StatefulShellBranch, under HomeShell's
      // `extendBody: true` scaffold: the sheet must be pushed on the root navigator or the
      // floating bottom bar paints over it (same reason as the Pianificazioni sheet).
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RapportinoFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  Future<void> _createNewDraft() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final id = await createLocalDraft(ref, title: 'Nuovo rapporto di intervento');
      if (!mounted) return;
      if (id == null) {
        // Refused rather than authored by a placeholder. See createLocalDraft.
        showAppToast(
          context,
          message: 'Accedi per creare un rapporto di intervento.',
          tone: ToastTone.warning,
        );
        return;
      }
      context.push(AppRoutes.rapportiniEditor(id));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RapportiniListBody(
      filters: _filters,
      query: _query,
      searchCtrl: _searchCtrl,
      creating: _creating,
      onFilterChanged: (f) => setState(() => _filters = f),
      onQueryChanged: (q) => setState(() => _query = q),
      onOpenFilters: _openFilters,
      onNew: _createNewDraft,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Body
// ══════════════════════════════════════════════════════════════════════════════

class _RapportiniListBody extends ConsumerWidget {
  const _RapportiniListBody({
    required this.filters,
    required this.query,
    required this.searchCtrl,
    required this.creating,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.onOpenFilters,
    required this.onNew,
  });

  final _RapportinoFilters filters;
  final String query;
  final TextEditingController searchCtrl;
  final bool creating;
  final ValueChanged<_RapportinoFilters> onFilterChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onOpenFilters;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(rapportiniListProvider);
    final allDrafts = draftsAsync.valueOrNull ?? const <DraftReport>[];
    final businessTime = ref.watch(businessTimeProvider);

    // One stream each for the whole list, not one per row. These are deliberately the UNFILTERED
    // admin streams: a report's customer/site can be deactivated after the report was written, and
    // its mirror row still exists. Filtering the lookup to active rows would make the meta line
    // silently drop a name the report still references (the view screen resolves names unfiltered
    // too). The sheet's Cliente/Sede pickers keep their active-only streams.
    final customersById = {
      for (final c in ref.watch(adminCustomersProvider).valueOrNull ?? const <Customer>[]) c.id: c,
    };
    final locationsById = {
      for (final l in ref.watch(adminLocationsProvider).valueOrNull ?? const <Location>[]) l.id: l,
    };

    final filtered = allDrafts.where((draft) {
      return _matchesStatus(draft, filters.status) &&
          _matchesContext(draft, filters, locationsById, businessTime) &&
          _matchesQuery(draft, query, customersById, locationsById, businessTime);
    }).toList();

    final daInviareCount = filtered.where(_isDaInviare).length;
    final hasActiveFilter = query.trim().isNotEmpty || !filters.isEmpty;
    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;

    final loading = draftsAsync.isLoading && !draftsAsync.hasValue;
    final unavailable = draftsAsync.hasError && !draftsAsync.hasValue;

    final state = unavailable
        ? ListShellState.unavailable
        : loading
        ? ListShellState.loading
        : ListShellState.content;

    final groups = _group(filtered);
    // `rowBuilder` receives presentation data only; keep the drafts behind each key so the
    // Dismissible/delete overlay can still be built.
    final draftsByKey = {for (final draft in filtered) ValueKey('rapportino-${draft.id}'): draft};

    final empty = hasActiveFilter
        ? const EmptyState(
            icon: LucideIcons.searchX,
            title: 'Nessun risultato',
            body: 'Nessun rapportino corrisponde ai filtri scelti.',
          )
        : neverSynced
        ? const EmptyState(
            icon: LucideIcons.cloudOff,
            title: 'Rapportini non ancora scaricati',
            body:
                'Questo telefono non ha ancora completato una sincronizzazione: i rapportini '
                'compariranno qui appena i dati saranno scaricati.',
          )
        : const EmptyState(
            icon: LucideIcons.fileText,
            title: 'Nessun rapportino',
            body: 'I rapportini appariranno qui.',
          );

    return ListShell(
      title: 'Rapportini',
      subtitle: 'Il documento che deve uscire dal cantiere: bozza, firma, invio.',
      showBack: true,
      action: ListHeaderAction(label: 'Nuovo', onPressed: creating ? null : onNew),
      searchController: searchCtrl,
      searchHint: 'Cerca rapportino, cliente, sede o data…',
      onSearchChanged: onQueryChanged,
      filters: _quickFilters,
      activeFilterId: filters.status.name,
      onFilterSelected: (chip) => onFilterChanged(filters.withStatus(_statusFromId(chip.id))),
      onOpenFilters: onOpenFilters,
      groups: [
        for (final group in groups)
          ListGroupData(
            title: group.title,
            count: group.rows.length,
            rows: [
              for (final draft in group.rows)
                ListRowData(rowKey: ValueKey('rapportino-${draft.id}'), title: draft.title),
            ],
          ),
      ],
      summary: filtered.isEmpty
          ? null
          : ListSummaryData(
              left:
                  '${filtered.length} '
                  '${filtered.length == 1 ? 'rapportino' : 'rapportini'}',
              right: '$daInviareCount da inviare',
            ),
      state: state,
      empty: empty,
      unavailable: UnavailableState(
        icon: LucideIcons.alertTriangle,
        titolo: 'Rapportini non disponibili',
        motivo: 'Non è stato possibile leggere i rapportini salvati su questo telefono.',
        action: AppButton(
          label: 'Riprova',
          onPressed: () async {
            ref.invalidate(rapportiniListProvider);
            await refreshWithFeedback(context, ref);
          },
        ),
      ),
      onRefresh: () => refreshWithFeedback(context, ref),
      rowBuilder: (context, row) {
        final draft = draftsByKey[row.rowKey]!;
        return _RapportinoRow(
          draft: draft,
          customerName: _customerName(draft, customersById, locationsById),
          locationName: _locationName(draft, locationsById),
          dateLabel: _dateLabel(draft, businessTime),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Filtering helpers
// ══════════════════════════════════════════════════════════════════════════════

_RapportinoFilter _statusFromId(String? id) {
  return _RapportinoFilter.values.firstWhere(
    (f) => f.name == id,
    orElse: () => _RapportinoFilter.tutti,
  );
}

/// A report that has not left this device yet: Bozza, a rejected send, ready-to-submit, or an
/// in-flight submit. This is the prototype's `Da inviare`.
bool _isDaInviare(DraftReport draft) => !rapportinoIsSubmitted(draft);

bool _matchesStatus(DraftReport draft, _RapportinoFilter filter) {
  final label = rapportinoStatusLabel(draft);
  return switch (filter) {
    _RapportinoFilter.tutti => true,
    _RapportinoFilter.bozza => _isDaInviare(draft),
    _RapportinoFilter.inviata => label == 'Inviata',
    _RapportinoFilter.respinta => label == 'Respinta',
    _RapportinoFilter.pagata => label == 'Pagata',
    _RapportinoFilter.annullato => label == 'Annullato',
  };
}

bool _matchesContext(
  DraftReport draft,
  _RapportinoFilters filters,
  Map<String, Location> locationsById,
  BusinessTime businessTime,
) {
  if (filters.onlyToSend && !_isDaInviare(draft)) return false;

  if (filters.customerId != null) {
    final customerId = _resolvedCustomerId(draft, locationsById);
    if (customerId != filters.customerId) return false;
  }

  if (filters.locationId != null && draft.locationId != filters.locationId) {
    return false;
  }

  if (filters.technicianId != null && draft.insertedUserId != filters.technicianId) {
    return false;
  }

  if (filters.dateFrom != null || filters.dateTo != null) {
    final date = businessTime.businessDateOf(draft.updatedAt ?? draft.createdAt);
    if (filters.dateFrom != null) {
      final from = _civil(filters.dateFrom!);
      if (date.isBefore(from)) return false;
    }
    if (filters.dateTo != null) {
      final to = _civil(filters.dateTo!);
      if (date.isAfter(to)) return false;
    }
  }

  return true;
}

bool _matchesQuery(
  DraftReport draft,
  String query,
  Map<String, Customer> customersById,
  Map<String, Location> locationsById,
  BusinessTime businessTime,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;

  final haystack = [
    draft.title,
    draft.numero ?? '',
    _customerName(draft, customersById, locationsById),
    _locationName(draft, locationsById),
    _dateLabel(draft, businessTime),
    DateFormat('dd/MM/yy', 'it').format(draft.updatedAt ?? draft.createdAt),
    DateFormat('dd/MM/yyyy', 'it').format(draft.updatedAt ?? draft.createdAt),
  ].join(' ').toLowerCase();

  return haystack.contains(needle);
}

DateTime _civil(DateTime date) => DateTime.utc(date.year, date.month, date.day);

String? _resolvedCustomerId(DraftReport draft, Map<String, Location> locationsById) {
  final customerId = draft.customerId;
  if (customerId != null && customerId.isNotEmpty) return customerId;
  return locationsById[draft.locationId]?.customerId;
}

String _customerName(
  DraftReport draft,
  Map<String, Customer> customersById,
  Map<String, Location> locationsById,
) {
  final customerId = _resolvedCustomerId(draft, locationsById);
  if (customerId != null) {
    final name = customersById[customerId]?.companyName;
    if (name != null && name.trim().isNotEmpty) return name;
  }
  return _metadataField(draft.metadataJson, 'customerFreeText') ?? '';
}

String _locationName(DraftReport draft, Map<String, Location> locationsById) {
  final locationId = draft.locationId;
  if (locationId.isNotEmpty) {
    final name = locationsById[locationId]?.name;
    if (name != null && name.trim().isNotEmpty) return name;
  }
  return _metadataField(draft.metadataJson, 'locationFreeText') ?? '';
}

String? _metadataField(String? json, String key) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map && decoded[key] is String) {
      final value = (decoded[key] as String).trim();
      return value.isEmpty ? null : value;
    }
  } catch (_) {
    // Malformed legacy metadata is not a display error: fall through to "no value".
  }
  return null;
}

String _dateLabel(DraftReport draft, BusinessTime businessTime) {
  final date = businessTime.businessDateOf(draft.updatedAt ?? draft.createdAt);
  if (date == businessTime.businessToday()) return 'oggi';
  return formatWorkDate(date, 'dd/MM/yy', locale: 'it');
}

/// The prototype's group order. Groups that the prototype does not name (`Controllati`,
/// `Respinti`, `Annullati`) are kept so every mirrored server state stays visible under `Tutti`;
/// `Firmati` is dropped because it is signature state, not a status (see the task report).
List<({String title, List<DraftReport> rows})> _group(List<DraftReport> drafts) {
  final groups = <({String title, List<DraftReport> rows})>[];
  void add(String title, bool Function(DraftReport) matches) {
    final rows = drafts.where(matches).toList();
    if (rows.isNotEmpty) groups.add((title: title, rows: rows));
  }

  add('Da inviare', _isDaInviare);
  add('In revisione', (d) => rapportinoStatusLabel(d) == 'Inviata');
  add('Controllati', (d) => rapportinoStatusLabel(d) == 'Controllato');
  add('Fatturati', (d) => rapportinoStatusLabel(d) == 'Pagata');
  add('Respinti', (d) => rapportinoStatusLabel(d) == 'Respinta');
  add('Annullati', (d) => rapportinoStatusLabel(d) == 'Annullato');
  return groups;
}

// ══════════════════════════════════════════════════════════════════════════════
// Row
// ══════════════════════════════════════════════════════════════════════════════

/// Report ids whose server import is in flight (double-tap guard).
final _importingReportIds = <String>{};

class _RapportinoRow extends ConsumerWidget {
  const _RapportinoRow({
    required this.draft,
    required this.customerName,
    required this.locationName,
    required this.dateLabel,
  });

  final DraftReport draft;
  final String customerName;
  final String locationName;
  final String dateLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the hours label is used here. `rapportinoRowSummaryProvider` also opens the staff and
    // materiali streams, which this row never reads.
    final oreLabel = ref.watch(rapportinoOreProvider(draft.id));

    final statusLabel = rapportinoStatusLabel(draft);
    final opensEditor = rapportinoOpensEditor(draft);
    final canDelete = rapportinoCanDelete(draft);

    final meta = [
      customerName,
      locationName,
      dateLabel,
    ].where((part) => part.isNotEmpty).join(' · ');

    final signature = _signatureLabel(draft);
    final secondary = [signature, if (oreLabel != '—') oreLabel].join(' · ');

    final reference = ticketReference(draft.numero);
    final title = reference == null ? draft.title : '${draft.title} · $reference';

    final data = ListRowData(
      title: title,
      meta: meta.isEmpty ? null : meta,
      secondary: secondary.isEmpty ? null : secondary,
      status: statusLabel,
      statusTone: _toneFor(statusLabel),
      onTap: () => _open(context, ref, opensEditor: opensEditor),
    );

    Widget row = ListDocumentRow(data: data);

    // The shared row has no trailing action slot. Keep the existing, accessible delete entry
    // point as a minimal inline overlay in the row's bottom-right corner — the swipe alone is
    // not reachable for TalkBack/keyboard users, so removing this button would be a regression.
    if (canDelete) {
      row = Stack(
        children: [
          row,
          Positioned(
            right: 0,
            bottom: 0,
            child: IconButton(
              tooltip: 'Elimina',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(LucideIcons.trash2, size: 16, color: context.colors.inkMuted),
              onPressed: () => _confirmDeleteDraft(context, ref, draft),
            ),
          ),
        ],
      );
    }

    if (!canDelete) return row;

    return Dismissible(
      key: ValueKey('rapportino-${draft.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        child: Icon(LucideIcons.trash2, color: context.colors.red),
      ),
      confirmDismiss: (_) => _confirmDeleteDraft(context, ref, draft),
      child: row,
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, {required bool opensEditor}) async {
    // Only a Bozza opens the editor. Inviato / Respinto / Controllato / Fatturato (and an
    // Annullato) always open the read-only view; a Respinto offers "Rielabora" there.
    if (opensEditor) {
      // A Bozza that only arrived through sync is a header with no staff/materiali/controlli:
      // pull the full report first. Offline or failed means we do not open it at all.
      if (draft.stato == 'Bozza' && !draft.isLocalOnly) {
        if (!_importingReportIds.add(draft.id)) return;
        try {
          // The duplicate OfflineSyncBanner is gone (HomeShell owns the global one), and the
          // import below reads `isOnlineProvider`. Without a settled connectivity answer that
          // convenience bool is false while the notifier is still loading, which would send an
          // online phone down the mirror-only path. Wait for the real verdict first.
          await ref.read(connectivityProvider.future);
          await importServerReportForEditing(ref, reportId: draft.id);
        } on ServerReportNotEditableException {
          if (!context.mounted) return;
          unawaited(ref.read(syncProvider.notifier).performSync());
          showAppToast(
            context,
            message: 'Questo rapporto di intervento non è più modificabile.',
            tone: ToastTone.warning,
          );
          return;
        } catch (_) {
          if (!context.mounted) return;
          showAppToast(
            context,
            message:
                'Per aprire questo rapporto di intervento serve la connessione: i dati completi '
                'vanno scaricati sul telefono. Riprova più tardi.',
            tone: ToastTone.error,
          );
          return;
        } finally {
          _importingReportIds.remove(draft.id);
        }
        if (!context.mounted) return;
      }
      context.push(AppRoutes.rapportiniEditor(draft.id));
    } else {
      context.push(AppRoutes.rapportiniView(draft.id));
    }
  }
}

String _signatureLabel(DraftReport draft) {
  final hasTechnician = draft.technicianSignatureAllegatoId != null;
  final hasCustomer = draft.customerSignatureAllegatoId != null;
  final absenceReason = CustomerSignatureAbsenceReason.fromWire(
    draft.customerSignatureAbsenceReason,
  );

  if (hasTechnician && hasCustomer) return '2 firme';
  // The absence column is "why the customer did not sign" (`Assente/Rifiuta/Altro`), not a
  // blanket "not required". Show what was actually recorded; an unknown wire value falls back to
  // the neutral missing-signature wording.
  if (hasTechnician && absenceReason != null) return absenceReason.summaryLabel;
  if (hasTechnician) return 'Firma cliente mancante';
  if (hasCustomer) return 'Firma tecnico mancante';
  return 'Nessuna firma';
}

ListStatusTone _toneFor(String label) {
  return switch (label) {
    'Bozza' || 'In attesa di invio' || 'Invio…' => ListStatusTone.warn,
    kFailedSendStatusLabel => ListStatusTone.bad,
    'Inviata' => ListStatusTone.info,
    'Controllato' => ListStatusTone.warn,
    'Pagata' => ListStatusTone.good,
    'Respinta' || 'Annullato' => ListStatusTone.bad,
    _ => ListStatusTone.neutral,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Delete (Bozza only)
// ══════════════════════════════════════════════════════════════════════════════

Future<bool> _confirmDeleteDraft(BuildContext context, WidgetRef ref, DraftReport draft) async {
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Eliminare il rapporto di intervento?',
    message: '"${draft.title}" verrà eliminato definitivamente.',
  );
  if (!confirmed) return false;

  // A report with isLocalOnly == false exists on the server: the server delete must succeed
  // FIRST. Deleting locally first was a silent resurrection: offline, the server copy survived
  // and the next sync re-inserted the row.
  if (!draft.isLocalOnly) {
    try {
      await ref.read(dioProvider).delete<void>('/api/reports/${draft.id}');
    } on DioException catch (e) {
      if (!context.mounted) return false;
      // 404 = the server copy is already gone: fall through and clear the local mirror.
      if (e.response?.statusCode != 404) {
        showAppToast(
          context,
          message: e.response == null
              ? 'Per eliminare questo rapporto di intervento serve la connessione: riprova quando '
                    'sei online. Il rapporto di intervento non è stato eliminato.'
              : humanErrorMessage(e, azione: 'eliminare il rapporto di intervento'),
          tone: ToastTone.error,
        );
        return false;
      }
    } catch (e) {
      if (!context.mounted) return false;
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'eliminare il rapporto di intervento'),
        tone: ToastTone.error,
      );
      return false;
    }
  }

  await ref.read(draftReportRepositoryProvider).deleteDraft(draft.id);
  return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// Filter sheet
// ══════════════════════════════════════════════════════════════════════════════

class _RapportinoFilterSheet extends ConsumerStatefulWidget {
  const _RapportinoFilterSheet({required this.initial});

  final _RapportinoFilters initial;

  @override
  ConsumerState<_RapportinoFilterSheet> createState() => _RapportinoFilterSheetState();
}

class _RapportinoFilterSheetState extends ConsumerState<_RapportinoFilterSheet> {
  late _RapportinoFilter _status = widget.initial.status;
  late String? _customerId = widget.initial.customerId;
  late String? _locationId = widget.initial.locationId;
  late String? _technicianId = widget.initial.technicianId;
  late DateTime? _dateFrom = widget.initial.dateFrom;
  late DateTime? _dateTo = widget.initial.dateTo;
  late bool _onlyToSend = widget.initial.onlyToSend;

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const <Customer>[];
    final allLocations = ref.watch(allLocationsProvider).valueOrNull ?? const <Location>[];
    final colleagues = ref.watch(allColleaguesProvider).valueOrNull ?? const <Colleague>[];

    final locations = _customerId == null
        ? allLocations
        : allLocations.where((l) => l.customerId == _customerId).toList();
    final locationValue = locations.any((l) => l.id == _locationId) ? _locationId : null;
    final technicianValue = colleagues.any((c) => c.id == _technicianId) ? _technicianId : null;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Filtri', style: Theme.of(context).textTheme.titleMedium)),
                Text(
                  'Rapportini',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: context.colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Restringi per stato, contesto e periodo. Nessun identificativo interno.',
              style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
            ),
            const SizedBox(height: 12),
            Text(
              'STATO',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final filter in _RapportinoFilter.values)
                  AppChip(
                    label: filter.label,
                    active: _status == filter,
                    onTap: () => setState(() => _status = filter),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              label: 'Cliente',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _customerId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti')),
                  for (final customer in customers)
                    DropdownMenuItem(
                      value: customer.id,
                      child: Text(customer.companyName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _customerId = value;
                  _locationId = null;
                }),
              ),
            ),
            const SizedBox(height: 12),
            AppFieldShell(
              label: 'Sede',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: locationValue,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte')),
                  for (final location in locations)
                    DropdownMenuItem(
                      value: location.id,
                      child: Text(location.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _locationId = value),
              ),
            ),
            const SizedBox(height: 12),
            AppFieldShell(
              label: 'Tecnico',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: technicianValue,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti')),
                  for (final colleague in colleagues)
                    DropdownMenuItem(
                      value: colleague.id,
                      child: Text(colleague.displayName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _technicianId = value),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'PERIODO',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _DateFilterField(
                    label: 'Da',
                    value: _dateFrom == null ? 'Qualsiasi' : dateFmt.format(_dateFrom!),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateFilterField(
                    label: 'A',
                    value: _dateTo == null ? 'Qualsiasi' : dateFmt.format(_dateTo!),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Solo da inviare',
                    style: TextStyle(fontSize: 12, color: context.colors.ink),
                  ),
                ),
                AppToggle(
                  value: _onlyToSend,
                  onChanged: (value) => setState(() => _onlyToSend = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _RapportinoFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _RapportinoFilters(
                        status: _status,
                        customerId: _customerId,
                        locationId: _locationId,
                        technicianId: _technicianId,
                        dateFrom: _dateFrom,
                        dateTo: _dateTo,
                        onlyToSend: _onlyToSend,
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

class _DateFilterField extends StatelessWidget {
  const _DateFilterField({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFieldShell(
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.borderMedium),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.colors.ink),
          ),
        ),
      ),
    );
  }
}
