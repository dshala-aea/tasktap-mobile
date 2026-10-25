// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../data/timbratura/ticket_timer_sync_service.dart';
import '../../presentation/providers/auth_providers.dart';
import 'ticket_providers.dart' show mirroredTicketIsClosed;
import '../../presentation/providers/clock_disagreement_provider.dart';
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
/// Both paths carry the same client-generated key: the online start passes it as `clientId` so a
/// reply that never arrives can be retried onto the row it already owns, and the offline path
/// sends it to the batch upsert (see `TicketTimerApiClient`). Without a shared key the two paths
/// could each create a session for the same visit and bill the hours twice.

/// Starts the clock online when the server can be reached, locally when it cannot.
///
/// A failure that carried a RESPONSE is a decision the server already made — "you already have an
/// active ticket work log" — and is surfaced; one with no response never reached it, so the
/// session is written to the device and queued.
Future<void> startTicketTimer(WidgetRef ref, String ticketId) async {
  final repo = ref.read(ticketTimerRepositoryProvider);

  // A closed ticket is finished work and may not acquire new hours. The server would still open
  // the session — its in-progress marker deliberately leaves a closed ticket alone, so nothing
  // upstream refuses this — which makes this the one place that can. Checked before anything is
  // written to the mirror or queued, so a refusal leaves the device exactly as it was.
  if (await mirroredTicketIsClosed(ref.read(appDatabaseProvider), ticketId)) {
    throw const TicketTimerOnClosedTicket();
  }

  // The key this tap owns, generated before the call: a reply that never arrives is then retried
  // onto the same server row instead of opening a second timer with the same hours.
  final clientId = const Uuid().v4();

  Future<void> locally() async {
    final userId = await ref.read(internalUserIdProvider.future) ?? '';
    await repo.start(ticketId: ticketId, userId: userId, clientId: clientId);
    unawaited(ref.read(ticketTimerSyncServiceProvider).syncNow());
  }

  if (!ref.read(isOnlineProvider)) return locally();

  final TicketTimerStart started;
  try {
    // This is the tap instant: the online route is only taken when the tap reaches the server
    // now, and the server measures the gap from its own receipt time. Queued timer sessions go
    // through the batch upsert instead, which stamps a separate send-time reading.
    started = await ref
        .read(ticketWorkflowApiClientProvider)
        .startTimer(
          ticketId,
          clientId: clientId,
          deviceUtc: DateTime.now().toUtc(),
        );
  } on TicketWorkflowFailure catch (e) {
    if (e.cause?.response != null) rethrow;
    await locally();
    return;
  }

  // The server answered, and the row this key names is already closed: the reply to an earlier
  // attempt was lost long enough for the office to end the session. Queuing a local start here
  // would show a clock that is not running, so the technician is told instead.
  if (!started.isActive) throw const TicketTimerAlreadyClosed();

  // The server measured this phone's clock against its own receipt and, when the two were far
  // enough apart to matter, says so here. Recorded before the mirror write: the technician should
  // hear about a wrong clock on the same turn the hours are booked, not at the next sync.
  final disagreement = started.clockDisagreementSeconds;
  if (disagreement != null) {
    ref.read(clockDisagreementProvider.notifier).record(ticketId, disagreement);
  }

  // Mirror the running clock now, from the id the reply carries — not from the next delta sync.
  // Without this row, a technician who started the clock in the office and lost signal on the way
  // to site could not stop it: an offline "Ferma" has nothing to close.
  final userId = await ref.read(internalUserIdProvider.future) ?? '';
  await repo.adoptServerStart(
    serverId: started.id,
    clientId: clientId,
    ticketId: ticketId,
    userId: userId,
  );
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
    final disagreement = await ref
        .read(ticketWorkflowApiClientProvider)
        .stopTimer(ticketId, deviceUtc: DateTime.now().toUtc());
    // The close's answer carries the row's merged disagreement — same banner the start's answer
    // raises, so a skew first seen at the start is not lost when the session ends online.
    if (disagreement != null) {
      ref.read(clockDisagreementProvider.notifier).record(ticketId, disagreement);
    }
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

/// The ticket is closed, so its clock cannot be started.
///
/// Its own sentence, not a generic failure: the way back is a status change, which is on the same
/// screen the timer bar sits on.
class TicketTimerOnClosedTicket extends TicketWorkflowFailure {
  const TicketTimerOnClosedTicket()
    : super('Intervento chiuso: riaprilo dal suo stato per avviare un timer.');
}

/// The session this tap's key names is already closed, so there is nothing to show running.
///
/// Only reachable when a start's reply was lost and the office ended the session before the retry:
/// the server answers for the same row with `isActive: false`. Reporting it as a fresh start would
/// paint a clock that is not running and never will be.
class TicketTimerAlreadyClosed extends TicketWorkflowFailure {
  const TicketTimerAlreadyClosed()
    : super(
        'Questo timer risulta già chiuso sul server: aggiorna l\'intervento per vedere le ore '
        'registrate.',
      );
}
