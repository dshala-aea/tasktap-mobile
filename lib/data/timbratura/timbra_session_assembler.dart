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

/// What kind of interval this is.
///
/// A break is its own row on the server (`WorkLogType.Break`, later classified as
/// `ShortBreak`/`LongBreak` when it closes). Sending only ordinary intervals leaves the break as a
/// bare gap: the phone shows a pausa from its own events, while the office sees two ordinary rows
/// with nothing between them.
enum WorkIntervalKind { ordinary, breakInterval }

/// One work interval ready to be sent to the server.
class WorkInterval {
  const WorkInterval({
    required this.clientId,
    required this.startTime,
    this.endTime,
    this.latitude,
    this.longitude,
    this.gpsAccuracyMeters,
    this.kind = WorkIntervalKind.ordinary,
  });

  /// Stable identifier derived from the opening event's id.
  final String clientId;

  /// Ordinary work or a break. A break opens on the `pausa` event and closes on `ripresa`.
  final WorkIntervalKind kind;

  /// UTC timestamp of the interval start (ingresso or ripresa event).
  final DateTime startTime;

  /// UTC timestamp of the interval end (fine or pausa event), or null if active.
  final DateTime? endTime;

  /// GPS position captured on the opening (ingresso/ripresa) event, or null when none was
  /// captured — the backend's `MobileSessionDto` carries a single lat/lng pair per interval
  /// ("GPS latitude at punch time"), so only the opener's position is meaningful here.
  final double? latitude;
  final double? longitude;

  /// Device-reported GPS accuracy radius (meters) captured alongside [latitude]/[longitude] on
  /// the opening event. Same "opener only" rule as the coordinates themselves.
  final double? gpsAccuracyMeters;

  @override
  String toString() =>
      'WorkInterval(clientId: $clientId, start: $startTime, end: $endTime, '
      'lat: $latitude, lng: $longitude, accuracy: $gpsAccuracyMeters)';
}

// ── Assembler ─────────────────────────────────────────────────────────────────

