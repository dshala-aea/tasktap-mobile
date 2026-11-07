// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/time/business_time.dart' show formatWorkDate, parseDateOnly;
import '../../core/time/business_time_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_freshness_provider.dart';
import '../../data/tickets/pending_ticket_state.dart';
import '../../data/tickets/ticket_creation_queue_watcher.dart';
import '../../data/tickets/ticket_deletion.dart';
import '../../presentation/providers/auth_providers.dart' show internalUserIdProvider;
import '../../presentation/providers/schedule_providers.dart'
    show allColleaguesProvider, allCustomersProvider, allLocationsProvider;
import 'new_ticket_form_screen.dart';
import 'ticket_label.dart';
import 'ticket_providers.dart';

/// Quick-filter presets from the prototype's chip row.
///
/// `Oggi` is the prototype's today preset (a civil-date predicate over `dueDate`), not a status.
/// The remaining presets map onto the same status strings the list always filtered on, under the
/// prototype's copy (`Chiusi` replaces `Completati`).
enum _TicketFilter { tutti, oggi, aperti, inCorso, inAttesa, chiusi }

extension _TicketFilterX on _TicketFilter {
  String get label => switch (this) {
    _TicketFilter.tutti => 'Tutti',
    _TicketFilter.oggi => 'Oggi',
    _TicketFilter.aperti => 'Aperti',
    _TicketFilter.inCorso => 'In corso',
    _TicketFilter.inAttesa => 'In attesa',
    _TicketFilter.chiusi => 'Chiusi',
  };
}

/// Everything the list filters on. Quick chips change [status]; the `Filtri` sheet owns the rest.
class _TicketFilters {
  const _TicketFilters({
    this.status = _TicketFilter.tutti,
    this.customerId,
    this.locationId,
    this.technicianId,
    this.priority,
    this.dueFrom,
    this.dueTo,
    this.onlyMine = false,
  });

  final _TicketFilter status;
  final String? customerId;
  final String? locationId;
  final String? technicianId;
  final String? priority;

  /// Civil dates (`DateTime.utc(y, m, d)`) compared with `Ticket.dueDate`'s civil label.
  final DateTime? dueFrom;
  final DateTime? dueTo;
  final bool onlyMine;

  bool get isActive =>
      status != _TicketFilter.tutti ||
      customerId != null ||
      locationId != null ||
      technicianId != null ||
      priority != null ||
      dueFrom != null ||
      dueTo != null ||
      onlyMine;

  _TicketFilters withStatus(_TicketFilter next) => _TicketFilters(
    status: next,
    customerId: customerId,
    locationId: locationId,
    technicianId: technicianId,
    priority: priority,
    dueFrom: dueFrom,
    dueTo: dueTo,
    onlyMine: onlyMine,
  );
}

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  _TicketFilters _filters = const _TicketFilters();
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_TicketFilters>(
      context: context,
      // The ticket branch sits under HomeShell's floating nav (`extendBody: true`); pushing on the
      // root navigator keeps the sheet above the pill, the same call the schedule list makes.
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TicketFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    return _TicketListBody(
      filters: _filters,
      query: _query,
      searchCtrl: _searchCtrl,
      onFilterChanged: (f) => setState(() => _filters = f),
      onQueryChanged: (q) => setState(() => _query = q),
      onOpenFilters: _openFilters,
    );
  }
}

/// Group headings, in the prototype's order. `Chiusi` is the list's own answer to the `Chiusi`
/// filter — the prototype carries no closed example but does offer the filter.
const _groupOrder = ['Oggi', 'In corso', 'Altri aperti', 'In attesa', 'Chiusi'];

class _TicketListBody extends ConsumerWidget {
  const _TicketListBody({
    required this.filters,
    required this.query,
    required this.searchCtrl,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.onOpenFilters,
  });

  final _TicketFilters filters;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<_TicketFilters> onFilterChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final statusMapAsync = ref.watch(ticketStatusMapProvider);
    final statuses = ref.watch(ticketStatusesProvider).valueOrNull ?? const <TicketStatuse>[];
    final closedIds = ref.watch(closedTicketStatusIdsProvider).valueOrNull ?? const <int>{};
    final pendingTickets = ref.watch(pendingTicketsProvider).valueOrNull ?? const <PendingTicket>[];

