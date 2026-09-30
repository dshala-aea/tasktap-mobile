// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// Remote-origin shifts
//
// A shift is REMOTE-ORIGIN when its opener is an orphan-marked `ingresso`: the reconciler
// backfilled it because the server already had an open day this device never created (started on
// the office web or another phone). It lives on the server under a row whose clientId this device
// does not know, so the mobile batch (POST /worklog/mobile/sessions, matched by ClientId) can
// never act on it. Fine / Pausa / Ripresa taps on it go to the plain REST endpoints instead
// (see TimbraSyncService).
//
// PRODUCT NOTE — proper fix is server-side. Those endpoints stamp the SERVER's clock and accept no
// client timestamp, so a tap delivered late is recorded late: an offline Fine would stretch paid
// time, a Pausa+Ripresa delivered back to back would create a zero-length paid break, and a tap
// crossing midnight would flip the WorkDate. Until the backend accepts an optional client
// timestamp on end / break/start / break/end, the app is conservative: these taps are ONLINE-ONLY
// (refused offline), executed immediately, retried only within [remoteCommandTtl] and never sent
// as a Pausa+Ripresa pair. Backend follow-up for the product owner.
// ══════════════════════════════════════════════════════════════════════════════

import '../local/app_database.dart' show WorkSession;
import 'work_session_repository.dart';

/// A tap older than this is dropped instead of retried: the server would stamp it "now".
const remoteCommandTtl = Duration(minutes: 2);

/// A command older than this (or one already attempted once) is re-validated against
/// `GET /worklog/active` before it is sent, so a lost response can never double-deliver.
const remoteCommandStateCheckAfter = Duration(seconds: 20);

const offlineRemoteShiftMessage =
    'Sei offline: per fermare o mettere in pausa un turno avviato su un altro dispositivo '
    'serve la connessione';

const remoteCommandDroppedMessage = 'Timbratura non inviata, riprova';

const batchConflictMessage =
    'Timbratura non sincronizzata: esiste già un turno aperto su un altro dispositivo';

/// Thrown by the punch path when a remote-origin shift is tapped while offline.
class OfflineRemoteShiftException implements Exception {
  const OfflineRemoteShiftException();
  String get message => offlineRemoteShiftMessage;
  @override
  String toString() => offlineRemoteShiftMessage;
}

/// One of this device's own taps on a remote-origin shift, waiting to be executed.
class RemoteCommand {
  const RemoteCommand({required this.event, required this.openerTime, required this.assumesOnBreak});

  final WorkSession event;

  /// When the backfilled opener of the shift this tap acts on was placed.
  final DateTime openerTime;

  /// Whether the shift was on a break just before this tap (what the tap assumes of the server).
  final bool assumesOnBreak;
}

class RemoteShiftAnalysis {
  const RemoteShiftAnalysis({
    required this.ids,
    required this.commands,
    required this.openShiftIsRemote,
  });

  /// Every event belonging to a remote-origin shift (kept out of the mobile batch).
  final Set<String> ids;

  /// Pending, unmarked fine/pausa/ripresa taps on remote-origin shifts, in order.
  final List<RemoteCommand> commands;

  /// The currently open shift (if any) is remote-origin.
  final bool openShiftIsRemote;
}

/// [sessions] must be in chronological order (as the repository returns them).
RemoteShiftAnalysis analyseRemoteShifts(List<WorkSession> sessions) {
  final ids = <String>{};
  final commands = <RemoteCommand>[];
  var remote = false;
  var open = false;
  var paused = false;
  DateTime? opener;

  for (final s in sessions) {
    switch (s.eventType) {
      case 'ingresso':
        remote = s.notes == reconciledOrphanMarker;
        open = true;
        paused = false;
        opener = s.eventTime;
        if (remote) ids.add(s.id);
      case 'pausa':
      case 'ripresa':
      case 'fine':
        if (remote) {
          ids.add(s.id);
          if (s.isPendingSync && s.notes != reconciledOrphanMarker) {
            commands.add(
              RemoteCommand(event: s, openerTime: opener!, assumesOnBreak: paused),
            );
          }
        }
        if (s.eventType == 'pausa') paused = true;
        if (s.eventType == 'ripresa') paused = false;
        if (s.eventType == 'fine') {
          remote = false;
          open = false;
          paused = false;
        }
    }
  }
  return RemoteShiftAnalysis(ids: ids, commands: commands, openShiftIsRemote: open && remote);
}
