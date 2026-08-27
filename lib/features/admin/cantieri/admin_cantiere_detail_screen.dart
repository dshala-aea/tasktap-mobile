// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/vetro_map_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../rapportino/create_draft.dart';
import '../../ticket/ticket_providers.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ── Cantiere status label/colour ─────────────────────────────────────────────
//
// CantiereStatusEnum (WorkEnums.cs): Active=0, Completed=1, Cancelled=2 — same ordinals the
// create/edit form's Stato dropdown uses.
const Map<int, String> _cantiereStatoLabels = {0: 'Attivo', 1: 'Completato', 2: 'Annullato'};

String cantiereStatoLabel(int status) => _cantiereStatoLabels[status] ?? 'Attivo';

/// Single cantiere by id from Drift cache.
final adminCantiereDetailProvider = StreamProvider.autoDispose.family<CantieriData?, String>((
  ref,
  id,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)..where((c) => c.id.equals(id))).watchSingleOrNull();
});

/// Admin cantiere detail — read-only with edit FAB.
class AdminCantiereDetailScreen extends ConsumerWidget {
  const AdminCantiereDetailScreen({super.key, required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiereAsync = ref.watch(adminCantiereDetailProvider(cantiereId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/cantieri/$cantiereId/modifica');
          },
        ),
      ),
      body: cantiereAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(adminCantiereDetailProvider(cantiereId))),
        data: (cantiere) {
          if (cantiere == null) {
            return const UnavailableState(
              titolo: 'Cantiere non disponibile',
              motivo:
                  "L'elenco cantieri non è ancora sincronizzato sul "
                  'dispositivo, quindi questo cantiere non può essere '
                  'letto dalla cache locale anche se esiste sul server.',
            );
          }
          return _CantiereDetailBody(cantiere: cantiere, cantiereId: cantiereId);
        },
      ),
    );
  }
}

/// Delete confirmation dialog + API call — mirrors `_deleteCustomer` in
/// admin_customer_detail_screen.dart (no shared confirm-dialog widget exists yet in this app).
Future<void> _deleteCantiere(BuildContext context, WidgetRef ref, String cantiereId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminare il cantiere?'),
      content: const Text(
        "L'eliminazione è definitiva. Interventi e log collegati non saranno più raggiungibili "
        'da qui.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteCantiere(cantiereId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cantiere eliminato')));
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      // Every FK in this DB is Restrict — a cantiere with any linked ticket/report/worklog/
      // contact/assignment 409s with a specific message (CantieriController.Delete's own doc
      // comment: "not by omission"). humanErrorMessage surfaces that server sentence directly
      // instead of a generic one, since it names exactly why the delete was refused.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanErrorMessage(e, azione: 'eliminare il cantiere')),
          backgroundColor: context.colors.red,
        ),
      );
    }
  }
}

class _CantiereDetailBody extends ConsumerWidget {
  const _CantiereDetailBody({required this.cantiere, required this.cantiereId});

  final CantieriData cantiere;
  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startLabel = cantiere.startDate != null
        ? DateFormat('dd/MM/yyyy').format(cantiere.startDate!.toLocal())
        : '—';
    final endLabel = cantiere.endDate != null
        ? DateFormat('dd/MM/yyyy').format(cantiere.endDate!.toLocal())
        : '—';

