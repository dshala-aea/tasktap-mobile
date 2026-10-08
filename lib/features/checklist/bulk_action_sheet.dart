// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/widgets/widgets.dart';
import '../../domain/checklist/bulk_actions.dart';
import '../../domain/checklist/checklist_models.dart';
import '../../presentation/providers/report_editor_providers.dart';
import 'bulk_executor.dart';
import 'checklist_providers.dart';

/// Opens the bulk sheet for the assets currently shown. The undo snackbar is shown on the CALLER's
/// messenger so it outlives the sheet.
Future<void> showBulkActionSheet(
  BuildContext context, {
  required String reportId,
  required TicketChecklist tree,
  required Set<String> scopeAssetIds,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BulkActionSheet(
      reportId: reportId,
      tree: tree,
      scopeAssetIds: scopeAssetIds,
      messenger: messenger,
    ),
  );
}

enum _Mode { checked, notConforming, note }

class BulkActionSheet extends ConsumerStatefulWidget {
  const BulkActionSheet({
    super.key,
    required this.reportId,
    required this.tree,
    required this.scopeAssetIds,
    required this.messenger,
  });

  final String reportId;
  final TicketChecklist tree;
  final Set<String> scopeAssetIds;
  final ScaffoldMessengerState messenger;

  @override
  ConsumerState<BulkActionSheet> createState() => _BulkActionSheetState();
}

class _BulkActionSheetState extends ConsumerState<BulkActionSheet> {
  _Mode _mode = _Mode.checked;
  final _lineages = <String>{};
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _needsBoolean => _mode != _Mode.note;

  BulkRequest get _request => BulkRequest(
    assetIds: widget.scopeAssetIds,
    lineageIds: _lineages,
    boolValue: switch (_mode) {
      _Mode.checked => true,
      _Mode.notConforming => false,
      _Mode.note => null,
    },
    appendNote: _note.text,
  );

  Future<void> _apply(List<BulkLineageOption> options) async {
    if (_busy) return; // a replayed note would be appended twice
    setState(() {
      _busy = true;
      _error = null;
    });
    final answers = ref.read(controlAnswersProvider(widget.reportId));
    final plan = planBulk(request: _request, tree: widget.tree, existing: answers);
    if (plan.changes.isEmpty) {
      setState(() {
        _busy = false;
        _error = plan.problems.isNotEmpty
            ? describeBulkProblem(plan.problems.first, count: plan.problems.length)
            : 'Nessuna riga da aggiornare.';
      });
      return;
    }
    final executor = BulkExecutor(ref.read(reportEditorProvider(widget.reportId).notifier), widget.reportId);
    await executor.apply(plan);
    if (!mounted) return;
    final skipped = plan.skippedNonBoolean + plan.notApplicable + plan.problems.length;
    widget.messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Aggiornate ${plan.affected} righe'
          '${skipped > 0 ? ' ($skipped saltate)' : ''}.',
        ),
        action: SnackBarAction(label: 'Annulla', onPressed: () => executor.undo(plan)),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final all = bulkLineageOptions(widget.tree, widget.scopeAssetIds);
    final options = _needsBoolean ? all.where((o) => o.isBoolean).toList() : all;
    final pairs = options.where((o) => _lineages.contains(o.lineageId)).fold<int>(0, (s, o) => s + o.assetCount);
    final canApply = _lineages.isNotEmpty && (_mode != _Mode.note || _note.text.trim().isNotEmpty);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          children: [
            Text('Azioni in blocco',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: context.colors.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text('${widget.scopeAssetIds.length} asset mostrati',
                style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final e in {
                  _Mode.checked: 'Segna controllato',
                  _Mode.notConforming: 'Segna non conforme',
                  _Mode.note: 'Aggiungi nota',
                }.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _mode == e.key,
                    onSelected: (_) => setState(() {
                      _mode = e.key;
                      _lineages.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            for (final o in options)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(o.label),
                subtitle: Text('${o.assetCount} asset'),
                value: _lineages.contains(o.lineageId),
                onChanged: (v) => setState(() => v == true ? _lineages.add(o.lineageId) : _lineages.remove(o.lineageId)),
              ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField.multiline(
              label: _mode == _Mode.note ? 'Nota' : 'Nota (facoltativa)',
              controller: _note,
              maxLines: 3,
              maxLength: kBulkNoteMax,
              onChanged: (_) => setState(() {}),
            ),
            if (_lineages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Verranno aggiornate $pairs righe: ${widget.scopeAssetIds.length} asset × '
                  '${_lineages.length} ${_lineages.length == 1 ? 'controllo' : 'controlli'}.',
                  style: TextStyle(fontSize: 13, color: context.colors.ink),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!, style: TextStyle(color: context.colors.red, fontSize: 12)),
              ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Applica',
              isLoading: _busy,
              onPressed: canApply && !_busy ? () => _apply(options) : null,
            ),
          ],
        ),
      ),
    );
  }
}
