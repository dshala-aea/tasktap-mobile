// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// ProdottoMultiPickerSheet
//
// Multi-select checkbox list for "Asset coperti" on AdminContractFormScreen — replaces the old
// single-value ProdottoAssistenzaId picker (removed once the many-to-many join tables made it
// dead server-side; see admin_contract_form_screen.dart's own header comment). Built directly on
// `TeammatePickerSheet`'s own pattern (lib/features/timbra/teammate_picker_sheet.dart) — the only
// multi-select-people/-entity widget in this app before this — swapping teammates for prodotti.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';

/// Opens the asset picker as a bottom sheet. [prodotti] is the full candidate list (each a raw
/// `{id, name}` map, same shape `AdminApiClient.fetchProdottiAssistenza` returns); [initialIds]
/// are the ids already selected. Returns the confirmed selection, or null if dismissed.
Future<List<String>?> openProdottoMultiPickerSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> prodotti,
  required List<String> initialIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ProdottoMultiPickerSheetContent(prodotti: prodotti, initialIds: initialIds),
  );
}

class _ProdottoMultiPickerSheetContent extends StatefulWidget {
  const _ProdottoMultiPickerSheetContent({required this.prodotti, required this.initialIds});

  final List<Map<String, dynamic>> prodotti;
  final List<String> initialIds;

  @override
  State<_ProdottoMultiPickerSheetContent> createState() => _ProdottoMultiPickerSheetContentState();
}

class _ProdottoMultiPickerSheetContentState extends State<_ProdottoMultiPickerSheetContent> {
  late final Set<String> _selected = {...widget.initialIds};

  void _toggle(String prodottoId) {
    setState(() {
      if (!_selected.remove(prodottoId)) _selected.add(prodottoId);
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
                    'Asset coperti',
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
            child: widget.prodotti.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Nessun asset disponibile per questo cliente.'),
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
                          children: widget.prodotti.asMap().entries.map((entry) {
                            final i = entry.key;
                            final p = entry.value;
                            final id = p['id'] as String;
                            final name = p['name'] as String? ?? id;
                            final isSelected = _selected.contains(id);
                            final isLast = i == widget.prodotti.length - 1;

                            // A screen reader otherwise announces only the name — never whether
                            // this row is currently checked — because the checkbox-like icon is
                            // purely visual (an Icon carries no semantic checked state on its
                            // own). Same reasoning as TeammatePickerSheet's own row.
                            return Semantics(
                              button: true,
                              checked: isSelected,
                              child: InkWell(
                                onTap: () => _toggle(id),
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
                                        : Border(bottom: BorderSide(color: ctx.colors.borderLight)),
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
                                    ],
                                  ),
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
              onPressed: () => Navigator.of(ctx).pop(_selected.toList()),
            ),
          ),
        ],
      ),
    );
  }
}
