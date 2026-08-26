import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/widgets/vetro_button.dart';
import '../../core/widgets/vetro_card.dart';
import '../../core/widgets/vetro_compartment_tile.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart';
import '../../data/tickets/pending_ticket_attachment_state.dart';
import '../../data/tickets/ticket_attachment_upload_queue_watcher.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../admin/admin_api_client.dart';
import '../rapportino/create_draft.dart';
import 'edit_ticket_screen.dart';
import 'ticket_detail_api_client.dart';
import 'ticket_label.dart';
import 'ticket_providers.dart';
import 'ticket_workflow_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  /// Owned here rather than by the body, which is rebuilt on every ticket change.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Ordered by who is holding the phone.
  ///
  /// This was a pinned horizontal strip (four tabs fit a phone, there are eight — four sat past
  /// the visible edge), then an accordion (every name on screen, but the page grew as long as
  /// whichever section was open, and a technician had to scroll past a long one to reach the
  /// next). Now a grid of compartments: every name is on screen at a constant size regardless of
  /// what is open, and opening one is a bottom sheet over the ticket rather than the ticket
  /// itself growing and shrinking underneath you. The order survives from the tab era for the
  /// same reason it was chosen then — Dettagli/Report/Controllo/Allegati/Ore is the technician's
  /// own path through a ticket; Pianificazioni, Fabbisogno and Storico are office/lookup concerns
  /// and sit lower, not removed.
  static const _sectionLabels = [
    'Dettagli',
    'Report',
    'Controllo',
    'Allegati',
    'Ore',
    'Pianificazioni',
    'Fabbisogno',
    'Storico',
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
        // This reads the local mirror, so a failure here is the device's database, not the network.
        // It used to render `Errore: $e` — a Drift exception, full width, as the entire screen.
        // There is nothing a technician can do about it except back out, so say that.
        error: (e, _) => Column(
          children: [
            _TicketDetailHeader(title: 'Ticket'),
            const Expanded(
              child: SafeArea(
                top: false,
                child: UnavailableState(
                  titolo: 'Ticket non leggibile',
                  motivo:
                      'I dati salvati sul telefono non si aprono. Torna indietro e riprova; se '
                      'continua, sincronizza dalla Dashboard.',
                ),
              ),
            ),
          ],
        ),
        data: (ticket) {
          if (ticket == null) {
            return Column(
              children: [
                _TicketDetailHeader(title: 'Ticket'),
                SafeArea(
                  top: false,
                  child: EmptyState(
                    icon: LucideIcons.xCircle,
                    title: 'Ticket non trovato',
                    body: 'Il ticket richiesto non è disponibile in cache.',
                  ),
                ),
              ],
            );
          }
          return _TicketDetailBody(
            ticket: ticket,
            statusMap: statusMap,
            typeMap: typeMap,
            sectionLabels: _sectionLabels,
            scrollController: _scrollController,
          );
        },
      ),
    );
  }
}

/// The dark CHARCOAL plate every Operational surface (Timbra, the wizards) already carries —
/// Ticket detail was the one screen in that family still wearing the light Browsing header.
/// Local to this file rather than a change to [ScreenHeader] itself: only this screen needed it,
/// and [ScreenHeader]'s `dark` flag already covers the rest (see `new_ticket_form_screen.dart`).
class _TicketDetailHeader extends StatelessWidget {
  const _TicketDetailHeader({required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.CHARCOAL,
      child: SafeArea(
        bottom: false,
        child: ScreenHeader(
          title: title,
          subtitle: subtitle,
          showBack: true,
          dark: true,
          actions: actions,
        ),
      ),
    );
  }
}

class _TicketDetailBody extends ConsumerWidget {
  const _TicketDetailBody({
    required this.ticket,
    required this.statusMap,
    required this.typeMap,
    required this.sectionLabels,
    required this.scrollController,
  });

