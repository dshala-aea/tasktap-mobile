// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// LogoutFlow
//
// The decision half of "Esci dall'account", with no Flutter in it so the rule can
// be tested without pumping a widget: a logout with unsent work must not happen
// until the technician has answered a dialog that names the count. The generic
// "Sei sicuro?" is only ever shown for a device with nothing to lose.
//
// The widget half (`_LogoutSettingRow` in impostazioni_screen.dart) does the
// asking; this does the doing. Splitting them is what makes the requirement
// ("manual logout with N>0 requires confirmation") an assertion instead of a code
// review.
// ══════════════════════════════════════════════════════════════════════════════

/// What the technician chose in the unsent-work dialog.
///
/// [cancel] covers the dialog being dismissed (back button, tap outside) — never a logout.
enum LogoutIntent {
  /// Try to send everything first; log out only if nothing is left.
  sendNow,

  /// Consented data loss: the dialog named the count, the technician went ahead.
  signOutAnyway,

  /// Close the dialog and stay signed in.
  cancel,
}

/// What the app found before asking.
class LogoutPrompt {
  /// Nothing unsent: the ordinary "Sei sicuro di voler uscire?" confirmation is enough.
  const LogoutPrompt.generic() : unsentCount = 0;

  /// [unsentCount] items would be destroyed by the wipe the logout performs.
  const LogoutPrompt.unsent(this.unsentCount);

  final int unsentCount;

  /// True when the caller must show the explicit, count-naming dialog instead of the generic one.
  bool get requiresConfirmation => unsentCount > 0;
}

/// What actually happened after a choice.
class LogoutResult {
  const LogoutResult({required this.signedOut, this.remaining = 0});

  final bool signedOut;

  /// Items still unsent after a failed "Invia ora". Only meaningful when [signedOut] is false —
  /// the caller keeps the session and tells the technician, rather than logging out and losing
  /// exactly what the flush could not send.
  final int remaining;
}

class LogoutFlow {
  LogoutFlow({
    required Future<int> Function() unsentCount,
    required Future<void> Function() flush,
    required Future<void> Function() signOut,
  }) : _unsentCount = unsentCount,
       _flush = flush,
       _signOut = signOut;

  final Future<int> Function() _unsentCount;
  final Future<void> Function() _flush;
  final Future<void> Function() _signOut;

  int _lastCount = 0;

  /// Whether the generic confirmation is enough ([LogoutPrompt.generic]) or the count-naming one
  /// is required ([LogoutPrompt.unsent]).
  Future<LogoutPrompt> prepare() async {
    _lastCount = await _unsentCount();
    return _lastCount > 0 ? LogoutPrompt.unsent(_lastCount) : const LogoutPrompt.generic();
  }

  /// Carry out [intent]. Only this method ever calls [signOut], so no path can end the session
  /// without first having been through [prepare]/its dialog.
  Future<LogoutResult> apply(LogoutIntent intent) async {
    switch (intent) {
      case LogoutIntent.cancel:
        return const LogoutResult(signedOut: false);

      case LogoutIntent.signOutAnyway:
        await _signOut();
        return const LogoutResult(signedOut: true);

      case LogoutIntent.sendNow:
        await _flush();
        final remaining = await _unsentCount();
        if (remaining > 0) {
          // Do NOT log out: that is the whole point. The technician is told what is still stuck.
          return LogoutResult(signedOut: false, remaining: remaining);
        }
        await _signOut();
        return const LogoutResult(signedOut: true);
    }
  }
}
