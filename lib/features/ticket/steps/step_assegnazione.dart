// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../new_ticket_form_state.dart';
import '../ticket_api_client.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
        Text(
          'Assegnazione',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.colors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Opzionale — puoi assegnare un tecnico al ticket.',
          style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
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
                Icon(LucideIcons.cloudOff, size: 32, color: context.colors.inkMuted),
                const SizedBox(height: 8),
                Text(
                  'Impossibile caricare i tecnici.\nSeleziona un ticket senza assegnazione.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.colors.inkMuted,
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
                    color: context.colors.inkMuted,
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
    return AppTappable(
      onTap: onTap,
      color: isSelected ? AppColors.Y.withValues(alpha: 0.12) : context.colors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isSelected ? AppColors.Y : context.colors.borderStrong,
        width: isSelected ? 2 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
          children: [
            Icon(
              isSelected
                  ? LucideIcons.circleDot
                  : LucideIcons.circle,
              size: 20,
              color: isSelected ? AppColors.Y : context.colors.inkMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isSelected ? context.colors.ink : context.colors.inkMuted,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
      ),
    );
  }
}
