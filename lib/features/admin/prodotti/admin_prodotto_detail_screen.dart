// dart format width=100
import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/auth/access.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/time/business_time.dart' show formatWorkDate, parseDateOnly;
import '../../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../../core/utils/error_message.dart';
import '../../../core/widgets/detail/detail_activity_timeline.dart';
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/entitlements/entitlement_providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider, syncProvider;
import '../../../data/tickets/pending_ticket_repository.dart' show decodePendingStringList;
import '../../../presentation/providers/schedule_providers.dart'
    show customerByIdProvider, locationByIdProvider;
import '../../ticket/ticket_providers.dart' show ticketStatusMapProvider;
import '../admin_api_client.dart';

/// Serial numbers (Matricole) of one prodotto — a real 1:N sub-resource with add/remove only.
final adminProdottoMatricoleProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, prodottoId) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchMatricole(prodottoId);
    });

/// Tickets whose coverage list names this asset, from the local Drift mirror.
///
/// `Tickets.prodottoAssistenzaIdsJson` is the ticket's own complete statement of coverage, so the
/// history is offline-capable and needs no extra network read at page open.
final adminProdottoTicketsProvider = StreamProvider.autoDispose.family<List<Ticket>, String>((
  ref,
  prodottoId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch().map(
    (rows) => rows
        .where((t) => decodePendingStringList(t.prodottoAssistenzaIdsJson).contains(prodottoId))
        .toList(),
  );
});

/// Admin prodotto assistenza detail — the wave-0 summary shell.
///
/// Section order follows `other-details.html` for this subject (Storico-first):
/// Attività → Sintesi → Relazioni → Documenti. Documenti is hidden: the screen has no attachment
/// source. The hero owns `Modifica` (gated on the same contract-write capability as before), the
/// header keeps the delete action, and Matricole stay inline in Sintesi with their add/remove.
class AdminProdottoDetailScreen extends ConsumerWidget {
  const AdminProdottoDetailScreen({super.key, required this.prodotto});

  final Map<String, dynamic> prodotto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = prodotto['id'] as String? ?? '';
    if (id.isEmpty) {
      return const DetailScaffold.unavailable(
        screenTitle: 'Prodotto in assistenza',
        icon: LucideIcons.package,
        title: 'Prodotto non disponibile',
        reason: 'Apri il prodotto dall\'elenco Prodotti in assistenza per vederne il dettaglio.',
      );
    }
    return _ProdottoDetailBody(prodotto: prodotto);
  }
}

class _ProdottoDetailBody extends ConsumerWidget {
  const _ProdottoDetailBody({required this.prodotto});

  final Map<String, dynamic> prodotto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = prodotto['id'] as String;
    final name = _string(prodotto['name']) ?? 'Prodotto in assistenza';
    final codice = _string(prodotto['codice']) ?? '';
    final description = _string(prodotto['description']) ?? '';
    final notes = _string(prodotto['notes']) ?? '';
    final serialNumber = _string(prodotto['serialNumber']) ?? '';
    final marchio = _string(prodotto['marchio']) ?? '';
    final modello = _string(prodotto['modello']) ?? '';
    final tipo = _string(prodotto['tipo']) ?? '';
    final categoria = _string(prodotto['categoria']) ?? '';
    final um = _string(prodotto['um']) ?? '';
    final externalId = _string(prodotto['externalId']) ?? '';
    final customerId = _string(prodotto['customerId']);
    final locationId = _string(prodotto['locationId']);

    final businessTime = ref.watch(businessTimeProvider);
    final today = businessTime.businessToday();

    final warranty = parseDateOnly(prodotto['warrantyExpiryDate']);
    final lastMaintenance = parseDateOnly(prodotto['ultimaManutenzione']);
    final nextMaintenance = parseDateOnly(prodotto['prossimaManutenzione']);
    final installedAt = parseDateOnly(prodotto['dataInstallazione']);

