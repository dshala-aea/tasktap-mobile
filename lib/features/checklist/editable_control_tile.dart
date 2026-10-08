// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../domain/checklist/checklist_items.dart';
import 'control_answer_field.dart';

/// A checklist row in editable mode: label, required mark, description and the typed input.
class EditableControlTile extends ConsumerWidget {
  const EditableControlTile({
    super.key,
    required this.reportId,
    required this.item,
    this.showAssetName = false,
  });

  final String reportId;
  final ControlItem item;
  final bool showAssetName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final control = item.control;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding + 8,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAssetName)
            Text(
              item.asset.name,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.ink),
            ),
          Row(
            children: [
              Flexible(
                child: Text(
                  control.label,
                  style: TextStyle(
                    fontWeight: showAssetName ? FontWeight.w400 : FontWeight.w600,
                    fontSize: showAssetName ? 12 : 14,
                    color: showAssetName ? c.inkMuted : c.ink,
                  ),
                ),
              ),
              if (control.isRequired)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('*', style: TextStyle(color: c.red, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if ((control.description ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(control.description!, style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ),
          const SizedBox(height: AppSpacing.sm),
          ControlAnswerField(reportId: reportId, control: control),
        ],
      ),
    );
  }
}
