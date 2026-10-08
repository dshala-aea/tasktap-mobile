// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/key_val.dart';
import '../../../data/reference/reference_option.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../new_ticket_form_state.dart';
import '../reference_providers.dart';
import '../ticket_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Riepilogo
//
// Summary of all selections before submitting.
// ══════════════════════════════════════════════════════════════════════════════

class StepRiepilogoTicket extends ConsumerWidget {
  const StepRiepilogoTicket({
    super.key,
    required this.state,
    required this.onSubmit,
    this.isSubmitting = false,
  });

  final NewTicketFormState state;
  final VoidCallback onSubmit;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(allCustomersProvider);
    final locationsAsync = ref.watch(allLocationsProvider);
    final statusMapAsync = ref.watch(ticketStatusMapProvider);
    final typeMapAsync = ref.watch(ticketTypeMapProvider);

    final customers = customersAsync.valueOrNull ?? [];
    final locations = locationsAsync.valueOrNull ?? [];
    final statusMap = statusMapAsync.valueOrNull ?? {};
    final typeMap = typeMapAsync.valueOrNull ?? {};

    final customerName = customers
        .where((c) => c.id == state.customerId)
        .map((c) => c.companyName)
        .firstOrNull;

    final locationName = locations
        .where((l) => l.id == state.locationId)
        .map((l) => l.name)
        .firstOrNull;

    final typeName = state.typeId != null ? typeMap[state.typeId] : null;
    final statusName = state.statusId != null ? statusMap[state.statusId] : null;

    // The references, resolved to the same labels the pickers show — a technician confirming a
    // ticket should read "Manutenzione N-1", not a GUID (the complaint ticket_detail_screen.dart
    // already records for assignedUserId). Read from the same mirrored providers the pickers read,
    // so a label can never disagree with the row it came from.
    final refs = _referenceLabels(ref, state);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      children: [
        // ── Summary ────────────────────────────────────────────────────────
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Column(
            children: [
              if (state.title != null && state.title!.isNotEmpty)
                KeyVal(label: 'Titolo', value: state.title!),
              KeyVal(
                label: 'Cliente',
                value: customerName ?? '—',
                valueColor: state.customerId == null ? context.colors.red : null,
              ),
              KeyVal(
                label: 'Sede',
                value: locationName ?? '—',
                valueColor: state.locationId == null ? context.colors.red : null,
              ),
              if (refs.contract != null) KeyVal(label: 'Contratto', value: refs.contract!),
              if (refs.commessa != null) KeyVal(label: 'Commessa', value: refs.commessa!),
              KeyVal(
                label: 'Tipo',
                value: typeName ?? '—',
                valueColor: state.typeId == null ? context.colors.red : null,
              ),
              if (refs.prodotti.isNotEmpty)
                KeyVal(label: 'Prodotti assistenza', value: refs.prodotti.join(', ')),
              if (statusName != null) KeyVal(label: 'Stato', value: statusName),
              KeyVal(label: 'Priorità', value: state.priority),
              if (state.description != null && state.description!.isNotEmpty)
                KeyVal(label: 'Descrizione', value: state.description!),
              KeyVal(
                label: 'Assegnato a',
                value: state.assignedUserId != null
                    ? 'Tecnico selezionato'
                    : 'Nessuna assegnazione',
                showDivider: false,
              ),
            ],
          ),
        ),

        // ── Submit ─────────────────────────────────────────────────────────
        const SizedBox(height: 32),
        AppButton(
          label: 'Crea ticket',
          onPressed: isSubmitting ? null : onSubmit,
          isLoading: isSubmitting,
        ),
      ],
    );
  }
}

/// Resolves the wizard's reference ids to the labels its pickers show, through the same mirrored
/// providers the pickers read — never a second rendering of a contract's or a product's name.
///
/// An id no label resolves is dropped rather than printed: the whole point of this block is that a
/// technician confirming a ticket reads "Manutenzione N-1", not a GUID, and a row that cannot be
/// resolved is better absent than misread as a name. A `null` customer has no references to
/// resolve — they were cleared with it (see `step_cliente_sede.dart`).
({String? contract, String? commessa, List<String> prodotti}) _referenceLabels(
  WidgetRef ref,
  NewTicketFormState state,
) {
  final customerId = state.customerId;
  if (customerId == null) {
    return (contract: null, commessa: null, prodotti: const <String>[]);
  }

  String? labelOf(List<ReferenceOption> options, String id) =>
      options.where((o) => o.id == id).map((o) => o.label).firstOrNull;

  final contracts = ref.watch(localContractsProvider(customerId)).valueOrNull ?? const [];
  final commesse = ref.watch(localCommesseProvider(customerId)).valueOrNull ?? const [];
  final prodotti = ref.watch(localProdottiProvider(customerId)).valueOrNull ?? const [];

  return (
    contract: state.contractId == null ? null : labelOf(contracts, state.contractId!),
    commessa: state.commessaId == null ? null : labelOf(commesse, state.commessaId!),
    prodotti: [for (final id in state.prodottoAssistenzaIds) ?labelOf(prodotti, id)],
  );
}
