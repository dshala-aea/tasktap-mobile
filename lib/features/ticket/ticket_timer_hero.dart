// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/time/business_time.dart' show BusinessTime;
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/utils/error_message.dart' show humanErrorMessage;
import '../../core/widgets/app_toast.dart' show ToastTone, showAppToast;
import '../../core/widgets/detail/detail_hero.dart' show DetailAction;
import '../../data/sync/connectivity_provider.dart' show isOnlineProvider;
import '../../presentation/providers/auth_providers.dart' show internalUserIdProvider;
import '../dashboard/active_trackers_provider.dart' show formatElapsed, nowProvider;
import 'ticket_detail_api_client.dart' show TicketDetailOfflineException;
import 'ticket_providers.dart';
import 'ticket_timer_actions.dart' show startTicketTimer, stopTicketTimer;
import 'ticket_workflow_api_client.dart' show TicketWorkLogDto, TicketWorkflowFailure;

/// The sentence used while offline but the device's worklog mirror is readable.
///
/// Matches the old timer bar's copy: the action is enabled offline, so the live value must say the
/// timer still works rather than claiming it is unavailable.
const String _offlineTimerReason =
    'Offline: il timer funziona e verrà inviato appena torni online.';

/// The sentence used offline when the mirror holds no worklogs for this ticket.
///
/// An empty mirror is not evidence of zero hours, so it says the hours are not synced yet while
/// still making clear the timer itself works.
const String _offlineMirrorEmptyTimerReason =
    'Ore di questo ticket non ancora sincronizzate. Il timer funziona: verrà inviato appena torni online.';

/// Elapsed time of a running ticket worklog at [now].
///
/// `workDate` + `startTime` is a Rome wall-clock label (legacy frame), not UTC, so it is converted
/// with [BusinessTime.instantOfLegacyLabel]; clamped at zero against clock skew.
Duration ticketTimerElapsed(TicketWorkLogDto running, DateTime now, BusinessTime businessTime) {
  final start = businessTime.instantOfLegacyLabel(running.workDate, running.startTime);
  final elapsed = now.toUtc().difference(start);
  return elapsed.isNegative ? Duration.zero : elapsed;
}

/// The timer's live value in a detail hero: the ticking clock, or why it cannot be shown.
class TicketTimerLiveValue extends ConsumerWidget {
  const TicketTimerLiveValue({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worklogs = ref.watch(ticketWorklogsProvider(ticketId));
    final offline = !ref.watch(isOnlineProvider);
    final running = ref.watch(runningTicketWorklogProvider(ticketId));

    // A running clock is the one thing the hero can still show offline: the entry is in the local
    // mirror, and its elapsed value keeps ticking. The offline note is added underneath rather
    // than replacing it, exactly as the old timer bar did.
    if (running != null) {
      final elapsed = ticketTimerElapsed(
        running,
        ref.watch(nowProvider).value ?? DateTime.now().toUtc(),
        ref.watch(businessTimeProvider),
      );
      // The mockup's `.timer`: red mono 22, tabular, no extra marker.
      final value = Text(
        formatElapsed(elapsed),
        style: AppTextStyles.timerMono.copyWith(
          fontSize: 22,
          letterSpacing: -0.66,
          color: context.colors.accentInk,
        ),
      );

      if (!offline && !_isOffline(worklogs)) return value;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          value,
          const SizedBox(height: 4),
          Text(
            _isOffline(worklogs) ? _offlineMirrorEmptyTimerReason : _offlineTimerReason,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
          ),
        ],
      );
    }

    // No running clock: the old bar still said why the mirror cannot answer, or that it is still
    // checking, before falling back to "no timer".
    if (_isOffline(worklogs)) {
      return const Text(_offlineMirrorEmptyTimerReason);
    }
    if (worklogs.isLoading) {
      return const Text('Verifica timer…');
    }
    if (offline) {
      return const Text(_offlineTimerReason);
    }
    return const Text('Nessun timer attivo');
  }
}

/// The hero's primary action for the ticket clock: start it, or close it.
///
/// [isClosed] comes from the screen's own closed-state check. A closed ticket cannot start a new
/// session until it is reopened from the status pill, but a session already running (including one
/// opened before the close) can still be stopped.
DetailAction ticketTimerAction(
  BuildContext context,
  WidgetRef ref,
  String ticketId, {
  bool isClosed = false,
}) {
  final running = ref.watch(runningTicketWorklogProvider(ticketId));
  final busy = ref.watch(ticketTimerBusyProvider(ticketId));
  final currentUserId = ref.watch(internalUserIdProvider).value;

  final label = running == null ? 'Avvia intervento' : 'Chiudi intervento';

  if (busy) {
    return DetailAction(label: label, enabled: false, disabledReason: 'Aggiornamento del timer…');
  }

  // The running entry belongs to someone else. Stopping it from this device would close another
  // technician's session, so the action is visible but refuses with the reason.
  final runningUserId = running?.userId;
  if (runningUserId != null && currentUserId != null && runningUserId != currentUserId) {
    return DetailAction(
      label: label,
      enabled: false,
      disabledReason: 'Timer avviato da un altro tecnico',
    );
  }

  if (isClosed && running == null) {
    return const DetailAction(
      label: 'Avvia intervento',
      enabled: false,
      disabledReason: 'Intervento chiuso: riaprilo dallo stato qui sopra.',
    );
  }

  return DetailAction(
    label: label,
    onPressed: () => _toggle(context, ref, ticketId, running != null),
  );
}

bool _isOffline(AsyncValue<List<TicketWorkLogDto>> worklogs) =>
    worklogs.hasError && worklogs.error is TicketDetailOfflineException;

Future<void> _toggle(BuildContext context, WidgetRef ref, String ticketId, bool isRunning) async {
  // A rapid second tap can land before the busy rebuild paints the disabled action.
  if (ref.read(ticketTimerBusyProvider(ticketId))) return;
  ref.read(ticketTimerBusyProvider(ticketId).notifier).state = true;
  try {
    var queued = false;
    if (isRunning) {
      queued = await stopTicketTimer(ref, ticketId);
    } else {
      await startTicketTimer(ref, ticketId);
    }
    if (!context.mounted) return;
    if (queued) {
      showAppToast(
        context,
        message: 'Fermata registrata: verrà inviata al ritorno della connessione.',
        tone: ToastTone.warning,
      );
    }
    ref.invalidate(ticketWorklogsProvider(ticketId));
    try {
      await ref.read(ticketWorklogsProvider(ticketId).future);
    } on TicketDetailOfflineException {
      // The write landed; only the re-read had nothing to say (offline, empty mirror).
    }
  } on TicketWorkflowFailure catch (e) {
    if (context.mounted) {
      showAppToast(context, message: e.message, tone: ToastTone.error);
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'aggiornare il timer del ticket'),
        tone: ToastTone.error,
      );
    }
  } finally {
    if (context.mounted) {
      ref.read(ticketTimerBusyProvider(ticketId).notifier).state = false;
    }
  }
}
