// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/extension_fields_section.dart';
import '../new_ticket_form_state.dart';
import '../ticket_providers.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 — Dettagli Ticket
//
// Title (required), description (optional), type (required).
// ══════════════════════════════════════════════════════════════════════════════

class StepDettagliTicket extends ConsumerStatefulWidget {
  const StepDettagliTicket({
    super.key,
    required this.state,
    required this.onChanged,
    this.ticketId,
  });

  final NewTicketFormState state;
  final ValueChanged<NewTicketFormState> onChanged;

  /// The ticket being edited, or null while creating a new one. Gates [ExtensionFieldsSection]:
  /// tenant-defined custom fields save through `PUT /extension-fields/ticket/{id}/values`, which
  /// needs a real ticket id — the create wizard has none until the ticket is actually submitted,
  /// so the section only appears once EditTicketScreen hands this in.
  final String? ticketId;

  @override
  ConsumerState<StepDettagliTicket> createState() => _StepDettagliTicketState();
}

class _StepDettagliTicketState extends ConsumerState<StepDettagliTicket> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.state.title ?? '');
    _descCtrl = TextEditingController(text: widget.state.description ?? '');
  }

  @override
  void didUpdateWidget(covariant StepDettagliTicket oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers if the state was reset externally (e.g. back nav).
    if (oldWidget.state.title != widget.state.title && _titleCtrl.text != widget.state.title) {
      _titleCtrl.text = widget.state.title ?? '';
    }
    if (oldWidget.state.description != widget.state.description &&
        _descCtrl.text != widget.state.description) {
      _descCtrl.text = widget.state.description ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(ticketTypeMapProvider);
    final types = typesAsync.valueOrNull ?? {};

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      children: [
        // ── Title ──────────────────────────────────────────────────────────
        AppTextField(
          label: 'Titolo *',
          hint: 'Es. Manutenzione periodica',
          controller: _titleCtrl,
          onChanged: (v) => widget.onChanged(widget.state.copyWith(title: v)),
        ),

        const SizedBox(height: 20),

        // ── Description ────────────────────────────────────────────────────
        AppTextField.multiline(
          label: 'Descrizione',
          hint: 'Dettagli aggiuntivi…',
          controller: _descCtrl,
          onChanged: (v) => widget.onChanged(widget.state.copyWith(description: v)),
          maxLines: 4,
        ),

        const SizedBox(height: 24),

        // ── Type ───────────────────────────────────────────────────────────
        AppFieldShell(
          label: 'Tipo *',
          child: DropdownButtonFormField<int>(
            // initialValue only applies on first build. This screen already
            // resyncs its text controllers in didUpdateWidget when state is
            // reset externally (e.g. wizard back-navigation); key this field
            // by value so it gets the same resync via a fresh initialValue.
            key: ValueKey('tipo-${widget.state.typeId}'),
            initialValue: widget.state.typeId,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Seleziona tipo…'),
            items: types.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (id) =>
                id != null ? widget.onChanged(widget.state.copyWith(typeId: id)) : null,
          ),
        ),

        const SizedBox(height: 24),

        // ── Priority ───────────────────────────────────────────────────────
        AppFieldShell(
          label: 'Priorità',
          child: DropdownButtonFormField<String>(
            key: ValueKey('priorita-${widget.state.priority}'),
            initialValue: widget.state.priority,
            isExpanded: true,
            items: kTicketPriorities
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (p) =>
                p != null ? widget.onChanged(widget.state.copyWith(priority: p)) : null,
          ),
        ),

        if (widget.ticketId != null)
          ExtensionFieldsSection(entityType: 'ticket', entityId: widget.ticketId!),
      ],
    );
  }
}
