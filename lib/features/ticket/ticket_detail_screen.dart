import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/report_editor_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'ticket_providers.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() =>
      _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  int _tabIndex = 0;

  static const _tabs = [
    AppTab(label: 'Report'),
    AppTab(label: 'Controllo'),
    AppTab(label: 'Pianificazioni'),
    AppTab(label: 'Allegati'),
    AppTab(label: 'Fabbisogno'),
  ];

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketByIdProvider(widget.ticketId));
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? {};
    final typeMap = ref.watch(ticketTypeMapProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (ticket) {
          if (ticket == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(
                    title: 'Ticket',
                    showBack: true,
                  ),
                  EmptyState(
                    icon: LucideIcons.xCircle,
                    title: 'Ticket non trovato',
                    body: 'Il ticket richiesto non è disponibile in cache.',
                  ),
                ],
              ),
            );
          }
          return _TicketDetailBody(
            ticket: ticket,
            statusMap: statusMap,
            typeMap: typeMap,
            tabIndex: _tabIndex,
            onTabSelected: (i) => setState(() => _tabIndex = i),
            tabs: _tabs,
          );
        },
      ),
    );
  }
}

class _TicketDetailBody extends ConsumerWidget {
  const _TicketDetailBody({
    required this.ticket,
    required this.statusMap,
    required this.typeMap,
    required this.tabIndex,
    required this.onTabSelected,
    required this.tabs,
  });

  final Ticket ticket;
  final Map<int, String> statusMap;
  final Map<int, String> typeMap;
  final int tabIndex;
  final ValueChanged<int> onTabSelected;
  final List<AppTab> tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusName = statusMap[ticket.statusId] ?? '';
    final typeName = typeMap[ticket.typeId] ?? '';
    final shortId =
        ticket.id.length > 8 ? ticket.id.substring(0, 8) : ticket.id;
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'it')
        .format(ticket.createdAt.toLocal());
    final closedLabel = ticket.closedAt != null
        ? DateFormat('dd/MM/yyyy', 'it').format(ticket.closedAt!.toLocal())
        : '—';

    final customerAsync = ref.watch(customerByIdProvider(ticket.customerId));
    final locationAsync = ref.watch(locationByIdProvider(ticket.locationId));

    final customerName =
        customerAsync.valueOrNull?.companyName ?? ticket.customerId;
    final locationName = locationAsync.valueOrNull?.name ?? ticket.locationId;
    final tecnicoLabel = ticket.assignedUserId ?? '—';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: '#$shortId',
            subtitle: ticket.title,
            showBack: true,
          ),

          // Status pill + type chip row
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: Row(
              children: [
                if (statusName.isNotEmpty) StatusPill(stato: statusName),
                if (typeName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  AppChip(label: typeName, active: false),
                ],
              ],
            ),
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                // KeyVal card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          KeyVal(label: 'Cliente', value: customerName),
                          KeyVal(label: 'Sede', value: locationName),
                          KeyVal(label: 'Tecnico', value: tecnicoLabel),
                          KeyVal(label: 'Data', value: dateLabel),
                          KeyVal(
                            label: 'Chiusura',
                            value: closedLabel,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Descrizione card
                if (ticket.description != null &&
                    ticket.description!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Descrizione'),
                            const SizedBox(height: 4),
                            Text(
                              ticket.description!,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.DARK,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Note tecnico card
                if (ticket.technicianNotes != null &&
                    ticket.technicianNotes!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Note tecnico'),
                            const SizedBox(height: 4),
                            Text(
                              ticket.technicianNotes!,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.DARK,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Tabs
                SliverToBoxAdapter(
                  child: AppTabs(
                    tabs: tabs,
                    selectedIndex: tabIndex,
                    onSelected: onTabSelected,
                  ),
                ),

                // Tab content
                SliverToBoxAdapter(
                  child: _TabContent(
                    tabIndex: tabIndex,
                    ticketId: ticket.id,
                  ),
                ),

                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            ),
          ),

          // Bottom actions
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 8, 19, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppButton.secondary(
                        label: 'Cliente',
                        onPressed: () => context.push(
                          AppRoutes.clientiDetail(ticket.customerId),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Crea rapportino',
                        onPressed: () =>
                            _createRapportino(context, ref, ticket),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppButton.dark(
                  label: 'Timbra cantiere',
                  icon: const Icon(Icons.location_on_outlined),
                  onPressed: () => context.push(
                    AppRoutes.cantiereTimbraPath(
                      ticketId: ticket.id,
                      customerId: ticket.customerId,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createRapportino(
    BuildContext context,
    WidgetRef ref,
    Ticket ticket,
  ) async {
    final repo = ref.read(draftReportRepositoryProvider);
    final id = 'draft-${DateTime.now().millisecondsSinceEpoch}';
    await repo.createDraft(
      DraftReportsCompanion.insert(
        id: id,
        tenantId: 'local',
        createdAt: DateTime.now().toUtc(),
        title: 'Rapportino — ${ticket.title}',
        insertedUserId: 'local-user',
        locationId: ticket.locationId,
        ticketId: Value(ticket.id),
        customerId: Value(ticket.customerId),
        isLocalOnly: const Value(true),
        stato: const Value('Bozza'),
      ),
    );
    if (context.mounted) {
      context.push(AppRoutes.rapportiniEditor(id));
    }
  }
}

class _TabContent extends ConsumerWidget {
  const _TabContent({required this.tabIndex, required this.ticketId});

  final int tabIndex;
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tabIndex) {
      0 => const _EmptyTab(
          icon: LucideIcons.fileText,
          label: 'Nessun rapportino',
          body: 'I rapportini per questo ticket appariranno qui.',
        ),
      1 => const _EmptyTab(
          icon: LucideIcons.clipboardCheck,
          label: 'Nessun controllo',
          body: 'I controlli appariranno qui.',
        ),
      2 => _PianificazioniTab(ticketId: ticketId),
      3 => const _EmptyTab(
          icon: LucideIcons.paperclip,
          label: 'Nessun allegato',
          body: 'Gli allegati caricati appariranno qui.',
        ),
      4 => const _EmptyTab(
          icon: LucideIcons.package,
          label: 'Nessun fabbisogno',
          body: 'I materiali richiesti appariranno qui.',
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.label,
    required this.body,
  });

  final IconData icon;
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 0, 19, 0),
      child: EmptyState(icon: icon, title: label, body: body),
    );
  }
}

class _PianificazioniTab extends ConsumerWidget {
  const _PianificazioniTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesForTicketProvider(ticketId));

    return schedulesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => const _EmptyTab(
        icon: LucideIcons.calendar,
        label: 'Errore caricamento',
        body: 'Impossibile caricare le pianificazioni.',
      ),
      data: (schedules) => schedules.isEmpty
          ? const _EmptyTab(
              icon: LucideIcons.calendarOff,
              label: 'Nessuna pianificazione',
              body:
                  'Le pianificazioni collegate a questo ticket appariranno qui.',
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
              child: Column(
                children: schedules.map((s) {
                  final dateLabel = DateFormat('EEE d MMM HH:mm', 'it')
                      .format(s.activityDate.toLocal());
                  return ListRow(
                    leading: const Icon(
                      LucideIcons.calendarDays,
                      size: 20,
                      color: AppColors.MUTED,
                    ),
                    title: s.title.isNotEmpty ? s.title : 'Intervento',
                    subtitle: dateLabel,
                    showDivider: s != schedules.last,
                  );
                }).toList(),
              ),
            ),
    );
  }
}
