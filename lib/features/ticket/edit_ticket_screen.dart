// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/error_message.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../admin/admin_api_client.dart';
import 'new_ticket_form_state.dart';
import 'steps/step_cliente_sede.dart';
import 'steps/step_dettagli_ticket.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// EditTicketScreen
//
// Editing title/description/customer/location/type after a ticket has been
// created — mobile had no way to do this at all: the only PUT the app sent
// was assignTicket's narrow `{assignedUserId}`. This reuses the create
// wizard's own step widgets (StepClienteSede, StepDettagliTicket) rather than
// building a second, parallel form: they are already callback-driven
// (`state` in, `onChanged` out) and know nothing about *why* a value
// changed, only that it did, so pre-filling them from an existing ticket and
// submitting a PUT instead of a POST needs no changes to either widget
// itself.
//
// A 2-step mini-wizard rather than the full 4-step one: Assegnazione (who's
// on it) and Riepilogo (create-and-submit-to-the-outbox) are both
// creation-specific — this screen is not queued offline (see `_onSave`'s own
// note) and status/assignment already have their own controls on ticket
// detail. Priority is left out of StepDettagliTicket entirely in this mode —
// see `StepDettagliTicket.showPriority`'s doc comment.
// ══════════════════════════════════════════════════════════════════════════════

enum _EditStep { clienteSede, dettagli }

const _kEditSteps = [StepperStep(label: 'Cliente'), StepperStep(label: 'Dettagli')];

class EditTicketScreen extends ConsumerStatefulWidget {
  const EditTicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<EditTicketScreen> createState() => _EditTicketScreenState();
}

class _EditTicketScreenState extends ConsumerState<EditTicketScreen> {
  _EditStep _step = _EditStep.clienteSede;

  /// Null until the ticket has loaded once; seeded exactly once (see [_seedIfNeeded]) so a later
  /// re-emission of the local Drift mirror (e.g. from a sync landing mid-edit) never overwrites
  /// what the technician has typed.
  NewTicketFormState? _formState;
  bool _isSaving = false;

  late final ProviderSubscription<AsyncValue<Ticket?>> _ticketListener;

  int get _stepIndex => _EditStep.values.indexOf(_step);
  bool get _isLast => _step == _EditStep.dettagli;

  @override
  void initState() {
    super.initState();
    _ticketListener = ref.listenManual(
      ticketByIdProvider(widget.ticketId),
      (previous, next) => next.whenData(_seedIfNeeded),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _ticketListener.close();
    super.dispose();
  }

  void _seedIfNeeded(Ticket? ticket) {
    if (_formState != null || ticket == null) return;
    setState(() {
      _formState = NewTicketFormState(
        customerId: ticket.customerId,
        locationId: ticket.locationId,
        title: ticket.title,
        description: ticket.description,
        typeId: ticket.typeId,
        statusId: ticket.statusId,
      );
    });
  }

  void _onFormChanged(NewTicketFormState newState) {
    setState(() => _formState = newState);
  }

  bool get _canProceed {
    final s = _formState;
    if (s == null) return false;
    return switch (_step) {
      _EditStep.clienteSede => s.customerId != null && s.locationId != null,
      _EditStep.dettagli => s.title != null && s.title!.trim().isNotEmpty && s.typeId != null,
    };
  }

  void _goNext() {
    if (_step == _EditStep.clienteSede) setState(() => _step = _EditStep.dettagli);
  }

  void _goBack() {
    if (_step == _EditStep.dettagli) setState(() => _step = _EditStep.clienteSede);
  }

  /// A direct PUT, not queued through an offline outbox: unlike ticket *creation*
  /// (TicketCreationQueue), a mid-air edit has nothing sensible to show on the ticket list while
  /// it waits — the ticket already exists and is already visible with its old values. Offline or
  /// failure both just surface the error and leave the form filled in, so nothing typed is lost;
  /// the technician retries "Salva" themselves once they have signal.
  Future<void> _onSave() async {
    final s = _formState;
    if (s == null || !_canProceed || _isSaving) return;
    if (s.customerId == null || s.locationId == null || s.title == null || s.typeId == null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(adminApiClientProvider)
          .updateTicket(
            widget.ticketId,
            title: s.title,
            description: s.description ?? '',
            customerId: s.customerId,
            locationId: s.locationId,
            typeId: s.typeId,
          );

      // Safe to mirror locally: these are the exact values the server just accepted, not values
      // this client invented — same reasoning _TicketStatusRowState._changeStatus already relies
      // on for its own PUT. Keeps the ticket detail screen current without waiting on a sync.
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.tickets)..where((t) => t.id.equals(widget.ticketId))).write(
        TicketsCompanion(
          title: Value(s.title!),
          description: Value(s.description),
          customerId: Value(s.customerId!),
          locationId: Value(s.locationId!),
          typeId: Value(s.typeId!),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      if (!mounted) return;
      showAppToast(context, message: 'Ticket aggiornato', tone: ToastTone.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'salvare le modifiche'),
        tone: ToastTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _formState;
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const ScreenHeader(title: 'Modifica ticket', showBack: true),
                if (s != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      0,
                      AppSpacing.base,
                      AppSpacing.base,
                    ),
                    child: AppStepper(
                      steps: _kEditSteps,
                      currentIndex: _stepIndex,
                      onStepSelected: (i) => setState(() => _step = _EditStep.values[i]),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: s == null
                ? const Center(child: CircularProgressIndicator())
                : AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    child: switch (_step) {
                      _EditStep.clienteSede => StepClienteSede(
                        key: const ValueKey(_EditStep.clienteSede),
                        state: s,
                        onChanged: _onFormChanged,
                      ),
                      _EditStep.dettagli => StepDettagliTicket(
                        key: const ValueKey(_EditStep.dettagli),
                        state: s,
                        onChanged: _onFormChanged,
                        showPriority: false,
                      ),
                    },
                  ),
          ),
          if (s != null)
            SafeArea(
              top: false,
              child: Container(
                color: context.colors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePadding,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    if (_isLast) ...[
                      Expanded(
                        child: AppButton.secondary(
                          label: 'Indietro',
                          onPressed: _isSaving ? null : _goBack,
                          size: AppButtonSize.lg,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: AppButton(
                        label: _isLast ? (_isSaving ? 'Salvataggio…' : 'Salva') : 'Avanti',
                        onPressed: !_canProceed || _isSaving
                            ? null
                            : (_isLast ? _onSave : _goNext),
                        size: AppButtonSize.lg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
