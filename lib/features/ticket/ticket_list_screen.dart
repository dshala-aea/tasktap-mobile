import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/tickets/pending_ticket_state.dart';
import '../../data/tickets/ticket_creation_queue_watcher.dart';
import 'ticket_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
      body: Rack(
        child: SafeArea(
          child: _TicketListBody(
            filter: _filter,
            query: _query,
            searchCtrl: _searchCtrl,
            onFilterChanged: (f) => setState(() => _filter = f),
            onQueryChanged: (q) => setState(() => _query = q),
          ),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuovo ticket',
        onPressed: () async {
          final created = await context.push<bool>('/ticket/new');
          if (created == true && mounted) {
            // List auto-refreshes via StreamProvider, no manual refresh needed.
          }
        },
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

    // Compute counts for subtitle.
    final inCorsoCount = allTickets.where((t) {
      final name = statusMap[t.statusId]?.toLowerCase() ?? '';
      return name == 'in corso';
    }).length;

    // Filter + search.
    final filtered = allTickets.where((t) {
      final statusName = statusMap[t.statusId]?.toLowerCase() ?? '';
      final matchFilter = filter.statusMatch == null || statusName == filter.statusMatch;
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
            SliverToBoxAdapter(child: _PendingTicketsSection(pendingTickets: pendingTickets)),
          SliverToBoxAdapter(
            child: AppSearchBar(
              controller: searchCtrl,
              hint: 'Cerca ticket…',
              onChanged: onQueryChanged,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _TicketFilter.values.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
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
                child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
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
                return _TicketRow(
                  ticket: ticket,
                  statusName: statusName,
                  isLast: i == filtered.length - 1,
                );
              }, childCount: filtered.length),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
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
      padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In sospeso (${pendingTickets.length})',
            style: TextStyle(
              fontFamily: 'Sora',
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
      PendingTicketState.pendingSync => 'In attesa di connessione — verrà inviato automaticamente',
      PendingTicketState.submitting => 'Invio in corso…',
      PendingTicketState.failed => 'Invio non riuscito: ${ticket.error ?? 'errore sconosciuto'}',
      PendingTicketState.submitted => 'Inviato',
    };

    return Container(
      padding: const EdgeInsets.all(12),
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
                    fontFamily: 'Manrope',
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
                    fontFamily: 'Manrope',
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
              onPressed: () => ref.read(ticketCreationQueueProvider).retry(ticket.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketRow extends ConsumerWidget {
  const _TicketRow({required this.ticket, required this.statusName, required this.isLast});

  final Ticket ticket;
  final String statusName;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortId = ticket.id.length > 8 ? ticket.id.substring(0, 8) : ticket.id;
    final dateLabel = DateFormat('dd/MM/yy', 'it').format(ticket.createdAt.toLocal());

    return ListRow(
      // The one ticket you are actually on gets the strap, the same yellow mark the running
      // timbratura carries on the dashboard. Scanning a list of thirty for "which one am I on"
      // is the single most common thing a technician does on this screen.
      strapped: statusName.toLowerCase() == 'in corso',
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: context.colors.bg3, borderRadius: AppRack.insetShape),
        child: Icon(LucideIcons.ticket, size: 20, color: context.colors.inkMuted),
      ),
      title: ticket.title,
      subtitle: '#$shortId',
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (statusName.isNotEmpty) StatusPill(stato: statusName, small: true),
          const SizedBox(height: 2),
          Text(dateLabel, style: TextStyle(fontSize: 10, color: context.colors.inkMuted)),
        ],
      ),
      showDivider: !isLast,
      onTap: () => context.push('/ticket/${ticket.id}'),
    );
  }
}
