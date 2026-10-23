// ══════════════════════════════════════════════════════════════════════════════
// ClockDisagreement
//
// "Was this phone's clock off?" — the one fact about a timer session the phone
// cannot work out for itself. The server measures the device reading against its
// own receipt instant and answers with the gap only when it is a disagreement by
// the single definition that exists (`WorkLogClocks.IsFlagged`, ten minutes).
//
// Two responses carry it, and both feed this notifier:
//   * the online start's reply (`TicketTimerStart.clockDisagreementSeconds`);
//   * the queued batch upsert's per-session echo, which arrives later, when the
//     sync finally goes through (`TicketTimerSyncService`).
//
// In memory on purpose. The durable copy lives on the server, where the office's
// Correzioni list reads it; the phone only has to say it once, while the
// technician is looking at the clock. A Drift column would be a second,
// divergent copy of a value the server owns — and, per the plan's §2, the reading
// is taken at send time, so persisting it would also freeze a reading that was
// only ever true for one request.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signed seconds the server reported for each ticket whose clock disagreed, keyed by ticket id.
///
/// Positive means the phone was ahead of the server; negative means behind.
final clockDisagreementProvider =
    NotifierProvider<ClockDisagreementNotifier, Map<String, int>>(
      ClockDisagreementNotifier.new,
    );

class ClockDisagreementNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  /// Records the gap for one ticket. Idempotent: a batch that retries the same session reports the
  /// same value again, and re-notifying for an unchanged map would rebuild every listener for
  /// nothing.
  void record(String ticketId, int seconds) {
    if (state[ticketId] == seconds) return;
    state = {...state, ticketId: seconds};
  }

  /// The technician has seen it (and may already have fixed the phone's clock). The server keeps the
  /// record; only this screen's reminder goes away.
  void dismiss(String ticketId) {
    if (!state.containsKey(ticketId)) return;
    state = {...state}..remove(ticketId);
  }
}

/// How far off, in whole minutes, with the direction stated as a disagreement rather than as an
/// accusation — "segnava 12 min avanti", never "sei in ritardo".
///
/// Truncating, like the office's Correzioni column: 12 min 59 s reads as "12 min", and the number
/// is never rounded UP past the threshold the server used to decide there was a disagreement.
String describeClockDisagreement(int seconds) {
  final minutes = seconds.abs() ~/ 60;
  final direction = seconds > 0 ? 'avanti' : 'indietro';
  return '$minutes min $direction';
}

// ── The punch screens ─────────────────────────────────────────────────────────

/// The plain-timbra banner: the last disagreement the server reported for a queued timbra batch.
///
/// Not keyed by anything, unlike [clockDisagreementProvider]: a punch has no ticket, and the advice
/// is about this phone, not about one row. One value is enough because every session in a batch
/// carried the same send-time reading — the server compares per request, not per punch.
final timbraClockDisagreementProvider =
    NotifierProvider<ScreenClockDisagreementNotifier, int?>(
      ScreenClockDisagreementNotifier.new,
    );

/// The cantiere banner, a separate notifier from [timbraClockDisagreementProvider] on purpose: the
/// two screens run their own punch flow, and a cantiere batch's advice has no business appearing
/// over a plain attendance punch.
final cantiereClockDisagreementProvider =
    NotifierProvider<ScreenClockDisagreementNotifier, int?>(
      ScreenClockDisagreementNotifier.new,
    );

/// One screen's "the server says my clock was off" line. Same contract as the ticket map above:
/// record is idempotent (a batch retried every sync reports the same gap) and dismiss only clears
/// this screen's reminder — the server keeps the record.
class ScreenClockDisagreementNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void record(int seconds) {
    if (state == seconds) return;
    state = seconds;
  }

  void dismiss() {
    if (state == null) return;
    state = null;
  }
}