  final Ticket ticket;
  final Map<int, String> statusMap;
  final Map<int, String> typeMap;
  final List<String> sectionLabels;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusName = statusMap[ticket.statusId] ?? '';
    final typeName = typeMap[ticket.typeId] ?? '';
    final reference = ticketReference(ticket.numero);
    final dateLabel = DateFormat(
      'dd/MM/yyyy HH:mm',
      'it',
    ).format(ticket.createdAt.toLocal());
    final closedLabel = ticket.closedAt != null
        ? DateFormat('dd/MM/yyyy', 'it').format(ticket.closedAt!.toLocal())
        : '—';

    final customerAsync = ref.watch(customerByIdProvider(ticket.customerId));
    final locationAsync = ref.watch(locationByIdProvider(ticket.locationId));

    final customerName =
        customerAsync.valueOrNull?.companyName ?? ticket.customerId;
    final locationName = locationAsync.valueOrNull?.name ?? ticket.locationId;
    // Was the raw `assignedUserId` — a GUID, rendered at a technician as the answer to "who has
    // this job". Resolved from the synced colleagues mirror, so it still reads offline; falls back
    // to the id when the mirror does not know it rather than showing nothing.
    final assignedId = ticket.assignedUserId;
    final tecnicoLabel = assignedId == null
        ? '—'
        : (ref.watch(colleagueNameProvider(assignedId)).valueOrNull ??
              assignedId);

    // Feature audit module #11, Gap D: a technician working this ticket had no way to see the
    // contract it's tied to — contracts are only reachable via the admin-only /altro/contratti
    // route. This is read-only and deliberately small (name here, name/scadenza/condizioni in
    // the sheet it opens) — not a route to a full contract editor.
    final contractId = ticket.contractId;
    final contractAsync = contractId == null
        ? null
        : ref.watch(contractByIdProvider(contractId));
    final contractLabel = contractAsync?.when(
      data: (c) => c?['name'] as String? ?? '—',
      loading: () => 'Caricamento…',
      error: (e, _) => '—',
    );

