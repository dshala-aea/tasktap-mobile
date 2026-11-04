// dart format width=100
// lib/features/cantiere/cantiere_detail_screen.dart
//
// Cantiere info + the "Timbra cantiere" action (relocated from ticket detail — see this app's
// nav-restructure spec) + tickets linked to this cantiere. Reached from CantieriListScreen (no
// ticketId) or from a ticket's cantiere chip (ticketId set, carried through to the Timbra action
// so the resulting session still gets tagged the way it did when the button lived on the ticket).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/time/business_time.dart' show formatWorkDate;
import '../../core/utils/error_message.dart';
import '../../core/utils/maps_launcher.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/connectivity_provider.dart' show isOnlineProvider;
import '../../data/sync/sync_freshness_provider.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../rapportino/create_draft.dart';
import '../ticket/ticket_providers.dart' show commessaByIdProvider, ticketStatusMapProvider;
import '../timbra/cantiere_timbra_screen.dart'
    show
        cantiereActiveSessionProvider,
        cantiereCrewAssignmentsProvider,
        cantiereTodayHoursProvider,
        formatHoursMinutes,
        isLeadForCantiereProvider;
import 'cantiere_close_sheet.dart';
import 'cantiere_day.dart';
import 'cantiere_design.dart';
import 'cantiere_providers.dart';

class CantiereDetailScreen extends ConsumerStatefulWidget {
  const CantiereDetailScreen({super.key, required this.cantiereId, this.ticketId});

  final String cantiereId;

  /// Carried through from a ticket's cantiere chip, when reached that way — see this file's own
  /// header comment. Null when reached from the Cantieri tab directly.
  final String? ticketId;

  @override
  ConsumerState<CantiereDetailScreen> createState() => _CantiereDetailScreenState();
}

class _CantiereDetailScreenState extends ConsumerState<CantiereDetailScreen> {
  // Guards "Crea rapportino" against a double-tap: the button awaits a real network round-trip
  // (POST /api/reports/from-cantiere-worklogs), and on a slow connection — which this app is
  // explicitly built for — a second tap during that window would fire the create call again. The
  // first call already consumed this cantiere's unconsumed worklogs, so the second would create a
  // second, empty backend Report (burning a document number), a second local draft, and a double
  // navigation push. Same pattern as CantiereTimbraScreen's own `_isLoading` guard.
  bool _isCreatingRapportino = false;

  /// Anchor for the hero's "Dettagli" action: scrolls the page to the Dossier.
  final GlobalKey _dossierKey = GlobalKey();

  static String _statusLabel(int status) {
    switch (status) {
      case 0:
        return 'Attivo';
      case 1:
        return 'Completato';
      case 2:
        return 'Annullato';
      default:
        return '—';
    }
  }

  void _scrollToDossier() {
    final ctx = _dossierKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cantiereAsync = ref.watch(cantiereByIdProvider(widget.cantiereId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DetailAppBar(),
            Expanded(
              // Same RefreshIndicator+performSync() pattern as cantieri_list_screen.dart one level
              // up. Every branch below gets a real Scrollable (a RefreshIndicator only fires over
              // one).
              child: RefreshIndicator(
                onRefresh: () => refreshWithFeedback(context, ref),
                child: cantiereAsync.when(
                  loading: () => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.xxxl),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ],
                  ),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      UnavailableState(
                        icon: LucideIcons.hardHat,
                        titolo: 'Impossibile caricare il cantiere',
                        motivo: 'Trascina in basso per aggiornare, oppure riprova tra poco.',
                        action: AppButton(
                          label: 'Riprova',
                          size: AppButtonSize.sm,
                          fullWidth: false,
                          onPressed: () => ref.invalidate(cantiereByIdProvider(widget.cantiereId)),
                        ),
                      ),
                    ],
                  ),
                  data: (cantiere) {
                    if (cantiere == null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          UnavailableState(
                            icon: LucideIcons.hardHat,
                            titolo: 'Cantiere non trovato',
                            motivo: 'Non risulta sincronizzato su questo dispositivo.',
                          ),
                        ],
                      );
                    }

