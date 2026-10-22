// dart format width=100
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart' show syncServiceProvider;
import '../../data/timbratura/ticket_timer_sync_service.dart';
import '../../presentation/providers/auth_providers.dart';
import 'ticket_workflow_api_client.dart';

/// Start/stop for a ticket's timer, in the one place both entry points use.
///
/// Two screens drive the same clock — the ticket detail's timer bar and the dashboard's
/// running-clock strip — and they used to carry their own copies. The dashboard's copy called the
/// API directly and had no offline path at all, so "Ferma" from the dashboard with no signal
/// simply failed, while the same tap on the ticket screen queued the close. One rule, one
/// implementation: a call that reaches the server is a decision, and everything else is written to
/// the mirror and queued.
///
/// The online route is check-then-act and cannot be retried, which is why the offline path is a
/// different endpoint with a client-generated key (see `TicketTimerApiClient`).

/// Starts the clock online when the server can be reached, locally when it cannot.
///
/// A failure that carried a RESPONSE is a decision the server already made — "you already have an
/// active ticket work log" — and is surfaced; one with no response never reached it, so the
/// session is written to the device and queued.
Future<void> startTicketTimer(WidgetRef ref, String ticketId) async {
  final repo = ref.read(ticketTimerRepositoryProvider);
  Future<void> locally() async {
    final userId = await ref.read(internalUserIdProvider.future) ?? '';
    await repo.start(ticketId: ticketId, userId: userId);
    unawaited(ref.read(ticketTimerSyncServiceProvider).syncNow());
  }

  if (!ref.read(isOnlineProvider)) return locally();
  try {
    await ref.read(ticketWorkflowApiClientProvider).startTimer(ticketId);
  } on TicketWorkflowFailure catch (e) {
    if (e.cause?.response != null) rethrow;
    await locally();
    return;
  }
  unawaited(_pullIntoMirror(ref));
}

/// Pulls the session the server just started into the mirror.
///
/// `POST /worklogs/start` answers 200 with no body, so the server id — the key this row will ever
/// have — is not in hand and cannot be written here. Without the row, an app restart with no
/// signal shows no running clock on that ticket, and an offline "Ferma" has nothing to close. The
/// delta sync carries the signed-in technician's own sessions including any still running, so it
/// is the one thing that fills it.
///
/// Failures are swallowed: the start already succeeded, and the same sync runs on reconnect.
Future<void> _pullIntoMirror(WidgetRef ref) async {
  try {
    await ref.read(syncServiceProvider).sync();
  } catch (e) {
    debugPrint('ticket timer: pull after start failed ($e)');
  }
}

/// Stops the ticket's clock, returning true when the close exists only on this device.
///
/// Closing in the mirror happens on BOTH paths: a session this device started lives nowhere else,
/// and a server session that gets closed here is re-sent as a close, which the batch upsert
/// accepts and applies idempotently. The return value is what lets a caller say "registrata, verrà
/// inviata al ritorno della connessione" instead of leaving the technician to guess whether it
/// landed.
///
/// Offline, a close is only possible when this device holds the session. Claiming otherwise would
/// be the worst outcome available: the technician is told the hours are safe while the clock keeps
/// running on the server, and nothing on the phone will ever send a stop.
Future<bool> stopTicketTimer(WidgetRef ref, String ticketId) async {
  final repo = ref.read(ticketTimerRepositoryProvider);
  // True when a row was actually closed, i.e. when there is something to send later.
  Future<bool> closeLocally() async {
    final closed = await repo.stop(ticketId);
    if (closed == null) return false;
    unawaited(ref.read(ticketTimerSyncServiceProvider).syncNow());
    return true;
  }

  if (!ref.read(isOnlineProvider)) {
    if (await closeLocally()) return true;
    throw const TicketTimerNotOnDevice();
  }
  try {
    await ref.read(ticketWorkflowApiClientProvider).stopTimer(ticketId);
  } on TicketWorkflowFailure catch (e) {
    // The mirror is closed on every path where it holds the session: a technician who tapped
    // "Ferma" ends the clock they see, and the queued close re-sends it through the idempotent
    // upsert. A refused close still has to be told, so the failure is not swallowed.
    final recorded = await closeLocally();
    if (e.cause?.response != null) rethrow;
    // The request never reached the server. "Queued" is only true if the close was recorded.
    if (!recorded) rethrow;
    return true;
  }
  await closeLocally();
  return false;
}

/// No signal, and no session on this device to close.
///
/// Happens when the clock was started online and the app was killed before the sync that mirrors
/// the session ran. Distinct from a network failure: retrying immediately cannot help, which is
/// what the message says.
class TicketTimerNotOnDevice extends TicketWorkflowFailure {
  const TicketTimerNotOnDevice()
    : super(
        'Senza connessione posso fermare solo un timer avviato da questo telefono con i dati '
        'disponibili. Riprova quando hai segnale.',
      );
}
