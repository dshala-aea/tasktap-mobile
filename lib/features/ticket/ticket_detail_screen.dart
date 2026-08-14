import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/report_editor_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../admin/admin_api_client.dart';
import 'ticket_detail_api_client.dart';
import 'ticket_providers.dart';
import 'ticket_workflow_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  int _tabIndex = 0;

  static const _tabs = [
    AppTab(label: 'Report'),
    AppTab(label: 'Controllo'),
    AppTab(label: 'Pianificazioni'),
    AppTab(label: 'Allegati'),
    AppTab(label: 'Fabbisogno'),
    AppTab(label: 'Ore'),
    AppTab(label: 'Storico'),
  ];

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketByIdProvider(widget.ticketId));
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? {};
    final typeMap = ref.watch(ticketTypeMapProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (ticket) {
          if (ticket == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(title: 'Ticket', showBack: true),
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
    final shortId = ticket.id.length > 8 ? ticket.id.substring(0, 8) : ticket.id;
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'it').format(ticket.createdAt.toLocal());
    final closedLabel = ticket.closedAt != null
        ? DateFormat('dd/MM/yyyy', 'it').format(ticket.closedAt!.toLocal())
        : '—';

    final customerAsync = ref.watch(customerByIdProvider(ticket.customerId));
    final locationAsync = ref.watch(locationByIdProvider(ticket.locationId));

    final customerName = customerAsync.valueOrNull?.companyName ?? ticket.customerId;
    final locationName = locationAsync.valueOrNull?.name ?? ticket.locationId;
    // Was the raw `assignedUserId` — a GUID, rendered at a technician as the answer to "who has
    // this job". Resolved from the synced colleagues mirror, so it still reads offline; falls back
    // to the id when the mirror does not know it rather than showing nothing.
    final assignedId = ticket.assignedUserId;
    final tecnicoLabel = assignedId == null
        ? '—'
        : (ref.watch(colleagueNameProvider(assignedId)).valueOrNull ?? assignedId);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(title: '#$shortId', subtitle: ticket.title, showBack: true),

          // Status pill + type chip + the two workflow controls.
          //
          // Both controls live in this existing row on purpose. The bottom action stack already
          // carries four buttons and has twice been squeezed until something below it stopped
          // laying out; this row is already on screen and costs nothing to reuse. It is also where
          // they belong — changing a status is editing the thing the pill displays.
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: _TicketStatusRow(ticket: ticket, statusName: statusName, typeName: typeName),
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                // Timer: status and control together, at the top of the content.
                //
                // Deliberately not in the bottom action stack, which already carries four
                // buttons. Adding a fifth control there cost 74dp of the scroll viewport on every
                // ticket — enough that the tab strip below it stopped being laid out at all on a
                // short screen, since slivers build lazily. It belongs with the content anyway:
                // it reports state as much as it offers an action.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
                    child: _TicketTimerBar(ticketId: ticket.id),
                  ),
                ),

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
                          KeyVal(label: 'Chiusura', value: closedLabel, showDivider: false),
                        ],
                      ),
                    ),
                  ),
                ),

                // Descrizione card
                if (ticket.description != null && ticket.description!.isNotEmpty)
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
                                color: context.colors.ink,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Note tecnico card
                if (ticket.technicianNotes != null && ticket.technicianNotes!.isNotEmpty)
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
                                color: context.colors.ink,
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
                  child: AppTabs(tabs: tabs, selectedIndex: tabIndex, onSelected: onTabSelected),
                ),

                // Tab content
                SliverToBoxAdapter(
                  child: _TabContent(tabIndex: tabIndex, ticketId: ticket.id),
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
                        label: 'Assegna',
                        icon: const Icon(LucideIcons.userCheck, size: 16),
                        onPressed: () => _showAssignSheet(context, ref, ticket),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton.secondary(
                        label: 'Cliente',
                        onPressed: () => context.push(AppRoutes.clientiDetail(ticket.customerId)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Crea rapportino',
                        onPressed: () => _createRapportino(context, ref, ticket),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton.dark(
                        label: 'Timbra cantiere',
                        icon: const Icon(LucideIcons.mapPin),
                        onPressed: () => context.push(
                          AppRoutes.cantiereTimbraPath(
                            ticketId: ticket.id,
                            customerId: ticket.customerId,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createRapportino(BuildContext context, WidgetRef ref, Ticket ticket) async {
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

  void _showAssignSheet(BuildContext context, WidgetRef ref, Ticket ticket) {
    final api = ref.read(adminApiClientProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AssignSheet(api: api, ticket: ticket),
    );
  }
}

class _TabContent extends ConsumerWidget {
  const _TabContent({required this.tabIndex, required this.ticketId});

  final int tabIndex;
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tabIndex) {
      0 => _ReportTab(ticketId: ticketId),
      1 => _ControlloTab(ticketId: ticketId),
      2 => _PianificazioniTab(ticketId: ticketId),
      3 => _AllegatiTab(ticketId: ticketId),
      4 => _FabbisognoTab(ticketId: ticketId),
      5 => _OreTab(ticketId: ticketId),
      6 => _StoricoTab(ticketId: ticketId),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Centered spinner used by every fetch-on-demand tab while loading.
class _TabLoading extends StatelessWidget {
  const _TabLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
    );
  }
}

/// Shown when a fetch-on-demand tab's request fails. Distinguishes "offline"
/// ([TicketDetailOfflineException] — say so plainly) from any other error
/// (network hiccup, 500, …), so neither is mistaken for the other and
/// neither is mistaken for a genuine empty list.
class _TabError extends StatelessWidget {
  const _TabError({
    required this.icon,
    required this.offline,
    required this.offlineTitle,
    required this.offlineBody,
    required this.errorTitle,
    required this.errorBody,
  });

  final IconData icon;
  final bool offline;
  final String offlineTitle;
  final String offlineBody;
  final String errorTitle;
  final String errorBody;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 0, 19, 0),
      child: offline
          ? UnavailableState(icon: LucideIcons.wifiOff, titolo: offlineTitle, motivo: offlineBody)
          : UnavailableState(icon: icon, titolo: errorTitle, motivo: errorBody),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatQty(double qty) =>
    qty == qty.truncateToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(1);

// ── Report tab ───────────────────────────────────────────────────────────────

class _ReportTab extends ConsumerWidget {
  const _ReportTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(ticketReportsProvider(ticketId));

    return reportsAsync.when(
      loading: () => const _TabLoading(),
      error: (e, _) => _TabError(
        icon: LucideIcons.fileText,
        offline: e is TicketDetailOfflineException,
        offlineTitle: 'Rapportini non disponibili offline',
        offlineBody:
            'La lista dei rapportini di questo ticket richiede una '
            'connessione: riprova quando torni online.',
        errorTitle: 'Impossibile caricare i rapportini',
        errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (reports) {
        if (reports.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.fileText,
            label: 'Nessun rapportino',
            body: 'Non ci sono rapportini registrati per questo ticket.',
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
          child: Column(
            children: reports.map((r) {
              final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'it').format(r.createdAt.toLocal());
              return ListRow(
                leading: Icon(LucideIcons.fileText, size: 20, color: context.colors.inkMuted),
                title: r.title.isNotEmpty ? r.title : 'Rapportino',
                subtitle: dateLabel,
                meta: StatusPill(stato: r.statoLabel, small: true),
                showDivider: r != reports.last,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ── Controllo tab ────────────────────────────────────────────────────────────

class _ControlloTab extends ConsumerWidget {
  const _ControlloTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controlsAsync = ref.watch(ticketControlsProvider(ticketId));

    return controlsAsync.when(
      loading: () => const _TabLoading(),
      error: (e, _) => _TabError(
        icon: LucideIcons.clipboardCheck,
        offline: e is TicketDetailOfflineException,
        offlineTitle: 'Controlli non disponibili offline',
        offlineBody:
            'Il checklist di questo ticket richiede una connessione: riprova quando torni online.',
        errorTitle: 'Impossibile caricare i controlli',
        errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (groups) {
        final flat = flattenTicketControls(groups);
        if (flat.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.clipboardCheck,
            label: 'Nessun controllo previsto',
            body:
                'Questo ticket non ha un template di manutenzione collegato: non è previsto '
                'alcun controllo per questo intervento.',
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
          child: Column(
            children: flat
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TicketControlStatusCard(flat: f),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _TicketControlStatusCard extends StatelessWidget {
  const _TicketControlStatusCard({required this.flat});

  final FlatTicketControl flat;

  @override
  Widget build(BuildContext context) {
    final c = flat.control;
    final (icon, color) = switch (c.status) {
      'Completed' => (LucideIcons.checkCircle, context.colors.green),
      'NotApplicable' => (LucideIcons.xCircle, context.colors.inkMuted),
      _ => (LucideIcons.square, context.colors.inkDisabled),
    };
    final valueLabel = _valueLabel(c);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (flat.groupPath.isNotEmpty)
                  Text(
                    flat.groupPath,
                    style: TextStyle(color: context.colors.inkMuted, fontSize: 11),
                  ),
                Text(
                  c.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: context.colors.ink,
                  ),
                ),
                if (valueLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      valueLabel,
                      style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _valueLabel(TicketControlDto c) {
    switch (c.type) {
      case ControlType.checkbox:
      case ControlType.radioOnOff:
        if (c.boolValue == null) return null;
        return c.boolValue! ? 'Sì' : 'No';
      case ControlType.date:
        if (c.dateValue == null) return null;
        return DateFormat('dd/MM/yyyy', 'it').format(c.dateValue!.toLocal());
      case ControlType.freeText:
      case ControlType.singleChoice:
      case ControlType.unknown:
        return c.stringValue;
    }
  }
}

// ── Allegati tab ─────────────────────────────────────────────────────────────

class _AllegatiTab extends ConsumerWidget {
  const _AllegatiTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(ticketAttachmentsProvider(ticketId));

    return attachmentsAsync.when(
      loading: () => const _TabLoading(),
      error: (e, _) => _TabError(
        icon: LucideIcons.paperclip,
        offline: e is TicketDetailOfflineException,
        offlineTitle: 'Allegati non disponibili offline',
        offlineBody:
            'Gli allegati di questo ticket richiedono una connessione: riprova quando '
            'torni online.',
        errorTitle: 'Impossibile caricare gli allegati',
        errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (attachments) {
        if (attachments.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.paperclip,
            label: 'Nessun allegato',
            body: 'Non ci sono allegati caricati per questo ticket.',
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
          child: Column(
            children: attachments.map((a) {
              final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'it').format(a.createdAt.toLocal());
              return ListRow(
                leading: Icon(LucideIcons.paperclip, size: 20, color: context.colors.inkMuted),
                title: a.fileName,
                subtitle: '${_formatBytes(a.sizeBytes)} · $dateLabel',
                showDivider: a != attachments.last,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ── Fabbisogno tab ───────────────────────────────────────────────────────────

class _FabbisognoTab extends ConsumerWidget {
  const _FabbisognoTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(ticketMaterialiProvider(ticketId));

    return materialiAsync.when(
      loading: () => const _TabLoading(),
      error: (e, _) => _TabError(
        icon: LucideIcons.package,
        offline: e is TicketDetailOfflineException,
        offlineTitle: 'Fabbisogno non disponibile offline',
        offlineBody:
            'I materiali pianificati per questo ticket richiedono una connessione: '
            'riprova quando torni online.',
        errorTitle: 'Impossibile caricare il fabbisogno',
        errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (materiali) {
        if (materiali.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.package,
            label: 'Nessun fabbisogno',
            body: 'Non ci sono materiali pianificati per questo ticket.',
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
          child: Column(
            children: materiali.map((m) {
              final qtyLabel = m.unitaMisura != null
                  ? '${_formatQty(m.quantita)} ${m.unitaMisura}'
                  : _formatQty(m.quantita);
              return ListRow(
                leading: Icon(
                  LucideIcons.package,
                  size: 20,
                  color: m.disponibile ? context.colors.inkMuted : context.colors.red,
                ),
                title: m.nome,
                subtitle: m.codice != null ? '${m.codice} · $qtyLabel' : qtyLabel,
                meta: !m.disponibile
                    ? const AppChip(label: 'Non disponibile', active: false)
                    : null,
                showDivider: m != materiali.last,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.label, required this.body});

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
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
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
              body: 'Le pianificazioni collegate a questo ticket appariranno qui.',
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
              child: Column(
                children: schedules.map((s) {
                  final dateLabel = DateFormat(
                    'EEE d MMM HH:mm',
                    'it',
                  ).format(s.activityDate.toLocal());
                  return ListRow(
                    leading: Icon(
                      LucideIcons.calendarDays,
                      size: 20,
                      color: context.colors.inkMuted,
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

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.api, required this.ticket});

  final AdminApiClient api;
  final Ticket ticket;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  String? _selectedUserId;
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _technicians = [];

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.ticket.assignedUserId;
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    try {
      final techs = await widget.api.fetchTechnicians();
      if (mounted) {
        setState(() {
          _technicians = techs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.api.assignTicket(widget.ticket.id, _selectedUserId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Assegnazione aggiornata')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(19, 19, 19, MediaQuery.of(context).viewInsets.bottom + 19),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assegna tecnico', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedUserId,
              decoration: const InputDecoration(labelText: 'Tecnico', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('Non assegnato')),
                ..._technicians.map(
                  (t) => DropdownMenuItem(
                    value: t['id'] as String,
                    child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selectedUserId = v),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _isSaving ? 'Salvataggio…' : 'Salva',
              onPressed: _isSaving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Timer bar
// ══════════════════════════════════════════════════════════════════════════════

/// Start and stop the clock against this ticket.
///
/// The routes behind it (`POST .../worklogs/start|stop`) have been live the whole time with no
/// call site, so a technician could open a ticket and read every detail of it while having no way
/// to book a minute of the work against it.
///
/// The bar takes the rack's strap when a clock is running: the same yellow mark the dashboard puts
/// on a live tracker and the ticket list puts on the in-corso row. A technician who has left a
/// timer going overnight should see the same signal wherever they land.
class _TicketTimerBar extends ConsumerStatefulWidget {
  const _TicketTimerBar({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_TicketTimerBar> createState() => _TicketTimerBarState();
}

class _TicketTimerBarState extends ConsumerState<_TicketTimerBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // Re-read rather than patching local state: the server owns whether a clock is running, and
      // this screen has just changed it.
      ref.invalidate(ticketWorklogsProvider(widget.ticketId));
      await ref.read(ticketWorklogsProvider(widget.ticketId).future);
    } on TicketWorkflowFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: context.colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(ticketWorklogsProvider(widget.ticketId));

    // Offline is stated, not hidden behind a disabled button with no explanation. These writes
    // have no idempotent upsert to queue against, so there is nothing to promise here.
    if (async.hasError && async.error is TicketDetailOfflineException) {
      return AppCard(
        child: Row(
          children: [
            Icon(LucideIcons.cloudOff, size: 16, color: c.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Timer non disponibile offline',
                style: TextStyle(fontSize: 12, color: c.inkMuted),
              ),
            ),
          ],
        ),
      );
    }

    final running = ref.watch(runningTicketWorklogProvider(widget.ticketId));
    final isRunning = running != null;

    return AppCard(
      strapped: isRunning,
      child: Row(
        children: [
          Icon(
            isRunning ? LucideIcons.timer : LucideIcons.clock,
            size: 18,
            color: isRunning ? c.ink : c.inkMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              switch ((async.isLoading, isRunning)) {
                (true, _) => 'Verifica timer…',
                (false, true) => 'Timer in corso',
                (false, false) => 'Nessun timer attivo',
              },
              style: TextStyle(
                fontSize: 13,
                fontWeight: isRunning ? FontWeight.w700 : FontWeight.w500,
                color: isRunning ? c.ink : c.inkMuted,
              ),
            ),
          ),
          if (_busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            AppButton(
              label: isRunning ? 'Ferma' : 'Avvia',
              size: AppButtonSize.sm,
              fullWidth: false,
              variant: isRunning ? AppButtonVariant.dark : AppButtonVariant.primary,
              onPressed: async.isLoading
                  ? null
                  : () => _run(() {
                      final api = ref.read(ticketWorkflowApiClientProvider);
                      return isRunning
                          ? api.stopTimer(widget.ticketId)
                          : api.startTimer(widget.ticketId);
                    }),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Status row: the two workflow controls
// ══════════════════════════════════════════════════════════════════════════════

/// The status pill (tap to change it) plus "Prendi in carico" when nobody owns the ticket.
///
/// `PUT /api/Tickets/{id}/status` and `POST /api/Tickets/{id}/self-assign` were both live with no
/// caller, so a technician could see a ticket was Aperto and unassigned and had no way to take it
/// or move it along.
///
/// ## Why the two refresh differently
///
/// The screen reads its ticket from the Drift mirror, so a server-only write leaves the row on
/// screen stale until the next sync — which is what the existing assign sheet does today.
///
/// A **status** change writes through to the mirror as well: the id we send is the id the server
/// accepted, so copying it locally states nothing we do not know. A **self-assign** does not. The
/// server sets `AssignedUserId` from its own notion of the caller, and this client's `AuthUser.id`
/// is not guaranteed to be that value — writing it locally would be guessing an identifier into a
/// record, which is the one thing this app does not do. So self-assign asks for a sync and lets
/// the server's answer land.
class _TicketStatusRow extends ConsumerStatefulWidget {
  const _TicketStatusRow({required this.ticket, required this.statusName, required this.typeName});

  final Ticket ticket;
  final String statusName;
  final String typeName;

  @override
  ConsumerState<_TicketStatusRow> createState() => _TicketStatusRowState();
}

class _TicketStatusRowState extends ConsumerState<_TicketStatusRow> {
  bool _busy = false;

  void _report(String message, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? context.colors.green : context.colors.red,
      ),
    );
  }

  Future<void> _selfAssign() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(ticketWorkflowApiClientProvider).selfAssign(widget.ticket.id);
      _report('Ticket assegnato a te.', ok: true);
      // No local write — see the class doc. The sync brings back whatever id the server actually
      // recorded, and the Drift stream under this screen updates itself when it lands.
      await ref.read(syncProvider.notifier).performSync();
    } on TicketWorkflowFailure catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(int statusId, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketWorkflowApiClientProvider)
          .updateStatus(ticketId: widget.ticket.id, statusId: statusId);

      // Safe to mirror: this is the value the server just accepted, not a value we invented.
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.tickets)..where((t) => t.id.equals(widget.ticket.id))).write(
        TicketsCompanion(statusId: Value(statusId), updatedAt: Value(DateTime.now().toUtc())),
      );

      _report('Stato aggiornato: $label', ok: true);
    } on TicketWorkflowFailure catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStatusSheet() async {
    final statuses = ref.read(ticketStatusMapProvider).valueOrNull ?? {};
    if (statuses.isEmpty) {
      _report('Elenco stati non disponibile. Attendi la sincronizzazione.');
      return;
    }

    final chosen = await showModalBottomSheet<MapEntry<int, String>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRack.cellRadius)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 16, 19, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cambia stato',
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ctx.colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final entry in statuses.entries)
              ListRow(
                title: entry.value,
                strapped: entry.key == widget.ticket.statusId,
                meta: entry.key == widget.ticket.statusId
                    ? Icon(LucideIcons.check, size: 16, color: ctx.colors.ink)
                    : null,
                onTap: () => Navigator.of(ctx).pop(entry),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen == null || chosen.key == widget.ticket.statusId) return;
    await _changeStatus(chosen.key, chosen.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unassigned = widget.ticket.assignedUserId == null;

    return Row(
      children: [
        if (widget.statusName.isNotEmpty)
          // A 44dp target around the pill: the pill itself is a 20dp badge, and this is now a
          // control rather than a label.
          AppTappable(
            onTap: _busy ? null : _openStatusSheet,
            borderRadius: AppRack.insetShape,
            semanticLabel: 'Stato: ${widget.statusName}. Tocca per cambiare.',
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusPill(stato: widget.statusName),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronRight, size: 14, color: c.inkMuted),
                ],
              ),
            ),
          ),
        if (widget.typeName.isNotEmpty) ...[
          const SizedBox(width: 8),
          AppChip(label: widget.typeName, active: false),
        ],
        const Spacer(),
        if (_busy)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else if (unassigned)
          AppButton(
            label: 'Prendi in carico',
            size: AppButtonSize.sm,
            fullWidth: false,
            onPressed: _selfAssign,
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Ore tab — the time booked against this ticket
// ══════════════════════════════════════════════════════════════════════════════

/// Every worklog entry on the ticket, newest first.
///
/// The timer bar above already reads this provider, but only to answer "is a clock running". The
/// entries themselves — who booked what, and how long — had no surface at all, so a technician
/// could start and stop a timer and never see what it recorded.
class _OreTab extends ConsumerWidget {
  const _OreTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketWorklogsProvider(ticketId));

    return async.when(
      loading: () => const _TabLoading(),
      error: (e, _) => _TabError(
        icon: LucideIcons.clock,
        offline: e is TicketDetailOfflineException,
        offlineTitle: 'Ore non disponibili offline',
        offlineBody:
            'Le ore registrate su questo ticket si leggono solo online: '
            'riprova quando torni in copertura.',
        errorTitle: 'Impossibile caricare le ore',
        errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.clock,
            label: 'Nessuna ora registrata',
            body: 'Avvia il timer o aggiungi le ore manualmente per registrarle su questo ticket.',
          );
        }

        // Only closed entries contribute. A running one has no duration yet, and counting it as
        // zero would quietly understate the total on exactly the ticket being worked.
        final closed = entries.where((e) => !e.isRunning);
        final total = closed.fold<Duration>(Duration.zero, (a, e) => a + e.duration!);
        final running = entries.where((e) => e.isRunning).length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                strapped: running > 0,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Totale registrato',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.inkMuted,
                        ),
                      ),
                    ),
                    Text(
                      _hhmm(total),
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (running > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    // Stated, so the total is not mistaken for the whole story while a clock runs.
                    running == 1
                        ? 'Un timer è ancora in corso e non è incluso nel totale.'
                        : '$running timer sono ancora in corso e non sono inclusi nel totale.',
                    style: GoogleFonts.manrope(fontSize: 11, color: context.colors.inkMuted),
                  ),
                ),
              const SizedBox(height: 10),
              for (final e in entries) _WorklogRow(entry: e),
            ],
          ),
        );
      },
    );
  }
}

class _WorklogRow extends StatelessWidget {
  const _WorklogRow({required this.entry});

  final TicketWorkLogDto entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dateLabel = DateFormat('EEE d MMM', 'it').format(entry.workDate.toLocal());
    final span = entry.endTime == null
        ? '${_hhmm(entry.startTime)} → in corso'
        : '${_hhmm(entry.startTime)} – ${_hhmm(entry.endTime!)}';

    return ListRow(
      strapped: entry.isRunning,
      leading: Icon(
        entry.isManualEntry ? LucideIcons.pencil : LucideIcons.timer,
        size: 20,
        color: entry.isRunning ? c.ink : c.inkMuted,
      ),
      title: dateLabel,
      subtitle: [
        span,
        if (entry.isManualEntry) 'inserimento manuale',
        if (entry.description != null && entry.description!.isNotEmpty) entry.description!,
      ].join(' · '),
      meta: Text(
        // An open entry shows a dash, not 0:00 — the same refusal to draw a stopped-looking clock
        // that the dashboard hero and TicketWorkLogDto.duration both make.
        entry.duration == null ? '—' : _hhmm(entry.duration!),
        style: GoogleFonts.sora(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: entry.isRunning ? c.inkMuted : c.ink,
        ),
      ),
    );
  }
}

/// `H:MM`, counting hours past 24 rather than wrapping — an overnight entry reads 26:10, not 2:10.
String _hhmm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).abs().toString().padLeft(2, '0');
  return '$h:$m';
}

// ══════════════════════════════════════════════════════════════════════════════
// Storico tab — the ticket's audit trail
// ══════════════════════════════════════════════════════════════════════════════

/// Field-by-field history, newest first.
///
/// The backend records the change as raw column names and raw values (`StatusId`, `1` → `2`),
/// because it is an audit table rather than a display projection. Rendering that verbatim would
/// put database identifiers in front of a technician, so field names are translated and the two
/// id-valued fields are resolved through the maps this screen already holds.
class _StoricoTab extends ConsumerWidget {
  const _StoricoTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketHistoryProvider(ticketId));
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? {};
    final typeMap = ref.watch(ticketTypeMapProvider).valueOrNull ?? {};

    return async.when(
      loading: () => const _TabLoading(),
      error: (e, _) => _TabError(
        icon: LucideIcons.history,
        offline: e is TicketDetailOfflineException,
        offlineTitle: 'Storico non disponibile offline',
        offlineBody:
            'La cronologia delle modifiche si legge solo online: '
            'riprova quando torni in copertura.',
        errorTitle: 'Impossibile caricare lo storico',
        errorBody: 'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.history,
            label: 'Nessuna modifica registrata',
            body: 'Le modifiche a questo ticket compariranno qui.',
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
          child: Column(
            children: [
              for (final e in entries)
                ListRow(
                  leading: Icon(LucideIcons.history, size: 20, color: context.colors.inkMuted),
                  title: _fieldLabel(e.fieldName),
                  subtitle: _change(e, statusMap, typeMap),
                  meta: Text(
                    DateFormat('dd/MM HH:mm', 'it').format(e.changedAt.toLocal()),
                    style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The audit table stores column names. Untranslated ones fall through as-is rather than being
  /// hidden: a change nobody can name still happened, and dropping it would make the trail lie.
  static String _fieldLabel(String field) => switch (field) {
    'StatusId' => 'Stato',
    'AssignedUserId' => 'Tecnico assegnato',
    'TypeId' => 'Tipo',
    'Title' => 'Titolo',
    'Description' => 'Descrizione',
    'TechnicianNotes' => 'Note tecnico',
    'InternalNotes' => 'Note interne',
    'ClosedAt' => 'Chiusura',
    _ => field,
  };

  static String _change(
    TicketHistoryEntryDto e,
    Map<int, String> statusMap,
    Map<int, String> typeMap,
  ) {
    String render(String? v) {
      if (v == null || v.isEmpty) return '—';
      final asInt = int.tryParse(v);
      if (asInt != null) {
        if (e.fieldName == 'StatusId') return statusMap[asInt] ?? v;
        if (e.fieldName == 'TypeId') return typeMap[asInt] ?? v;
      }
      return v;
    }

    return '${render(e.oldValue)} → ${render(e.newValue)}';
  }
}
