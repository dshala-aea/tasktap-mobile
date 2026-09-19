// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// TeammatePickerSheet
//
// Multi-select checkbox list for "Seleziona squadra" on CantiereTimbraScreen — a lead picking
// which assigned teammates to batch-start a cantiere clock-in for. No multi-select-people widget
// existed anywhere in this app before this (confirmed via a full-repo grep during planning), so
// this is built from scratch, visually based on this same screen's own single-select cantiere
// picker (_CheckInBody's AppCard/InkWell row list in cantiere_timbra_screen.dart) — swapping the
// single-select highlight for a per-row checkbox toggle.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../../core/theme/app_text_styles.dart';

/// Opens the teammate picker as a bottom sheet. Returns the selected userIds, or null if the
/// technician dismissed the sheet without confirming a selection.
Future<List<String>?> openTeammatePickerSheet(
  BuildContext context, {
  required List<CantiereCrewAssignmentDto> assignments,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _TeammatePickerSheetContent(assignments: assignments),
  );
}

class _TeammatePickerSheetContent extends ConsumerStatefulWidget {
  const _TeammatePickerSheetContent({required this.assignments});

  final List<CantiereCrewAssignmentDto> assignments;

  @override
  ConsumerState<_TeammatePickerSheetContent> createState() => _TeammatePickerSheetContentState();
}

class _TeammatePickerSheetContentState extends ConsumerState<_TeammatePickerSheetContent> {
  final Set<String> _selected = {};

  void _toggle(String userId) {
    setState(() {
      if (!_selected.remove(userId)) _selected.add(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: AppSpacing.xs),
            child: SheetHandle(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Seleziona squadra',
                    style: TextStyle(
                      fontFamily: 'Archivo Narrow',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ctx.colors.ink,
                    ),
                  ),
                ),
                HeaderIconBtn(
                  icon: LucideIcons.x,
                  label: 'Chiudi',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: ctx.colors.borderLight),
          Expanded(
            child: widget.assignments.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Nessun membro assegnato a questo cantiere.'),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      AppSpacing.base,
                      AppSpacing.pagePadding,
                      AppSpacing.base,
                    ),
                    // One `AppCard.pressable` per row, same selectable-row primitive
                    // `seleziona_cantiere_screen.dart`'s own single-select cantiere picker uses —
                    // this used to hand-roll a single `AppCard` wrapping a `Column` of raw
                    // `InkWell`s with a manually computed top/bottom corner radius per row index, a
                    // second selectable-row pattern doing the same job as that screen's own one.
                    children: widget.assignments.map((a) {
                      final isSelected = _selected.contains(a.userId);
                      // Same fallback contract as everywhere else colleagueNameProvider is read:
                      // fall back to the raw id rather than show nothing when the local mirror
                      // doesn't (yet) know this colleague.
                      final name =
                          ref.watch(colleagueNameProvider(a.userId)).valueOrNull ?? a.userId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        // A screen reader otherwise announces only the name — never whether this
                        // row is currently checked — because the checkbox-like icon is purely
                        // visual (an Icon carries no semantic checked state on its own).
                        child: Semantics(
                          button: true,
                          checked: isSelected,
                          child: AppCard.pressable(
                            onTap: () => _toggle(a.userId),
                            backgroundColor: isSelected ? AppColors.Y.withAlpha(31) : null,
                            borderColor: isSelected ? AppColors.Y : null,
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? LucideIcons.checkCircle2 : LucideIcons.square,
                                  size: 20,
                                  color: isSelected ? AppColors.Y : ctx.colors.inkMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: ctx.colors.ink,
                                    ),
                                  ),
                                ),
                                if (a.isLead)
                                  Text(
                                    'LEAD',
                                    style: TextStyle(
                                      fontFamily: 'Archivo',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: ctx.colors.inkMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              // Keyboard inset (viewInsets) plus the bottom safe-area/home-indicator inset
              // (padding) — the button otherwise sat flush against the home indicator on notched
              // devices whenever the keyboard was closed, since viewInsets.bottom is 0 in that
              // state and carries none of the safe-area reservation on its own. Same fix as
              // compartment_sheet.dart's own scroll padding.
              AppSpacing.base +
                  MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom,
            ),
            child: AppButton(
              label: 'Conferma (${_selected.length})',
              onPressed: _selected.isEmpty ? null : () => Navigator.of(ctx).pop(_selected.toList()),
            ),
          ),
        ],
      ),
    );
  }
}
