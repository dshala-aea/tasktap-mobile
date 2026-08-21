// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
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
        // ── Title ──────────────────────────────────────────────────────────
        if (state.title != null && state.title!.isNotEmpty) ...[
          _SummaryRow(label: 'Titolo', value: state.title!),
          const SizedBox(height: 12),
        ],

        // ── Customer ───────────────────────────────────────────────────────
        _SummaryRow(
          label: 'Cliente',
          value: customerName ?? '—',
          isMissing: state.customerId == null,
        ),
        const SizedBox(height: 12),

        // ── Location ───────────────────────────────────────────────────────
        _SummaryRow(label: 'Sede', value: locationName ?? '—', isMissing: state.locationId == null),
        const SizedBox(height: 12),

        // ── Type ───────────────────────────────────────────────────────────
        _SummaryRow(label: 'Tipo', value: typeName ?? '—', isMissing: state.typeId == null),
        const SizedBox(height: 12),

        // ── Status ─────────────────────────────────────────────────────────
        if (statusName != null) ...[
          _SummaryRow(label: 'Stato', value: statusName),
          const SizedBox(height: 12),
        ],

        // ── Description ────────────────────────────────────────────────────
        if (state.description != null && state.description!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SummaryRow(label: 'Descrizione', value: state.description!),
        ],

        // ── Assignment ─────────────────────────────────────────────────────
        const SizedBox(height: 12),
        _SummaryRow(
          label: 'Assegnato a',
          value: state.assignedUserId != null ? 'Tecnico selezionato' : 'Nessuna assegnazione',
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

// ══════════════════════════════════════════════════════════════════════════════
// Summary row
// ══════════════════════════════════════════════════════════════════════════════

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.isMissing = false});

  final String label;
  final String value;
  final bool isMissing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: context.colors.bg3, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isMissing ? context.colors.red : context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