    final isActive = prodotto['isActive'] as bool? ?? true;
    final status = _statusOf(isActive: isActive, warranty: warranty, today: today);

    final customer = customerId == null
        ? null
        : ref.watch(customerByIdProvider(customerId)).valueOrNull;
    final location = locationId == null
        ? null
        : ref.watch(locationByIdProvider(locationId)).valueOrNull;
    final customerName = customer?.companyName.trim();
    final locationName = location?.name.trim();

    final entitlement = ref.watch(cachedEntitlementProvider).value;
    final canWrite = entitlement?.capabilities.contains('contratti.contract.write') ?? false;

    final heroFacts = [
      if (customerName != null && customerName.isNotEmpty) customerName,
      if (serialNumber.isNotEmpty) serialNumber,
      if (lastMaintenance != null) 'ultima ${formatWorkDate(lastMaintenance, 'dd/MM')}',
    ].join(' · ');

    final sintesiFacts = <DetailFact>[
      if (codice.isNotEmpty) DetailFact(label: 'Codice', value: codice),
      if (marchio.isNotEmpty) DetailFact(label: 'Marca', value: marchio),
      if (modello.isNotEmpty) DetailFact(label: 'Modello', value: modello),
      if (tipo.isNotEmpty) DetailFact(label: 'Tipo', value: tipo),
      if (categoria.isNotEmpty) DetailFact(label: 'Categoria', value: categoria),
      if (um.isNotEmpty) DetailFact(label: 'Unità di misura', value: um),
      if (warranty != null)
        DetailFact(label: 'Garanzia', value: formatWorkDate(warranty, 'dd/MM/yyyy')),
      if (nextMaintenance != null)
        DetailFact(
          label: 'Prossima manutenzione',
          value: formatWorkDate(nextMaintenance, 'dd/MM/yyyy'),
        ),
      if (installedAt != null)
        DetailFact(label: 'Data installazione', value: formatWorkDate(installedAt, 'dd/MM/yyyy')),
      if (externalId.isNotEmpty) DetailFact(label: 'ID gestionale', value: externalId),
    ];

    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? const {};
    final tickets = ref.watch(adminProdottoTicketsProvider(id)).valueOrNull ?? const [];
    final events = [
      for (final ticket in tickets)
        DetailActivityEvent(
          time: formatWorkDate(businessTime.businessDateOf(ticket.createdAt), 'dd/MM/yy'),
          title: ticket.numero == null || ticket.numero!.isEmpty
              ? ticket.title
              : '${ticket.numero} · ${ticket.title}',
          meta: statusMap[ticket.statusId],
          tone: _ticketClosed(ticket, statusMap) ? DetailEventTone.good : DetailEventTone.neutral,
        ),
    ];

    final relations = <({String title, String meta, VoidCallback onTap})>[
      if (customerId != null && customerId.isNotEmpty)
        (
          title: 'Cliente',
          meta: customerName != null && customerName.isNotEmpty
              ? customerName
              : 'Cliente collegato',
          onTap: () => context.push(AppRoutes.clientiDetail(customerId)),
        ),
      if (locationId != null && locationId.isNotEmpty)
        (
          title: 'Sede',
          meta: locationName != null && locationName.isNotEmpty ? locationName : 'Sede collegata',
          onTap: () => context.push('/altro/sedi/$locationId'),
        ),
    ];

    final matricoleAsync = ref.watch(adminProdottoMatricoleProvider(id));

