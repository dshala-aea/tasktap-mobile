// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/rack.dart';
import '../../../data/local/app_database.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../new_ticket_form_state.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 — Cliente + Sede
//
// Select a customer from the Drift cache, then a location (cascading filter).
// ══════════════════════════════════════════════════════════════════════════════

class StepClienteSede extends ConsumerStatefulWidget {
  const StepClienteSede({super.key, required this.state, required this.onChanged});

  final NewTicketFormState state;
  final ValueChanged<NewTicketFormState> onChanged;

  @override
  ConsumerState<StepClienteSede> createState() => _StepClienteSedeState();
}

class _StepClienteSedeState extends ConsumerState<StepClienteSede> {
  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];

    // Filter locations by selected customer.
    final allLocationsAsync = ref.watch(allLocationsProvider);
    final allLocations = allLocationsAsync.valueOrNull ?? [];
    final locations = widget.state.customerId != null
        ? allLocations.where((l) => l.customerId == widget.state.customerId).toList()
        : <Location>[];

    final selectedCustomer = customers.where((c) => c.id == widget.state.customerId).firstOrNull;

    final selectedLocation = locations.where((l) => l.id == widget.state.locationId).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      children: [
        // ── Customer ──────────────────────────────────────────────────────
        _SectionLabel(text: 'Cliente *'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // initialValue only applies on first build; this field's value can
          // be reset externally (e.g. wizard back-navigation), so key it by
          // the value to force a fresh widget — and thus a fresh
          // initialValue — whenever it changes underneath us.
          key: ValueKey('cliente-${widget.state.customerId}'),
          initialValue: widget.state.customerId,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Seleziona cliente…'),
          items: customers
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)))
              .toList(),
          onChanged: (id) {
            widget.onChanged(
              widget.state.copyWith(
                customerId: id,
                locationId: null, // reset location when customer changes
              ),
            );
          },
          validator: (v) => v == null ? 'Campo obbligatorio' : null,
        ),

        const SizedBox(height: 12),
        // Rule 3 of the rack grammar: an empty slot is drawn, not left blank. Before a customer
        // is picked this is what the step has to say — the field above is the only content, and
        // the gap down to "Avanti" used to read as unfinished rather than "not filled in yet".
        if (selectedCustomer != null)
          _CustomerSummary(customer: selectedCustomer)
        else
          const ShadowBoard(
            label: 'Cliente non ancora selezionato',
            icon: LucideIcons.briefcase,
            height: 72,
          ),

        // ── Location ──────────────────────────────────────────────────────
        const SizedBox(height: 24),
        _SectionLabel(text: 'Sede *'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // Same reasoning as the customer field above — the customer
          // dropdown's onChanged resets locationId externally (line ~78),
          // so this must be rekeyed to pick up the reset.
          key: ValueKey('sede-${widget.state.locationId}'),
          initialValue: widget.state.locationId,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: widget.state.customerId != null
                ? 'Seleziona sede…'
                : 'Prima seleziona un cliente',
          ),
          items: locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
          onChanged: widget.state.customerId != null
              ? (id) => widget.onChanged(widget.state.copyWith(locationId: id))
              : null,
          validator: (v) => v == null ? 'Campo obbligatorio' : null,
        ),

        const SizedBox(height: 12),
        if (selectedLocation != null)
          _LocationSummary(location: selectedLocation)
        else if (widget.state.customerId != null)
          const ShadowBoard(
            label: 'Sede non ancora selezionata',
            icon: LucideIcons.mapPin,
            height: 72,
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline summary cards
// ══════════════════════════════════════════════════════════════════════════════

class _CustomerSummary extends StatelessWidget {
  const _CustomerSummary({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: context.colors.bg3, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty)
            _InfoRow(label: 'Referente', value: customer.contactPerson!),
          if (customer.phone != null && customer.phone!.isNotEmpty)
            _InfoRow(label: 'Telefono', value: customer.phone!),
          if (customer.email != null && customer.email!.isNotEmpty)
            _InfoRow(label: 'Email', value: customer.email!),
        ],
      ),
    );
  }
}

class _LocationSummary extends StatelessWidget {
  const _LocationSummary({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (location.address != null && location.address!.isNotEmpty) location.address!,
      if (location.city != null && location.city!.isNotEmpty) location.city!,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: context.colors.bg3, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.isNotEmpty) _InfoRow(label: 'Indirizzo', value: parts.join(', ')),
          if (location.phone != null && location.phone!.isNotEmpty)
            _InfoRow(label: 'Telefono', value: location.phone!),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared small widgets
// ══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Sora',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: context.colors.ink,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text('$label: ', style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted)),
          Expanded(
            child: Text(value, style: AppTextStyles.bodySmall.copyWith(color: context.colors.ink)),
          ),
        ],
      ),
    );
  }
}
