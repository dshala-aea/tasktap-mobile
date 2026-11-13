// dart format width=100
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';

/// Asks for the mandatory rejection reason and submits it.
///
/// [onSubmit] returns null when the server accepted the decision (the sheet closes), or a message
/// to show inline while keeping the sheet — and the typed reason — open. A 400 that the server
/// will repeat (already decided) is terminal: the caller can return null after surfacing it.
Future<void> showRejectReasonSheet(
  BuildContext context, {
  required String title,
  required Future<String?> Function(String reason) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RejectReasonSheet(title: title, onSubmit: onSubmit),
  );
}

class _RejectReasonSheet extends StatefulWidget {
  const _RejectReasonSheet({required this.title, required this.onSubmit});

  final String title;
  final Future<String?> Function(String reason) onSubmit;

  @override
  State<_RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<_RejectReasonSheet> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _canSubmit => !_busy && _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(_controller.text.trim());
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: context.colors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Il motivo è obbligatorio.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField.multiline(
            label: 'Motivo del rifiuto',
            controller: _controller,
            autofocus: true,
            maxLength: 1000,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.red),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Annulla',
                  size: AppButtonSize.sm,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton.danger(
                  label: 'Conferma rifiuto',
                  size: AppButtonSize.sm,
                  isLoading: _busy,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
