import 'package:flutter/material.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import 'ticket_detail_api_client.dart';

/// More controls than this and the sections start collapsed (unless the caller opts out).
const int kControlGroupCollapseAbove = 10;

/// A ticket's checklist as nested, collapsible sections, mirroring the template's hierarchy instead
/// of one flat run of controls. Only the ticket-level checklist uses it; per-asset checklists are
/// rendered by their own screens, unchanged.
///
/// Sections start open — nothing hidden — unless the checklist has more than [collapseAbove]
/// controls, when they start collapsed with Espandi/Comprimi tutto (null never collapses by
/// default: the fill-in form uses that, so a required control is never hidden on arrival). A
/// collapsed section keeps its children alive, so a half-typed answer survives a collapse.
class ControlGroupAccordion extends StatefulWidget {
  const ControlGroupAccordion({
    super.key,
    required this.groups,
    required this.controlBuilder,
    this.collapseAbove = kControlGroupCollapseAbove,
    this.summaryFor,
  });

  final List<TicketControlGroupDto> groups;

  /// Builds one control row. [FlatTicketControl.groupPath] is the section path down to it.
  final Widget Function(FlatTicketControl flat) controlBuilder;

  final int? collapseAbove;

  /// Optional header caption for a section, from every control in it and its subsections.
  final String? Function(List<TicketControlDto> controls)? summaryFor;

  @override
  State<ControlGroupAccordion> createState() => _ControlGroupAccordionState();
}

class _ControlGroupAccordionState extends State<ControlGroupAccordion> {
  final Map<String, bool> _overrides = {};
  bool? _allOpen;

  List<TicketControlDto> _controlsOf(TicketControlGroupDto g) => [
    ...g.controls,
    for (final s in g.subgroups) ..._controlsOf(s),
  ];

  bool get _many {
    final limit = widget.collapseAbove;
    if (limit == null) return false;
    return widget.groups.expand(_controlsOf).length > limit;
  }

  bool _isOpen(String id) => _overrides[id] ?? _allOpen ?? !_many;

  void _toggle(String id) => setState(() => _overrides[id] = !_isOpen(id));

  void _setAll(bool open) => setState(() {
    _overrides.clear();
    _allOpen = open;
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_many)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => _setAll(true), child: const Text('Espandi tutto')),
              TextButton(onPressed: () => _setAll(false), child: const Text('Comprimi tutto')),
            ],
          ),
        for (final g in widget.groups) _group(context, g, '', 0, colors),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    TicketControlGroupDto group,
    String parentPath,
    int depth,
    AppPalette colors,
  ) {
    final all = _controlsOf(group);
    if (all.isEmpty) return const SizedBox.shrink();
    final path = parentPath.isEmpty ? group.name : '$parentPath › ${group.name}';
    final open = _isOpen(group.id);
    final summary = widget.summaryFor?.call(all);
    return Padding(
      padding: EdgeInsets.only(left: depth > 0 ? AppSpacing.md : 0, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: group.name,
            child: InkWell(
              onTap: () => _toggle(group.id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Icon(
                      open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                      size: 18,
                      color: colors.inkMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        group.name,
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: depth == 0 ? 15 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (summary != null)
                      Text(summary, style: TextStyle(color: colors.inkMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          Visibility(
            visible: open,
            maintainState: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in group.controls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: widget.controlBuilder(FlatTicketControl(groupPath: path, control: c)),
                  ),
                for (final s in group.subgroups) _group(context, s, path, depth + 1, colors),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
