// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereSessionAssembler
//
// Pure function: folds an ordered list of today's CantierePunche events into a
// list of site intervals that map 1-to-1 with the backend's
// `POST /api/cantiereworklog/mobile/sessions` batch DTO. Mirrors
// timbra_session_assembler.dart exactly, with the cantiere/customer/ticket
// context carried from the opener.
//
// Event vocabulary:
//   'ingresso' — opens a new interval (site context set here)
//   'uscita'   — closes the open interval; carries the clock-out screen's own fields
// ══════════════════════════════════════════════════════════════════════════════

import '../local/app_database.dart';

// ── DTO ───────────────────────────────────────────────────────────────────────

/// One cantiere work interval ready to be sent to the server.
class CantiereWorkInterval {
  const CantiereWorkInterval({
    required this.clientId,
    required this.cantiereId,
    required this.customerId,
    this.ticketId,
    this.description,
    required this.startTime,
    this.endTime,
    this.latitude,
    this.longitude,
    this.safetyNotes,
    this.departureLatitude,
    this.departureLongitude,
  });

  /// Stable identifier derived from the opening event's id.
  final String clientId;

  /// Site context, carried from the opening ('ingresso') event.
  final String cantiereId;
  final String customerId;
  final String? ticketId;

  /// Work description: the opener's, unless the clock-out carried one — see
  /// [assembleCantiereIntervals]'s 'uscita' rule.
  final String? description;

  /// UTC timestamp of the interval start ('ingresso' event).
  final DateTime startTime;

  /// UTC timestamp of the interval end ('uscita' event), or null if active.
  final DateTime? endTime;

  /// GPS position captured on the opening event, or null when none was captured.
  final double? latitude;
  final double? longitude;

  /// The clock-out screen's fields, carried from the closing ('uscita') event. Null on an
  /// interval that is still open on the device, and on one whose closing event recorded none.
  final String? safetyNotes;
  final double? departureLatitude;
  final double? departureLongitude;

  @override
  String toString() =>
      'CantiereWorkInterval(clientId: $clientId, cantiereId: $cantiereId, '
      'customerId: $customerId, ticketId: $ticketId, start: $startTime, end: $endTime, '
      'lat: $latitude, lng: $longitude, safetyNotes: $safetyNotes, '
      'departureLat: $departureLatitude, departureLng: $departureLongitude)';
}

// ── Assembler ─────────────────────────────────────────────────────────────────

/// Folds [events] (in chronological order) into a list of [CantiereWorkInterval]s.
///
/// Rules:
/// - `ingresso` → opens interval; clientId = event id; carries site context.
/// - `uscita`   → closes the open interval with that timestamp as endTime, and contributes the
///   clock-out fields (description, safety note, departure GPS).
/// - An open interval (no closing event yet) → endTime null (active). A close with no open
///   interval, or an event missing its site context, is ignored (defensive — shouldn't happen in
///   normal flow).
///
/// [businessDateOf] maps an instant to the business calendar date it belongs to (see
/// timbra_session_assembler.dart's identical parameter). The upload queue is no longer day-scoped,
/// so one call can carry several days: an 'ingresso' from a LATER day must not close a still-open
/// interval it finds — that would invent up to a full day of worksite time — so it leaves it open
/// instead. An 'uscita' from a later day still closes it: a genuine overnight visit.
List<CantiereWorkInterval> assembleCantiereIntervals(
  List<CantierePunche> events, {
  DateTime Function(DateTime instant)? businessDateOf,
}) {
  final intervals = <CantiereWorkInterval>[];

  String? openClientId;
  String? openCantiereId;
  String? openCustomerId;
  String? openTicketId;
  String? openDescription;
  DateTime? openStart;
  double? openLatitude;
  double? openLongitude;

  /// [endTime] is null when the interval must stay open (see [businessDateOf] above).
  ///
  /// [closing] is the 'uscita' event doing the closing, when there is one. Its own fields are the
  /// clock-out screen's answers and win over the opener's where the two overlap
  /// ([CantierePunche.description]): the online `end` route overwrites the row's Description with
  /// whatever was typed on leaving, so an offline close that kept the arrival note instead would
  /// submit a different record than the same visit made online.
  void closeOpen(DateTime? endTime, {CantierePunche? closing}) {
    // Captured-and-mutated variables are never promoted by flow analysis, even after a null
    // check — so the check has to run against local, single-assignment copies instead.
    final clientId = openClientId;
    final cantiereId = openCantiereId;
    final customerId = openCustomerId;
    final start = openStart;
    if (clientId == null || start == null || cantiereId == null || customerId == null) {
      return;
    }
    intervals.add(
      CantiereWorkInterval(
        clientId: clientId,
        cantiereId: cantiereId,
        customerId: customerId,
        ticketId: openTicketId,
        description: closing?.description ?? openDescription,
        startTime: start,
        endTime: endTime,
        latitude: openLatitude,
        longitude: openLongitude,
        // Only meaningful together with a real end: an interval left open has not reached the
        // clock-out screen yet, so it can carry no safety note and no departure fix.
        safetyNotes: endTime == null ? null : closing?.safetyNotes,
        departureLatitude: endTime == null ? null : closing?.departureLatitude,
        departureLongitude: endTime == null ? null : closing?.departureLongitude,
      ),
    );
    openClientId = null;
    openCantiereId = null;
    openCustomerId = null;
    openTicketId = null;
    openDescription = null;
    openStart = null;
    openLatitude = null;
    openLongitude = null;
  }

  for (final e in events) {
    final t = e.eventTime; // stored as UTC by the repo

    switch (e.eventType) {
      case 'ingresso':
        // Close any accidentally-open interval (defensive: shouldn't happen in normal flow) —
        // unless it opened on an earlier business day, in which case it stays open (see above).
        final openStartNow = openStart;
        final crossesDay =
            openStartNow != null &&
            businessDateOf != null &&
            businessDateOf(openStartNow) != businessDateOf(t);
        closeOpen(crossesDay ? null : t);
        openClientId = e.id;
        openCantiereId = e.cantiereId;
        openCustomerId = e.customerId;
        openTicketId = e.ticketId;
        openDescription = e.description;
        openStart = t;
        openLatitude = e.latitude;
        openLongitude = e.longitude;

      case 'uscita':
        closeOpen(t, closing: e);

      default:
        // Unknown event type — ignore.
        break;
    }
  }

  // If still open, emit an active interval (endTime null). Same local-copy reasoning as
  // closeOpen above.
  final finalClientId = openClientId;
  final finalCantiereId = openCantiereId;
  final finalCustomerId = openCustomerId;
  final finalStart = openStart;
  if (finalClientId != null &&
      finalStart != null &&
      finalCantiereId != null &&
      finalCustomerId != null) {
    intervals.add(
      CantiereWorkInterval(
        clientId: finalClientId,
        cantiereId: finalCantiereId,
        customerId: finalCustomerId,
        ticketId: openTicketId,
        description: openDescription,
        startTime: finalStart,
        endTime: null,
        latitude: openLatitude,
        longitude: openLongitude,
      ),
    );
  }

  return intervals;
}
