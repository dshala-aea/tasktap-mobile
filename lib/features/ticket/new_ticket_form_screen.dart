// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_stepper.dart';
import 'steps/step_assegnazione.dart';
import 'steps/step_cliente_sede.dart';
import 'steps/step_dettagli_ticket.dart';
import 'new_ticket_form_state.dart';
import 'steps/step_riepilogo_ticket.dart';
import 'ticket_api_client.dart';
import 'ticket_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Form steps enum
// ══════════════════════════════════════════════════════════════════════════════

enum _FormStep { clienteSede, dettagli, assegnazione, riepilogo }

const _kSteps = [
  StepperStep(label: 'Cliente'),
  StepperStep(label: 'Dettagli'),
  StepperStep(label: 'Assegna'),
  StepperStep(label: 'Riepilogo'),
];

// ══════════════════════════════════════════════════════════════════════════════
// NewTicketFormScreen
// ══════════════════════════════════════════════════════════════════════════════

class NewTicketFormScreen extends ConsumerStatefulWidget {
  const NewTicketFormScreen({super.key});

  @override
  ConsumerState<NewTicketFormScreen> createState() =>
      _NewTicketFormScreenState();
}

class _NewTicketFormScreenState extends ConsumerState<NewTicketFormScreen> {
  _FormStep _step = _FormStep.clienteSede;
  NewTicketFormState _formState = const NewTicketFormState();
  bool _isSubmitting = false;

  int get _stepIndex => _FormStep.values.indexOf(_step);
  bool get _isFirst => _step == _FormStep.clienteSede;
  bool get _isLast => _step == _FormStep.riepilogo;

  /// Auto-select default status on first build.
  @override
  void initState() {
    super.initState();
    // Default status will be set when TicketStatuses data loads (via build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDefaultStatus();
    });
  }

  void _ensureDefaultStatus() {
    final statusMapAsync = ref.read(ticketStatusMapProvider);
    statusMapAsync.whenData((statusMap) {
      if (_formState.statusId == null) {
        // Find the default status (isDefault == true).
        final defaultEntry = statusMap.entries.firstOrNull;
        // We don't have isDefault in the map, but the first entry
        // from the query is typically the default. Alternatively, we can
        // read it from a dedicated provider.
        // For now, pick the first status as default.
        if (defaultEntry != null) {
          setState(() {
            _formState = _formState.copyWith(statusId: defaultEntry.key);
          });
        }
      }
    });
  }

  void _goNext() {
    final values = _FormStep.values;
    final idx = values.indexOf(_step);
    if (idx < values.length - 1) {
      setState(() => _step = values[idx + 1]);
    }
  }

  void _goBack() {
    final values = _FormStep.values;
    final idx = values.indexOf(_step);
    if (idx > 0) {
      setState(() => _step = values[idx - 1]);
    }
  }

  void _onFormChanged(NewTicketFormState newState) {
    setState(() => _formState = newState);
  }

  Future<void> _onSubmit() async {
    if (!_formState.isValid || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(ticketApiClientProvider);
      await client.createTicket(
        title: _formState.title!,
        description: _formState.description,
        customerId: _formState.customerId!,
        locationId: _formState.locationId!,
        assignedUserId: _formState.assignedUserId,
        statusId: _formState.statusId!,
        typeId: _formState.typeId!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ticket creato con successo'),
            backgroundColor: AppColors.GREEN,
          ),
        );
        Navigator.of(context).pop(true); // return true = created
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: ${e.toString()}'),
            backgroundColor: AppColors.RED,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      appBar: AppBar(
        backgroundColor: AppColors.CHARCOAL,
        foregroundColor: AppColors.INV,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Nuovo ticket',
          style: AppTextStyles.titleMedium.copyWith(color: AppColors.INV),
        ),
      ),
      body: Column(
        children: [
          // ── Stepper ──────────────────────────────────────────────────────
          Container(
            color: AppColors.CHARCOAL,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: AppStepper(
              steps: _kSteps,
              currentIndex: _stepIndex,
            ),
          ),

          // ── Step content ─────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: _buildStep(key: ValueKey(_step)),
            ),
          ),

          // ── Bottom nav ───────────────────────────────────────────────────
          _BottomNavBar(
            isFirst: _isFirst,
            isLast: _isLast,
            onBack: _goBack,
            onNext: _goNext,
            canProceed: _canProceed,
          ),
        ],
      ),
    );
  }

  bool get _canProceed {
    return switch (_step) {
      _FormStep.clienteSede =>
        _formState.customerId != null && _formState.locationId != null,
      _FormStep.dettagli =>
        _formState.title != null &&
        _formState.title!.trim().isNotEmpty &&
        _formState.typeId != null,
      _FormStep.assegnazione => true, // optional
      _FormStep.riepilogo => false, // submit button instead
    };
  }

  Widget _buildStep({required Key key}) {
    return switch (_step) {
      _FormStep.clienteSede => StepClienteSede(
          key: key,
          state: _formState,
          onChanged: _onFormChanged,
        ),
      _FormStep.dettagli => StepDettagliTicket(
          key: key,
          state: _formState,
          onChanged: _onFormChanged,
        ),
      _FormStep.assegnazione => StepAssegnazione(
          key: key,
          state: _formState,
          onChanged: _onFormChanged,
        ),
      _FormStep.riepilogo => StepRiepilogoTicket(
          key: key,
          state: _formState,
          onSubmit: _onSubmit,
          isSubmitting: _isSubmitting,
        ),
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom navigation bar
// ══════════════════════════════════════════════════════════════════════════════

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onNext,
    required this.canProceed,
  });

  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool canProceed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.WHITE,
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
        child: Row(
          children: [
            if (!isFirst) ...[
              Expanded(
                child: AppButton.secondary(
                  label: 'Indietro',
                  onPressed: onBack,
                  size: AppButtonSize.lg,
                ),
              ),
              if (!isLast) const SizedBox(width: 12),
            ],
            if (!isLast)
              Expanded(
                child: AppButton(
                  label: 'Avanti',
                  onPressed: canProceed ? onNext : null,
                  size: AppButtonSize.lg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
