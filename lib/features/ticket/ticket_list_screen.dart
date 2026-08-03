import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'ticket_providers.dart';

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
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: _TicketListBody(
          filter: _filter,
          query: _query,
          searchCtrl: _searchCtrl,
          onFilterChanged: (f) => setState(() => _filter = f),
          onQueryChanged: (q) => setState(() => _query = q),
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
      final matchFilter =
          filter.statusMatch == null || statusName == filter.statusMatch;
      final matchQuery = query.isEmpty ||
          t.title.toLowerCase().contains(query.toLowerCase()) ||
          t.id.toLowerCase().contains(query.toLowerCase());
      return matchFilter && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Ticket',
            subtitle: '${allTickets.length} totali · $inCorsoCount in corso',
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.filter,
                onTap: () {},
              ),
            ],
          ),
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
              child: Padding(
                padding: EdgeInsets.all(48),
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
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final ticket = filtered[i];
                final statusName = statusMap[ticket.statusId] ?? '';
                return _TicketRow(
                  ticket: ticket,
                  statusName: statusName,
                  isLast: i == filtered.length - 1,
                );
              },
              childCount: filtered.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

class _TicketRow extends ConsumerWidget {
  const _TicketRow({
    required this.ticket,
    required this.statusName,
    required this.isLast,
  });

  final Ticket ticket;
  final String statusName;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortId =
        ticket.id.length > 8 ? ticket.id.substring(0, 8) : ticket.id;
    final dateLabel =
        DateFormat('dd/MM/yy', 'it').format(ticket.createdAt.toLocal());

    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.BG3,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(LucideIcons.ticket, size: 20, color: AppColors.MUTED),
      ),
      title: ticket.title,
      subtitle: '#$shortId',
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (statusName.isNotEmpty) StatusPill(stato: statusName, small: true),
          const SizedBox(height: 2),
          Text(
            dateLabel,
            style: const TextStyle(fontSize: 10, color: AppColors.MUTED),
          ),
        ],
      ),
      showDivider: !isLast,
      onTap: () => context.push('/ticket/${ticket.id}'),
    );
  }
}