    return DetailScaffold(
      screenTitle: 'Prodotto in assistenza',
      headerActions: [
        CapabilityGate(
          capability: 'contratti.contract.write',
          child: HeaderIconBtn(
            icon: LucideIcons.trash2,
            label: 'Elimina asset',
            glass: true,
            onTap: () => _deleteProdotto(context, ref, id, name),
          ),
        ),
      ],
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · asset',
        kicker: 'Summary · asset',
        title: name,
        status: DetailStatus(label: status.$1, tone: status.$2),
        subtitle: heroFacts.isEmpty ? null : heroFacts,
        // The primary action stays on screen when denied so the hero does not lose its only
        // affordance; it is disabled and states why, matching the other detail screens.
        primaryAction: DetailAction(
          label: 'Modifica',
          enabled: canWrite,
          disabledReason: canWrite ? null : noPermissionReason,
          onPressed: canWrite
              ? () async {
                  await context.push<bool>('/altro/prodotti/$id/modifica', extra: prodotto);
                }
              : null,
        ),
      ),
      sections: [
        DetailSectionData(
          title: 'Attività',
          isEmpty: events.isEmpty,
          trailing: events.isEmpty
              ? null
              : DetailSectionMeta(
                  events.length == 1 ? '1 intervento' : '${events.length} interventi',
                ),
          child: DetailActivityTimeline(events: events),
        ),
        DetailSectionData(
          title: 'Sintesi',
          trailing: sintesiFacts.isEmpty
              ? null
              : DetailSectionMeta(
                  sintesiFacts.length == 1 ? '1 campo' : '${sintesiFacts.length} campi',
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sintesiFacts.isNotEmpty) DetailFactsGrid(facts: sintesiFacts),
              if (description.isNotEmpty) _TextBlock(label: 'Descrizione', text: description),
              if (notes.isNotEmpty) _TextBlock(label: 'Note', text: notes),
              _MatricoleGroup(prodottoId: id, matricoleAsync: matricoleAsync, canEdit: canWrite),
              ExtensionFieldsSection(
                entityType: 'prodottoassistenza',
                entityId: id,
                canEdit: canWrite,
              ),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Relazioni',
          isEmpty: relations.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < relations.length; i++)
                DetailLinkRow(
                  title: relations[i].title,
                  meta: relations[i].meta,
                  onTap: relations[i].onTap,
                  showDivider: i < relations.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String? _string(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

(String, DetailStatusTone?) _statusOf({
  required bool isActive,
  required DateTime? warranty,
  required DateTime today,
}) {
  if (!isActive) return ('Inattivo', null);
  if (warranty == null) return ('Attivo', null);
  return warranty.isBefore(today)
      ? ('Garanzia scaduta', DetailStatusTone.warn)
      : ('In garanzia', DetailStatusTone.good);
}

bool _ticketClosed(Ticket ticket, Map<int, String> statusMap) {
  if (ticket.closedAt != null) return true;
  final status = statusMap[ticket.statusId]?.toLowerCase();
  return status == 'chiuso' || status == 'completato';
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.docCode.copyWith(
              fontSize: 8,
              letterSpacing: 0.64,
              color: colors.inkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5, height: 1.4, color: colors.ink),
          ),
        ],
      ),
    );
  }
}

class _MatricoleGroup extends ConsumerWidget {
  const _MatricoleGroup({
    required this.prodottoId,
    required this.matricoleAsync,
    required this.canEdit,
  });

  final String prodottoId;
  final AsyncValue<List<Map<String, dynamic>>> matricoleAsync;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    Widget body;
    switch (matricoleAsync) {
      case AsyncData(:final value):
        if (value.isEmpty) {
          body = Text(
            'Nessuna matricola registrata.',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5, color: colors.inkMuted),
          );
        } else {
          body = Column(
            children: [
              for (var i = 0; i < value.length; i++)
                DetailLinkRow(
                  title: _string(value[i]['numero']) ?? 'Matricola',
                  showDivider: i < value.length - 1,
                  trailing: _MatricolaTrailing(
                    note: _string(value[i]['note']),
                    onRemove: canEdit
                        ? () => _deleteMatricola(
                            context,
                            ref,
                            prodottoId: prodottoId,
                            matricolaId: value[i]['id'] as String,
                            numero: _string(value[i]['numero']) ?? 'Matricola',
                          )
                        : null,
                  ),
                ),
            ],
          );
        }
      case AsyncError():
        body = ref.watch(isOnlineProvider)
            ? AppSectionError(
                onRetry: () => ref.invalidate(adminProdottoMatricoleProvider(prodottoId)),
              )
            : Text(
                'Matricole non disponibili offline.',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5, color: colors.inkMuted),
              );
      default:
        body = const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MATRICOLE',
                  style: AppTextStyles.docCode.copyWith(
                    fontSize: 8,
                    letterSpacing: 0.64,
                    color: colors.inkMuted,
                  ),
                ),
              ),
              if (canEdit)
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 18),
                  tooltip: 'Aggiungi matricola',
                  onPressed: () => _openAddMatricolaSheet(context, ref, prodottoId: prodottoId),
                ),
            ],
          ),
          body,
        ],
      ),
    );
  }
}