/// Folds [sessions] (in chronological order) into a list of [WorkInterval]s.
///
/// Rules:
/// - `ingresso` → opens an ordinary interval; clientId = event id
/// - `pausa`    → closes the open ordinary interval, then opens a BREAK interval at the same
///                instant; the break's clientId is the `pausa` event id
/// - `ripresa`  → closes the open BREAK interval, then opens an ordinary interval; clientId = the
///                `ripresa` event id
/// - `fine`     → closes whatever is open (ordinary or break) with that timestamp as endTime
/// - An open interval (no closing event yet) → endTime null (active)
/// - Events before a valid opener are ignored (defensive)
///
/// A break must be its own interval. Folding `pausa`/`ripresa` into the ordinary intervals only
/// (the old behaviour) left the break as a bare gap: the phone drew a pausa from its local events,
/// but the server received two ordinary rows and nothing between them, so the office/payroll never
/// saw a `WorkLogType.Break` and could not classify it as a short or long break.
///
/// [businessDateOf] maps an instant to the business calendar date it belongs to ([BusinessTime]
/// supplies this in the app; a plain function keeps this assembler pure and testable without a
/// zone). The upload queue is no longer day-scoped — a pending punch from ANY day is sent — so one
/// call can now see several days. Without this callback an 'ingresso' that finds an interval still
/// open closes it at its own timestamp: right within one day (a tap sequence that lost its close),
/// wrong across days, where it would invent up to a full day of paid time for a shift the
/// technician simply never clocked out of. With the callback such an opener leaves that interval
/// open instead (emitted as still active, which is what the local data actually says). A
/// `fine`/`pausa` from a later day still closes it: that is a genuine overnight shift. A break is
/// exempt from that guard: a pausa before midnight closed by a ripresa after it is a real break and
/// is emitted closed.
List<WorkInterval> assembleIntervals(
  List<WorkSession> sessions, {
  DateTime Function(DateTime instant)? businessDateOf,
}) {
  final intervals = <WorkInterval>[];

  String? openClientId;
  DateTime? openStart;
  WorkIntervalKind openKind = WorkIntervalKind.ordinary;
  double? openLatitude;
  double? openLongitude;
  double? openAccuracy;

  void addOpen(DateTime? end, {bool applyCrossDayGuard = false}) {
    if (openClientId == null || openStart == null) return;
    final crossesDay =
        applyCrossDayGuard &&
        openKind == WorkIntervalKind.ordinary &&
        end != null &&
        businessDateOf != null &&
        businessDateOf(openStart!) != businessDateOf(end);

    // Never emit an OPEN break, and never one whose close belongs to another business day.
    // The server allows one open row per user: an open break left behind by today's batch would
    // make the next day's ordinary interval collide with it. The break is still drawn locally from
    // the pausa; it is sent as soon as the ripresa (or fine) closes it on the same day. An
    // overnight break stays the gap it is today, deliberately, rather than risking a 409.
    if (openKind == WorkIntervalKind.breakInterval &&
        (end == null ||
            (businessDateOf != null && businessDateOf(openStart!) != businessDateOf(end)))) {
      openClientId = null;
      openStart = null;
      openKind = WorkIntervalKind.ordinary;
      openLatitude = null;
      openLongitude = null;
      openAccuracy = null;
      return;
    }

    intervals.add(
      WorkInterval(
        clientId: openClientId!,
        startTime: openStart!,
        endTime: crossesDay ? null : end,
        latitude: openLatitude,
        longitude: openLongitude,
        gpsAccuracyMeters: openAccuracy,
        kind: openKind,
      ),
    );
    openClientId = null;
    openStart = null;
    openKind = WorkIntervalKind.ordinary;
    openLatitude = null;
    openLongitude = null;
    openAccuracy = null;
  }

  void open({
    required String clientId,
    required DateTime start,
    required WorkIntervalKind kind,
    double? latitude,
    double? longitude,
    double? accuracy,
  }) {
    openClientId = clientId;
    openStart = start;
    openKind = kind;
    openLatitude = latitude;
    openLongitude = longitude;
    openAccuracy = accuracy;
  }

  for (final s in sessions) {
    final t = s.eventTime; // stored as UTC by the repo

    switch (s.eventType) {
      case 'ingresso':
        // Close any accidentally-open interval (defensive: shouldn't happen in normal flow).
        addOpen(t, applyCrossDayGuard: true);
        open(
          clientId: s.id,
          start: t,
          kind: WorkIntervalKind.ordinary,
          latitude: s.latitude,
          longitude: s.longitude,
          accuracy: s.gpsAccuracyMeters,
        );

      case 'pausa':
        // Close the ordinary interval, then open the break at the same instant. A pausa with no
        // open ordinary interval is ignored (defensive), as before.
        if (openClientId != null && openKind == WorkIntervalKind.ordinary) {
          addOpen(t);
          open(clientId: s.id, start: t, kind: WorkIntervalKind.breakInterval);
        }

      case 'ripresa':
        // Close the break (a break across midnight is still closed at the resume instant), then
        // open the next ordinary interval. If no break was open, this is just an ordinary opener,
        // matching the old defensive behaviour.
        addOpen(t, applyCrossDayGuard: openKind == WorkIntervalKind.ordinary);
        open(
          clientId: s.id,
          start: t,
          kind: WorkIntervalKind.ordinary,
          latitude: s.latitude,
          longitude: s.longitude,
          accuracy: s.gpsAccuracyMeters,
        );

      case 'fine':
        // Closes the ordinary interval or the break; a shift ended while on a break leaves no
        // ordinary interval after it.
        addOpen(t);

      default:
        // Unknown event type — ignore
        break;
    }
  }

  // If still open, emit the active interval (endTime null).
  addOpen(null);

  return intervals;
}
