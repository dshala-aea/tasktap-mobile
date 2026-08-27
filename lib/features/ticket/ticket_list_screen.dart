import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/tickets/pending_ticket_state.dart';
import '../../data/tickets/ticket_creation_queue_watcher.dart';
import '../../presentation/providers/schedule_providers.dart' show allLocationsProvider, allCustomersProvider;
import 'ticket_label.dart';
import 'ticket_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Filter options for the ticket list.
enum _TicketFilter { tutti, aperti, inCorso, inAttesa, completati }

extension _TicketFilterLabel on _TicketFilter {
  String get label => switch (this) {
    _TicketFilter.tutti => 'Tutti',
    _TicketFilter.aperti => 'Aperti',
    _TicketFilter.inCorso => 'In corso',
    _TicketFilter.inAttesa => 'In attesa',
    _TicketFilter.completati => 'Completati',
  };

  String? get statusMatch => switch (this) {
    _TicketFilter.tutti => null,
    _TicketFilter.aperti => 'aperto',
    _TicketFilter.inCorso => 'in corso',
    _TicketFilter.inAttesa => 'in attesa',
    _TicketFilter.completati => 'completato',
  };
}

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  _TicketFilter _filter = _TicketFilter.tutti;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _TicketListBody(
          filter: _filter,
          query: _query,
          searchCtrl: _searchCtrl,
          onFilterChanged: (f) => setState(() => _filter = f),
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuovo ticket',
          onPressed: () async {
            final created = await context.push<bool>('/ticket/new');
            if (created == true && mounted) {
              // List auto-refreshes via StreamProvider, no manual refresh needed.
            }
          },
        ),
      ),
    );
  }
}