                    final address = [
                      cantiere.address,
                      cantiere.city,
                      cantiere.postalCode,
                    ].where((s) => s != null && s.isNotEmpty).join(', ');

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TitleBlock(cantiere: cantiere, address: address),
                          _SiteStateCard(
                            cantiere: cantiere,
                            ticketId: widget.ticketId,
                            isCreatingRapportino: _isCreatingRapportino,
                            onCreateRapportino: () => _handleCreateRapportino(cantiere),
                            onDetails: _hasDossier(cantiere) ? _scrollToDossier : null,
                          ),
                          CantiereDayLedger(cantiereId: cantiere.id),
                          _SquadraSection(cantiereId: cantiere.id),
                          _TicketsSection(cantiereId: cantiere.id),
                          KeyedSubtree(
                            key: _dossierKey,
                            child: _DettagliSection(cantiere: cantiere),
                          ),
                          // After the dossier: "what I have worked here", readable with no
                          // signal. Not in the mockup; kept because it is the only place a past
                          // shift is visible offline.
                          _TimbratureSection(cantiereId: cantiere.id),
                          // Only when there's an address worth plotting.
                          if (address.isNotEmpty) _MapSection(cantiere: cantiere, address: address),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Crea rapportino" — calls `POST /api/reports/from-cantiere-worklogs` and opens the ordinary
  /// rapportino editor on the resulting draft. See [createCantiereReportDraft] for the full
  /// create-then-hydrate flow and why the local draft reuses the backend-issued report id.
  Future<void> _handleCreateRapportino(CantieriData cantiere) async {
    if (_isCreatingRapportino) return; // Belt-and-suspenders alongside the disabled button.
    setState(() => _isCreatingRapportino = true);

    final address = [
      cantiere.address,
      cantiere.city,
      cantiere.postalCode,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    String? id;
    try {
      id = await createCantiereReportDraft(
        ref,
        cantiereId: cantiere.id,
        cantiereName: cantiere.name,
        customerId: cantiere.customerId,
        tenantId: cantiere.tenantId,
        workAddress: address.isEmpty ? null : address,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingRapportino = false);
        showAppToast(
          context,
          message: humanErrorMessage(e, azione: 'creare il rapporto di intervento'),
          tone: ToastTone.error,
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isCreatingRapportino = false);

    if (id == null) {
      showAppToast(
        context,
        message: 'Accedi per creare un rapporto di intervento.',
        tone: ToastTone.warning,
      );
      return;
    }
    context.push(AppRoutes.rapportiniEditor(id));
  }
}

bool _hasDossier(CantieriData c) =>
    c.customerId != null ||
    c.commessaId != null ||
    c.startDate != null ||
    c.endDate != null ||
    (c.notes != null && c.notes!.isNotEmpty);

// ══════════════════════════════════════════════════════════════════════════════
// App bar — back, "Cantiere" in display 18/600, the overflow dots. 50px, no rule.
// ══════════════════════════════════════════════════════════════════════════════

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Indietro',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(LucideIcons.chevronLeft, size: 22, color: context.colors.ink),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Cantiere', style: cantiereDisplay(context, 18))),
            Text('···', style: TextStyle(color: context.colors.inkMuted, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Kicker, title and sub line.
// ══════════════════════════════════════════════════════════════════════════════

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.cantiere, required this.address});

  final CantieriData cantiere;
  final String address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerId = cantiere.customerId;
    final customer = customerId == null
        ? null
        : ref.watch(customerByIdProvider(customerId)).valueOrNull?.companyName;
    final sub = [
      if (customer != null && customer.isNotEmpty) 'Cliente $customer',
      if (address.isNotEmpty) address,
    ].join(' · ');
    final kicker = cantiereMono(context, 9, letterSpacing: 0.9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              // The mockup's reference code (C-2026-018) has no source on the Cantieri mirror, so
              // the red ref is the word alone rather than an invented number.
              Text('CANTIERE', style: kicker.copyWith(color: context.colors.accentInk)),
              const SizedBox(width: 8),
              Text('·', style: kicker),
              const SizedBox(width: 8),
              Text('OGGI', style: kicker),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            cantiere.name,
            style: cantiereDisplay(
              context,
              29,
              weight: FontWeight.w700,
              letterSpacing: -0.725,
              height: 1,
            ),
          ),
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            style: cantiereBody(context, 11.5, color: context.colors.inkMuted, height: 1.4),
          ),
        if (cantiere.status != 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: CantiereStamp(
              label: _CantiereDetailScreenState._statusLabel(cantiere.status),
              color: context.colors.inkMuted,
            ),
          ),
        ],
        const SizedBox(height: 13),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Hero — one card answers "am I on site", "how long today", and offers the single next action.
// A live timer is mounted only for an open session.
// ══════════════════════════════════════════════════════════════════════════════

class _SiteStateCard extends ConsumerWidget {
  const _SiteStateCard({
    required this.cantiere,
    this.ticketId,
    required this.isCreatingRapportino,
    required this.onCreateRapportino,
    this.onDetails,
  });