    // Which of those rows the server has refused over a reference this client can repair. The list
    // observes that fact through its own provider rather than deciding it — the queue owns the
    // column, and a row leaves this set the moment a repair clears it.
    final repairableIds = {
      for (final t in ref.watch(repairablePendingTicketsProvider).valueOrNull ?? <PendingTicket>[])
        t.id,
    };

    final statusMap = statusMapAsync.valueOrNull ?? const <int, String>{};
    final statusById = {for (final s in statuses) s.id: s};
    final allTickets = ticketsAsync.valueOrNull ?? const <Ticket>[];

    // One stream each for the whole list, not one per row: a per-row location/customer/colleague
    // watch would open (and tear down on scroll-out) live subscriptions for every visible row.
    final locationsById = {
      for (final l in ref.watch(allLocationsProvider).valueOrNull ?? const <Location>[]) l.id: l,
    };
    final customersById = {
      for (final c in ref.watch(allCustomersProvider).valueOrNull ?? const <Customer>[]) c.id: c,
    };
    final colleaguesById = {
      for (final c in ref.watch(allColleaguesProvider).valueOrNull ?? const <Colleague>[]) c.id: c,
    };
    final myId = ref.watch(internalUserIdProvider).valueOrNull;
    final businessToday = ref.watch(businessTimeProvider).businessToday();

    bool isClosed(Ticket t) => t.closedAt != null || closedIds.contains(t.statusId);

    String statusNameOf(Ticket t) => statusMap[t.statusId] ?? '';

    bool isInProgress(Ticket t) {
      final status = statusById[t.statusId];
      if (status != null) return status.isInProgress;
      return statusNameOf(t).toLowerCase() == 'in corso';
    }

    bool isWaiting(Ticket t) => statusNameOf(t).toLowerCase() == 'in attesa';

    bool isDueToday(Ticket t) {
      final due = parseDateOnly(t.dueDate);
      return due != null && due == businessToday;
    }

    // `agentId` is the separate "Riferimento" field on the detail screen, not the technician
    // working the job. A ticket with no assignee shows no technician rather than borrowing it.
    String? technicianNameOf(Ticket t) {
      final id = t.assignedUserId;
      if (id == null) return null;
      return colleaguesById[id]?.displayName;
    }

    bool matchesStatus(Ticket t) {
      switch (filters.status) {
        case _TicketFilter.tutti:
          return true;
        case _TicketFilter.oggi:
          // The prototype's `Oggi` is today's work, not "every open ticket": the same predicate the
          // `Oggi` group uses, over the ticket's civil due date.
          return !isClosed(t) && isDueToday(t);
        case _TicketFilter.aperti:
          // The pre-redesign `Aperti` facet, kept reachable through the sheet even though the
          // prototype has no chip for it.
          return !isClosed(t) && statusNameOf(t).toLowerCase() == 'aperto';
        case _TicketFilter.inCorso:
          // Chips, groups and the footer share these three predicates, so a tenant status renamed
          // away from the literal `In corso` still filters and groups the same way.
          return !isClosed(t) && isInProgress(t);
        case _TicketFilter.inAttesa:
          return !isClosed(t) && isWaiting(t);
        case _TicketFilter.chiusi:
          return isClosed(t);
      }
    }

    final search = query.trim().toLowerCase();
    final filtered = allTickets.where((t) {
      if (!matchesStatus(t)) return false;
      if (filters.customerId != null && t.customerId != filters.customerId) return false;
      if (filters.locationId != null && t.locationId != filters.locationId) return false;
      if (filters.technicianId != null && t.assignedUserId != filters.technicianId) {
        return false;
      }
      if (filters.priority != null && t.priority != filters.priority) return false;

      final due = parseDateOnly(t.dueDate);
      if (filters.dueFrom != null && (due == null || due.isBefore(filters.dueFrom!))) {
        return false;
      }
      if (filters.dueTo != null && (due == null || due.isAfter(filters.dueTo!))) {
        return false;
      }
      if (filters.onlyMine && (myId == null || t.assignedUserId != myId)) return false;

      if (search.isEmpty) return true;
      final customer = customersById[t.customerId]?.companyName ?? '';
      final location = locationsById[t.locationId];
      final where = '${location?.name ?? ''} ${location?.city ?? ''}';
      final technician = technicianNameOf(t) ?? '';
      final reference = ticketReference(t.numero) ?? '';
      return t.title.toLowerCase().contains(search) ||
          t.id.toLowerCase().contains(search) ||
          reference.toLowerCase().contains(search) ||
          customer.toLowerCase().contains(search) ||
          where.toLowerCase().contains(search) ||
          technician.toLowerCase().contains(search);
    }).toList();