class _TicketListBody extends ConsumerWidget {
  const _TicketListBody({
    required this.filter,
    required this.query,
    required this.searchCtrl,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  final _TicketFilter filter;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<_TicketFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final statusMapAsync = ref.watch(ticketStatusMapProvider);
    final pendingTickets = ref.watch(pendingTicketsProvider).valueOrNull ?? [];

    final statusMap = statusMapAsync.valueOrNull ?? {};
    final allTickets = ticketsAsync.valueOrNull ?? [];

    // One stream each for the whole list, not one per row: this list can run to hundreds of
    // tickets, and a per-row locationByIdProvider/customerByIdProvider watch opened (and tore
    // down, on scroll-out) two live Drift subscriptions per visible row.
    final locationsById = {
      for (final l in ref.watch(allLocationsProvider).valueOrNull ?? <Location>[]) l.id: l,
    };
    final customersById = {
      for (final c in ref.watch(allCustomersProvider).valueOrNull ?? <Customer>[]) c.id: c,
    };

    // Compute counts for subtitle.
    final inCorsoCount = allTickets.where((t) {
      final name = statusMap[t.statusId]?.toLowerCase() ?? '';
      return name == 'in corso';
    }).length;

    // Filter + search.
    final filtered = allTickets.where((t) {
      final statusName = statusMap[t.statusId]?.toLowerCase() ?? '';
      final matchFilter =
          filter.statusMatch == null || statusName == filter.statusMatch;
      final matchQuery =
          query.isEmpty ||
          t.title.toLowerCase().contains(query.toLowerCase()) ||
          t.id.toLowerCase().contains(query.toLowerCase());
      return matchFilter && matchQuery;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(syncProvider.notifier).performSync(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            // The filter icon that used to sit here was `onTap: () {}` — and redundant besides: the
            // status chips twelve pixels below it are the filter, and they work. A dead control
            // next to a live one doing the same job teaches the technician to distrust both.
            child: ScreenHeader(
              title: 'Ticket',
              subtitle: '${allTickets.length} totali · $inCorsoCount in corso',
            ),
          ),
          if (pendingTickets.isNotEmpty)
            SliverToBoxAdapter(
              child: _PendingTicketsSection(pendingTickets: pendingTickets),
            ),
          SliverToBoxAdapter(
            child: AppSearchBar(
              controller: searchCtrl,
              hint: 'Cerca ticket…',
              onChanged: onQueryChanged,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.md,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _TicketFilter.values.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: AppChip(
                        label: f.label,
                        active: filter == f,
                        onTap: () => onFilterChanged(f),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          if (ticketsAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxxl),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.ticket,
                title: 'Nessun ticket',
                body: 'I ticket sincronizzati appariranno qui.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final ticket = filtered[i];
                final statusName = statusMap[ticket.statusId] ?? '';
                final location = locationsById[ticket.locationId];
                final customerName = location != null ? customersById[location.customerId]?.companyName : null;
                final where = [
                  customerName,
                  location?.city,
                ].where((s) => s != null && s.isNotEmpty).join(' · ');
                return _TicketRow(
                  ticket: ticket,
                  statusName: statusName,
                  where: where,
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

// ── Pending (locally-created, not-yet-confirmed) tickets ───────────────────────

class _PendingTicketsSection extends StatelessWidget {
  const _PendingTicketsSection({required this.pendingTickets});

  final List<PendingTicket> pendingTickets;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        0,
        AppSpacing.pagePadding,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In sospeso (${pendingTickets.length})',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final t in pendingTickets) ...[
            _PendingTicketRow(ticket: t),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PendingTicketRow extends ConsumerWidget {
  const _PendingTicketRow({required this.ticket});

  final PendingTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = PendingTicketState.fromString(ticket.state);
    final isFailed = state == PendingTicketState.failed;

    final String subtitle = switch (state) {
      PendingTicketState.pendingSync =>
        'In attesa di connessione — verrà inviato automaticamente',
      PendingTicketState.submitting => 'Invio in corso…',
      PendingTicketState.failed =>
        'Invio non riuscito: ${ticket.error ?? 'errore sconosciuto'}',
      PendingTicketState.submitted => 'Inviato',
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isFailed ? context.colors.redSoft : context.colors.bg3,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isFailed ? LucideIcons.alertTriangle : LucideIcons.wifiOff,
            size: 18,
            color: isFailed ? context.colors.red : context.colors.inkMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ticket.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isFailed) ...[
            const SizedBox(width: 8),
            AppButton(
              label: 'Riprova',
              size: AppButtonSize.sm,
              onPressed: () =>
                  ref.read(ticketCreationQueueProvider).retry(ticket.id),
            ),
          ],
        ],
      ),
    );
  }
}

/// Vetro (module #2). Was a [ListRow] — icon avatar, title, reference-number subtitle, status
/// pill and date off to the side. Replaced because that told you *what kind of thing* a row was,
/// not what to do about it: title alone rarely says where to go or how urgent it is, and opening
/// every row just to triage a list of thirty is the exact complaint that started this redesign.
///
/// A priority stripe (real `Ticket.priority`, synced since schema 20 — see `app_database.dart`)
/// replaces the old leading icon tile; description, cliente/località (resolved the same way
/// `work_queue_section.dart` already does, not a new lookup) and due date fill out the row. No
/// `VetroGlass`/blur here on purpose: this list can run to hundreds of rows, and a per-row
/// backdrop filter during scroll is exactly the "many small instances" cost that widget's own doc
/// comment warns against — flat rows on the page ground, divided by `context.vetro.hairline`,
/// read as the same system without paying for it.
class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.ticket,
    required this.statusName,
    required this.where,
    required this.isLast,
  });

  final Ticket ticket;
  final String statusName;

  /// Cliente · città, resolved once for the whole list — see `_TicketListBody`'s own comment on
  /// why this is no longer a per-row provider watch.
  final String where;
  final bool isLast;

  Color _priorityColor(BuildContext context, AppVetroPalette v, String? priority) => switch (priority) {
    'Urgente' => v.statusBad,
    'Alta' => v.statusWarn,
    'Media' => v.tint,
    _ => context.colors.inkFaint, // Bassa, or unset — neutral, not a fifth accent colour
  };

  /// The stripe's own colour is invisible to a colorblind technician or a screen reader —
  /// spoken/announced priority instead of relying on hue alone to triage a list of thirty tickets.
  String _priorityLabel(String? priority) => switch (priority) {
    'Urgente' => 'Priorità urgente',
    'Alta' => 'Priorità alta',
    'Media' => 'Priorità media',
    _ => 'Priorità bassa',
  };

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final reference = ticketReference(ticket.numero);

    final dueDate = ticket.dueDate;
    final isOverdue = dueDate != null &&
        dueDate.isBefore(DateTime.now()) &&
        statusName.toLowerCase() != 'completato';
    final dueLabel = dueDate == null ? null : DateFormat('dd/MM/yy', 'it').format(dueDate.toLocal());

    return Semantics(
      // The stripe colour is a sighted-only cue; this is the same information for TalkBack/
      // VoiceOver, and for a sighted colorblind technician who can't tell the hues apart either.
      label: '${_priorityLabel(ticket.priority)}. ${ticket.title}${statusName.isNotEmpty ? ', $statusName' : ''}',
      button: true,
      child: InkWell(
      onTap: () => context.push('/ticket/${ticket.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 11),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: v.hairline)),
        ),
        // IntrinsicHeight, not a bare `Row(crossAxisAlignment: stretch, ...)`: this row lives
        // inside a SliverChildBuilderDelegate item, which sizes to its own content and hands the
        // Row no bounded height — `stretch` needs one to stretch the stripe into, and without
        // IntrinsicHeight giving it one first, layout throws (RenderFlex._computeSizes, unbounded
        // height) rather than silently doing something wrong.
        child: IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: _priorityColor(context, v, ticket.priority),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (reference != null)
                        Text(
                          reference,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.colors.inkFaint,
                            letterSpacing: 0.3,
                          ),
                        ),
                      const Spacer(),
                      if (statusName.isNotEmpty) StatusPill(stato: statusName, small: true, outlined: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ticket.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (ticket.description != null && ticket.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      ticket.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.inkMuted),
                    ),
                  ],
                  if (where.isNotEmpty || dueLabel != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (where.isNotEmpty) ...[
                          Icon(LucideIcons.mapPin, size: 11, color: context.colors.inkFaint),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              where,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: context.colors.ink,
                              ),
                            ),
                          ),
                        ],
                        if (dueLabel != null) ...[
                          const Spacer(),
                          Text(
                            dueLabel,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w600,
                              color: isOverdue ? v.statusBad : context.colors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          ),
        ),
      ),
      ),
    );
  }
}
