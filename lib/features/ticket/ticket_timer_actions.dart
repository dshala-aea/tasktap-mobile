// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/connectivity_provider.dart';
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
  }
}

/// Stops the ticket's clock, returning true when the close exists only on this device.
///
/// Closing in the mirror happens on BOTH paths: a session this device started lives nowhere else,
/// and a server session that gets closed here is re-sent as a close, which the batch upsert
/// accepts and applies idempotently. The return value is what lets a caller say "registrata, verrà
/// inviata al ritorno della connessione" instead of leaving the technician to guess whether it
/// landed.
Future<bool> stopTicketTimer(WidgetRef ref, String ticketId) async {
  final repo = ref.read(ticketTimerRepositoryProvider);
  Future<void> closeLocally() async {
    final closed = await repo.stop(ticketId);
    if (closed != null) {
      unawaited(ref.read(ticketTimerSyncServiceProvider).syncNow());
    }
  }

  if (!ref.read(isOnlineProvider)) {
    await closeLocally();
    return true;
  }
  try {
    await ref.read(ticketWorkflowApiClientProvider).stopTimer(ticketId);
  } on TicketWorkflowFailure catch (e) {
    // The mirror is closed either way: a technician who tapped "Ferma" ends the clock they see,
    // and the queued close re-sends it through the idempotent upsert. A refused close still has
    // to be told, so the failure is not swallowed.
    await closeLocally();
    if (e.cause?.response != null) rethrow;
    return true;
  }
  await closeLocally();
  return false;
}