    final buckets = <String, List<Ticket>>{for (final name in _groupOrder) name: <Ticket>[]};
    for (final t in filtered) {
      final String bucket;
      if (isClosed(t)) {
        bucket = 'Chiusi';
      } else if (isDueToday(t)) {
        bucket = 'Oggi';
      } else if (isInProgress(t)) {
        bucket = 'In corso';
      } else if (isWaiting(t)) {
        bucket = 'In attesa';
      } else {
        bucket = 'Altri aperti';
      }
      buckets[bucket]!.add(t);
    }

    final inCorsoCount = filtered.where(isInProgress).length;
    final hasActiveFilter = filters.isActive || search.isNotEmpty;

    // Three different things reach the empty branch, and only two of them are answers:
    //  - a filter or a search that matches nothing is "no result" for a question just asked;
    //  - an empty mirror on a device that has never synced is "not downloaded yet";
    //  - anything else is the tenant genuinely having no ticket in view.
    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
    Widget empty = const EmptyState(
      key: ValueKey('empty'),
      icon: LucideIcons.ticket,
      title: 'Nessun ticket',
      body: 'Non ci sono ticket da mostrare.',
    );
    if (allTickets.isEmpty) {
      if (neverSynced) {
        empty = const EmptyState(
          key: ValueKey('empty-not-downloaded'),
          icon: LucideIcons.cloudOff,
          title: 'Ticket non ancora scaricati',
          body:
              'Questo telefono non ha ancora completato una sincronizzazione: '
              'i ticket compariranno qui appena i dati saranno scaricati.',
        );
      }
    } else if (hasActiveFilter) {
      empty = const EmptyState(
        key: ValueKey('empty-filter'),
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: 'Nessun ticket corrisponde ai filtri scelti.',
      );
    }

    final state = ticketsAsync.isLoading && allTickets.isEmpty
        ? ListShellState.loading
        : ticketsAsync.hasError && allTickets.isEmpty
        ? ListShellState.unavailable
        : ListShellState.content;

    final regularGroups = [
      for (final name in _groupOrder)
        if (buckets[name]!.isNotEmpty) (title: name, rows: buckets[name]!),
    ];

    // `rowBuilder` receives presentation data only; keep the entities behind each key so the
    // pending strip and the full ticket row can still be built.
    final pendingByKey = {
      for (final ticket in pendingTickets) ValueKey('pending-${ticket.id}'): ticket,
    };
    final ticketsByKey = {for (final ticket in filtered) ValueKey('ticket-${ticket.id}'): ticket};

    final groups = <ListGroupData>[
      if (pendingTickets.isNotEmpty)
        ListGroupData(
          title: 'In sospeso',
          count: pendingTickets.length,
          rows: [
            for (final ticket in pendingTickets)
              ListRowData(rowKey: ValueKey('pending-${ticket.id}'), title: ticket.title),
          ],
        ),
      for (final group in regularGroups)
        ListGroupData(
          title: group.title,
          count: group.rows.length,
          rows: [
            for (final ticket in group.rows)
              ListRowData(rowKey: ValueKey('ticket-${ticket.id}'), title: ticket.title),
          ],
        ),
      // Pending rows stay visible under an empty filter result. The shell only renders its
      // `empty` slot when there is no group at all, so the empty answer rides in as one row.
      if (regularGroups.isEmpty && pendingTickets.isNotEmpty)
        ListGroupData(
          rows: [ListRowData(rowKey: const ValueKey('ticket-empty'), title: '')],
        ),
    ];

