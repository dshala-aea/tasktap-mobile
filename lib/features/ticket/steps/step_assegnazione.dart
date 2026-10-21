// dart format width=100
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/sync/connectivity_provider.dart' show isOnlineProvider;
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../new_ticket_form_state.dart';
import '../ticket_api_client.dart';
import 'blamed_field_notice.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 — Assegnazione
//
// Optional: assign a technician. The live `/api/users` list while online; the
// synced `colleagues` mirror offline (or when the call itself fails), so a
// ticket created on site can still be assigned instead of defaulting to nobody.
// ══════════════════════════════════════════════════════════════════════════════

/// The tenant's technicians: the live list online, the mirrored colleagues otherwise.
///
/// Shared beyond this step — the admin pickers (contract → generate schedules, magazzino
/// assignment, schedule form) read the same provider — so the fallback is deliberately the same
/// map shape the API returns rather than a new type.
final techniciansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(isOnlineProvider)) {
    try {
      return await ref.watch(ticketApiClientProvider).fetchTechnicians();
    } catch (e) {
      // A radio that says online but cannot reach the server is the case the mirror exists for;
      // the technician picker must not collapse to "nobody" on it.
      debugPrint('techniciansProvider: live fetch failed ($e) — using the colleagues mirror');
    }
  }
  final db = ref.watch(appDatabaseProvider);
  final rows = await (db.select(
    db.colleagues,
  )..orderBy([(c) => OrderingTerm.asc(c.displayName)])).get();
  return [
    for (final c in rows)
      {
        'id': c.id,
        'displayName': c.displayName,
        // The sync carries one display name; the split is presentation only, for the callers that
        // build "firstName lastName" themselves (this step) rather than reading `displayName`.
        'firstName': _firstNameOf(c.displayName),
        'lastName': _lastNameOf(c.displayName),
        'email': null,
      },
  ];
});

String _firstNameOf(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.first;
}

String _lastNameOf(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.length < 2 ? '' : parts.skip(1).join(' ');
}

class StepAssegnazione extends ConsumerStatefulWidget {
  const StepAssegnazione({
    super.key,
    required this.state,
    required this.onChanged,
    this.blamedField,
  });

  final NewTicketFormState state;
  final ValueChanged<NewTicketFormState> onChanged;

  /// The request field the server refused, when this wizard is a repair — see
  /// [BlamedFieldNotice]. Names `assignedUserId`, or null.
  final String? blamedField;

  @override
  ConsumerState<StepAssegnazione> createState() => _StepAssegnazioneState();
}

class _StepAssegnazioneState extends ConsumerState<StepAssegnazione> {
  @override
  Widget build(BuildContext context) {
    final techsAsync = ref.watch(techniciansProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      children: [
        Text(
          'Assegnazione',
          style: TextStyle(
            fontFamily: 'Archivo',
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

        // ── Blamed technician ──────────────────────────────────────────────
        // Above the list, including "Nessuna assegnazione": the refused technician is gone from the
        // selection, and clearing the field entirely is a legitimate repair the notice must not
        // look like a warning against.
        BlamedFieldNotice(field: 'assignedUserId', blamedField: widget.blamedField),

        // ── No assignment button ───────────────────────────────────────────
        _AssignmentOption(
          label: 'Nessuna assegnazione',
          isSelected: widget.state.assignedUserId == null,
          onTap: () => widget.onChanged(widget.state.copyWith(assignedUserId: null)),
        ),

        const SizedBox(height: 12),

        // ── Technician list ────────────────────────────────────────────────
        techsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Icon(LucideIcons.cloudOff, size: 32, color: context.colors.inkMuted),
                const SizedBox(height: 8),
                Text(
                  'Impossibile caricare i tecnici.\nSeleziona un ticket senza assegnazione.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
                ),
              ],
            ),
          ),
          data: (techs) {
            if (techs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Nessun tecnico disponibile.',
                  style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
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
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _AssignmentOption(
                    label: name,
                    isSelected: widget.state.assignedUserId == id,
                    onTap: () => widget.onChanged(widget.state.copyWith(assignedUserId: id)),
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
  const _AssignmentOption({required this.label, required this.isSelected, required this.onTap});

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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 14),
      child: Row(
        children: [
          Icon(
            isSelected ? LucideIcons.circleDot : LucideIcons.circle,
            size: 20,
            color: isSelected ? AppColors.Y : context.colors.inkMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: isSelected ? context.colors.ink : context.colors.inkMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
