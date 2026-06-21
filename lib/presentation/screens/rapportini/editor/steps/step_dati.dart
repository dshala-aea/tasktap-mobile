// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/app_text_field.dart';
import '../../../../providers/report_editor_providers.dart';
import '../../../../providers/schedule_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 — Dati generali
//
// Fields: title, description, cliente (cache picker + free-text fallback),
// work address, linked ticket OR cantiere (cache pickers + free-text fallback).
// GPS is captured here automatically via geolocator (optional — no Android SDK
// in test env, so we degrade gracefully).
// ══════════════════════════════════════════════════════════════════════════════

class StepDati extends ConsumerStatefulWidget {
  const StepDati({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<StepDati> createState() => _StepDatiState();
}

class _StepDatiState extends ConsumerState<StepDati> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _detailsCtrl;
  late final TextEditingController _customerFreeTextCtrl;
  late final TextEditingController _workAddressCtrl;
  late final TextEditingController _ticketFreeTextCtrl;
  late final TextEditingController _cantiereFreeTextCtrl;
  late final TextEditingController _locationFreeTextCtrl;

  /// Tracks whether we're in "free-text" mode for customer / location / ticket /
  /// cantiere, or using the cached picker.
  bool _customerFreeTextMode = false;
  bool _locationFreeTextMode = false;
  bool _ticketFreeTextMode = false;
  bool _cantiereFreeTextMode = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(reportEditorProvider(widget.reportId));
    _titleCtrl = TextEditingController(text: s.title);
    _detailsCtrl = TextEditingController(text: s.details);
    _customerFreeTextCtrl =
        TextEditingController(text: s.customerFreeText ?? '');
    _workAddressCtrl = TextEditingController(text: s.workAddress ?? '');
    _ticketFreeTextCtrl = TextEditingController(text: s.ticketFreeText ?? '');
    _cantiereFreeTextCtrl =
        TextEditingController(text: s.cantiereFreeText ?? '');
    _locationFreeTextCtrl =
        TextEditingController(text: s.locationFreeText ?? '');

    _customerFreeTextMode = s.customerFreeText?.isNotEmpty ?? false;
    _locationFreeTextMode = s.locationFreeText?.isNotEmpty ?? false;
    _ticketFreeTextMode = s.ticketFreeText?.isNotEmpty ?? false;
    _cantiereFreeTextMode = s.cantiereFreeText?.isNotEmpty ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _detailsCtrl.dispose();
    _customerFreeTextCtrl.dispose();
    _workAddressCtrl.dispose();
    _ticketFreeTextCtrl.dispose();
    _cantiereFreeTextCtrl.dispose();
    _locationFreeTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier =
        ref.read(reportEditorProvider(widget.reportId).notifier);
    final customers = ref.watch(allCustomersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader('Titolo e descrizione'),
          const SizedBox(height: 8),

          // Title
          AppTextField(
            controller: _titleCtrl,
            label: 'Titolo *',
            hint: 'Es. Manutenzione impianto...',
            onChanged: (v) => notifier.setTitle(v),
          ),
          const SizedBox(height: 12),

          // Description
          AppTextField(
            controller: _detailsCtrl,
            label: 'Descrizione',
            hint: 'Descrizione intervento...',
            maxLines: 3,
            onChanged: (v) => notifier.setDetails(v),
          ),
          const SizedBox(height: 20),

          // ── Cliente ──────────────────────────────────────────────────────
          const _SectionHeader('Cliente *'),
          const SizedBox(height: 8),
          customers.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, st) => _FreeTextField(
              ctrl: _customerFreeTextCtrl,
              label: 'Nome cliente',
              onChanged: (v) => notifier.setCustomerFreeText(v),
            ),
            data: (list) {
              if (list.isEmpty || _customerFreeTextMode) {
                return _FreeTextField(
                  ctrl: _customerFreeTextCtrl,
                  label: 'Nome cliente (testo libero)',
                  onChanged: (v) => notifier.setCustomerFreeText(v),
                  trailing: list.isNotEmpty
                      ? TextButton(
                          onPressed: () =>
                              setState(() => _customerFreeTextMode = false),
                          child: const Text('Da lista'),
                        )
                      : null,
                );
              }
              final selected = ref
                  .read(reportEditorProvider(widget.reportId))
                  .customerId;
              return _CachePicker<_NamedItem>(
                label: 'Seleziona cliente',
                items: list
                    .map((c) => _NamedItem(id: c.id, name: c.companyName))
                    .toList(),
                selectedId: selected,
                onSelected: (id) => notifier.setCustomerFromCache(id),
                onFreeText: () {
                  setState(() => _customerFreeTextMode = true);
                  notifier.setCustomerFromCache('');
                },
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Indirizzo di lavoro ───────────────────────────────────────────
          const _SectionHeader('Indirizzo di lavoro'),
          const SizedBox(height: 8),
          AppTextField(
            controller: _workAddressCtrl,
            label: 'Indirizzo',
            hint: 'Via, numero civico...',
            onChanged: (v) => notifier.setWorkAddress(v),
          ),
          const SizedBox(height: 20),

          // ── Location ──────────────────────────────────────────────────────
          const _SectionHeader('Ubicazione / Sede'),
          const SizedBox(height: 8),
          _LocationPicker(
            reportId: widget.reportId,
            freeTextMode: _locationFreeTextMode,
            freeTextCtrl: _locationFreeTextCtrl,
            onFreeTextChanged: (v) => notifier.setLocationFreeText(v),
            onToggleFreeText: (v) => setState(() => _locationFreeTextMode = v),
            onCacheSelected: (id) => notifier.setLocationFromCache(id),
          ),
          const SizedBox(height: 20),

          // ── Ticket / Cantiere ─────────────────────────────────────────────
          const _SectionHeader('Ticket o Cantiere (opzionale)'),
          const SizedBox(height: 8),
          _TicketCantierePicker(
            reportId: widget.reportId,
            ticketFreeTextMode: _ticketFreeTextMode,
            cantiereFreeTextMode: _cantiereFreeTextMode,
            ticketCtrl: _ticketFreeTextCtrl,
            cantiereCtrl: _cantiereFreeTextCtrl,
            onTicketFreeText: (v) => notifier.setTicketFreeText(v),
            onCantiereFreeText: (v) => notifier.setCantiereFreeText(v),
            onToggleTicketFreeText: (v) =>
                setState(() => _ticketFreeTextMode = v),
            onToggleCantiereFreeText: (v) =>
                setState(() => _cantiereFreeTextMode = v),
            onTicketFromCache: (id) => notifier.setTicketFromCache(id),
            onCantiereFromCache: (id) => notifier.setCantiereFromCache(id),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: Colors.black87,
      ),
    );
  }
}

class _FreeTextField extends StatelessWidget {
  const _FreeTextField({
    required this.ctrl,
    required this.label,
    required this.onChanged,
    this.trailing,
  });

