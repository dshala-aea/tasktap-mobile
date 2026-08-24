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
//   'uscita'   — closes the open interval (no context of its own)
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
  });

  /// Stable identifier derived from the opening event's id.
  final String clientId;

  /// Site context, carried from the opening ('ingresso') event.
  final String cantiereId;
  final String customerId;
  final String? ticketId;
  final String? description;

  /// UTC timestamp of the interval start ('ingresso' event).
  final DateTime startTime;

  /// UTC timestamp of the interval end ('uscita' event), or null if active.
  final DateTime? endTime;

  /// GPS position captured on the opening event, or null when none was captured.
  final double? latitude;
  final double? longitude;

  @override
  String toString() =>
      'CantiereWorkInterval(clientId: $clientId, cantiereId: $cantiereId, '
      'customerId: $customerId, ticketId: $ticketId, start: $startTime, end: $endTime, '
      'lat: $latitude, lng: $longitude)';
}

// ── Assembler ─────────────────────────────────────────────────────────────────

/// Folds [events] (in chronological order) into a list of [CantiereWorkInterval]s.
///
/// Rules:
/// - `ingresso` → opens interval; clientId = event id; carries site context.
/// - `uscita`   → closes the open interval with that timestamp as endTime.
/// - An open interval (no closing event yet) → endTime null (active).
/// - A close event with no open interval, or an event missing its site context, is ignored
///   (defensive — shouldn't happen in normal flow).
List<CantiereWorkInterval> assembleCantiereIntervals(List<CantierePunche> events) {
  final intervals = <CantiereWorkInterval>[];

  String? openClientId;
  String? openCantiereId;
  String? openCustomerId;
  String? openTicketId;
  String? openDescription;
  DateTime? openStart;
  double? openLatitude;
  double? openLongitude;

  void closeOpen(DateTime endTime) {
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
        description: openDescription,
        startTime: start,
        endTime: endTime,
        latitude: openLatitude,
        longitude: openLongitude,
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
        // Close any accidentally-open interval (defensive: shouldn't happen in normal flow).
        closeOpen(t);
        openClientId = e.id;
        openCantiereId = e.cantiereId;
        openCustomerId = e.customerId;
        openTicketId = e.ticketId;
        openDescription = e.description;
        openStart = t;
        openLatitude = e.latitude;
        openLongitude = e.longitude;

      case 'uscita':
        closeOpen(t);

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
