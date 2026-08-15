// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/ai/ai_api_client.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
// section_title omitted — using inline _SL below to avoid double padding
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 — Dettagli
//
// Folds the old step_dati content (title, description, cliente, work-address,
// ticket/cantiere, GPS) into the new 4-step shell.
// All notifier calls are identical to the old step_dati — only presentation
// is restyled to use AppCard / SectionTitle / AppTextField from the DS.
// ══════════════════════════════════════════════════════════════════════════════

class StepDettagli extends ConsumerStatefulWidget {
  const StepDettagli({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<StepDettagli> createState() => _StepDettagliState();
}

class _StepDettagliState extends ConsumerState<StepDettagli> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _detailsCtrl;
  late final TextEditingController _customerFreeTextCtrl;
  late final TextEditingController _workAddressCtrl;
  late final TextEditingController _ticketFreeTextCtrl;
  late final TextEditingController _cantiereFreeTextCtrl;
  late final TextEditingController _locationFreeTextCtrl;

  bool _aiBusy = false;
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
    _customerFreeTextCtrl = TextEditingController(text: s.customerFreeText ?? '');
    _workAddressCtrl = TextEditingController(text: s.workAddress ?? '');
    _ticketFreeTextCtrl = TextEditingController(text: s.ticketFreeText ?? '');
    _cantiereFreeTextCtrl = TextEditingController(text: s.cantiereFreeText ?? '');
    _locationFreeTextCtrl = TextEditingController(text: s.locationFreeText ?? '');

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
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    final state = ref.watch(reportEditorProvider(widget.reportId));
    final customers = ref.watch(allCustomersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(19, 16, 19, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Context card (ticket/cantiere pre-linked) ──────────────────────
          if (state.ticketId != null || state.cantiereId != null) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(LucideIcons.link, size: 18, color: AppColors.Y),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.ticketId != null
                          ? 'Collegato al ticket ${state.ticketId}'
                          : 'Collegato al cantiere ${state.cantiereId}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: context.colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Titolo e descrizione ───────────────────────────────────────────
          _SL(title: 'Titolo e descrizione'),
          const SizedBox(height: 8),
          _AiDraftButton(
            scheduleId: state.scheduleId,
            ticketId: state.ticketId,
            busy: _aiBusy,
            onDraft: _generateAiDraft,
          ),
          AppTextField(
            controller: _titleCtrl,
            label: 'Titolo *',
            hint: 'Es. Manutenzione impianto...',
            onChanged: (v) => notifier.setTitle(v),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _detailsCtrl,
            label: 'Descrizione',
            hint: 'Descrizione intervento...',
            maxLines: 3,
            onChanged: (v) => notifier.setDetails(v),
          ),
          const SizedBox(height: 20),

          // ── Cliente ───────────────────────────────────────────────────────
          _SL(title: 'Cliente *'),
          const SizedBox(height: 8),
          customers.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _FreeTextField(
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
                          onPressed: () => setState(() => _customerFreeTextMode = false),
                          child: const Text('Da lista'),
                        )
                      : null,
                );
              }
              final selected = state.customerId;
              return _CachePicker(
                label: 'Seleziona cliente',
                items: list.map((c) => _NamedItem(id: c.id, name: c.companyName)).toList(),
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

          // ── Indirizzo di lavoro ────────────────────────────────────────────
          _SL(title: 'Indirizzo di lavoro'),
          const SizedBox(height: 8),
          AppTextField(
            controller: _workAddressCtrl,
            label: 'Indirizzo',
            hint: 'Via, numero civico...',
            onChanged: (v) => notifier.setWorkAddress(v),
          ),
          const SizedBox(height: 20),

          // ── Ubicazione / Sede ──────────────────────────────────────────────
          _SL(title: 'Ubicazione / Sede'),
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

          // ── Ticket o Cantiere (opzionale) ──────────────────────────────────
          _SL(title: 'Ticket o Cantiere (opzionale)'),
          const SizedBox(height: 8),
          _TicketCantierePicker(
            reportId: widget.reportId,
            ticketFreeTextMode: _ticketFreeTextMode,
            cantiereFreeTextMode: _cantiereFreeTextMode,
            ticketCtrl: _ticketFreeTextCtrl,
            cantiereCtrl: _cantiereFreeTextCtrl,
            onTicketFreeText: (v) => notifier.setTicketFreeText(v),
            onCantiereFreeText: (v) => notifier.setCantiereFreeText(v),
            onToggleTicketFreeText: (v) => setState(() => _ticketFreeTextMode = v),
            onToggleCantiereFreeText: (v) => setState(() => _cantiereFreeTextMode = v),
            onTicketFromCache: (id) => notifier.setTicketFromCache(id),
            onCantiereFromCache: (id) => notifier.setCantiereFromCache(id),
          ),
          const SizedBox(height: 20),

          // ── GPS ────────────────────────────────────────────────────────────
          _GpsCapture(reportId: widget.reportId),
        ],
      ),
    );
  }

  /// Ask the server for a drafted title and description for this intervento.
  ///
  /// Applies to the two fields the editor can actually hold. `technicianNotes` comes back from the
  /// model too, but `ReportEditorState` hardcodes it to null and exposes no setter, so applying it
  /// would mean inventing storage for it here — a change to the draft model, not to this button.
  ///
  /// Never overwrites silently. Anything the technician has already typed is what they observed on
  /// site; a model's guess must not replace it without being asked.
  Future<void> _generateAiDraft(String scheduleId, String? ticketId) async {
    if (_aiBusy) return;

    final editor = ref.read(reportEditorProvider(widget.reportId));
    final hasTyped = editor.title.trim().isNotEmpty || editor.details.trim().isNotEmpty;
    if (hasTyped) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sostituire il testo?'),
          content: const Text(
            'Titolo e descrizione contengono già del testo. '
            'La bozza AI lo sostituirà.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sostituisci'),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    setState(() => _aiBusy = true);
    try {
      final draft = await ref
          .read(aiApiClientProvider)
          .generateDraft(scheduleId: scheduleId, ticketId: ticketId);

      final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
      _titleCtrl.text = draft.title;
      _detailsCtrl.text = draft.details;
      await notifier.setTitle(draft.title);
      await notifier.setDetails(draft.details);

      // The allowance is the whole company's, so it can move without this technician doing
      // anything. Re-read it rather than decrementing a local copy.
      ref.invalidate(aiQuotaProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bozza generata (${draft.modelUsed}). Rileggila prima di inviare.'),
          backgroundColor: context.colors.green,
        ),
      );
    } on AiQuotaExhaustedException catch (e) {
      if (!mounted) return;
      final when = e.resetsAt == null
          ? 'il primo del mese'
          : DateFormat('d MMMM', 'it').format(e.resetsAt!.toLocal());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quota AI della tua azienda esaurita. Si azzera $when.'),
          backgroundColor: context.colors.amber,
        ),
      );
    } on AiFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: context.colors.red));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }
}