    // Feature audit module #13, Gap 6: mobile already syncs `Ticket.commessaId` but showed it
    // nowhere. Resolved the same way as the contract row above — live-fetched, no local mirror.
    final commessaId = ticket.commessaId;
    final commessaAsync = commessaId == null
        ? null
        : ref.watch(commessaByIdProvider(commessaId));
    final commessaLabel = commessaAsync?.when(
      data: (c) => c?['codice'] as String? ?? '—',
      loading: () => 'Caricamento…',
      error: (e, _) => '—',
    );

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The job leads; the reference supports it.
          //
          // This was the other way round — `#3f2a1c8e` as the page title, in the largest type on
          // the screen, with the ticket's actual name demoted to the subtitle. The technician
          // arrived at a screen whose headline was eight characters of a GUID and had to read the
          // second line to find out which job they were looking at.
          //
          // Where the ticket has no number the subtitle is simply absent. Nothing is invented and
          // the id never comes back.
          //
          // Ticket is an Operational surface (same family as Timbra and the rapportino/ticket
          // wizards, which already carry the dark CHARCOAL plate) — this used to be the one
          // Operational screen still wearing the light Browsing-surface header. Only the header
          // gets the dark plate; the body below stays light. A long, dense detail page with many
          // KeyVal rows reads better at high contrast outdoors than it would crammed onto a dark
          // ground, and nothing below this line changes — the bottom action stack has twice been
          // squeezed until something under it stopped laying out, so it is not touched here.
          _TicketDetailHeader(
            title: ticket.title,
            subtitle: reference,
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.pencil,
                label: 'Modifica',
                glass: true,
                onTap: () => _openEditTicket(context, ticket),
              ),
              HeaderIconBtn(
                icon: LucideIcons.userCheck,
                label: 'Assegna',
                glass: true,
                onTap: () => _showAssignSheet(context, ref, ticket),
              ),
            ],
          ),

          // Status pill + type chip + the two workflow controls.
          //
          // Both controls live in this existing row on purpose. The bottom action stack already
          // carries four buttons and has twice been squeezed until something below it stopped
          // laying out; this row is already on screen and costs nothing to reuse. It is also where
          // they belong — changing a status is editing the thing the pill displays.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              AppSpacing.md,
            ),
            child: _TicketStatusRow(
              ticket: ticket,
              statusName: statusName,
              typeName: typeName,
            ),
          ),

          Expanded(
            child: CustomScrollView(
              controller: scrollController,
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
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      0,
                      AppSpacing.pagePadding,
                      AppSpacing.md,
                    ),
                    child: _TicketTimerBar(ticketId: ticket.id),
                  ),
                ),

                // Now: just enough to know where you stand. Data, Chiusura, Descrizione and Note
                // tecnico moved into the Dettagli compartment below — they're read once, not on
                // every glance at this ticket, and belonged with the rest of the reference record
                // rather than pinned above it.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      0,
                      AppSpacing.pagePadding,
                      AppSpacing.base,
                    ),
                    child: VetroCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyVal(
                            label: 'Cliente',
                            value: customerName,
                            onTap: () =>
                                context.push(AppRoutes.clientiDetail(ticket.customerId)),
                          ),
                          KeyVal(label: 'Sede', value: locationName),
                          KeyVal(
                            label: 'Tecnico',
                            value: tecnicoLabel,
                            showDivider: contractLabel != null || commessaLabel != null,
                          ),
                          if (contractLabel != null)
                            KeyVal(
                              label: 'Contratto',
                              value: contractLabel,
                              showDivider: commessaLabel != null,
                              onTap: () => _showContractSummarySheet(context, contractId!),
                            ),
                          if (commessaLabel != null)
                            KeyVal(
                              label: 'Commessa',
                              value: commessaLabel,
                              showDivider: false,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // The record — a grid of compartments, not an accordion. Each opens a bottom
                // sheet over the ticket rather than growing the page in place: the ticket's own
                // shape stays constant no matter which section (or how much of it) is open. See
                // _sectionLabels' own doc comment for the fuller reasoning and what this replaced.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      0,
                      AppSpacing.pagePadding,
                      AppSpacing.base,
                    ),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.5,
                      children: [
                        for (final label in sectionLabels)
                          VetroCompartmentTile(
                            icon: _sectionIcon(label),
                            label: label,
                            onTap: () => openCompartmentSheet(
                              context,
                              label: label,
                              content: label == 'Dettagli'
                                  ? _DettagliSheet(
                                      dateLabel: dateLabel,
                                      closedLabel: closedLabel,
                                      description: ticket.description,
                                      technicianNotes: ticket.technicianNotes,
                                    )
                                  : _sectionContent(label, ticket.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: EdgeInsets.only(bottom: context.navClearance),
                ),
              ],
            ),
          ),

          // Bottom actions — one primary, state-driven.
          //
          // Used to be two equal-weight buttons on every ticket regardless of state. An
          // unassigned ticket isn't yours to start work on yet — "Prendi in carico" already leads
          // the status row above, so the bar stays empty rather than repeating that control in a
          // second place. Once assigned, "Crea rapportino" is what a technician does on a ticket
          // (see the status-row comment); "Timbra cantiere" is real and still one tap away, but
          // demoted to a smaller secondary control underneath rather than sharing equal billing.
          if (ticket.assignedUserId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.sm,
                AppSpacing.pagePadding,
                AppSpacing.base,
              ),
              child: Column(
                children: [
                  VetroButton(
                    label: 'Crea rapportino',
                    onPressed: () => _createRapportino(context, ref, ticket),
                  ),
                  const SizedBox(height: 8),
                  // compact for the smaller type/padding "demoted" look the comment above calls
                  // for, wrapped to force full width — VetroButton's compact flag is otherwise
                  // never full-width (it's tuned for inline controls like a timer bar's buttons).
                  SizedBox(
                    width: double.infinity,
                    child: VetroButton(
                      label: 'Timbra cantiere',
                      icon: const Icon(LucideIcons.mapPin),
                      compact: true,
                      secondary: true,
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
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Future<void> _createRapportino(
    BuildContext context,
    WidgetRef ref,
    Ticket ticket,
  ) async {
    final id = await createLocalDraft(
      ref,
      title: 'Rapportino — ${ticket.title}',
      locationId: ticket.locationId,
      ticketId: ticket.id,
      customerId: ticket.customerId,
      // The ticket's own tenant, rather than whatever row the mirror lookup finds first.
      tenantId: ticket.tenantId,
    );
    if (!context.mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accedi per creare un rapportino.')),
      );
      return;
    }
    context.push(AppRoutes.rapportiniEditor(id));
  }

  /// Pushed rather than a sheet: [EditTicketScreen] reuses the create-wizard's own step widgets
  /// (StepClienteSede / StepDettagliTicket), which are built to fill a page, not to sit inside a
  /// DraggableScrollableSheet the way the compartment tabs do.
  void _openEditTicket(BuildContext context, Ticket ticket) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditTicketScreen(ticketId: ticket.id)));
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

  /// Feature audit module #11, Gap D — read-only contract summary, opened from the "Contratto"
  /// row above. Deliberately just a sheet, not a route: the contract editor itself stays behind
  /// the admin-only /altro/contratti path, and this technician-facing surface only needs to
  /// answer "what contract is this ticket under, and when/on what terms".
  void _showContractSummarySheet(BuildContext context, String contractId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ContractSummarySheet(contractId: contractId),
    );
  }
}

