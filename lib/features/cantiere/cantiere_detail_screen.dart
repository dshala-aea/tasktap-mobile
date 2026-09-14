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
import '../../core/utils/error_message.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../rapportino/create_draft.dart';
import '../ticket/ticket_providers.dart' show commessaByIdProvider;
import '../timbra/cantiere_timbra_screen.dart' show cantiereCrewAssignmentsProvider;
import 'cantiere_map_card.dart';
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

  @override
  Widget build(BuildContext context) {
    final cantiereAsync = ref.watch(cantiereByIdProvider(widget.cantiereId));
    final ticketsAsync = ref.watch(ticketsForCantiereProvider(widget.cantiereId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Cantiere', showBack: true),
            Expanded(
              child: cantiereAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const UnavailableState(
                  icon: LucideIcons.hardHat,
                  titolo: 'Impossibile caricare il cantiere',
                  motivo: 'Riprova tra poco.',
                ),
                data: (cantiere) {
                  if (cantiere == null) {
                    return const UnavailableState(
                      icon: LucideIcons.hardHat,
                      titolo: 'Cantiere non trovato',
                      motivo: 'Non risulta sincronizzato su questo dispositivo.',
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      AppSpacing.sm,
                      AppSpacing.pagePadding,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cantiere.name,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.ink,
                                ),
                              ),
                              if (cantiere.address != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  cantiere.address!,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              AppBadge(label: _statusLabel(cantiere.status)),
                            ],
                          ),
                        ),

                        // ── Map ────────────────────────────────────────────────────
                        //
                        // Only when there's an address worth plotting — same gate
                        // admin_cantiere_detail_screen.dart's own map section uses.
                        if (cantiere.address != null && cantiere.address!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          CantiereMapCard(
                            cantiereId: cantiere.id,
                            address: [
                              cantiere.address,
                              cantiere.city,
                              cantiere.postalCode,
                            ].where((s) => s != null && s.isNotEmpty).join(', '),
                          ),
                        ],

                        // ── Dettagli ───────────────────────────────────────────────
                        _DettagliSection(cantiere: cantiere),

                        // ── Squadra assegnata ─────────────────────────────────────
                        _SquadraSection(cantiereId: cantiere.id),

                        const SizedBox(height: 8),
                        AppButton(
                          label: 'Timbra cantiere',
                          icon: const Icon(LucideIcons.mapPin),
                          onPressed: () => context.push(
                            AppRoutes.cantiereTimbraPath(
                              cantiereId: cantiere.id,
                              ticketId: widget.ticketId,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ── Crea rapportino ──────────────────────────────────────────
                        //
                        // The office/admin equivalent of this button (admin_cantiere_detail_
                        // screen.dart) creates a purely local draft with blank hours via
                        // createLocalDraft. A technician standing on-site has already logged
                        // hours against this cantiere (Timbra cantiere, above) — this button
                        // calls the cantiere-only report endpoint instead, so the editor opens
                        // with those hours (and, if this technician started the batch as squadra
                        // lead, their whole team's hours) already filled in.
                        AppButton(
                          label: 'Crea rapportino',
                          icon: const Icon(LucideIcons.fileText),
                          isLoading: _isCreatingRapportino,
                          onPressed: _isCreatingRapportino
                              ? null
                              : () => _handleCreateRapportino(cantiere),
                        ),
                        const SizedBox(height: 24),
                        const SectionTitle(title: 'Ticket collegati'),
                        const SizedBox(height: 8),
                        ticketsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text(
                            'Impossibile caricare i ticket collegati.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: context.colors.red,
                            ),
                          ),
                          data: (tickets) {
                            if (tickets.isEmpty) {
                              return Text(
                                'Nessun ticket collegato',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: context.colors.inkMuted,
                                ),
                              );
                            }
                            return AppCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: tickets.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final t = entry.value;
                                  return ListRow(
                                    title: t.title,
                                    showDivider: i != tickets.length - 1,
                                    onTap: () => context.push(AppRoutes.ticketDetailPath(t.id)),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
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
          message: humanErrorMessage(e, azione: 'creare il rapportino'),
          tone: ToastTone.error,
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isCreatingRapportino = false);

    if (id == null) {
      showAppToast(context, message: 'Accedi per creare un rapportino.', tone: ToastTone.warning);
      return;
    }
    context.push(AppRoutes.rapportiniEditor(id));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Dettagli — Cliente/Commessa/Periodo/Note. All five fields
// (customerId/commessaId/startDate/endDate/notes) are already synced to the local Cantieri
// mirror (see this file's own header/task context) but were shown nowhere on this screen before
// now. Each row is skipped independently when its field is absent (same contract
// admin_cantiere_detail_screen.dart's own detail card uses for Commessa); the whole section
// collapses to nothing when every field is, rather than showing an empty card.
// ══════════════════════════════════════════════════════════════════════════════

class _DettagliSection extends ConsumerWidget {
  const _DettagliSection({required this.cantiere});

  final CantieriData cantiere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNotes = cantiere.notes != null && cantiere.notes!.isNotEmpty;
    final hasAnything =
        cantiere.customerId != null ||
        cantiere.commessaId != null ||
        cantiere.startDate != null ||
        cantiere.endDate != null ||
        hasNotes;
    if (!hasAnything) return const SizedBox.shrink();

    // Live-fetched, no local mirror for either — same shape as
    // admin_cantiere_detail_screen.dart's own Cliente/Commessa rows. `error`/`null` both fall
    // back to '—': a commessa lookup throws TicketDetailOfflineException while offline (see
    // commessaByIdProvider's own doc comment), which must read the same as "not resolved yet",
    // not surface as a broken row on an otherwise-fine offline screen.
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
    if (start != null && end != null) {
      periodoLabel =
          '${DateFormat('dd/MM/yyyy').format(start.toLocal())} – '
          '${DateFormat('dd/MM/yyyy').format(end.toLocal())}';
    } else if (start != null) {
      periodoLabel = 'Dal ${DateFormat('dd/MM/yyyy').format(start.toLocal())}';
    } else if (end != null) {
      periodoLabel = 'Fino al ${DateFormat('dd/MM/yyyy').format(end.toLocal())}';
    }

    final entries = <({String label, String value, bool vertical})>[
      if (customerId != null) (label: 'Cliente', value: customerLabel ?? '—', vertical: false),
      if (commessaId != null) (label: 'Commessa', value: commessaLabel ?? '—', vertical: false),
      if (periodoLabel != null) (label: 'Periodo', value: periodoLabel, vertical: false),
      if (hasNotes) (label: 'Note', value: cantiere.notes!, vertical: true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Dettagli'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Column(
            children: entries.asMap().entries.map((e) {
              final entry = e.value;
              return KeyVal(
                label: entry.label,
                value: entry.value,
                vertical: entry.vertical,
                showDivider: e.key != entries.length - 1,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Squadra assegnata — read-only crew list from the same `cantiereCrewAssignmentsProvider`
// (GET /api/cantieri/{id}/assegnazioni) the batch-timbra "Seleziona squadra" picker already uses
// (cantiere_timbra_screen.dart / teammate_picker_sheet.dart) — same data, no new fetch. Collapses
// to nothing while loading, on error (including offline — see that provider's own doc comment on
// why AsyncError there is an expected, not exceptional, state), or when nobody is assigned: this
// is a convenience read, not something this screen's primary Timbra/Crea-rapportino flows depend
// on, so it must never block or clutter the rest of the page while it resolves.
// ══════════════════════════════════════════════════════════════════════════════

class _SquadraSection extends ConsumerWidget {
  const _SquadraSection({required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(cantiereCrewAssignmentsProvider(cantiereId));

    return assignmentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (assignments) {
        if (assignments.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'Squadra assegnata'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: assignments.asMap().entries.map((entry) {
                  final i = entry.key;
                  final a = entry.value;
                  // Same fallback contract as everywhere else colleagueNameProvider is read: the
                  // raw id rather than nothing, when the local mirror doesn't (yet) know them.
                  final name = ref.watch(colleagueNameProvider(a.userId)).valueOrNull ?? a.userId;
                  return ListRow(
                    leading: AppAvatar(name: name, size: 36),
                    title: name,
                    meta: a.isLead
                        ? Text(
                            'LEAD',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: context.colors.inkMuted,
                            ),
                          )
                        : null,
                    showDivider: i != assignments.length - 1,
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}