    return ListShell(
      title: 'Ticket',
      subtitle: 'Il lavoro aperto adesso, non l’archivio degli interventi.',
      action: ListHeaderAction(
        label: 'Nuovo',
        onPressed: () async {
          final created = await context.push<bool>('/ticket/new');
          if (created == true && context.mounted) {
            // The list auto-refreshes via StreamProvider; nothing to do on return.
          }
        },
      ),
      banner: const OfflineSyncBanner(),
      searchController: searchCtrl,
      searchHint: 'Cerca ticket, cliente, sede o numero…',
      onSearchChanged: onQueryChanged,
      filters: const [
        ListFilterChipData(label: 'Tutti', id: 'tutti'),
        ListFilterChipData(label: 'Oggi', id: 'oggi'),
        ListFilterChipData(label: 'In corso', id: 'inCorso'),
        ListFilterChipData(label: 'In attesa', id: 'inAttesa'),
        ListFilterChipData(label: 'Chiusi', id: 'chiusi'),
      ],
      activeFilterId: filters.status.name,
      onFilterSelected: (chip) {
        final next = _TicketFilter.values.firstWhere((f) => f.name == chip.id);
        onFilterChanged(filters.withStatus(next));
      },
      onOpenFilters: onOpenFilters,
      groups: groups,
      summary: regularGroups.isEmpty
          ? null
          : ListSummaryData(
              // Pending rows are visible above, so they belong in the total too.
              left: '${filtered.length + pendingTickets.length} ticket',
              right: '$inCorsoCount in corso',
            ),
      state: state,
      empty: empty,
      unavailable: UnavailableState(
        icon: LucideIcons.ticket,
        titolo: 'Ticket non disponibili',
        motivo: 'Non è stato possibile leggere i ticket salvati su questo dispositivo.',
        action: AppButton(label: 'Riprova', onPressed: () => refreshWithFeedback(context, ref)),
      ),
      onRefresh: () => refreshWithFeedback(context, ref),
      rowBuilder: (context, row) {
        final key = row.rowKey;
        if (key == const ValueKey('ticket-empty')) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: empty,
          );
        }
        final pending = pendingByKey[key];
        if (pending != null) {
          return _PendingTicketRow(
            ticket: pending,
            isRepairable: repairableIds.contains(pending.id),
          );
        }
        final ticket = ticketsByKey[key]!;
        return _TicketRow(
          ticket: ticket,
          statusName: statusNameOf(ticket),
          isClosed: isClosed(ticket),
          technicianName: technicianNameOf(ticket),
          customerName: customersById[ticket.customerId]?.companyName,
          location: locationsById[ticket.locationId],
          today: businessToday,
        );
      },
    );
  }
}

/// One server ticket row: the prototype's title/meta/secondary/stamp anatomy.
class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.ticket,
    required this.statusName,
    required this.isClosed,
    required this.technicianName,
    required this.customerName,
    required this.location,
    required this.today,
  });

  final Ticket ticket;
  final String statusName;
  final bool isClosed;
  final String? technicianName;
  final String? customerName;
  final Location? location;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final place = location?.city ?? location?.name;
    final meta = _joinNonEmpty([customerName, place, technicianName]);

    final priority = ticket.priority;
    final priorityLine = switch (priority) {
      null => null,
      'Urgente' => 'priorità urgente',
      _ => '${priority.toLowerCase()} priorità',
    };

    final due = parseDateOnly(ticket.dueDate);
    String? dueLine;
    if (due != null) {
      final label = formatWorkDate(due, 'dd/MM/yy', locale: 'it');
      if (due == today) {
        dueLine = 'oggi';
      } else if (!isClosed && due.isBefore(today)) {
        dueLine = 'scaduto · $label';
      } else {
        dueLine = 'scadenza $label';
      }
    }
    final secondary = _joinNonEmpty([priorityLine, dueLine]);

    return ListDocumentRow(
      data: ListRowData(
        title: ticket.title,
        meta: meta.isEmpty ? null : meta,
        secondary: secondary.isEmpty ? null : secondary,
        status: statusName.isEmpty ? null : statusName,
        statusTone: _toneForStatus(statusName),
        onTap: () => context.push('/ticket/${ticket.id}'),
      ),
    );
  }
}