/// Read-only Nome/Scadenza/Condizioni for the contract a ticket is tied to. See
/// [_TicketDetailBody._showContractSummarySheet]'s doc comment for why this is a sheet and not a
/// route into the admin contract editor.
class _ContractSummarySheet extends ConsumerWidget {
  const _ContractSummarySheet({required this.contractId});

  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contractByIdProvider(contractId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.base,
          AppSpacing.pagePadding,
          AppSpacing.base,
        ),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => const UnavailableState(
            titolo: 'Contratto non disponibile',
            motivo: 'Impossibile leggere i dati del contratto. Riprova quando torni online.',
          ),
          data: (contract) {
            if (contract == null) {
              return const EmptyState(
                icon: LucideIcons.fileText,
                title: 'Contratto non trovato',
                body: 'Il contratto collegato non è disponibile.',
              );
            }
            final name = contract['name'] as String? ?? '—';
            final endDate = contract['endDate'] as String?;
            final scadenzaLabel = endDate != null
                ? DateFormat('dd/MM/yyyy', 'it').format(DateTime.parse(endDate))
                : 'Nessuna data fine';
            final condizioni = contract['condizioni'] as String?;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StepLabel(title: 'Contratto'),
                const SizedBox(height: 4),
                KeyVal(label: 'Nome', value: name),
                KeyVal(label: 'Scadenza', value: scadenzaLabel),
                KeyVal(
                  label: 'Condizioni',
                  value: condizioni != null && condizioni.isNotEmpty ? condizioni : '—',
                  showDivider: false,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A titled paragraph inside the ticket's fact card.
///
/// Uses [StepLabel], the in-card heading, rather than [SectionTitle], the page-level one that was
/// nested here before — 18px with its own 20/19/10 padding, inside a card that already pads.
class _Prose extends StatelessWidget {
  const _Prose({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepLabel(title: title),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: context.colors.ink,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a compartment's label to its content widget. A switch on the label, not an index, so the
/// tile grid and its content can never drift apart by position — the label in `_sectionLabels` is
/// also the key here. 'Dettagli' isn't here: it needs ticket fields already resolved by
/// `_TicketDetailBody`, not a ticketId-keyed provider, so its call site builds `_DettagliSheet`
/// directly instead of routing through this switch.
Widget _sectionContent(String label, String ticketId) => switch (label) {
  'Report' => _ReportTab(ticketId: ticketId),
  'Controllo' => _ControlloTab(ticketId: ticketId),
  'Allegati' => _AllegatiTab(ticketId: ticketId),
  'Ore' => _OreTab(ticketId: ticketId),
  'Pianificazioni' => _PianificazioniTab(ticketId: ticketId),
  'Fabbisogno' => _FabbisognoTab(ticketId: ticketId),
  'Storico' => _StoricoTab(ticketId: ticketId),
  _ => const SizedBox.shrink(),
};

/// Icon for a compartment tile. A switch on the same label set as [_sectionContent], kept
/// separate because the grid needs it before a tile is ever tapped (unlike the content, which is
/// built lazily on tap).
IconData _sectionIcon(String label) => switch (label) {
  'Dettagli' => LucideIcons.clipboardList,
  'Report' => LucideIcons.fileText,
  'Controllo' => LucideIcons.clipboardCheck,
  'Allegati' => LucideIcons.paperclip,
  'Ore' => LucideIcons.clock,
  'Pianificazioni' => LucideIcons.calendarDays,
  'Fabbisogno' => LucideIcons.package,
  'Storico' => LucideIcons.history,
  _ => LucideIcons.circle,
};

/// The Dettagli compartment: what used to sit above the fold on every ticket, now read on demand.
class _DettagliSheet extends StatelessWidget {
  const _DettagliSheet({
    required this.dateLabel,
    required this.closedLabel,
    required this.description,
    required this.technicianNotes,
  });

  final String dateLabel;
  final String closedLabel;
  final String? description;
  final String? technicianNotes;

  @override
  Widget build(BuildContext context) {
    final hasDescription = description?.isNotEmpty ?? false;
    final hasNotes = technicianNotes?.isNotEmpty ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyVal(label: 'Data', value: dateLabel),
          KeyVal(
            label: 'Chiusura',
            value: closedLabel,
            showDivider: hasDescription || hasNotes,
          ),
          if (hasDescription) _Prose(title: 'Descrizione', body: description!),
          if (hasNotes) _Prose(title: 'Note tecnico', body: technicianNotes!),
        ],
      ),
    );
  }
}

/// Centered spinner used by every fetch-on-demand tab while loading.
class _TabLoading extends StatelessWidget {
  const _TabLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        0,
        AppSpacing.pagePadding,
        0,
      ),
      child: offline
          ? UnavailableState(
              icon: LucideIcons.wifiOff,
              titolo: offlineTitle,
              motivo: offlineBody,
            )
          : UnavailableState(icon: icon, titolo: errorTitle, motivo: errorBody),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatQty(double qty) => qty == qty.truncateToDouble()
    ? qty.toStringAsFixed(0)
    : qty.toStringAsFixed(1);

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
        errorBody:
            'Si è verificato un errore durante il caricamento. Riprova più tardi.',
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.md,
            AppSpacing.pagePadding,
            0,
          ),
          child: Column(
            children: reports.map((r) {
              final dateLabel = DateFormat(
                'dd/MM/yyyy HH:mm',
                'it',
              ).format(r.createdAt.toLocal());
              return ListRow(
                leading: Icon(
                  LucideIcons.fileText,
                  size: 20,
                  color: context.colors.inkMuted,
                ),
                title: r.title.isNotEmpty ? r.title : 'Rapportino',
                subtitle: dateLabel,
                meta: StatusPill(stato: r.statoLabel, small: true, outlined: true),
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
        errorBody:
            'Si è verificato un errore durante il caricamento. Riprova più tardi.',
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.md,
            AppSpacing.pagePadding,
            0,
          ),
          child: Column(
            children: flat
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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

    return VetroCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: 10,
      ),
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
                    style: TextStyle(
                      color: context.colors.inkMuted,
                      fontSize: 11,
                    ),
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
                      style: TextStyle(
                        color: context.colors.inkMuted,
                        fontSize: 12,
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
    final pending = ref.watch(pendingTicketAttachmentsProvider(ticketId)).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Always offered, regardless of whether the server list loaded, errored, or says
        // offline: a technician on site with no signal is exactly who most needs to be able to
        // capture a photo now rather than be told to come back later.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.md,
            AppSpacing.pagePadding,
            0,
          ),
          child: _AttachmentUploadButtons(ticketId: ticketId),
        ),
        if (pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.base,
              AppSpacing.pagePadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In sospeso (${pending.length})',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                for (final a in pending) ...[
                  _PendingAttachmentRow(attachment: a),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        attachmentsAsync.when(
          loading: () => const _TabLoading(),
          error: (e, _) => _TabError(
            icon: LucideIcons.paperclip,
            offline: e is TicketDetailOfflineException,
            offlineTitle: 'Allegati non disponibili offline',
            offlineBody:
                'Gli allegati già caricati su questo ticket richiedono una connessione per '
                'essere elencati: riprova quando torni online.',
            errorTitle: 'Impossibile caricare gli allegati',
            errorBody:
                'Si è verificato un errore durante il caricamento. Riprova più tardi.',
          ),
          data: (attachments) {
            if (attachments.isEmpty) {
              // Never claims there really is nothing when a pending upload is sitting above —
              // the empty state is about the server-confirmed list only.
              return pending.isNotEmpty
                  ? const SizedBox.shrink()
                  : const _EmptyTab(
                      icon: LucideIcons.paperclip,
                      label: 'Nessun allegato',
                      body: 'Non ci sono allegati caricati per questo ticket.',
                    );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.base,
                AppSpacing.pagePadding,
                0,
              ),
              child: Column(
                children: attachments.map((a) {
                  final dateLabel = DateFormat(
                    'dd/MM/yyyy HH:mm',
                    'it',
                  ).format(a.createdAt.toLocal());
                  return ListRow(
                    leading: Icon(
                      LucideIcons.paperclip,
                      size: 20,
                      color: context.colors.inkMuted,
                    ),
                    title: a.fileName,
                    subtitle: '${_formatBytes(a.sizeBytes)} · $dateLabel',
                    showDivider: a != attachments.last,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Galleria / Fotocamera — picks a photo and hands it to [TicketAttachmentUploadQueue].
///
/// Mirrors StepMaterialiFold's `_pickImage` (the rapportino's established photo-capture pattern):
/// same package (`image_picker`), same `imageQuality: 80`, same "one honest sentence" failure
/// message for a local capture/read error. What differs is what happens to the file afterwards —
/// a rapportino photo is folded into the draft and uploaded when the whole rapportino submits;
/// here there is no parent draft, so the queue uploads (or offline-queues) it immediately.
class _AttachmentUploadButtons extends ConsumerStatefulWidget {
  const _AttachmentUploadButtons({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_AttachmentUploadButtons> createState() => _AttachmentUploadButtonsState();
}

class _AttachmentUploadButtonsState extends ConsumerState<_AttachmentUploadButtons> {
  bool _busy = false;

  Future<void> _pickImage(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: source, imageQuality: 80);
      if (xfile == null) return;

      final file = File(xfile.path);
      final bytes = await file.readAsBytes();

      // Rejected client-side, before it is ever queued or sent: a rejection after the file sat
      // in the offline outbox for a while would read as a delayed, unexplained failure.
      if (bytes.length > kMaxTicketAttachmentBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'File troppo grande: il limite per gli allegati è 10 MB. Scegline uno più piccolo.',
            ),
            backgroundColor: context.colors.red,
          ),
        );
        return;
      }

      final isOnline = ref.read(isOnlineProvider);
      final outcome = await ref
          .read(ticketAttachmentUploadQueueProvider)
          .upload(
            ticketId: widget.ticketId,
            localPath: xfile.path,
            fileName: xfile.name,
            contentType: 'image/jpeg',
            sizeBytes: bytes.length,
            isOnline: isOnline,
          );

      if (!mounted) return;
      if (outcome.isQueuedOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Sei offline: la foto è stata salvata e verrà caricata automaticamente alla '
              'riconnessione.',
            ),
            backgroundColor: context.colors.amber,
          ),
        );
      } else if (outcome.isSubmitted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allegato caricato')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(outcome.error ?? 'Caricamento non riuscito.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    } catch (e) {
      // Local capture and file read — never a server call, so there is no status to interpret.
      // Mirrors StepMaterialiFold's own _pickImage catch for exactly this reason.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Foto non salvata. Riprova, e controlla lo spazio libero sul telefono.',
            ),
            backgroundColor: context.colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(LucideIcons.image),
            label: const Text('Galleria'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.camera),
            label: const Text('Fotocamera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: context.colors.brandOn,
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

/// One not-yet-confirmed attachment — offline, uploading, or failed. Mirrors
/// `_PendingTicketRow` on the ticket list (same three-state read, same colours), the established
/// pattern for "something local hasn't reached the server yet" in this app.
class _PendingAttachmentRow extends ConsumerWidget {
  const _PendingAttachmentRow({required this.attachment});

  final PendingTicketAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = PendingTicketAttachmentState.fromString(attachment.state);
    final isFailed = state == PendingTicketAttachmentState.failed;

    final String subtitle = switch (state) {
      PendingTicketAttachmentState.pendingSync =>
        'In attesa di connessione — verrà caricato automaticamente',
      PendingTicketAttachmentState.submitting => 'Caricamento…',
      PendingTicketAttachmentState.failed =>
        'Caricamento non riuscito: ${attachment.error ?? 'errore sconosciuto'}',
      PendingTicketAttachmentState.submitted => 'Caricato',
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
                  attachment.fileName,
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
                  style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
                ),
              ],
            ),
          ),
          if (isFailed)
            TextButton(
              onPressed: () =>
                  ref.read(ticketAttachmentUploadQueueProvider).retry(attachment.id),
              child: const Text('Riprova'),
            ),
        ],
      ),
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
        errorBody:
            'Si è verificato un errore durante il caricamento. Riprova più tardi.',
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.md,
            AppSpacing.pagePadding,
            0,
          ),
          child: Column(
            children: materiali.map((m) {
              final qtyLabel = m.unitaMisura != null
                  ? '${_formatQty(m.quantita)} ${m.unitaMisura}'
                  : _formatQty(m.quantita);
              return ListRow(
                leading: Icon(
                  LucideIcons.package,
                  size: 20,
                  color: m.disponibile
                      ? context.colors.inkMuted
                      : context.colors.red,
                ),
                title: m.nome,
                subtitle: m.codice != null
                    ? '${m.codice} · $qtyLabel'
                    : qtyLabel,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        0,
        AppSpacing.pagePadding,
        0,
      ),
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
          padding: EdgeInsets.all(AppSpacing.xxl),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.md,
                AppSpacing.pagePadding,
                0,
              ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assegnazione aggiornata')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile salvare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
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
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
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
            AppFieldShell(
              label: 'Tecnico',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedUserId,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Non assegnato'),
                  ),
                  ..._technicians.map(
                    (t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text(
                        t['displayName'] as String? ??
                            t['email'] as String? ??
                            '',
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedUserId = v),
              ),
            ),
          const SizedBox(height: 16),
          VetroButton(
            label: _isSaving ? 'Salvataggio…' : 'Salva',
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _save,
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
/// The bar shows a pulsing green [LiveDot] when a clock is running — the same equipment-lamp mark
/// the dashboard's active-tracker strip uses, not the accent strap (that means selected/priority,
/// not live; see LiveDot's own doc comment). A technician who has left a timer going overnight
/// should see the same signal wherever they land.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: context.colors.red),
      );
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
      return VetroCard(
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

    return VetroCard(
      child: Row(
        children: [
          if (isRunning) ...[const LiveDot(), const SizedBox(width: 10)],
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
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            VetroButton(
              label: isRunning ? 'Ferma' : 'Avvia',
              compact: true,
              // Same stop-red/tint split as TimbraScreen's punch button — "ending" a running
              // clock reuses that colour, not a fresh red.
              gradientColors: isRunning
                  ? const [AppColors.stopLight, AppColors.stopDark]
                  : null,
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
  const _TicketStatusRow({
    required this.ticket,
    required this.statusName,
    required this.typeName,
  });

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
      await ref
          .read(ticketWorkflowApiClientProvider)
          .selfAssign(widget.ticket.id);
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
      await (db.update(
        db.tickets,
      )..where((t) => t.id.equals(widget.ticket.id))).write(
        TicketsCompanion(
          statusId: Value(statusId),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRack.cellRadius),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.base,
                AppSpacing.pagePadding,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cambia stato',
                      style: TextStyle(
                        fontFamily: 'Inter',
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
                  StatusPill(stato: widget.statusName, outlined: true),
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
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (unassigned)
          VetroButton(label: 'Prendi in carico', compact: true, onPressed: _selfAssign),
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
        errorBody:
            'Si è verificato un errore durante il caricamento. Riprova più tardi.',
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const _EmptyTab(
            icon: LucideIcons.clock,
            label: 'Nessuna ora registrata',
            body:
                'Avvia il timer o aggiungi le ore manualmente per registrarle su questo ticket.',
          );
        }

        // Only closed entries contribute. A running one has no duration yet, and counting it as
        // zero would quietly understate the total on exactly the ticket being worked.
        final closed = entries.where((e) => !e.isRunning);
        final total = closed.fold<Duration>(
          Duration.zero,
          (a, e) => a + e.duration!,
        );
        final running = entries.where((e) => e.isRunning).length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.md,
            AppSpacing.pagePadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VetroCard(
                child: Row(
                  children: [
                    if (running > 0) ...[const LiveDot(), const SizedBox(width: 8)],
                    Expanded(
                      child: Text(
                        'Totale registrato',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.inkMuted,
                        ),
                      ),
                    ),
                    Text(
                      _hhmm(total),
                      style: TextStyle(
                        fontFamily: 'Inter',
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
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: context.colors.inkMuted,
                    ),
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
    final dateLabel = DateFormat(
      'EEE d MMM',
      'it',
    ).format(entry.workDate.toLocal());
    final span = entry.endTime == null
        ? '${_hhmm(entry.startTime)} → in corso'
        : '${_hhmm(entry.startTime)} – ${_hhmm(entry.endTime!)}';

    return ListRow(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.isRunning) ...[const LiveDot(), const SizedBox(width: 6)],
          Icon(
            entry.isManualEntry ? LucideIcons.pencil : LucideIcons.timer,
            size: 20,
            color: entry.isRunning ? c.ink : c.inkMuted,
          ),
        ],
      ),
      title: dateLabel,
      subtitle: [
        span,
        if (entry.isManualEntry) 'inserimento manuale',
        if (entry.description != null && entry.description!.isNotEmpty)
          entry.description!,
      ].join(' · '),
      meta: Text(
        // An open entry shows a dash, not 0:00 — the same refusal to draw a stopped-looking clock
        // that the dashboard hero and TicketWorkLogDto.duration both make.
        entry.duration == null ? '—' : _hhmm(entry.duration!),
        style: TextStyle(
          fontFamily: 'Inter',
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
        errorBody:
            'Si è verificato un errore durante il caricamento. Riprova più tardi.',
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.md,
            AppSpacing.pagePadding,
            0,
          ),
          child: Column(
            children: [
              for (final e in entries)
                ListRow(
                  leading: Icon(
                    LucideIcons.history,
                    size: 20,
                    color: context.colors.inkMuted,
                  ),
                  title: _fieldLabel(e.fieldName),
                  subtitle: _change(e, statusMap, typeMap),
                  meta: Text(
                    DateFormat(
                      'dd/MM HH:mm',
                      'it',
                    ).format(e.changedAt.toLocal()),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.inkMuted,
                    ),
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
