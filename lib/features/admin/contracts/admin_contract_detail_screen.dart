// dart format width=100
import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm, countAll;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/time/business_time.dart' show formatWorkDate, parseDateOnly;
import '../../../core/time/business_time_providers.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/detail/detail_activity_timeline.dart';
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../ticket/steps/step_assegnazione.dart' show techniciansProvider;
import '../../ticket/ticket_providers.dart' show ticketStatusMapProvider;
import '../../../presentation/providers/schedule_providers.dart'
    show customerByIdProvider, locationByIdProvider;
import '../admin_api_client.dart';

/// The tickets the contract covers, from the local mirror.
///
/// A contract has no product or schedule relation in the local schema: the only join that
/// survives offline is `Tickets.contractId`. Reading it keeps the Attività section honest — it
/// shows the interventions this device actually knows about, and hides the section when none
/// are mirrored rather than claiming the contract has never been used.
final _contractTicketsProvider = StreamProvider.autoDispose.family<List<Ticket>, String>((
  ref,
  contractId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.contractId.equals(contractId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// How many interventions the Attività section shows before hiding the rest.
const int _activityLimit = 5;

/// The number of schedules attached to the contract's tickets, from the same local mirror.
///
/// `Schedules` has no `contractId` column; a schedule reaches its contract through the ticket it
/// covers. Counting in SQL keeps the relation cheap even when the contract has years of rows.
final _contractScheduleCountProvider = StreamProvider.autoDispose.family<int, String>((
  ref,
  contractId,
) {
  final db = ref.watch(appDatabaseProvider);
  final ticketIds = db.selectOnly(db.tickets)
    ..addColumns([db.tickets.id])
    ..where(db.tickets.contractId.equals(contractId));
  final count = countAll();
  final query = db.selectOnly(db.schedules)
    ..addColumns([count])
    ..where(db.schedules.ticketId.isInQuery(ticketIds));
  return query.map((row) => row.read(count) ?? 0).watchSingle();
});

enum _ContractState { inScadenza, attivo, scaduto, inattivo }

extension on _ContractState {
  String get label => switch (this) {
    _ContractState.inScadenza => 'In scadenza',
    _ContractState.attivo => 'Attivo',
    _ContractState.scaduto => 'Scaduto',
    _ContractState.inattivo => 'Inattivo',
  };

  DetailStatusTone get tone => switch (this) {
    _ContractState.inScadenza => DetailStatusTone.warn,
    _ContractState.attivo => DetailStatusTone.good,
    _ContractState.scaduto => DetailStatusTone.bad,
    _ContractState.inattivo => DetailStatusTone.bad,
  };
}

/// Admin contract detail — the wave-0 summary shell.
///
/// Hero + `Modifica`, then Sintesi (scadenze) → Relazioni → Attività → Documenti. Empty sections
/// are hidden by the shell. The delete action stays in the header; `Genera pianificazione` stays a
/// hero secondary action, so there is no FAB competing with the hero's primary action.
class AdminContractDetailScreen extends ConsumerWidget {
  const AdminContractDetailScreen({super.key, required this.contract});

  final Map<String, dynamic> contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = _string(contract['id']);
    if (id == null || id.isEmpty) {
      // The route carries the contract as `extra`; a deep link without it has nothing to show.
      return const DetailScaffold.unavailable(
        screenTitle: 'Contratto',
        icon: LucideIcons.fileX,
        title: 'Contratto non disponibile',
        reason: "Apri il contratto dall'elenco per vederne i dettagli.",
      );
    }
    return _ContractDetailBody(contract: contract, contractId: id);
  }
}

class _ContractDetailBody extends ConsumerWidget {
  const _ContractDetailBody({required this.contract, required this.contractId});

  final Map<String, dynamic> contract;
  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = _string(contract['name']);
    final numero = _string(contract['numero']);
    final codice = _string(contract['codice']);
    final tipo = _string(contract['tipo']);
    final descrizione = _string(contract['description']);
    final condizioni = _string(contract['condizioni']);
    final externalId = _string(contract['externalId']);
    final note = _string(contract['notes']);
    final customerId = _string(contract['customerId']);
    final locationId = _string(contract['locationId']);
    final startDate = parseDateOnly(contract['startDate']);
    final endDate = parseDateOnly(contract['endDate']);
    final price = _number(contract['price']);
    final frequencyValue = _int(contract['frequencyValue']);
    final frequencyUnit = _string(contract['frequencyUnit']);
    final autoRenewal = contract['autoRenewal'] is bool ? contract['autoRenewal'] as bool : null;
    final scadenzaGiorni = _int(contract['scadenzaGiorni']);
    final isActive = contract['isActive'] is bool ? contract['isActive'] as bool : true;

    final businessTime = ref.watch(businessTimeProvider);
    final state = _stateFor(
      endDate: endDate,
      isActive: isActive,
      today: businessTime.businessToday(),
    );

    final customer = customerId == null
        ? null
        : ref.watch(customerByIdProvider(customerId)).valueOrNull;
    final location = locationId == null
        ? null
        : ref.watch(locationByIdProvider(locationId)).valueOrNull;
    final tickets = ref.watch(_contractTicketsProvider(contractId)).valueOrNull ?? const <Ticket>[];
    final scheduleCount = ref.watch(_contractScheduleCountProvider(contractId)).valueOrNull ?? 0;
    final statusNames = ref.watch(ticketStatusMapProvider).valueOrNull ?? const <int, String>{};

    final endLabel = endDate == null ? 'Nessuna scadenza' : 'scade ${_formatDate(endDate)}';
    final factParts = <String>[
      if (customer != null && customer.companyName.trim().isNotEmpty) customer.companyName,
      endLabel,
      if (autoRenewal != null) autoRenewal ? 'rinnovo auto' : 'rinnovo manuale',
    ];

    final sintesiFacts = <DetailFact>[
      if (scadenzaGiorni != null) DetailFact(label: 'Preavviso', value: '$scadenzaGiorni giorni'),
      if (frequencyValue != null && frequencyUnit != null)
        DetailFact(label: 'Frequenza', value: _frequencyLabel(frequencyValue, frequencyUnit)),
      if (startDate != null) DetailFact(label: 'Inizio', value: _formatDate(startDate)),
      if (price != null) DetailFact(label: 'Prezzo', value: _formatCurrency(price)),
      if (numero != null && numero.isNotEmpty) DetailFact(label: 'Numero', value: numero),
      if (codice != null && codice.isNotEmpty) DetailFact(label: 'Codice', value: codice),
      if (tipo != null && tipo.isNotEmpty) DetailFact(label: 'Tipo', value: tipo),
      if (condizioni != null) DetailFact(label: 'Condizioni', value: condizioni),
      if (externalId != null) DetailFact(label: 'ID esterno', value: externalId),
    ];

    final relations = <_Relation>[
      if (customer != null && customerId != null && customer.companyName.trim().isNotEmpty)
        _Relation(
          title: 'Cliente',
          meta: customer.companyName,
          onTap: () => context.push(AppRoutes.clientiDetail(customerId)),
        ),
      if (location != null && locationId != null && location.name.trim().isNotEmpty)
        _Relation(
          title: 'Sede',
          meta: location.name,
          onTap: () => context.push('/altro/sedi/$locationId'),
        ),
      if (scheduleCount > 0)
        _Relation(
          title: 'Pianificazioni',
          meta: scheduleCount == 1 ? '1 pianificazione' : '$scheduleCount pianificazioni',
        ),
    ];

    final shownTickets = tickets.take(_activityLimit);
    final activityEvents = [
      for (final ticket in shownTickets)
        DetailActivityEvent(
          time: _formatDate(businessTime.businessDateOf(ticket.createdAt)),
          title: ticket.title.isNotEmpty ? ticket.title : 'Intervento',
          meta: statusNames[ticket.statusId],
        ),
    ];

    return DetailScaffold(
      screenTitle: 'Contratto',
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · contratto',
        // The prototype renders the whole ref in red; the split kicker/context would mute half.
        kicker: 'Summary · contratto',
        title: name == null || name.isEmpty
            ? (numero == null || numero.isEmpty ? 'Contratto' : numero)
            : name,
        status: DetailStatus(label: state.label, tone: state.tone),
        subtitle: factParts.join(' · '),
        primaryAction: DetailAction(
          label: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/contratti/$contractId/modifica', extra: contract);
          },
        ),
        secondaryActions: [
          DetailAction(
            label: 'Genera pianificazione',
            icon: const Icon(LucideIcons.calendarDays),
            onPressed: () => _openGeneraScheduleDialog(context, ref, contract),
          ),
        ],
      ),
      headerActions: [
        HeaderIconBtn(
          icon: LucideIcons.trash2,
          label: 'Elimina contratto',
          glass: true,
          onTap: () => _deleteContract(
            context,
            ref,
            contractId,
            name == null || name.isEmpty ? 'questo contratto' : name,
          ),
        ),
      ],
      sections: [
        DetailSectionData(
          title: 'Sintesi',
          isEmpty: sintesiFacts.isEmpty && descrizione == null && note == null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailFactsGrid(facts: sintesiFacts),
              if (descrizione != null)
                Padding(
                  padding: EdgeInsets.only(top: sintesiFacts.isEmpty ? 0 : AppSpacing.md),
                  child: _ContractTextBlock(label: 'Descrizione', value: descrizione),
                ),
              if (note != null)
                Padding(
                  padding: EdgeInsets.only(
                    top: sintesiFacts.isEmpty && descrizione == null ? 0 : AppSpacing.md,
                  ),
                  child: _ContractTextBlock(label: 'Note', value: note),
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
                  meta: relations[i].onTap == null ? relations[i].meta : null,
                  trailing: relations[i].onTap == null
                      ? null
                      : _RelationTrailing(meta: relations[i].meta),
                  onTap: relations[i].onTap,
                  showDivider: i < relations.length - 1,
                ),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Attività',
          isEmpty: activityEvents.isEmpty,
          trailing: tickets.length > _activityLimit
              ? DetailSectionMeta('ultimi $_activityLimit di ${tickets.length}')
              : null,
          child: DetailActivityTimeline(events: activityEvents),
        ),
      ],
    );
  }

  static _ContractState _stateFor({
    required DateTime? endDate,
    required bool isActive,
    required DateTime today,
  }) {
    if (endDate != null && endDate.isBefore(today)) {
      return _ContractState.scaduto;
    }
    if (!isActive) return _ContractState.inattivo;
    if (endDate != null &&
        endDate.isAfter(today) &&
        !endDate.isAfter(today.add(const Duration(days: 30)))) {
      return _ContractState.inScadenza;
    }
    return _ContractState.attivo;
  }

  static String _formatDate(DateTime date) => formatWorkDate(date, 'dd/MM/yyyy');

  static String _formatCurrency(num price) =>
      NumberFormat.currency(locale: 'it_IT', symbol: '€').format(price);

  static String _frequencyLabel(int value, String unit) {
    if (value != 1) return '$value ${_frequencyUnitLabel(unit)}';
    final singular = switch (unit) {
      'Days' => 'giorno',
      'Years' => 'anno',
      _ => 'mese',
    };
    return '1 $singular';
  }

  static String _frequencyUnitLabel(String unit) => switch (unit) {
    'Days' => 'giorni',
    'Years' => 'anni',
    _ => 'mesi',
  };
}