/// A locally-created ticket that has not been confirmed by the server. The shared
/// [ListDocumentRow] carries the row anatomy; its existing Correggi / Riprova / Elimina actions sit
/// inline in the strip below, because the shared row contract has no action slot.
class _PendingTicketRow extends ConsumerWidget {
  const _PendingTicketRow({required this.ticket, required this.isRepairable});

  final PendingTicket ticket;

  /// The server refused this row over a reference that no longer resolves, so no resend will ever
  /// be accepted: it is offered for repair instead of for retry (see [TicketCreationQueue]).
  final bool isRepairable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = PendingTicketState.fromString(ticket.state);
    final isFailed = state == PendingTicketState.failed;
    final isSubmitting = state == PendingTicketState.submitting;

    final label = switch (state) {
      PendingTicketState.pendingSync => 'In sospeso',
      PendingTicketState.submitting => 'Invio',
      PendingTicketState.failed => isRepairable ? 'Da correggere' : 'Non inviato',
      PendingTicketState.submitted => 'Inviato',
    };
    final tone = switch (state) {
      PendingTicketState.pendingSync => ListStatusTone.warn,
      PendingTicketState.submitting => ListStatusTone.info,
      PendingTicketState.failed => ListStatusTone.bad,
      PendingTicketState.submitted => ListStatusTone.good,
    };

    final row = ListDocumentRow(
      data: ListRowData(
        title: ticket.title,
        meta: _pendingSubtitle(ticket, isRepairable: isRepairable),
        status: label,
        statusTone: tone,
        leading: Icon(
          isFailed ? LucideIcons.alertTriangle : LucideIcons.wifiOff,
          size: 16,
          color: isFailed ? context.colors.red : context.colors.inkMuted,
        ),
      ),
    );

    final hasPrimary = isRepairable || isFailed;
    if (!hasPrimary && isSubmitting) return row;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              if (isRepairable)
                // "Correggi", NOT "Riprova": a resend would carry the very id the server just
                // refused, so this button could only fail again.
                AppButton(
                  label: 'Correggi',
                  size: AppButtonSize.sm,
                  fullWidth: false,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(builder: (_) => NewTicketFormScreen(repairRow: ticket)),
                  ),
                )
              else if (isFailed)
                AppButton(
                  label: 'Riprova',
                  size: AppButtonSize.sm,
                  fullWidth: false,
                  onPressed: () => ref.read(ticketCreationQueueProvider).retry(ticket.id),
                ),
              const Spacer(),
              // A `submitting` row is excluded because a create request is in flight and its
              // outcome is unknown; removing the row here could leave a server ticket with no
              // local row to reconcile it.
              if (!isSubmitting)
                IconButton(
                  icon: Icon(LucideIcons.trash2, size: 18, color: context.colors.inkMuted),
                  tooltip: 'Elimina',
                  onPressed: () => _confirmDeletePendingTicket(context, ref, ticket),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `null`/empty parts are dropped and the rest joined with the prototype's middle dot.
String _joinNonEmpty(Iterable<String?> parts) =>
    parts.where((p) => p != null && p.trim().isNotEmpty).cast<String>().join(' · ');

ListStatusTone? _toneForStatus(String statusName) {
  // The prototype stamps `In attesa` amber, while the app's shared family maps it to info. The
  // prototype wins for this one label; every other status keeps the shared mapping.
  return statusName.trim().toLowerCase() == 'in attesa' ? ListStatusTone.warn : null;
}

String _pendingSubtitle(PendingTicket ticket, {required bool isRepairable}) {
  final state = PendingTicketState.fromString(ticket.state);
  return switch (state) {
    PendingTicketState.pendingSync => 'In attesa di connessione — verrà inviato automaticamente',
    PendingTicketState.submitting => 'Invio in corso…',
    // A repairable row's stored message is the 404's own prose ("Non trovato sul server…"), which
    // says what went wrong but not what to do about it — the action beside it says that.
    PendingTicketState.failed =>
      isRepairable
          ? 'Un riferimento non è più valido: correggi il ticket per inviarlo'
          : 'Invio non riuscito: ${ticket.error ?? 'errore sconosciuto'}',
    PendingTicketState.submitted => 'Inviato',
  };
}

/// Permanently removes a ticket that only ever existed on this device.
///
/// Pure local cleanup — no network, so it works with no signal, which is the whole point: a
/// technician must be able to get rid of a failed/duplicate row without waiting for a connection.
/// Deliberately NOT gated on `sistema.tenant.admin` (unlike the server-side delete on the detail
/// screen): the server never saw this row, and it is the technician's own offline draft.
Future<void> _confirmDeletePendingTicket(
  BuildContext context,
  WidgetRef ref,
  PendingTicket ticket,
) async {
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Eliminare il ticket?',
    message: '"${ticket.title}" verrà eliminato definitivamente da questo dispositivo.',
  );
  if (!confirmed || !context.mounted) return;

  await ref.read(ticketDeletionServiceProvider).deleteLocalOnly(ticket.id);
  if (context.mounted) {
    showAppToast(context, message: 'Ticket eliminato', tone: ToastTone.success);
  }
}

