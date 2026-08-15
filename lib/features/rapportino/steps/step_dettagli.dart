// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/location/location_service.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/ai/ai_api_client.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
// Uses StepLabel (the padding-free sibling of SectionTitle) — these headings sit inside cards
// that already carry their own padding.
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
  late final TextEditingController _workAddressCtrl;

  bool _aiBusy = false;

  /// Whether the optional ticket/cantiere link is expanded.
  ///
  /// Starts closed. A rapportino is almost always opened from the thing it is about, so the link
  /// is already made; when it is not, it is genuinely optional and does not deserve two pickers
  /// and an "— oppure —" divider sitting between the technician and the next step.
  bool _showCollegamento = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(reportEditorProvider(widget.reportId));
    _titleCtrl = TextEditingController(text: s.title);
    _detailsCtrl = TextEditingController(text: s.details);
    _workAddressCtrl = TextEditingController(text: s.workAddress ?? '');
    _showCollegamento =
        (s.ticketFreeText?.isNotEmpty ?? false) || (s.cantiereFreeText?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _detailsCtrl.dispose();
    _workAddressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    final state = ref.watch(reportEditorProvider(widget.reportId));
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const [];
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? const [];
    final tickets = ref.watch(allTicketsProvider).valueOrNull ?? const [];
    final cantieri = ref.watch(allCantieriProvider).valueOrNull ?? const [];

    // A rapportino opened from a ticket or a cantiere already knows what it is about. Naming it
    // once at the top and dropping the pickers is the difference between confirming a fact and
    // re-entering it.
    final linkedTicket = _findName(tickets.map((t) => (t.id, t.title)), state.ticketId);
    final linkedCantiere = _findName(cantieri.map((c) => (c.id, c.name)), state.cantiereId);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(19, 16, 19, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (linkedTicket != null || linkedCantiere != null) ...[
            _LinkedChip(
              label: linkedTicket != null ? 'Ticket' : 'Cantiere',
              value: linkedTicket ?? linkedCantiere!,
            ),
            const SizedBox(height: 16),
          ],

          _AiDraftButton(
            scheduleId: state.scheduleId,
            ticketId: state.ticketId,
            busy: _aiBusy,
            onDraft: _generateAiDraft,
          ),

          // No section headings above these. Every one of them restated the label of the single
          // field beneath it — "Titolo e descrizione" over a field called "Titolo", "Cliente *"
          // over a field called "Cliente". Saying it twice is not emphasis, it is one more line
          // to scroll past on a phone held in one hand.
          AppTextField(
            controller: _titleCtrl,
            label: 'Titolo *',
            hint: 'Es. Manutenzione impianto...',
            onChanged: (v) => notifier.setTitle(v),
          ),
          const SizedBox(height: 12),

          AppLookupField(
            label: 'Cliente *',
            hint: 'Cerca o scrivi il nome',
            items: [for (final c in customers) LookupItem(id: c.id, name: c.companyName)],
            selectedId: state.customerId,
            initialText: state.customerFreeText,
            emptyCacheHint: 'Nessun cliente sincronizzato — scrivi il nome, verrà collegato dopo.',
            onSelected: notifier.setCustomerFromCache,
            onFreeText: notifier.setCustomerFreeText,
          ),
          const SizedBox(height: 12),

          AppLookupField(
            label: 'Sede',
            hint: 'Cerca o scrivi l\'ubicazione',
            items: [for (final l in locations) LookupItem(id: l.id, name: l.name)],
            selectedId: state.locationId,
            initialText: state.locationFreeText,
            onSelected: notifier.setLocationFromCache,
            onFreeText: notifier.setLocationFreeText,
          ),
          const SizedBox(height: 12),

          AppTextField(
            controller: _workAddressCtrl,
            label: 'Indirizzo di lavoro',
            hint: 'Via, numero civico...',
            onChanged: (v) => notifier.setWorkAddress(v),
          ),
          const SizedBox(height: 12),

          AppTextField(
            controller: _detailsCtrl,
            label: 'Descrizione',
            hint: 'Cosa hai trovato, cosa hai fatto...',
            maxLines: 3,
            onChanged: (v) => notifier.setDetails(v),
          ),

          // ── Collegamento, only when there isn't one already ─────────────────
          if (linkedTicket == null && linkedCantiere == null) ...[
            const SizedBox(height: 8),
            if (!_showCollegamento)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showCollegamento = true),
                  icon: const Icon(LucideIcons.link, size: 16),
                  label: const Text('Collega a ticket o cantiere'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
              )
            else ...[
              const SizedBox(height: 4),
              AppLookupField(
                label: 'Ticket',
                hint: 'Cerca o scrivi il riferimento',
                items: [for (final t in tickets) LookupItem(id: t.id, name: t.title)],
                initialText: state.ticketFreeText,
                onSelected: notifier.setTicketFromCache,
                onFreeText: notifier.setTicketFreeText,
              ),
              const SizedBox(height: 12),
              AppLookupField(
                label: 'Cantiere',
                hint: 'Cerca o scrivi il nome',
                items: [for (final c in cantieri) LookupItem(id: c.id, name: c.name)],
                initialText: state.cantiereFreeText,
                onSelected: notifier.setCantiereFromCache,
                onFreeText: notifier.setCantiereFreeText,
              ),
            ],
          ],

          const SizedBox(height: 16),
          _GpsCapture(reportId: widget.reportId),
        ],
      ),
    );
  }

  /// The display name for an id, or null when there is nothing resolved to show.
  static String? _findName(Iterable<(String, String)> pairs, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final (candidateId, name) in pairs) {
      if (candidateId == id) return name;
    }
    // Resolved to an id the cache does not hold yet. Showing the raw GUID would be worse than
    // showing nothing — it reads as corruption, and it is not information.
    return null;
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
            onPressed: () => _captureGps(context, ref),
            icon: const Icon(LucideIcons.locateFixed, size: 16),
            label: Text(hasGps ? 'Aggiorna' : 'Acquisisci'),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          ),
        ],
      ),
    );
  }

  /// Capture the real position, or record none at all.
  ///
  /// This used to write `(0.0, 0.0)` — Null Island, in the Gulf of Guinea — set the "acquired"
  /// state and render "GPS: 0.00000, 0.00000" as though it had been measured. A snackbar admitted
  /// it was a mock, but the *record* did not: a rapportino could reach an invoice carrying a
  /// coordinate that was never anywhere. The comment claiming geolocator was not wired had been
  /// stale for some time; `cantiere_timbra_screen` has been using it through this same service.
  ///
  /// There is no fallback value, deliberately. An absent position is a fact the office can act on;
  /// a fabricated one is not distinguishable from a real one.
  Future<void> _captureGps(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final messenger = ScaffoldMessenger.of(context);

    // Off in Impostazioni resolves to the disabled service, which answers null like a denial —
    // so say which of the two it is rather than reporting a generic failure.
    if (!ref.read(gpsPreferenceProvider)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Geolocalizzazione disattivata. Attivala in Impostazioni per registrare la posizione.',
          ),
        ),
      );
      return;
    }

    final coords = await ref.read(locationServiceProvider).getCurrentPosition();

    if (coords == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Posizione non disponibile. Controlla il GPS e i permessi, poi riprova.'),
        ),
      );
      return;
    }

    notifier.setGps(coords.lat, coords.lng);
  }
}

// ── Shared helper widgets (same logic as old step_dati helpers) ───────────────

/// The ticket or cantiere this rapportino belongs to, stated once.
///
/// Replaces a card that read "Collegato al ticket 3f2a1c8e-…" — a GUID presented to a technician
/// as if it were the name of something. It identified nothing they could recognise, and it was
/// the first thing on the screen.
class _LinkedChip extends StatelessWidget {
  const _LinkedChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.link, size: 14, color: AppColors.Y),
        const SizedBox(width: 6),
        Text('$label · ', style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.ink),
          ),
        ),
      ],
    );
  }
}

// ── Inline section label (no built-in padding — avoids double-pad) ─────────────

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