  final TextEditingController ctrl;
  final String label;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppTextField(
            controller: ctrl,
            label: label,
            onChanged: onChanged,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _NamedItem {
  const _NamedItem({required this.id, required this.name});
  final String id;
  final String name;
}

class _CachePicker<T extends _NamedItem> extends StatelessWidget {
  const _CachePicker({
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    required this.onFreeText,
  });

  final String label;
  final List<T> items;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onFreeText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedId?.isNotEmpty == true ? selectedId : null,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          isExpanded: true,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onFreeText,
            child: const Text('Non trovo → testo libero'),
          ),
        ),
      ],
    );
  }
}

class _LocationPicker extends ConsumerWidget {
  const _LocationPicker({
    required this.reportId,
    required this.freeTextMode,
    required this.freeTextCtrl,
    required this.onFreeTextChanged,
    required this.onToggleFreeText,
    required this.onCacheSelected,
  });

  final String reportId;
  final bool freeTextMode;
  final TextEditingController freeTextCtrl;
  final ValueChanged<String> onFreeTextChanged;
  final ValueChanged<bool> onToggleFreeText;
  final ValueChanged<String> onCacheSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // For simplicity show all locations (filter by customer could be added)
    final locAsync = ref.watch(allLocationsProvider);

    return locAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, st) => _FreeTextField(
        ctrl: freeTextCtrl,
        label: 'Ubicazione',
        onChanged: onFreeTextChanged,
      ),
      data: (list) {
        if (list.isEmpty || freeTextMode) {
          return _FreeTextField(
            ctrl: freeTextCtrl,
            label: 'Ubicazione (testo libero)',
            onChanged: onFreeTextChanged,
            trailing: list.isNotEmpty
                ? TextButton(
                    onPressed: () => onToggleFreeText(false),
                    child: const Text('Da lista'),
                  )
                : null,
          );
        }
        final selected =
            ref.read(reportEditorProvider(reportId)).locationId;
        return _CachePicker<_NamedItem>(
          label: 'Seleziona ubicazione',
          items: list.map((l) => _NamedItem(id: l.id, name: l.name)).toList(),
          selectedId: selected,
          onSelected: onCacheSelected,
          onFreeText: () => onToggleFreeText(true),
        );
      },
    );
  }
}

