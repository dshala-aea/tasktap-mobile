// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_tappable.dart';
import '../../../core/widgets/extension_fields_section.dart';
import '../../../data/reference/reference_option.dart';
import '../../admin/admin_widgets.dart';
import '../new_ticket_form_state.dart';
import '../reference_picker.dart';
import '../reference_providers.dart';
import '../ticket_providers.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 — Dettagli Ticket
//
// Title (required), description (optional), type (required).
// ══════════════════════════════════════════════════════════════════════════════

/// "Nessuno" pops `''` (never a real agent id) so it is distinguishable from dismissing the sheet
/// without picking anything (pops `null`, which must leave the field untouched, not clear it —
/// backing out of a picker is not the same gesture as explicitly clearing a field).
const String _kNoneSentinel = '';

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

  /// Labels for the prodotti this step itself picked, kept only for the chips below the picker.
  ///
  /// A chip needs a label, but [NewTicketFormState] holds ids — deliberately, since that is what
  /// the wire wants. The mirror resolves most of them (`localProdottiProvider`), but a row reached
  /// by an online search is materialised into the mirror asynchronously and the provider that
  /// already resolved for this customer will not re-run on its own. Remembering the label at the
  /// moment of the pick is what keeps the chip from showing a raw GUID in that window.
  final Map<String, String> _prodottoLabels = {};

  /// Re-keying the "add a product" picker after each pick resets its text, so the next product can
  /// be typed for without first clearing the previous one — the field holds a *pick*, not the
  /// selection list, and the chips below are where the selection lives.
  int _prodottoPickerEpoch = 0;

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

  Future<void> _pickAgent(List<ReferenceOption> agents) async {
    final pickedId = await showModalBottomSheet<String?>(
      context: context,
      // The sheet carries its own search field, so it has to make room for the keyboard.
      isScrollControlled: true,
      builder: (sheetContext) => _AgentPickerSheet(
        localItems: agents,
        search: (q) => ref.read(referenceSearchClientProvider).searchAgents(query: q),
      ),
    );
    if (pickedId == null) return; // Dismissed without picking — leave the field as it was.
    widget.onChanged(
      pickedId == _kNoneSentinel
          ? widget.state.copyWith(clearAgentId: true)
          : widget.state.copyWith(agentId: pickedId),
    );
  }

  /// Prodotti assistenza — the customer's assets this ticket covers. A multi-select drawn as
  /// chips (the selection) plus one "[ReferencePickerField]" that adds to it, because the field
  /// picks exactly one row and the request carries a list.
  ///
  /// The customer is required by step 1, so the disabled branch is a guard rather than a state a
  /// technician reaches: with no customer there is nothing to scope the mirror or the search to.
  Widget _buildProdotti() {
    final customerId = widget.state.customerId;
    final prodotti = customerId == null
        ? const <ReferenceOption>[]
        : ref.watch(localProdottiProvider(customerId)).valueOrNull ?? const <ReferenceOption>[];
    final byId = {for (final p in prodotti) p.id: p};
    final ids = widget.state.prodottoAssistenzaIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ids.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final id in ids)
                Chip(
                  key: ValueKey('prodotto-chip-$id'),
                  label: Text(_prodottoLabels[id] ?? byId[id]?.label ?? id),
                  onDeleted: () => widget.onChanged(
                    widget.state.copyWith(prodottoAssistenzaIds: [...ids]..remove(id)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ReferencePickerField(
          // Re-keyed after every pick (see _prodottoPickerEpoch) so the field empties itself and
          // the next product can be typed for immediately.
          key: ValueKey('prodotto-adder-$_prodottoPickerEpoch'),
          label: 'Prodotti assistenza',
          localItems: prodotti,
          search: (q) async => customerId == null
              ? const <ReferenceOption>[]
              : ref
                    .read(referenceSearchClientProvider)
                    .searchProdottiAssistenza(customerId: customerId, query: q),
          hint: 'Cerca prodotto…',
          emptyCacheHint: customerId == null
              ? 'Seleziona prima un cliente.'
              : 'Nessun prodotto in cache. Cerca per nome.',
          enabled: customerId != null,
          onSelected: (option) {
            // A pick released by editing the text (null) is not a product to add.
            if (option == null || ids.contains(option.id)) return;
            ref.invalidate(localProdottiProvider(customerId!));
            setState(() {
              _prodottoLabels[option.id] = option.label;
              _prodottoPickerEpoch++;
            });
            widget.onChanged(widget.state.copyWith(prodottoAssistenzaIds: [...ids, option.id]));
          },
        ),
      ],
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

        // ── Prodotti assistenza ────────────────────────────────────────────
        // Multi-select, scoped to the same customer as Contratto/Commessa. The chips are the
        // selection; the picker below them only adds to it.
        _buildProdotti(),

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
        // NOT the assignee (Tecnico, step_assegnazione.dart) and NOT a User. "Riferimento" is the
        // legacy Agente (`Core/Entities/Agent.cs`) — a different entity the server validates with
        // `EnsureExistsAsync<Agent>`. Filling it from `/api/users?role=Technician` meant every
        // ticket created with a reference was rejected 404 and, quietly, through the queue, never
        // arrived. It reads the agents mirror, and searches `/api/agents`.
        Consumer(
          builder: (context, ref, _) {
            final agentsAsync = ref.watch(localAgentsProvider(''));
            final agents = agentsAsync.valueOrNull ?? const <ReferenceOption>[];
            final selected = agents
                .where((a) => a.id == widget.state.agentId)
                .map((a) => a.label)
                .firstOrNull;
            return AppFieldShell(
              label: 'Riferimento',
              child: AppTappable(
                key: const ValueKey('agent-field'),
                onTap: () => _pickAgent(agents),
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

// ══════════════════════════════════════════════════════════════════════════════
// Riferimento picker sheet
// ══════════════════════════════════════════════════════════════════════════════

/// The Riferimento picker's sheet: the mirrored agents, plus a search that reaches the server.
///
/// A sheet rather than [ReferencePickerField] because this field's keys (`agent-field`,
/// `agent-picker-<id>`) are an existing surface this change must not move. The behaviour is the
/// same two-source merge that field uses: local first — the only source offline — and the search's
/// results joined to it, never replacing it, because the mirror is what a ticket can be written
/// from (see [ReferencePickerField]'s own doc comment for the full reasoning).
class _AgentPickerSheet extends StatefulWidget {
  const _AgentPickerSheet({required this.localItems, required this.search});

  final List<ReferenceOption> localItems;
  final Future<List<ReferenceOption>> Function(String query) search;

  @override
  State<_AgentPickerSheet> createState() => _AgentPickerSheetState();
}

class _AgentPickerSheetState extends State<_AgentPickerSheet> {
  static const _debounceDelay = Duration(milliseconds: 300);

  final _queryCtrl = TextEditingController();
  Timer? _debounce;
  List<ReferenceOption> _results = const [];

  /// Monotonic per search — a slow answer must not land on top of a faster later one, same rule as
  /// [ReferencePickerField].
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  /// Local first, then the search's, deduped by id with the local row winning.
  List<ReferenceOption> get _merged {
    final byId = <String, ReferenceOption>{for (final o in widget.localItems) o.id: o};
    for (final o in _results) {
      byId.putIfAbsent(o.id, () => o);
    }
    // An agent with no name is not pickable — the same guard the old user-map sheet applied to
    // "first + last name".
    return byId.values.where((o) => o.label.trim().isNotEmpty).toList(growable: false);
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    final seq = ++_seq;
    if (query.isEmpty) {
      if (_results.isNotEmpty) setState(() => _results = const []);
      return;
    }
    _debounce = Timer(_debounceDelay, () async {
      final found = await widget.search(query);
      if (!mounted || seq != _seq) return;
      setState(() => _results = found);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.sm,
              ),
              child: AppTextField(
                key: const ValueKey('agent-search-field'),
                controller: _queryCtrl,
                label: 'Cerca agente',
                hint: 'Nome, telefono o email…',
                onChanged: _onQueryChanged,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    key: const ValueKey('agent-picker-none'),
                    title: const Text('Nessuno'),
                    onTap: () => Navigator.of(context).pop(_kNoneSentinel),
                  ),
                  for (final agent in _merged)
                    ListTile(
                      key: ValueKey('agent-picker-${agent.id}'),
                      title: Text(agent.label),
                      subtitle: agent.subtitle != null ? Text(agent.subtitle!) : null,
                      onTap: () => Navigator.of(context).pop(agent.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
