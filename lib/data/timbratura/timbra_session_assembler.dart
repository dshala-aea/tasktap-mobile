// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// TimbraSessionAssembler
//
// Pure function: folds an ordered list of today's WorkSession events into a
// list of work intervals that map 1-to-1 with backend WorkLog rows.
//
// Event vocabulary (from timbra_providers.dart consts):
//   'ingresso'  — opens a new interval
//   'fine'      — closes the open interval (shift end)
//   'pausa'     — closes the open interval (pause start)
//   'ripresa'   — opens a new interval (resume after pause)
//
// clientId is derived deterministically from the opening event's id so that
// re-syncing the same data maps to the same server row (idempotent).
// ══════════════════════════════════════════════════════════════════════════════

import '../local/app_database.dart';

// ── DTO ───────────────────────────────────────────────────────────────────────

/// One work interval ready to be sent to the server.
class WorkInterval {
  const WorkInterval({
    required this.clientId,
    required this.startTime,
    this.endTime,
  });

  /// Stable identifier derived from the opening event's id.
  final String clientId;

  /// UTC timestamp of the interval start (ingresso or ripresa event).
  final DateTime startTime;

  /// UTC timestamp of the interval end (fine or pausa event), or null if active.
  final DateTime? endTime;

  @override
  String toString() =>
      'WorkInterval(clientId: $clientId, start: $startTime, end: $endTime)';
}

// ── Assembler ─────────────────────────────────────────────────────────────────

/// Folds [sessions] (in chronological order) into a list of [WorkInterval]s.
///
/// Rules:
/// - `ingresso` → opens interval; clientId = event id
/// - `ripresa`  → opens interval; clientId = event id
/// - `pausa`    → closes the open interval with that timestamp as endTime
/// - `fine`     → closes the open interval with that timestamp as endTime
/// - An open interval (no closing event yet) → endTime null (active)
/// - Events before a valid opener are ignored (defensive)
List<WorkInterval> assembleIntervals(List<WorkSession> sessions) {
  final intervals = <WorkInterval>[];

  String? openClientId;
  DateTime? openStart;

  for (final s in sessions) {
    final t = s.eventTime; // stored as UTC by the repo

    switch (s.eventType) {
      case 'ingresso':
      case 'ripresa':
        // Close any accidentally-open interval (defensive: shouldn't happen in normal flow)
        if (openClientId != null && openStart != null) {
          intervals.add(WorkInterval(
            clientId: openClientId,
            startTime: openStart,
            endTime: t,
          ));
        }
        openClientId = s.id;
        openStart = t;

      case 'fine':
      case 'pausa':
        if (openClientId != null && openStart != null) {
          intervals.add(WorkInterval(
            clientId: openClientId,
            startTime: openStart,
            endTime: t,
          ));
          openClientId = null;
          openStart = null;
        }
        // else: close event with no open interval — ignore

      default:
        // Unknown event type — ignore
        break;
    }
  }

  // If still open, emit active interval (endTime null).
  if (openClientId != null && openStart != null) {
    intervals.add(WorkInterval(
      clientId: openClientId,
      startTime: openStart,
      endTime: null,
    ));
  }

  return intervals;
}