/// Long free text under the Sintesi facts grid: a mono label above wrapped prose.
class _ContractTextBlock extends StatelessWidget {
  const _ContractTextBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
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
          value,
          style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5, height: 1.4, color: colors.ink),
        ),
      ],
    );
  }
}

class _Relation {
  const _Relation({required this.title, required this.meta, this.onTap});

  final String title;
  final String meta;
  final VoidCallback? onTap;
}

/// The right-hand side of a tappable relation row: the mono meta plus the chevron that says the
/// row opens something. Non-tappable rows keep `DetailLinkRow`'s own meta treatment.
class _RelationTrailing extends StatelessWidget {
  const _RelationTrailing({required this.meta});

  final String meta;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            meta.toUpperCase(),
            maxLines: 2,
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
        const SizedBox(width: 6),
        Icon(LucideIcons.chevronRight, size: 14, color: context.colors.inkMuted),
      ],
    );
  }
}

String? _string(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

num? _number(Object? value) => value is num
    ? value
    : value is String
    ? num.tryParse(value)
    : null;

int? _int(Object? value) => value is num
    ? value.toInt()
    : value is String
    ? int.tryParse(value)
    : null;

/// Delete confirmation dialog + API call — dialog itself is the shared `confirmDeleteDialog`.
/// `humanErrorMessage` already surfaces the backend's 409 message
/// ("Impossibile eliminare: il contratto ha prodotti, pianificazioni o interventi collegati")
/// verbatim when every foreign key referencing this contract is `DeleteBehavior.Restrict`.
Future<void> _deleteContract(
  BuildContext context,
  WidgetRef ref,
  String contractId,
  String name,
) async {
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Eliminare il contratto?',
    message:
        'Il contratto "$name" verrà eliminato definitivamente. L\'operazione non può essere '
        'annullata.',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteContract(contractId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      showAppToast(context, message: 'Contratto eliminato', tone: ToastTone.success);
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'eliminare il contratto'),
        tone: ToastTone.error,
      );
    }
  }
}

