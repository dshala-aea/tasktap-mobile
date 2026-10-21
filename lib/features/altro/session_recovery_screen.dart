import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/auth/session_recovery.dart';
import '../../data/auth/session_recovery_providers.dart';
import '../../presentation/providers/auth_providers.dart';

/// The one screen a forced sign-out can lead to on the *next* sign-in, when the account that
/// came back is not the one whose data the device still holds.
///
/// A forced sign-out (confirmed `invalid_grant`) no longer wipes the local database — that wipe
/// used to run while the queues were still full of unsent work (audit F1). The cost of keeping
/// the data is this decision: on a shared device, the previous tenant's cached tickets, customers
/// and cantieri must not be shown to the next person. So the app stops here, says exactly what is
/// at stake (including the unsent count), and wipes only when the technician confirms.
///
/// Reached and left only through `buildRouter`'s redirect (see `SessionRecoveryController`): the
/// route is guarded like every other, and once [SessionRecoveryState] stops being
/// [SessionRecoveryNeedsDiscard] the redirect moves on to /dashboard by itself.
class SessionRecoveryScreen extends ConsumerStatefulWidget {
  const SessionRecoveryScreen({super.key});

  @override
  ConsumerState<SessionRecoveryScreen> createState() => _SessionRecoveryScreenState();
}

class _SessionRecoveryScreenState extends ConsumerState<SessionRecoveryScreen> {
  bool _busy = false;

  Future<void> _discard() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionRecoveryProvider.notifier).discard();
      // The redirect moves to /dashboard once the state is idle; nothing else to do here. If the
      // widget survives the rebuild (it should not), stop showing a spinner.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leave without discarding — sign the current account out and keep the marker intact, so the
  /// decision is asked again for whichever account signs in next.
  ///
  /// Deliberately `IAuthRepository.signOut` (credentials only) rather than
  /// `SessionEnder.endForced()`: that would re-stamp the retained-owner marker with the account
  /// that is leaving now, losing track of whose data is actually on the device.
  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
      ref.read(sessionRecoveryProvider.notifier).reset();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionRecoveryProvider);
    final unsent = state is SessionRecoveryNeedsDiscard ? state.unsentCount : 0;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Dati di un altro account'),
            Expanded(
              child: UnavailableState(
                icon: LucideIcons.alertTriangle,
                titolo: 'Questo dispositivo contiene i dati di un altro account',
                motivo: unsent == 0
                    ? 'Un accesso precedente è scaduto e i dati locali non sono stati cancellati. '
                          'Per continuare vanno eliminati.'
                    : unsent == 1
                    ? 'Un accesso precedente è scaduto lasciando 1 elemento non inviato sul '
                          'dispositivo. Se continui verrà perso definitivamente.'
                    : 'Un accesso precedente è scaduto lasciando $unsent elementi non inviati sul '
                          'dispositivo. Se continui verranno persi definitivamente.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton.danger(
                    label: 'Elimina e continua',
                    isLoading: _busy,
                    onPressed: _busy ? null : _discard,
                  ),
                  const SizedBox(height: 10),
                  AppButton.ghost(
                    label: 'Esci',
                    onPressed: _busy ? null : _leave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