class _MatricolaTrailing extends StatelessWidget {
  const _MatricolaTrailing({required this.note, required this.onRemove});

  final String? note;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              note!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTextStyles.docCode.copyWith(
                fontSize: 7.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                color: context.colors.inkMuted,
              ),
            ),
          ),
        if (onRemove != null)
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: 18),
            tooltip: 'Rimuovi matricola',
            onPressed: onRemove,
          ),
      ],
    );
  }
}

Future<void> _deleteMatricola(
  BuildContext context,
  WidgetRef ref, {
  required String prodottoId,
  required String matricolaId,
  required String numero,
}) async {
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Rimuovere la matricola?',
    message: 'Vuoi rimuovere la matricola "$numero" da questo asset?',
    confirmLabel: 'Rimuovi',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteMatricola(prodottoId, matricolaId);
    ref.invalidate(adminProdottoMatricoleProvider(prodottoId));
    if (context.mounted) {
      showAppToast(context, message: 'Matricola rimossa', tone: ToastTone.success);
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(context, message: 'Impossibile eliminare. Riprova.', tone: ToastTone.error);
    }
  }
}

void _openAddMatricolaSheet(BuildContext context, WidgetRef ref, {required String prodottoId}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _AddMatricolaSheet(
      prodottoId: prodottoId,
      api: ref.read(adminApiClientProvider),
      onSaved: () => ref.invalidate(adminProdottoMatricoleProvider(prodottoId)),
    ),
  );
}

/// Delete confirmation dialog + API call — same shape as the other admin details.
Future<void> _deleteProdotto(
  BuildContext context,
  WidgetRef ref,
  String prodottoId,
  String name,
) async {
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Eliminare l\'asset?',
    message:
        'L\'asset "$name" verrà eliminato definitivamente. L\'operazione non può '
        'essere annullata.',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteProdottoAssistenza(prodottoId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      showAppToast(context, message: 'Asset eliminato', tone: ToastTone.success);
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'eliminare l\'asset'),
        tone: ToastTone.error,
      );
    }
  }
}

class _AddMatricolaSheet extends StatefulWidget {
  const _AddMatricolaSheet({required this.prodottoId, required this.api, required this.onSaved});

  final String prodottoId;
  final AdminApiClient api;
  final VoidCallback onSaved;

  @override
  State<_AddMatricolaSheet> createState() => _AddMatricolaSheetState();
}

class _AddMatricolaSheetState extends State<_AddMatricolaSheet> {
  final _numeroCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.api.addMatricola(
        widget.prodottoId,
        numero: numero,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      widget.onSaved();
      if (mounted) {
        showAppToast(context, message: 'Matricola aggiunta', tone: ToastTone.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
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
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            AppSpacing.pagePadding,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: SheetHandle(),
            ),
            Text('Aggiungi matricola', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            AppTextField(label: 'Numero di serie *', hint: 'Es. SN-00123', controller: _numeroCtrl),
            const SizedBox(height: 16),
            AppTextField(label: 'Note', controller: _noteCtrl),
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
      ),
    );
  }
}
