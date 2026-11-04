// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_text_styles.dart';
import '../../core/time/business_time.dart' show BusinessTime;
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/utils/error_message.dart' show humanErrorMessage;
import '../../core/widgets/app_toast.dart' show ToastTone, showAppToast;
import '../../core/widgets/detail/detail_hero.dart' show DetailAction;
import '../../core/widgets/live_dot.dart';
import '../dashboard/active_trackers_provider.dart' show formatElapsed, nowProvider;
import 'ticket_detail_api_client.dart' show TicketDetailOfflineException;
import 'ticket_providers.dart';
import 'ticket_timer_actions.dart' show startTicketTimer, stopTicketTimer;
import 'ticket_workflow_api_client.dart' show TicketWorkLogDto, TicketWorkflowFailure;

/// The one sentence used wherever the ticket timer cannot be shown or driven.
const String _offlineTimerReason = 'Timer non disponibile offline';

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
    if (_isOffline(worklogs)) {
      return const Text(_offlineTimerReason);
    }

    final running = ref.watch(runningTicketWorklogProvider(ticketId));
    if (running == null) {
      return const Text('Nessun timer attivo');
    }

    final elapsed = ticketTimerElapsed(
      running,
      ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc(),
      ref.watch(businessTimeProvider),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LiveDot(),
        const SizedBox(width: 8),
        Text(
          formatElapsed(elapsed),
          style: AppTextStyles.docCode.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The hero's primary action for the ticket clock: start it, or close it.
DetailAction ticketTimerAction(BuildContext context, WidgetRef ref, String ticketId) {
  final running = ref.watch(runningTicketWorklogProvider(ticketId));
  final busy = ref.watch(ticketTimerBusyProvider(ticketId));

  if (busy) {
    return DetailAction(
      label: running == null ? 'Avvia intervento' : 'Chiudi intervento',
      enabled: false,
      disabledReason: 'Aggiornamento del timer…',
    );
  }

  return DetailAction(
    label: running == null ? 'Avvia intervento' : 'Chiudi intervento',
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
    if (queued && context.mounted) {
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
