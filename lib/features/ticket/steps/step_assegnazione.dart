// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../new_ticket_form_state.dart';
import '../ticket_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 — Assegnazione
//
// Optional: assign a technician. Fetches from backend API (no Users table
// in Drift). Shows a loading state, or a message if offline.
// ══════════════════════════════════════════════════════════════════════════════

/// Provider that fetches technicians from the backend.
final techniciansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final client = ref.watch(ticketApiClientProvider);
  return client.fetchTechnicians();
});

class StepAssegnazione extends ConsumerStatefulWidget {
  const StepAssegnazione({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final NewTicketFormState state;
  final ValueChanged<NewTicketFormState> onChanged;

  @override
  ConsumerState<StepAssegnazione> createState() => _StepAssegnazioneState();
}

class _StepAssegnazioneState extends ConsumerState<StepAssegnazione> {
  @override
  Widget build(BuildContext context) {
    final techsAsync = ref.watch(techniciansProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 24),
      children: [
        const Text(
          'Assegnazione',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.DARK,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Opzionale — puoi assegnare un tecnico al ticket.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.MUTED),
        ),
        const SizedBox(height: 16),

        // ── No assignment button ───────────────────────────────────────────
        _AssignmentOption(
          label: 'Nessuna assegnazione',
          isSelected: widget.state.assignedUserId == null,
          onTap: () => widget.onChanged(
            widget.state.copyWith(assignedUserId: null),
          ),
        ),

        const SizedBox(height: 12),

        // ── Technician list ────────────────────────────────────────────────
        techsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.cloud_off, size: 32, color: AppColors.MUTED),
                const SizedBox(height: 8),
                Text(
                  'Impossibile caricare i tecnici.\nSeleziona un ticket senza assegnazione.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.MUTED,
                  ),
                ),
              ],
            ),
          ),
          data: (techs) {
            if (techs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nessun tecnico disponibile.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.MUTED,
                  ),
                ),
              );
            }

            return Column(
              children: techs.map((tech) {
                final id = tech['id'] as String;
                final firstName = tech['firstName'] as String? ?? '';
                final lastName = tech['lastName'] as String? ?? '';
                final name = '$firstName $lastName'.trim();
                if (name.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AssignmentOption(
                    label: name,
                    isSelected: widget.state.assignedUserId == id,
                    onTap: () =>
                        widget.onChanged(widget.state.copyWith(assignedUserId: id)),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Assignment option card
// ══════════════════════════════════════════════════════════════════════════════

class _AssignmentOption extends StatelessWidget {
  const _AssignmentOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.Y.withValues(alpha: 0.12) : AppColors.WHITE,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.Y : AppColors.BS,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 20,
              color: isSelected ? AppColors.Y : AppColors.MUTED,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isSelected ? AppColors.DARK : AppColors.MUTED,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