    // Feature audit module #13, Gap 6: mobile already syncs `Cantiere.commessaId` but showed it
    // nowhere. Resolved the same way as the ticket detail screen's own commessa row — live-
    // fetched via the shared commessaByIdProvider, no local mirror exists for commesse.
    final commessaId = cantiere.commessaId;
    final commessaAsync = commessaId == null
        ? null
        : ref.watch(commessaByIdProvider(commessaId));
    final commessaLabel = commessaAsync?.when(
      data: (c) => c?['codice'] as String? ?? '—',
      loading: () => 'Caricamento…',
      error: (e, _) => '—',
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: cantiere.name,
            subtitle: cantiere.city ?? '',
            showBack: true,
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.trash2,
                label: 'Elimina cantiere',
                glass: true,
                onTap: () => _deleteCantiere(context, ref, cantiereId),
              ),
            ],
          ),
        ),
        // ── Map / Naviga ─────────────────────────────────────────────────
        //
        // A real gap the Vetro mockup's own `.mapcard` called for — an address shown with no way
        // to act on it. Only when there's an address worth navigating to.
        if (cantiere.address != null && cantiere.address!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                0,
              ),
              child: VetroMapCard(
                address: [
                  cantiere.address,
                  cantiere.city,
                  cantiere.postalCode,
                ].where((s) => s != null && s.isNotEmpty).join(', '),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: VetroCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                children: [
                  KeyVal(label: 'Nome', value: cantiere.name),
                  KeyVal(label: 'Stato', value: cantiereStatoLabel(cantiere.status)),
                  KeyVal(label: 'Città', value: cantiere.city ?? '—'),
                  KeyVal(label: 'Indirizzo', value: cantiere.address ?? '—'),
                  KeyVal(label: 'CAP', value: cantiere.postalCode ?? '—'),
                  KeyVal(label: 'Inizio', value: startLabel),
                  KeyVal(label: 'Fine', value: endLabel, showDivider: commessaLabel != null),
                  if (commessaLabel != null)
                    KeyVal(
                      label: 'Commessa',
                      value: commessaLabel,
                      onTap: commessaId == null
                          ? null
                          : () => context.push('/altro/commesse/$commessaId'),
                    ),
                  KeyVal(
                    label: 'Note',
                    value: cantiere.notes?.isNotEmpty == true ? cantiere.notes! : '—',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Crea rapportino ──────────────────────────────────────────────
        //
        // Cantiere had no path into a rapportino at all — a technician on-site had to back out
        // to Rapportini and start blank, typing the customer/address/cantiere link by hand. Same
        // prefill contract as Ticket detail's own "Crea rapportino" (createLocalDraft): every
        // field this screen already knows goes straight into the draft.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              AppSpacing.pagePadding,
            ),
            child: VetroButton(
              label: 'Crea rapportino',
              icon: const Icon(LucideIcons.fileText),
              onPressed: () => _createRapportino(context, ref, cantiere),
            ),
          ),
        ),

        // ── Contatti (Gap 1) ────────────────────────────────────────────
        SliverToBoxAdapter(child: _ContactsSection(cantiereId: cantiereId)),

        // ── Personale (Gap 2) ───────────────────────────────────────────
        SliverToBoxAdapter(child: _CrewSection(cantiereId: cantiereId)),

        // ── Ore / Interventi / Rapportini (Gap 6, read-only) ────────────
        SliverToBoxAdapter(child: _WorkLogsSection(cantiereId: cantiereId)),
        SliverToBoxAdapter(child: _TicketsSection(cantiereId: cantiereId)),
        SliverToBoxAdapter(child: _ReportsSection(cantiereId: cantiereId)),

        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }

  Future<void> _createRapportino(
    BuildContext context,
    WidgetRef ref,
    CantieriData cantiere,
  ) async {
    final address = [
      cantiere.address,
      cantiere.city,
      cantiere.postalCode,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    final id = await createLocalDraft(
      ref,
      title: 'Rapportino — ${cantiere.name}',
      cantiereId: cantiere.id,
      customerId: cantiere.customerId,
      tenantId: cantiere.tenantId,
      workAddress: address.isEmpty ? null : address,
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
}

// ══════════════════════════════════════════════════════════════════════════════
// Live sub-resource providers — none of these are synced to Drift (contacts and crew
// assignments have no local mirror at all; tickets/reports/work-logs are read live everywhere
// else in the app too). Mirrors web's CantiereSections.tsx, which fetches the same way.
// ══════════════════════════════════════════════════════════════════════════════

/// `GET /api/cantieri/{id}` — the only source for a cantiere's contacts and crew assignments.
final adminCantiereRemoteDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, id) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchCantiereDetail(id);
    });

/// Interventi (tickets) raised on this cantiere.
final adminCantiereTicketsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchCantiereTickets(id);
    });

/// Rapportini documenting work on this cantiere.
final adminCantiereReportsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchReports(cantiereId: id);
    });

/// Hours logged on this cantiere.
final adminCantiereWorkLogsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchCantiereWorkLogs(id);
    });

// ══════════════════════════════════════════════════════════════════════════════
// Contatti (Gap 1)
// ══════════════════════════════════════════════════════════════════════════════