  final CantieriData cantiere;
  final String? ticketId;
  final bool isCreatingRapportino;
  final VoidCallback onCreateRapportino;
  final VoidCallback? onDetails;

  static String _hm(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(cantiereActiveSessionProvider);
    final activeHere = active?.cantiereId == cantiere.id;
    final activeElsewhere = active != null && !activeHere;
    final today = ref.watch(cantiereTodayHoursProvider(cantiere.id));
    final closed = cantiere.status != 0;
    final crewCount = ref.watch(cantiereCrewAssignmentsProvider(cantiere.id)).valueOrNull?.length;
    final crewTail = crewCount != null && crewCount > 0 ? ' · squadra di $crewCount' : '';

    return CantiereCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(activeHere ? 'IN CANTIERE' : 'OGGI', style: cantiereMini(context)),
                if (activeHere)
                  CantiereLiveElapsed(
                    start: active!.startTime,
                    clock: true,
                    style: cantiereTimer(context),
                  )
                else
                  Text(
                    formatHoursMinutes(today),
                    style: cantiereTimer(context).copyWith(color: context.colors.ink),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: activeHere
                ? CantiereHeroCopy(
                    before: 'Ingresso alle ',
                    bold: _hm(active!.startTime),
                    after: crewTail,
                  )
                : CantiereHeroCopy(
                    before: today > Duration.zero
                        ? 'Ore lavorate oggi su questo cantiere'
                        : 'Nessuna timbratura oggi',
                  ),
          ),
          if (activeElsewhere)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CantiereHeroCopy(
                before:
                    'Sei già in cantiere su un altro sito. Chiudi quella sessione prima di timbrare qui.',
              ),
            ),
          if (closed)
            const CantiereHeroCopy(before: 'Cantiere chiuso: non è possibile timbrare.')
          else if (activeHere)
            CantiereButton(
              label: 'Timbra uscita',
              onPressed: () => showCantiereCloseSheet(
                context,
                cantiereId: cantiere.id,
                cantiereName: cantiere.name,
                startTime: active!.startTime,
              ),
            )
          else
            CantiereButton(
              label: 'Timbra cantiere',
              onPressed: activeElsewhere
                  ? null
                  : () => context.push(
                      AppRoutes.cantiereTimbraPath(cantiereId: cantiere.id, ticketId: ticketId),
                    ),
            ),
          Padding(
            padding: EdgeInsets.only(top: closed ? 12 : 8),
            child: Row(
              children: [
                Expanded(
                  child: CantiereButton(
                    label: 'Crea rapportino',
                    kind: CantiereButtonKind.secondary,
                    compact: true,
                    loading: isCreatingRapportino,
                    onPressed: onCreateRapportino,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CantiereButton(
                    label: 'Dettagli',
                    kind: CantiereButtonKind.ghost,
                    compact: true,
                    onPressed: onDetails,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Squadra — read-only crew from `cantiereCrewAssignmentsProvider` (online API, Drift mirror
// offline). Loading/error collapse to nothing (an error is "unavailable", never "no crew"); an
// empty answer says "not downloaded yet" on a never-synced offline phone and "none" otherwise.
// The red "Scansiona" link is lead-only, as the badge scanner's own entry is.
// ══════════════════════════════════════════════════════════════════════════════

class _SquadraSection extends ConsumerWidget {
  const _SquadraSection({required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(cantiereCrewAssignmentsProvider(cantiereId));
    // Offline plus a mirror that has never been filled is "we don't know", not "nobody".
    final crewUnknown =
        !ref.watch(isOnlineProvider) &&
        ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
    final isLead = ref.watch(isLeadForCantiereProvider(cantiereId));

    return assignmentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (assignments) {
        return CantiereSection(
          title: 'Squadra',
          note: isLead ? 'Scansiona' : null,
          onNoteTap: isLead
              ? () => context.push(AppRoutes.cantiereBadgeScanPath(cantiereId))
              : null,
          child: assignments.isEmpty
              ? CantiereCard(
                  child: Text(
                    crewUnknown ? 'Squadra non ancora scaricata' : 'Nessuna squadra assegnata',
                    style: cantiereBody(context, 11, color: context.colors.inkMuted),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in assignments)
                      _CrewChip(
                        // Same fallback as everywhere colleagueNameProvider is read: the raw id
                        // rather than nothing when the mirror doesn't (yet) know them.
                        name: ref.watch(colleagueNameProvider(a.userId)).valueOrNull ?? a.userId,
                        isLead: a.isLead,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _CrewChip extends StatelessWidget {
  const _CrewChip({required this.name, required this.isLead});

  final String name;
  final bool isLead;

  static String _initials(String name) {
    final parts = name.split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: c.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: c.bg3, shape: BoxShape.circle),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Text(
                    _initials(name),
                    style: cantiereDisplay(context, 10, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(child: Text(name, style: cantiereBody(context, 10.5))),
            if (isLead) ...[const SizedBox(width: 7), const CantiereMiniStamp(label: 'LEAD')],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Ticket collegati — `ticketsForCantiereProvider`, rows of 11px text with the status in mono 8
// and 1px rules above and below.
// ══════════════════════════════════════════════════════════════════════════════

class _TicketsSection extends ConsumerWidget {
  const _TicketsSection({required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsForCantiereProvider(cantiereId));
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? const <int, String>{};

    return CantiereSection(
      title: 'Ticket collegati',
      child: ticketsAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => UnavailableState(
          icon: LucideIcons.ticket,
          titolo: 'Impossibile caricare i ticket collegati',
          motivo: 'Trascina in basso per aggiornare, oppure riprova tra poco.',
          action: AppButton(
            label: 'Riprova',
            size: AppButtonSize.sm,
            fullWidth: false,
            onPressed: () => ref.invalidate(ticketsForCantiereProvider(cantiereId)),
          ),
        ),
        data: (tickets) {
          if (tickets.isEmpty) {
            return CantiereCard(
              child: Text(
                'Nessun ticket collegato',
                style: cantiereBody(context, 11, color: context.colors.inkMuted),
              ),
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.colors.divider)),
            ),
            child: Column(
              children: [
                for (final t in tickets)
                  _TicketRow(
                    title: t.title,
                    status: statusMap[t.statusId],
                    onTap: () => context.push(AppRoutes.ticketDetailPath(t.id)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.title, required this.status, required this.onTap});

  final String title;
  final String? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cantiereBody(context, 11),
                ),
              ),
              if (status != null && status!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(status!.toUpperCase(), style: cantiereMono(context, 8)),
              ],
              const SizedBox(width: 8),
              Text('›', style: cantiereBody(context, 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Dossier — Cliente / Commessa / Periodo (+ Note) as a bordered two-column facts grid. Every
// field is already in the local Cantieri mirror; each cell is skipped independently, and the whole
// section collapses when none is present.
// ══════════════════════════════════════════════════════════════════════════════

class _DettagliSection extends ConsumerWidget {
  const _DettagliSection({required this.cantiere});

  final CantieriData cantiere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hasDossier(cantiere)) return const SizedBox.shrink();
    final hasNotes = cantiere.notes != null && cantiere.notes!.isNotEmpty;

    // Both resolve from what the phone already has. `error`/`null` fall back to '—': the commessa
    // lookup throws TicketDetailOfflineException when neither the server nor the mirror can
    // answer, which must read the same as "not resolved yet", not as a broken cell.
    final customerId = cantiere.customerId;
    final customerAsync = customerId == null ? null : ref.watch(customerByIdProvider(customerId));
    final customerLabel = customerAsync?.when(
      data: (c) => c?.companyName,
      loading: () => 'Caricamento…',
      error: (e, _) => null,
    );

    final commessaId = cantiere.commessaId;
    final commessaAsync = commessaId == null ? null : ref.watch(commessaByIdProvider(commessaId));
    final commessaLabel = commessaAsync?.when(
      data: (c) => c?['codice'] as String?,
      loading: () => 'Caricamento…',
      error: (e, _) => null,
    );

    String? periodoLabel;
    final start = cantiere.startDate;
    final end = cantiere.endDate;
    final dm = DateFormat('dd/MM');
    if (start != null && end != null) {
      periodoLabel = '${dm.format(start.toLocal())} – ${dm.format(end.toLocal())}';
    } else if (start != null) {
      periodoLabel = 'Dal ${dm.format(start.toLocal())}';
    } else if (end != null) {
      periodoLabel = 'Fino al ${dm.format(end.toLocal())}';
    }

    final cells = <({String label, String value})>[
      if (customerId != null) (label: 'Cliente', value: customerLabel ?? '—'),
      if (commessaId != null) (label: 'Commessa', value: commessaLabel ?? '—'),
      if (periodoLabel != null) (label: 'Periodo', value: periodoLabel),
    ];

    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      final left = cells[i];
      final right = i + 1 < cells.length ? cells[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Fact(label: left.label, value: left.value),
              ),
              SizedBox(width: 1, child: ColoredBox(color: c.divider)),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _Fact(label: right.label, value: right.value),
              ),
            ],
          ),
        ),
      );
    }
    if (hasNotes) rows.add(_Fact(label: 'Note', value: cantiere.notes!, wrap: true));

    return CantiereSection(
      title: 'Dossier',
      note: '${cells.length + (hasNotes ? 1 : 0)} campi',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: c.borderLight),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[if (i > 0) const CantiereRule(), rows[i]],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.wrap = false});

  final String label;
  final String value;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(label.toUpperCase(), style: cantiereMono(context, 8, letterSpacing: 0.64)),
          ),
          Text(
            value,
            maxLines: wrap ? null : 1,
            overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
            style: cantiereBody(context, 11.5, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Le tue timbrature — the signed-in technician's own shifts on this site, from the
// `cantiere_work_logs` mirror (so a shift worked yesterday is visible today, offline or not).
// Loading/error collapse to nothing; empty says "not downloaded yet" only when that can't be
// trusted.
// ══════════════════════════════════════════════════════════════════════════════

class _TimbratureSection extends ConsumerWidget {
  const _TimbratureSection({required this.cantiereId});

  final String cantiereId;

  /// `WorkLogApprovalStatusEnum`, as the server stores it.
  static String _approvalLabel(int status) => switch (status) {
    1 => 'Inviato',
    2 => 'Approvato',
    3 => 'Respinto',
    _ => 'Bozza',
  };

  /// `HH:mm` for a seconds-into-the-day value — the form a legacy row carries.
  static String _hm(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// The shift length. True instants when the row has them — the only safe way across midnight —
  /// otherwise the time-of-day pair, which on an overnight shift reads negative and is shown as
  /// the domain's own overnight correction rather than a nonsense duration.
  static String _duration(CantiereWorkLog w) {
    Duration d;
    if (w.startUtc != null && w.endUtc != null) {
      d = w.endUtc!.difference(w.startUtc!);
    } else if (w.endSeconds != null) {
      d = Duration(seconds: w.endSeconds! - w.startSeconds);
      if (d.isNegative) d += const Duration(hours: 24);
    } else {
      return 'in corso';
    }
    return '${d.inHours}h ${d.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
  }

  /// The shift's wall clock. Always the business-zone time of day the server stored, never the
  /// phone's own zone: a technician whose handset is set to another timezone (or travelling) must
  /// read the same hours the office prices the job from.
  static String _window(CantiereWorkLog w) {
    final start = _hm(w.startSeconds);
    final end = w.endSeconds == null ? null : _hm(w.endSeconds!);
    return end == null ? '$start – in corso' : '$start – $end';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(cantiereWorkLogMirrorProvider(cantiereId));
    // Offline with a mirror that has never been filled is "we don't know", not "you never punched".
    final unknown =
        !ref.watch(isOnlineProvider) &&
        ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;

    return logsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (logs) {
        return CantiereSection(
          title: 'Le tue timbrature',
          child: CantiereCard(
            padding: logs.isEmpty
                ? const EdgeInsets.all(14)
                : const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: logs.isEmpty
                ? Text(
                    unknown ? 'Timbrature non ancora scaricate' : 'Nessuna timbratura registrata',
                    style: cantiereBody(context, 11, color: context.colors.inkMuted),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < logs.length; i++) ...[
                        if (i > 0) const CantiereRule(),
                        CantiereLedgerRow(
                          done: true,
                          // A calendar label, not an instant: formatting its y/m/d fields with no
                          // zone conversion is what keeps the day right west of UTC.
                          title: formatWorkDate(logs[i].workDate, 'dd/MM/yyyy'),
                          meta: '${_window(logs[i])}  ·  ${_duration(logs[i])}',
                          time: _approvalLabel(logs[i].approvalStatus),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Mappa — the drawn map card: a 78px map drawing with the red site pin, and a footer row with the
// address and "Apri in Mappe". The drawing opens the in-app map view; the footer hands the
// address to the device's maps app.
// ══════════════════════════════════════════════════════════════════════════════

class _MapSection extends StatelessWidget {
  const _MapSection({required this.cantiere, required this.address});

  final CantieriData cantiere;
  final String address;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void openMap() => context.push(AppRoutes.cantiereMapPath(cantiere.id));

    return CantiereSection(
      title: 'Mappa',
      note: 'Apri',
      onNoteTap: openMap,
      child: Column(
        children: [
          InkWell(
            onTap: openMap,
            borderRadius: BorderRadius.circular(2),
            child: const CantiereMapArt(),
          ),
          InkWell(
            onTap: () => openMapsForAddress(address),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(
                  left: BorderSide(color: c.borderLight),
                  right: BorderSide(color: c.borderLight),
                  bottom: BorderSide(color: c.borderLight),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cantiereBody(context, 10.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('APRI IN MAPPE', style: cantiereMono(context, 8)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
