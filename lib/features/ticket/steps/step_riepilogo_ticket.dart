// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/key_val.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../new_ticket_form_state.dart';
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      children: [
        // ── Summary ────────────────────────────────────────────────────────
        VetroCard(
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
              KeyVal(
                label: 'Tipo',
                value: typeName ?? '—',
                valueColor: state.typeId == null ? context.colors.red : null,
              ),
              if (statusName != null) KeyVal(label: 'Stato', value: statusName),
              KeyVal(label: 'Priorità', value: state.priority),
              if (state.description != null && state.description!.isNotEmpty)
                KeyVal(label: 'Descrizione', value: state.description!),
              KeyVal(
                label: 'Assegnato a',
                value: state.assignedUserId != null ? 'Tecnico selezionato' : 'Nessuna assegnazione',
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