// ── GPS capture widget ────────────────────────────────────────────────────────

class _GpsCapture extends ConsumerWidget {
  const _GpsCapture({required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final hasGps = state.gpsLatitude != null && state.gpsLongitude != null;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            hasGps ? LucideIcons.mapPin : LucideIcons.mapPinOff,
            color: hasGps ? context.colors.green : context.colors.inkMuted,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasGps
                  ? 'GPS: ${state.gpsLatitude!.toStringAsFixed(5)}, '
                        '${state.gpsLongitude!.toStringAsFixed(5)}'
                  : 'Posizione GPS non acquisita',
              style: TextStyle(
                fontSize: 13,
                color: hasGps ? context.colors.ink : context.colors.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _captureGps(context, notifier),
            icon: const Icon(LucideIcons.locateFixed, size: 16),
            label: Text(hasGps ? 'Aggiorna' : 'Acquisisci'),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          ),
        ],
      ),
    );
  }

  Future<void> _captureGps(BuildContext context, ReportEditorNotifier notifier) async {
    // Use a fixed mock position in test/offline environments.
    // In production the geolocator package would be called here.
    // Since step_dati doesn't actually call geolocator (no SDK in test env),
    // we replicate the same graceful degradation: capture button stores
    // a fixed "last-known" fallback and shows an error snackbar on failure.
    try {
      // Attempt to get position via geolocator if available.
      // Import is intentionally not at top-level to avoid compile failure
      // on platforms where geolocator is not configured.
      const double lat = 0.0;
      const double lng = 0.0;
      // NOTE: replace the two lines above with a real geolocator call when
      // the plugin is fully wired for the platform:
      //   final pos = await Geolocator.getCurrentPosition();
      //   notifier.setGps(pos.latitude, pos.longitude);
      notifier.setGps(lat, lng);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS non disponibile — posizione mock salvata'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore GPS: $e')));
      }
    }
  }
}