// ── Filter sheet ────────────────────────────────────────────────────────────

class _TicketFilterSheet extends ConsumerStatefulWidget {
  const _TicketFilterSheet({required this.initial});

  final _TicketFilters initial;

  @override
  ConsumerState<_TicketFilterSheet> createState() => _TicketFilterSheetState();
}

class _TicketFilterSheetState extends ConsumerState<_TicketFilterSheet> {
  late _TicketFilter _status = widget.initial.status;
  late String? _customerId = widget.initial.customerId;
  late String? _locationId = widget.initial.locationId;
  late String? _technicianId = widget.initial.technicianId;
  late String? _priority = widget.initial.priority;
  late DateTime? _dueFrom = widget.initial.dueFrom;
  late DateTime? _dueTo = widget.initial.dueTo;
  late bool _onlyMine = widget.initial.onlyMine;

  static const _priorities = ['Bassa', 'Media', 'Alta', 'Urgente'];
  static const _statusOptions = [
    _TicketFilter.oggi,
    _TicketFilter.aperti,
    _TicketFilter.inCorso,
    _TicketFilter.inAttesa,
    _TicketFilter.chiusi,
  ];

  Future<void> _pickDate({required bool isFrom}) async {
    final current = isFrom ? _dueFrom : _dueTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 1095)),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      final civil = DateTime.utc(picked.year, picked.month, picked.day);
      if (isFrom) {
        _dueFrom = civil;
      } else {
        _dueTo = civil;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const <Customer>[];
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? const <Location>[];
    final colleagues = ref.watch(allColleaguesProvider).valueOrNull ?? const <Colleague>[];
    final myId = ref.watch(internalUserIdProvider).valueOrNull;

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
                value: _customerId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti i clienti')),
                  ...customers.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _customerId = v;
                  if (v != null &&
                      _locationId != null &&
                      !locations.any((l) => l.id == _locationId && l.customerId == v)) {
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
                value: _locationId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte le sedi')),
                  ...visibleLocations.map(
                    (l) =>
                        DropdownMenuItem(value: l.id, child: Text(_joinNonEmpty([l.name, l.city]))),
                  ),
                ],
                onChanged: (v) => setState(() => _locationId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFieldShell(
              label: 'Tecnico',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _technicianId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutti i tecnici')),
                  ...colleagues.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.displayName)),
                  ),
                ],
                onChanged: (v) => setState(() => _technicianId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFieldShell(
              label: 'Priorità',
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _priority,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte le priorità')),
                  ..._priorities.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                ],
                onChanged: (v) => setState(() => _priority = v),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const AppFieldLabel(label: 'Periodo', enabled: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Da',
                    value: _dueFrom,
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'A',
                    value: _dueTo,
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo i miei ticket'),
              subtitle: myId == null
                  ? const Text('Disponibile dopo la prima sincronizzazione')
                  : null,
              value: _onlyMine,
              onChanged: myId == null ? null : (v) => setState(() => _onlyMine = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _TicketFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _TicketFilters(
                        status: _status,
                        customerId: _customerId,
                        locationId: _locationId,
                        technicianId: _technicianId,
                        priority: _priority,
                        dueFrom: _dueFrom,
                        dueTo: _dueTo,
                        onlyMine: _onlyMine,
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
  const _DateField({required this.label, required this.value, required this.onTap});

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