/// Opens the "Genera pianificazione" confirmation dialog. Materializing recurring Schedule rows
/// is a real write with real consequences (up to a year of rows in one call), so this asks for the
/// one thing the backend genuinely requires and cannot default — an assignee — before firing.
Future<void> _openGeneraScheduleDialog(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> contract,
) async {
  final contractId = contract['id'] as String;
  final startDate = contract['startDate'] as String?;
  final endDate = contract['endDate'] as String?;
  final rangeLabel = _generaScheduleRangeLabel(startDate, endDate);

  final userId = await showDialog<String>(
    context: context,
    builder: (ctx) => _GeneraScheduleDialog(rangeLabel: rangeLabel),
  );
  if (userId == null || !context.mounted) return;
  if (!ensureOnlineOrWarn(context, ref)) return;

  try {
    final result = await ref
        .read(adminApiClientProvider)
        .generaSchedule(contractId, userId: userId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      showAppToast(
        context,
        message: result.message.isNotEmpty
            ? result.message
            : '${result.created} pianificazioni generate.',
        tone: ToastTone.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'generare la pianificazione'),
        tone: ToastTone.error,
      );
    }
  }
}

/// Mirrors `ContractsController.GeneraSchedule`'s own fallback: `dateFrom ?? contract.StartDate`
/// and `dateTo ?? contract.EndDate ?? dateFrom.AddMonths(3)` — shown so the confirm dialog states
/// what will actually be generated, not just that something will be.
String _generaScheduleRangeLabel(String? startDate, String? endDate) {
  final fmt = DateFormat('dd/MM/yyyy');
  final from = startDate != null ? DateTime.parse(startDate) : null;
  final fromLabel = from != null ? fmt.format(from) : '—';
  if (endDate != null) {
    return 'Dal $fromLabel al ${fmt.format(DateTime.parse(endDate))}';
  }
  if (from != null) {
    return 'Dal $fromLabel per 3 mesi (il contratto non ha una data fine)';
  }
  return 'Intervallo del contratto';
}

