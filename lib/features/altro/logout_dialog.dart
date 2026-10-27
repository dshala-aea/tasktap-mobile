// dart format width=100
import 'package:flutter/material.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import 'logout_flow.dart';

/// The explicit logout confirmation shown when the device holds unsent work.
///
/// Same Vetro chrome as [confirmDeleteDialog] (same card, same button language, same "Annulla on
/// the left"), but this dialog cannot be answered with one button: "Invia ora" is the primary
/// action because sending is what the technician almost always wants, "Esci comunque" is the
/// destructive one, and dismissing is always "stay signed in". The generic confirm is only used
/// when the count is zero — a dialog that says nothing is lost must not be dressed like one that
/// says a day's work is.
///
/// Returns the chosen [LogoutIntent], or null when the dialog was dismissed.
Future<LogoutIntent?> showUnsentWorkLogoutDialog(
  BuildContext context, {
  required int unsentCount,
}) {
  final plural = unsentCount != 1;
  final items = plural ? '$unsentCount elementi' : '1 elemento';
  final verb = plural ? 'verranno persi' : 'verrà perso';

  return showDialog<LogoutIntent>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elementi non inviati',
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ctx.colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$items non inviat${plural ? 'i' : 'o'} $verb se esci ora. '
              'Invia prima di uscire per non perderli.',
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: ctx.colors.inkMuted),
            ),
            const SizedBox(height: 20),
            // Primary, and first: sending is the action that loses nothing.
            AppButton(
              label: 'Invia ora',
              icon: const Icon(LucideIcons.send, size: 16),
              onPressed: () => Navigator.of(ctx).pop(LogoutIntent.sendNow),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Annulla',
                    onPressed: () => Navigator.of(ctx).pop(LogoutIntent.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton.danger(
                    label: 'Esci comunque',
                    onPressed: () => Navigator.of(ctx).pop(LogoutIntent.signOutAnyway),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Runs [run] (the flush + sign-out of "Invia ora", or a plain sign-out) behind a
/// non-dismissible progress sheet and returns its result — null if it failed.
///
/// The sheet owns the await and closes *itself*, but only while it is still the navigator's
/// current route — see [_LogoutProgressDialogState._run].
Future<LogoutResult?> runLogoutWithProgress(
  BuildContext context,
  Future<LogoutResult> Function() run,
) {
  return showDialog<LogoutResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LogoutProgressDialog(run: run),
  );
}

class _LogoutProgressDialog extends StatefulWidget {
  const _LogoutProgressDialog({required this.run});

  final Future<LogoutResult> Function() run;

  @override
  State<_LogoutProgressDialog> createState() => _LogoutProgressDialogState();
}

class _LogoutProgressDialogState extends State<_LogoutProgressDialog> {
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    LogoutResult? result;
    try {
      result = await widget.run();
    } catch (_) {
      // Nothing to sign out around: the caller treats null as "not done" and stays put.
      result = null;
    }

    if (!mounted) return;

    // Close the sheet only while it is still the route the navigator has on top.
    //
    // On a successful sign-out the router has already replaced the page underneath with
    // /login, and the Navigator — not this widget — is the one taking the sheet down: the
    // transition delegate pops the pageless sheet above the exiting page (`markForPop`), and
    // that exit animation outlives the wipe this method was waiting for. By the time we get
    // here the sheet is therefore still `mounted` but no longer `isCurrent`.
    //
    // `Navigator.pop()` does not pop "my" route; it pops the topmost *present* one. With the
    // sheet already exiting, that is the /login page — it was popped out of a navigator whose
    // router still believes it is there, leaving an empty navigator with nothing to rebuild
    // it, i.e. the blank screen that only an app restart cleared.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Invio in corso…',
                style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