class _TicketCantierePicker extends ConsumerWidget {
  const _TicketCantierePicker({
    required this.reportId,
    required this.ticketFreeTextMode,
    required this.cantiereFreeTextMode,
    required this.ticketCtrl,
    required this.cantiereCtrl,
    required this.onTicketFreeText,
    required this.onCantiereFreeText,
    required this.onToggleTicketFreeText,
    required this.onToggleCantiereFreeText,
    required this.onTicketFromCache,
    required this.onCantiereFromCache,
  });

  final String reportId;
  final bool ticketFreeTextMode;
  final bool cantiereFreeTextMode;
  final TextEditingController ticketCtrl;
  final TextEditingController cantiereCtrl;
  final ValueChanged<String> onTicketFreeText;
  final ValueChanged<String> onCantiereFreeText;
  final ValueChanged<bool> onToggleTicketFreeText;
  final ValueChanged<bool> onToggleCantiereFreeText;
  final ValueChanged<String> onTicketFromCache;
  final ValueChanged<String> onCantiereFromCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(allTicketsProvider);
    final cantieri = ref.watch(allCantieriProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ticket ────────────────────────────────────────────────────────
        tickets.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, st) => _FreeTextField(
            ctrl: ticketCtrl,
            label: 'Rif. Ticket',
            onChanged: onTicketFreeText,
          ),
          data: (list) {
            if (list.isEmpty || ticketFreeTextMode) {
              return _FreeTextField(
                ctrl: ticketCtrl,
                label: 'Rif. Ticket (testo libero)',
                onChanged: onTicketFreeText,
                trailing: list.isNotEmpty
                    ? TextButton(
                        onPressed: () => onToggleTicketFreeText(false),
                        child: const Text('Da lista'),
                      )
                    : null,
              );
            }
            final selected =
                ref.read(reportEditorProvider(reportId)).ticketId;
            return _CachePicker<_NamedItem>(
              label: 'Seleziona ticket',
              items: list
                  .map((t) => _NamedItem(id: t.id, name: t.title))
                  .toList(),
              selectedId: selected,
              onSelected: onTicketFromCache,
              onFreeText: () => onToggleTicketFreeText(true),
            );
          },
        ),
        const SizedBox(height: 12),

        const Center(child: Text('— oppure —', style: TextStyle(color: Colors.grey))),
        const SizedBox(height: 12),

        // ── Cantiere ──────────────────────────────────────────────────────
        cantieri.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, st) => _FreeTextField(
            ctrl: cantiereCtrl,
            label: 'Cantiere',
            onChanged: onCantiereFreeText,
          ),
          data: (list) {
            if (list.isEmpty || cantiereFreeTextMode) {
              return _FreeTextField(
                ctrl: cantiereCtrl,
                label: 'Cantiere (testo libero)',
                onChanged: onCantiereFreeText,
                trailing: list.isNotEmpty
                    ? TextButton(
                        onPressed: () => onToggleCantiereFreeText(false),
                        child: const Text('Da lista'),
                      )
                    : null,
              );
            }
            final selected =
                ref.read(reportEditorProvider(reportId)).cantiereId;
            return _CachePicker<_NamedItem>(
              label: 'Seleziona cantiere',
              items: list
                  .map((c) => _NamedItem(id: c.id, name: c.name))
                  .toList(),
              selectedId: selected,
              onSelected: onCantiereFromCache,
              onFreeText: () => onToggleCantiereFreeText(true),
            );
          }, // ignore: missing_return
        ),
      ],
    );
  }
}