/// Technician picker + confirm — the one input `GeneraScheduleRequest.UserId` genuinely requires
/// (a plain, non-nullable `Guid`; every generated Schedule needs an assignee). Fed by the same
/// `techniciansProvider` the schedule form's own "Tecnico" tab uses.
class _GeneraScheduleDialog extends ConsumerStatefulWidget {
  const _GeneraScheduleDialog({required this.rangeLabel});

  final String rangeLabel;

  @override
  ConsumerState<_GeneraScheduleDialog> createState() => _GeneraScheduleDialogState();
}

class _GeneraScheduleDialogState extends ConsumerState<_GeneraScheduleDialog> {
  String? _selectedUserId;

  @override
  Widget build(BuildContext context) {
    final techniciansAsync = ref.watch(techniciansProvider);
    final technicians = techniciansAsync.valueOrNull ?? [];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generare la pianificazione?',
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Verranno create le pianificazioni ricorrenti del contratto. ${widget.rangeLabel}.',
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.inkMuted),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Tecnico *',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedUserId,
                items: technicians
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedUserId = v),
                hint: const Text('Seleziona un tecnico'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(label: 'Annulla', onPressed: () => Navigator.pop(context)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Genera',
                    onPressed: _selectedUserId == null
                        ? null
                        : () => Navigator.pop(context, _selectedUserId),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
