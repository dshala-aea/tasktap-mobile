import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/report_editor_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../admin/admin_api_client.dart';
import 'ticket_detail_api_client.dart';
import 'ticket_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
      backgroundColor: context.colors.bg2,
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
                        label: 'Assegna',
                        icon: const Icon(LucideIcons.userCheck, size: 16),
                        onPressed: () => _showAssignSheet(context, ref, ticket),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton.secondary(
                        label: 'Cliente',
                        onPressed: () => context.push(
                          AppRoutes.clientiDetail(ticket.customerId),
                        ),
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
                        onPressed: () =>
                            _createRapportino(context, ref, ticket),
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

  void _showAssignSheet(
    BuildContext context,
    WidgetRef ref,
    Ticket ticket,
  ) {
    final api = ref.read(adminApiClientProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AssignSheet(
        api: api,
        ticket: ticket,
      ),
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
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
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
          ? UnavailableState(
              icon: LucideIcons.wifiOff,
              titolo: offlineTitle,
              motivo: offlineBody,
            )
          : UnavailableState(
              icon: icon,
              titolo: errorTitle,
              motivo: errorBody,
            ),
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
        offlineBody: 'La lista dei rapportini di questo ticket richiede una '
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
              final dateLabel =
                  DateFormat('dd/MM/yyyy HH:mm', 'it').format(r.createdAt.toLocal());
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
            body: 'Questo ticket non ha un template di manutenzione collegato: non è previsto '
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
        offlineBody: 'Gli allegati di questo ticket richiedono una connessione: riprova quando '
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
              final dateLabel =
                  DateFormat('dd/MM/yyyy HH:mm', 'it').format(a.createdAt.toLocal());
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
        offlineBody: 'I materiali pianificati per questo ticket richiedono una connessione: '
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
                meta: !m.disponibile ? const AppChip(label: 'Non disponibile', active: false) : null,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assegnazione aggiornata')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        19,
        19,
        19,
        MediaQuery.of(context).viewInsets.bottom + 19,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assegna tecnico',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedUserId,
              decoration: const InputDecoration(
                labelText: 'Tecnico',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Non assegnato'),
                ),
                ..._technicians.map((t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                    )),
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
