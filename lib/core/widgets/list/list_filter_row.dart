import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../app_tappable.dart';
import 'list_models.dart';

/// The prototype's quick-filter row: a wrapped row of mono uppercase chips plus the trailing red
/// `Filtri` chip that opens the caller's filter sheet.
///
/// The chips are presets (one facet at a time, `Attivi`/`Tutti`/…). Screens with combinable facets
/// keep every facet reachable through [onOpenFilters]; the shell does not know either model.
///
/// ```dart
/// ListFilterRow(
///   filters: const [ListFilterChipData(label: 'Attivi'), ListFilterChipData(label: 'Tutti')],
///   activeIndex: 0,
///   onSelected: (chip) => setState(...),
///   onOpenFilters: () => showFilterSheet(...),
/// )
/// ```
class ListFilterRow extends StatelessWidget {
  const ListFilterRow({
    super.key,
    this.filters = const [],
    this.activeId,
    this.activeIndex,
    this.onSelected,
    this.onOpenFilters,
    this.filtersLabel = 'Filtri',
  });

  final List<ListFilterChipData> filters;

  /// Selection by [ListFilterChipData.id]; wins over [activeIndex] when both are supplied.
  final String? activeId;

  /// Selection by position, for screens whose chips have no stable id.
  final int? activeIndex;

  final ValueChanged<ListFilterChipData>? onSelected;

  /// Opens the caller-supplied filter sheet. Renders the trailing red chip when non-null.
  final VoidCallback? onOpenFilters;

  final String filtersLabel;

  bool _isActive(int index) {
    if (activeId != null) return filters[index].id == activeId;
    return activeIndex == index;
  }

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty && onOpenFilters == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        0,
        AppSpacing.pagePadding,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < filters.length; i++)
                  _FilterChip(
                    label: filters[i].label,
                    active: _isActive(i),
                    onTap: onSelected == null
                        ? null
                        : () => onSelected!(filters[i]),
                  ),
              ],
            ),
          ),
          if (onOpenFilters != null) ...[
            const SizedBox(width: 6),
            _FilterChip(
              label: filtersLabel,
              accent: true,
              onTap: onOpenFilters,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    this.active = false,
    this.accent = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = active ? colors.ink : colors.surface;
    final fg = active
        ? colors.surface
        : (accent ? colors.accentInk : colors.inkMuted);
    final border = active
        ? colors.ink
        : (accent ? colors.accentInk : colors.borderLight);

    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.32,
            color: fg,
          ),
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: active,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: AppTappable(
        onTap: onTap,
        borderRadius: AppRack.freeShape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(widthFactor: 1, heightFactor: 1, child: chip),
        ),
      ),
    );
  }
}
