// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/error_message.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../../ticket/steps/step_assegnazione.dart' show techniciansProvider;
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin contract detail — read-only with edit FAB.
///
/// Feature audit module #11: Gap A's new fields (numero, codice, tipo, externalId, autoRenewal,
/// scadenzaGiorni, condizioni, prodottoAssistenzaId) are now shown; Gap B adds a delete action
/// behind a confirm dialog; Gap C adds a "Genera pianificazione" trigger for
/// `POST /contracts/{id}/genera-schedule`, previously entirely unreachable from mobile.
class AdminContractDetailScreen extends ConsumerWidget {
  const AdminContractDetailScreen({super.key, required this.contract});

  final Map<String, dynamic> contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = contract['id'] as String? ?? '';
    final name = contract['name'] as String? ?? '';
    final numero = contract['numero'] as String? ?? '';
    final codice = contract['codice'] as String? ?? '';
    final tipo = contract['tipo'] as String? ?? '';
    final externalId = contract['externalId'] as String? ?? '';
    final prodottoAssistenzaId = contract['prodottoAssistenzaId'] as String?;
    final condizioni = contract['condizioni'] as String? ?? '';
    final description = contract['description'] as String? ?? '';
    final notes = contract['notes'] as String? ?? '';
    final price = contract['price'] as num?;
    final startDate = contract['startDate'] as String?;
    final endDate = contract['endDate'] as String?;
    final frequencyValue = contract['frequencyValue'] as int? ?? 1;
    // The backend serializes ContractFrequencyUnit as a STRING ("Days"/"Months"/"Years") — see
    // AdminApiClient.createContract's doc comment.
    final frequencyUnit = contract['frequencyUnit'] as String? ?? 'Months';
    final autoRenewal = contract['autoRenewal'] as bool? ?? false;
    final scadenzaGiorni = contract['scadenzaGiorni'] as int?;

    final startLabel = startDate != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(startDate))
        : '—';
    final endLabel = endDate != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(endDate))
        : 'Nessuna data fine';
    final priceLabel = price != null ? '€${price.toStringAsFixed(2)}' : '—';
    final freqLabel = '$frequencyValue ${_frequencyUnitLabel(frequencyUnit)}';
    final isActive = contract['isActive'] as bool? ?? true;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.fabSafeBottom),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>(
              '/altro/contratti/${contract['id']}/modifica',
              extra: contract,
            );
          },
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ScreenHeader(
                    title: name,
                    showBack: true,
                    actions: id.isEmpty
                        ? const []
                        : [
                            HeaderIconBtn(
                              icon: LucideIcons.trash2,
                              label: 'Elimina contratto',
                              glass: true,
                              onTap: () => _deleteContract(context, ref, id, name),
                            ),
                          ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.pagePadding),
                    child: VetroCard(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.md,
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                StatusPill(stato: isActive ? 'Attivo' : 'Inattivo', outlined: true),
                              ],
                            ),
                          ),
                          Divider(height: 1, thickness: 1, color: context.colors.borderLight),
                          KeyVal(label: 'Nome', value: name),
                          KeyVal(
                            label: 'Numero contratto',
                            value: numero.isNotEmpty ? numero : '—',
                          ),
                          KeyVal(label: 'Codice', value: codice.isNotEmpty ? codice : '—'),
                          KeyVal(label: 'Tipo', value: tipo.isNotEmpty ? tipo : '—'),
                          KeyVal(
                            label: 'Prodotto in assistenza',
                            value: prodottoAssistenzaId != null && prodottoAssistenzaId.isNotEmpty
                                ? prodottoAssistenzaId
                                : '—',
                          ),
                          KeyVal(
                            label: 'Descrizione',
                            value: description.isNotEmpty ? description : '—',
                          ),
                          KeyVal(label: 'Data inizio', value: startLabel),
                          KeyVal(label: 'Data fine', value: endLabel),
                          KeyVal(label: 'Frequenza', value: freqLabel),
                          KeyVal(label: 'Prezzo', value: priceLabel),
                          KeyVal(
                            label: 'Preavviso scadenza',
                            value: scadenzaGiorni != null ? '$scadenzaGiorni giorni' : '—',
                          ),
                          KeyVal(label: 'Rinnovo automatico', value: autoRenewal ? 'Sì' : 'No'),
                          KeyVal(
                            label: 'Condizioni',
                            value: condizioni.isNotEmpty ? condizioni : '—',
                          ),
                          KeyVal(
                            label: 'ID esterno',
                            value: externalId.isNotEmpty ? externalId : '—',
                          ),
                          KeyVal(
                            label: 'Note',
                            value: notes.isNotEmpty ? notes : '—',
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Genera pianificazione (Gap C) ───────────────────────────────
                if (id.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: VetroButton(
                        label: 'Genera pianificazione',
                        secondary: true,
                        onPressed: () => _openGeneraScheduleDialog(context, ref, contract),
                      ),
                    ),
                  ),

                SliverPadding(padding: EdgeInsets.only(bottom: context.fabSafeBottom)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _frequencyUnitLabel(String unit) => switch (unit) {
    'Days' => 'giorni',
    'Years' => 'anni',
    _ => 'mesi',
  };
}

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

/// Opens the "Genera pianificazione" confirmation dialog (Gap C). Materializing recurring
/// Schedule rows is a real write with real consequences (up to a year of rows in one call), so
/// this asks for the one thing the backend genuinely requires and cannot default — an assignee —
/// before firing, rather than a bare "sei sicuro?" confirm.
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

    return AlertDialog(
      title: const Text('Generare la pianificazione?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verranno create le pianificazioni ricorrenti del contratto. ${widget.rangeLabel}.'),
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
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        TextButton(
          onPressed: _selectedUserId == null ? null : () => Navigator.pop(context, _selectedUserId),
          child: const Text('Genera'),
        ),
      ],
    );
  }
}