// ── Shared helper widgets (same logic as old step_dati helpers) ───────────────

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
          child: AppTextField(controller: ctrl, label: label, onChanged: onChanged),
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

class _CachePicker extends StatelessWidget {
  const _CachePicker({
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    required this.onFreeText,
  });

  final String label;
  final List<_NamedItem> items;
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
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
    final locAsync = ref.watch(allLocationsProvider);

    return locAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) =>
          _FreeTextField(ctrl: freeTextCtrl, label: 'Ubicazione', onChanged: onFreeTextChanged),
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
        final selected = ref.read(reportEditorProvider(reportId)).locationId;
        return _CachePicker(
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
    final state = ref.watch(reportEditorProvider(reportId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ticket ────────────────────────────────────────────────────────
        tickets.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) =>
              _FreeTextField(ctrl: ticketCtrl, label: 'Rif. Ticket', onChanged: onTicketFreeText),
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
            return _CachePicker(
              label: 'Seleziona ticket',
              items: list.map((t) => _NamedItem(id: t.id, name: t.title)).toList(),
              selectedId: state.ticketId,
              onSelected: onTicketFromCache,
              onFreeText: () => onToggleTicketFreeText(true),
            );
          },
        ),
        const SizedBox(height: 12),

        Center(
          child: Text('— oppure —', style: TextStyle(color: context.colors.inkMuted)),
        ),
        const SizedBox(height: 12),

        // ── Cantiere ─────────────────────────────────────────────────────
        cantieri.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) =>
              _FreeTextField(ctrl: cantiereCtrl, label: 'Cantiere', onChanged: onCantiereFreeText),
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
            return _CachePicker(
              label: 'Seleziona cantiere',
              items: list.map((c) => _NamedItem(id: c.id, name: c.name)).toList(),
              selectedId: state.cantiereId,
              onSelected: onCantiereFromCache,
              onFreeText: () => onToggleCantiereFreeText(true),
            );
          },
        ),
      ],
    );
  }
}

// ── Inline section label (no built-in padding — avoids double-pad) ─────────────

class _SL extends StatelessWidget {
  const _SL({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF363636),
      ),
    );
  }
}

/// Offers an AI draft, and says what it costs before it is pressed.
///
/// Hidden entirely when the report has no `scheduleId`: the endpoint requires one — the server
/// draws the intervento's context from the schedule — so with no schedule there is nothing to
/// draft from and a disabled button would only raise a question it cannot answer.
class _AiDraftButton extends ConsumerWidget {
  const _AiDraftButton({
    required this.scheduleId,
    required this.ticketId,
    required this.busy,
    required this.onDraft,
  });

  final String? scheduleId;
  final String? ticketId;
  final bool busy;
  final Future<void> Function(String scheduleId, String? ticketId) onDraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = scheduleId;
    if (id == null) return const SizedBox.shrink();

    final c = context.colors;
    final quota = ref.watch(aiQuotaProvider);
    final exhausted = quota.valueOrNull?.exhausted ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Icon(LucideIcons.penTool, size: 18, color: exhausted ? c.inkDisabled : c.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bozza automatica',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: exhausted ? c.inkMuted : c.ink,
                    ),
                  ),
                  Text(
                    // The count is the company's, not this technician's, and it is spent whether
                    // or not the result is kept. Both belong on the button, not in a help page.
                    switch (quota) {
                      AsyncData(:final value) when value.exhausted =>
                        'Quota aziendale esaurita per questo mese',
                      AsyncData(:final value) =>
                        '${value.remaining} generazioni rimaste all\'azienda questo mese',
                      AsyncError() => 'Quota non verificabile ora',
                      _ => 'Verifica quota…',
                    },
                    style: TextStyle(fontSize: 11, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              AppButton(
                label: 'Genera',
                size: AppButtonSize.sm,
                fullWidth: false,
                onPressed: exhausted ? null : () => onDraft(id, ticketId),
              ),
          ],
        ),
      ),
    );
  }
}
