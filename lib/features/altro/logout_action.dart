// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import '../../data/auth/session_recovery_providers.dart';
import '../../presentation/providers/auth_providers.dart';
import 'logout_dialog.dart';
import 'logout_flow.dart';

// ══════════════════════════════════════════════════════════════════════════════
// confirmLogout — the one widget half of "Esci dall'account"
//
// Logout wipes the local database, so the only acceptable behaviour is: count what is
// unsent, name that count, and let "Invia ora" try before anything is lost. That rule
// used to live inside Impostazioni's own `_confirmLogout`. The Altro hub and the Profilo
// screen each ran a generic "Sei sicuro?" and then called `signOut()` directly, which
// destroyed exactly the work the count would have named — the same silent loss the
// count dialog exists to prevent, reachable from two other buttons.
//
// Keeping the action in one place is what makes "no logout path can skip the count" a
// property of the code rather than a review note: a new logout row has to call this to
// get the standard confirmation at all.
//
// `logout_flow.dart` still holds the decision logic and stays Flutter-free so it can be
// tested without pumping a widget; this file is only the asking.
// ══════════════════════════════════════════════════════════════════════════════

/// Ask, then act: the count-naming dialog when the device holds unsent work, the generic
/// confirmation when it holds none, and "Invia ora" gets one attempt before anything is lost.
///
/// [title] and [confirmLabel] let each surface keep its own wording ("Esci dall'account" /
/// "Esci" in Altro and Impostazioni, "Disconnetti" in Profilo) — only the wording differs; the
/// decision does not.
Future<void> confirmLogout(
  BuildContext context,
  WidgetRef ref, {
  String title = "Esci dall'account",
  String confirmLabel = 'Esci',
}) async {
  final flow = LogoutFlow(
    unsentCount: () async => (await ref.read(unsentWorkCounterProvider).count()).total,
    flush: () => ref.read(unsentWorkFlusherProvider).flush(),
    signOut: () => ref.read(loginProvider.notifier).signOut(),
  );

  final prompt = await flow.prepare();
  if (!context.mounted) return;

  LogoutIntent? intent;
  if (prompt.requiresConfirmation) {
    intent = await showUnsentWorkLogoutDialog(context, unsentCount: prompt.unsentCount);
  } else {
    final confirmed = await confirmDeleteDialog(
      context,
      title: title,
      message: 'Sei sicuro di voler uscire dall\'account?',
      confirmLabel: confirmLabel,
    );
    intent = confirmed ? LogoutIntent.signOutAnyway : null;
  }
  if (intent == null || intent == LogoutIntent.cancel) return;
  // Re-read through a fresh non-null local: a closure captures the *variable*, not the
  // promotion, so `intent` cannot be used directly inside the callback below.
  final chosen = intent;
  if (!context.mounted) return;

  final result = await runLogoutWithProgress(context, () => flow.apply(chosen));
  if (result == null || result.signedOut) return;

  // "Invia ora" could not send everything. Stay signed in — that is the point — and say how
  // much is still stuck so the technician can retry or leave deliberately.
  if (result.remaining > 0 && context.mounted) {
    showAppToast(
      context,
      message: result.remaining == 1
          ? '1 elemento non è stato inviato. Riprova o esci comunque.'
          : '${result.remaining} elementi non sono stati inviati. Riprova o esci comunque.',
      tone: ToastTone.warning,
    );
  }
}
