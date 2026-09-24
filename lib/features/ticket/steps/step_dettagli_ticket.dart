// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_tappable.dart';
import '../../../core/widgets/extension_fields_section.dart';
import '../../admin/admin_widgets.dart';
import '../new_ticket_form_state.dart';
import '../ticket_providers.dart';
import 'step_assegnazione.dart' show techniciansProvider;
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

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
  late final TextEditingController _technicianNotesCtrl;
  late final TextEditingController _tagsCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.state.title ?? '');
    _descCtrl = TextEditingController(text: widget.state.description ?? '');
    _technicianNotesCtrl = TextEditingController(text: widget.state.technicianNotes ?? '');
    _tagsCtrl = TextEditingController(text: widget.state.tags.join(', '));
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
    if (oldWidget.state.technicianNotes != widget.state.technicianNotes &&
        _technicianNotesCtrl.text != widget.state.technicianNotes) {
      _technicianNotesCtrl.text = widget.state.technicianNotes ?? '';
    }
    if (oldWidget.state.tags != widget.state.tags &&
        _tagsCtrl.text != widget.state.tags.join(', ')) {
      _tagsCtrl.text = widget.state.tags.join(', ');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _technicianNotesCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.state.dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) widget.onChanged(widget.state.copyWith(dueDate: picked));
  }

  /// "Nessuno" pops `''` (never a real agent id) so it's distinguishable from dismissing the
  /// sheet without picking anything (pops `null`, which must leave the field untouched, not clear
  /// it — backing out of a picker is not the same gesture as explicitly clearing a field).
  static const _kNoneSentinel = '';

  Future<void> _pickAgent(List<Map<String, dynamic>> technicians) async {
    final pickedId = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const ValueKey('agent-picker-none'),
              title: const Text('Nessuno'),
              onTap: () => Navigator.of(sheetContext).pop(_kNoneSentinel),
            ),
            for (final tech in technicians)
              if ('${tech['firstName'] ?? ''} ${tech['lastName'] ?? ''}'.trim().isNotEmpty)
                ListTile(
                  key: ValueKey('agent-picker-${tech['id']}'),
                  title: Text('${tech['firstName'] ?? ''} ${tech['lastName'] ?? ''}'.trim()),
                  onTap: () => Navigator.of(sheetContext).pop(tech['id'] as String),
                ),
          ],
        ),
      ),
    );
    if (pickedId == null) return; // Dismissed without picking — leave the field as it was.
    widget.onChanged(
      pickedId == _kNoneSentinel
          ? widget.state.copyWith(clearAgentId: true)
          : widget.state.copyWith(agentId: pickedId),
    );
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

        const SizedBox(height: 24),

        // ── Scadenza ───────────────────────────────────────────────────────
        AdminDateField(
          label: 'Scadenza',
          value: widget.state.dueDate != null
              ? DateFormat('dd/MM/yyyy').format(widget.state.dueDate!)
              : 'Seleziona data',
          onTap: _pickDueDate,
        ),

        const SizedBox(height: 24),

        // ── Note tecnico ──────────────────────────────────────────────────
        AppTextField.multiline(
          key: const ValueKey('technician-notes-field'),
          label: 'Note tecnico',
          hint: 'Note per il tecnico assegnato…',
          controller: _technicianNotesCtrl,
          onChanged: (v) => widget.onChanged(widget.state.copyWith(technicianNotes: v)),
          maxLines: 3,
        ),

        const SizedBox(height: 24),

        // ── Riferimento ────────────────────────────────────────────────────
        // A contact-reference field, not the assignee (Tecnico, step_assegnazione.dart) — same
        // Users list, same reasoning as web's TicketCreatePanel.
        Consumer(
          builder: (context, ref, _) {
            final techsAsync = ref.watch(techniciansProvider);
            final techs = techsAsync.valueOrNull ?? const <Map<String, dynamic>>[];
            final selected = techs
                .where((t) => t['id'] == widget.state.agentId)
                .map((t) => '${t['firstName'] ?? ''} ${t['lastName'] ?? ''}'.trim())
                .firstOrNull;
            return AppFieldShell(
              label: 'Riferimento',
              child: AppTappable(
                key: const ValueKey('agent-field'),
                onTap: () => _pickAgent(techs),
                color: context.colors.bg3,
                border: Border.all(color: context.colors.borderLight),
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected ?? 'Nessuno',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: selected != null ? context.colors.ink : context.colors.inkMuted,
                        ),
                      ),
                    ),
                    Icon(LucideIcons.chevronDown, size: 18, color: context.colors.inkMuted),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // ── Tag ────────────────────────────────────────────────────────────
        // Free-form, no catalogue behind them — same reasoning as web's comma-separated input.
        AppTextField(
          key: const ValueKey('tags-field'),
          label: 'Tag',
          hint: 'Separati da virgola',
          controller: _tagsCtrl,
          onChanged: (v) => widget.onChanged(
            widget.state.copyWith(
              tags: v.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
            ),
          ),
        ),

        if (widget.ticketId != null)
          ExtensionFieldsSection(entityType: 'ticket', entityId: widget.ticketId!),
      ],
    );
  }
}
