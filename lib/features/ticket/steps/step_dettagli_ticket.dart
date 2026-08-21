// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_text_field.dart';
import '../new_ticket_form_state.dart';
import '../ticket_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 — Dettagli Ticket
//
// Title (required), description (optional), type (required).
// ══════════════════════════════════════════════════════════════════════════════

class StepDettagliTicket extends ConsumerStatefulWidget {
  const StepDettagliTicket({super.key, required this.state, required this.onChanged});

  final NewTicketFormState state;
  final ValueChanged<NewTicketFormState> onChanged;

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
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null,
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
        _SectionLabel(text: 'Tipo *'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
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
          validator: (v) => v == null ? 'Campo obbligatorio' : null,
        ),
      ],
    );
  }
}

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