class _ContactsSection extends ConsumerWidget {
  const _ContactsSection({required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminCantiereRemoteDetailProvider(cantiereId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Contatti',
          action: IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Aggiungi contatto',
            onPressed: () => _openContactSheet(context, ref, cantiereId: cantiereId, contact: null),
          ),
        ),
        detailAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _SectionError(
            onRetry: () => ref.invalidate(adminCantiereRemoteDetailProvider(cantiereId)),
          ),
          data: (detail) {
            final contacts = (detail?['contacts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            if (contacts.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.users,
                title: 'Nessun contatto',
                body: 'Aggiungi un referente del cantiere con il pulsante +.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: contacts.asMap().entries.map((entry) {
                  final c = entry.value;
                  final name = c['name'] as String? ?? '';
                  final role = c['role'] as String?;
                  final phone = c['phone'] as String?;
                  final subtitleParts = [
                    if (role != null && role.isNotEmpty) role,
                    if (phone != null && phone.isNotEmpty) phone,
                  ];
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.user),
                    title: name.isNotEmpty ? name : 'Contatto',
                    subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' · ') : null,
                    meta: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.pencil, size: 18),
                          tooltip: 'Modifica contatto',
                          onPressed: () => _openContactSheet(
                            context,
                            ref,
                            cantiereId: cantiereId,
                            contact: c,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          tooltip: 'Elimina contatto',
                          onPressed: () => _deleteContact(context, ref, cantiereId: cantiereId,
                              contactId: c['id'] as String, name: name),
                        ),
                      ],
                    ),
                    showDivider: entry.key < contacts.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteContact(
    BuildContext context,
    WidgetRef ref, {
    required String cantiereId,
    required String contactId,
    required String name,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare il contatto?'),
        content: Text('Vuoi eliminare "$name" dai contatti del cantiere?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminApiClientProvider).deleteCantiereContact(cantiereId, contactId);
      ref.invalidate(adminCantiereRemoteDetailProvider(cantiereId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Contatto eliminato')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile eliminare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    }
  }

  void _openContactSheet(
    BuildContext context,
    WidgetRef ref, {
    required String cantiereId,
    required Map<String, dynamic>? contact,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ContactFormSheet(
        cantiereId: cantiereId,
        contact: contact,
        api: ref.read(adminApiClientProvider),
        onSaved: () => ref.invalidate(adminCantiereRemoteDetailProvider(cantiereId)),
      ),
    );
  }
}

/// Bottom sheet to add or edit a cantiere contact — mirrors
/// UpsertCantiereContactRequest (name required, role/phone/email/notes optional).
class _ContactFormSheet extends StatefulWidget {
  const _ContactFormSheet({
    required this.cantiereId,
    required this.contact,
    required this.api,
    required this.onSaved,
  });

  final String cantiereId;

  /// Null when adding; the existing contact map when editing.
  final Map<String, dynamic>? contact;
  final AdminApiClient api;
  final VoidCallback onSaved;

  @override
  State<_ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends State<_ContactFormSheet> {
  late final _nameCtrl = TextEditingController(text: widget.contact?['name'] as String?);
  late final _roleCtrl = TextEditingController(text: widget.contact?['role'] as String?);
  late final _phoneCtrl = TextEditingController(text: widget.contact?['phone'] as String?);
  late final _emailCtrl = TextEditingController(text: widget.contact?['email'] as String?);
  late final _notesCtrl = TextEditingController(text: widget.contact?['notes'] as String?);
  bool _isSaving = false;

  bool get _isEditing => widget.contact != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await widget.api.updateCantiereContact(
          widget.cantiereId,
          widget.contact!['id'] as String,
          name: name,
          role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await widget.api.addCantiereContact(
          widget.cantiereId,
          name: name,
          role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      }
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Contatto aggiornato' : 'Contatto aggiunto')),
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Modifica contatto' : 'Aggiungi contatto',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            AppTextField(label: 'Nome *', controller: _nameCtrl),
            const SizedBox(height: 16),
            AppTextField(label: 'Ruolo', controller: _roleCtrl),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Telefono',
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Email',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: VetroButton(
                label: _isSaving ? 'Salvataggio…' : 'Salva',
                onPressed: _isSaving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Personale / crew (Gap 2) — individual technician only, `CantiereAssignment` has no `SquadraId`
// (unlike `ScheduleAssignment`), so there is no squadra-level assignment to offer here.
// ══════════════════════════════════════════════════════════════════════════════

class _CrewSection extends ConsumerWidget {
  const _CrewSection({required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminCantiereRemoteDetailProvider(cantiereId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Personale',
          action: IconButton(
            icon: const Icon(LucideIcons.userPlus),
            tooltip: 'Aggiungi persona',
            onPressed: () => _openAddSheet(context, ref),
          ),
        ),
        detailAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _SectionError(
            onRetry: () => ref.invalidate(adminCantiereRemoteDetailProvider(cantiereId)),
          ),
          data: (detail) {
            final assignments =
                (detail?['assignments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            if (assignments.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.hardHat,
                title: 'Nessuna persona assegnata',
                body: 'Aggiungi un tecnico al cantiere con il pulsante +.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: assignments.asMap().entries.map((entry) {
                  final a = entry.value;
                  final userId = a['userId'] as String? ?? '';
                  final role = a['role'] as String?;
                  final nome = userId.isEmpty
                      ? null
                      : ref.watch(colleagueNameProvider(userId)).valueOrNull;
                  return ListRow(
                    leading: AppAvatar(name: nome ?? '?', size: 36),
                    title: nome ?? 'Persona non sincronizzata',
                    subtitle: role != null && role.isNotEmpty ? role : null,
                    meta: IconButton(
                      icon: const Icon(LucideIcons.userMinus, size: 18),
                      tooltip: 'Rimuovi dal cantiere',
                      onPressed: () => _removeAssignment(
                        context,
                        ref,
                        assignmentId: a['id'] as String,
                        nome: nome ?? 'questa persona',
                      ),
                    ),
                    showDivider: entry.key < assignments.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _removeAssignment(
    BuildContext context,
    WidgetRef ref, {
    required String assignmentId,
    required String nome,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere dal cantiere?'),
        content: Text('Vuoi rimuovere $nome dal personale assegnato a questo cantiere?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminApiClientProvider).removeCantiereAssignment(cantiereId, assignmentId);
      ref.invalidate(adminCantiereRemoteDetailProvider(cantiereId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Persona rimossa dal cantiere')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile salvare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    }
  }

  void _openAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddAssignmentSheet(
        cantiereId: cantiereId,
        api: ref.read(adminApiClientProvider),
        onSaved: () => ref.invalidate(adminCantiereRemoteDetailProvider(cantiereId)),
      ),
    );
  }
}

/// Bottom sheet to assign a technician to a cantiere — mirrors
/// CreateCantiereAssignmentRequest (userId required, role/dates optional). No squadra picker: see
/// this section's own header comment for why.
class _AddAssignmentSheet extends StatefulWidget {
  const _AddAssignmentSheet({required this.cantiereId, required this.api, required this.onSaved});

  final String cantiereId;
  final AdminApiClient api;
  final VoidCallback onSaved;

  @override
  State<_AddAssignmentSheet> createState() => _AddAssignmentSheetState();
}

class _AddAssignmentSheetState extends State<_AddAssignmentSheet> {
  final _roleCtrl = TextEditingController();
  String? _selectedUserId;
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _technicians = [];

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void dispose() {
    _roleCtrl.dispose();
    super.dispose();
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedUserId == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.api.addCantiereAssignment(
        widget.cantiereId,
        userId: _selectedUserId!,
        role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
      );
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Persona assegnata al cantiere')));
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
          Text('Aggiungi persona', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            AppFieldShell(
              label: 'Tecnico *',
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _selectedUserId,
                items: _technicians
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedUserId = v),
              ),
            ),
          const SizedBox(height: 16),
          AppTextField(label: 'Ruolo sul cantiere', controller: _roleCtrl),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: VetroButton(
              label: _isSaving ? 'Salvataggio…' : 'Aggiungi',
              onPressed: (_selectedUserId == null || _isSaving) ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Ore (Gap 6) — read-only hours logged on this cantiere.
// ══════════════════════════════════════════════════════════════════════════════

class _WorkLogsSection extends ConsumerWidget {
  const _WorkLogsSection({required this.cantiereId});

  final String cantiereId;

  static const Map<String, String> _approvalLabels = {
    'Draft': 'Bozza',
    'Submitted': 'Inviato',
    'Approved': 'Completato',
    'Rejected': 'Respinto',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(adminCantiereWorkLogsProvider(cantiereId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Ore'),
        logsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              _SectionError(onRetry: () => ref.invalidate(adminCantiereWorkLogsProvider(cantiereId))),
          data: (logs) {
            if (logs.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.clock,
                title: 'Nessuna ora registrata',
                body: 'Non risultano timbrature di cantiere per questo sito.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: logs.asMap().entries.map((entry) {
                  final log = entry.value;
                  final workDate = DateTime.tryParse(log['workDate'] as String? ?? '');
                  final dateLabel = workDate != null
                      ? DateFormat('dd/MM/yyyy', 'it').format(workDate.toLocal())
                      : '—';
                  final startTime = (log['startTime'] as String?)?.substring(0, 5) ?? '—';
                  final endTime = (log['endTime'] as String?)?.substring(0, 5);
                  final approval = log['approvalStatus'] as String?;
                  final stato = _approvalLabels[approval] ?? 'Bozza';
                  final userId = log['userId'] as String?;
                  final userName = userId == null
                      ? null
                      : ref.watch(colleagueNameProvider(userId)).valueOrNull;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.clock),
                    title: userName ?? dateLabel,
                    subtitle: userName != null
                        ? '$dateLabel · $startTime${endTime != null ? '–$endTime' : ' (in corso)'}'
                        : '$startTime${endTime != null ? '–$endTime' : ' (in corso)'}',
                    meta: StatusPill(stato: stato, small: true, outlined: true),
                    showDivider: entry.key < logs.length - 1,
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

// ══════════════════════════════════════════════════════════════════════════════
// Interventi (Gap 6) — read-only tickets raised on this cantiere.
// ══════════════════════════════════════════════════════════════════════════════

class _TicketsSection extends ConsumerWidget {
  const _TicketsSection({required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(adminCantiereTicketsProvider(cantiereId));
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Interventi'),
        ticketsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              _SectionError(onRetry: () => ref.invalidate(adminCantiereTicketsProvider(cantiereId))),
          data: (tickets) {
            if (tickets.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.ticket,
                title: 'Nessun intervento',
                body: 'Non risultano interventi collegati a questo cantiere.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: tickets.asMap().entries.map((entry) {
                  final t = entry.value;
                  final title = t['title'] as String? ?? 'Intervento';
                  final numero = t['numero'] as String?;
                  final statusId = t['statusId'] as int?;
                  final statusLabel = statusMap[statusId] ?? 'Aperto';
                  final id = t['id'] as String?;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.ticket),
                    title: title,
                    subtitle: numero != null && numero.isNotEmpty ? numero : null,
                    meta: StatusPill(stato: statusLabel, small: true, outlined: true),
                    onTap: id == null ? null : () => context.push('/ticket/$id'),
                    showDivider: entry.key < tickets.length - 1,
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

// ══════════════════════════════════════════════════════════════════════════════
// Rapportini (Gap 6) — read-only reports documenting work on this cantiere.
// ══════════════════════════════════════════════════════════════════════════════

class _ReportsSection extends ConsumerWidget {
  const _ReportsSection({required this.cantiereId});

  final String cantiereId;

  // ReportStatoEnum ordinal → Italian label. ReportsController's GetAll response is an anonymous
  // projection, which does not inherit the entity property's [JsonConverter] — `stato` arrives as
  // a bare int here (same as TicketReportSummary in ticket_detail_api_client.dart).
  static const Map<int, String> _statoLabels = {
    0: 'Bozza',
    1: 'Inviato',
    2: 'Controllato',
    3: 'Fatturato',
    4: 'Respinto',
    5: 'Annullato',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(adminCantiereReportsProvider(cantiereId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Rapportini'),
        reportsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              _SectionError(onRetry: () => ref.invalidate(adminCantiereReportsProvider(cantiereId))),
          data: (reports) {
            if (reports.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.fileText,
                title: 'Nessun rapportino',
                body: 'Non risultano rapportini collegati a questo cantiere.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: reports.asMap().entries.map((entry) {
                  final r = entry.value;
                  final title = r['title'] as String? ?? 'Rapportino';
                  final stato = r['stato'];
                  final statoLabel = _statoLabels[stato is int ? stato : int.tryParse('$stato')] ??
                      'Bozza';
                  final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '');
                  final dateLabel = createdAt != null
                      ? DateFormat('dd/MM/yyyy', 'it').format(createdAt.toLocal())
                      : null;
                  final id = r['id'] as String?;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.fileText),
                    title: title,
                    subtitle: dateLabel,
                    meta: StatusPill(stato: statoLabel, small: true, outlined: true),
                    onTap: id == null ? null : () => context.push('/altro/rapportini/view/$id'),
                    showDivider: entry.key < reports.length - 1,
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

// ══════════════════════════════════════════════════════════════════════════════
// Shared inline error for a section (distinct from the page-level [ErrorState] — a failed
// sub-section should not block the rest of the detail screen from being usable).
// ══════════════════════════════════════════════════════════════════════════════

class _SectionError extends StatelessWidget {
  const _SectionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Impossibile caricare. Riprova.',
              style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: context.colors.red),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    );
  }
}
