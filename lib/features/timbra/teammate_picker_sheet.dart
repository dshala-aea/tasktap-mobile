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
          const Padding(padding: EdgeInsets.only(top: 10, bottom: 4), child: SheetHandle()),
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
                      fontFamily: 'Inter',
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
                    children: [
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: widget.assignments.asMap().entries.map((entry) {
                            final i = entry.key;
                            final a = entry.value;
                            final isSelected = _selected.contains(a.userId);
                            final isLast = i == widget.assignments.length - 1;
                            // Same fallback contract as everywhere else colleagueNameProvider is
                            // read: fall back to the raw id rather than show nothing when the
                            // local mirror doesn't (yet) know this colleague.
                            final name =
                                ref.watch(colleagueNameProvider(a.userId)).valueOrNull ?? a.userId;

                            return InkWell(
                              onTap: () => _toggle(a.userId),
                              borderRadius: i == 0
                                  ? const BorderRadius.vertical(top: Radius.circular(20))
                                  : (isLast
                                        ? const BorderRadius.vertical(bottom: Radius.circular(20))
                                        : BorderRadius.zero),
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 56),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.base,
                                  vertical: AppSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.Y.withAlpha(31)
                                      : Colors.transparent,
                                  border: isLast
                                      ? null
                                      : Border(
                                          bottom: BorderSide(color: ctx.colors.borderLight),
                                        ),
                                ),
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
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: ctx.colors.ink,
                                        ),
                                      ),
                                    ),
                                    if (a.isLead)
                                      Text(
                                        'LEAD',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                          color: ctx.colors.inkMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              AppSpacing.base + MediaQuery.of(ctx).viewInsets.bottom,
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
