// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/local/app_database.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../new_ticket_form_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 — Cliente + Sede
//
// Select a customer from the Drift cache, then a location (cascading filter).
// ══════════════════════════════════════════════════════════════════════════════

class StepClienteSede extends ConsumerStatefulWidget {
  const StepClienteSede({
    super.key,
    required this.state,
    required this.onChanged,
  });

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
        ? allLocations
            .where((l) => l.customerId == widget.state.customerId)
            .toList()
        : <Location>[];

    final selectedCustomer = customers
        .where((c) => c.id == widget.state.customerId)
        .firstOrNull;

    final selectedLocation = locations
        .where((l) => l.id == widget.state.locationId)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 24),
      children: [
        // ── Customer ──────────────────────────────────────────────────────
        _SectionLabel(text: 'Cliente *'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: widget.state.customerId,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'Seleziona cliente…',
          ),
          items: customers
              .map(
                (c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.companyName),
                ),
              )
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

        if (selectedCustomer != null) ...[
          const SizedBox(height: 12),
          _CustomerSummary(customer: selectedCustomer),
        ],

        // ── Location ──────────────────────────────────────────────────────
        const SizedBox(height: 24),
        _SectionLabel(text: 'Sede *'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: widget.state.locationId,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: widget.state.customerId != null
                ? 'Seleziona sede…'
                : 'Prima seleziona un cliente',
          ),
          items: locations
              .map(
                (l) => DropdownMenuItem(
                  value: l.id,
                  child: Text(l.name),
                ),
              )
              .toList(),
          onChanged: widget.state.customerId != null
              ? (id) => widget.onChanged(widget.state.copyWith(locationId: id))
              : null,
          validator: (v) => v == null ? 'Campo obbligatorio' : null,
        ),

        if (selectedLocation != null) ...[
          const SizedBox(height: 12),
          _LocationSummary(location: selectedLocation),
        ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.BG3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer.contactPerson != null &&
              customer.contactPerson!.isNotEmpty)
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
      if (location.address != null && location.address!.isNotEmpty)
        location.address!,
      if (location.city != null && location.city!.isNotEmpty) location.city!,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.BG3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.isNotEmpty)
            _InfoRow(label: 'Indirizzo', value: parts.join(', ')),
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
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.DARK,
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.MUTED),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.DARK),
            ),
          ),
        ],
      ),
    );
  }
}
