// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/entitlements/entitlement_providers.dart';
import '../../data/timbratura/cantiere_timbra_sync_service.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../data/worklogs/active_tracker_api_client.dart';
import '../../features/ticket/ticket_timer_actions.dart';
import '../../features/ticket/ticket_workflow_api_client.dart';
import '../../data/timbratura/remote_shift.dart' show OfflineRemoteShiftException;
import '../../presentation/providers/clock_disagreement_provider.dart';
import '../timbra/timbra_providers.dart';
import 'active_trackers_provider.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// What is running, right now, with the controls to stop it.
///
/// ## Why this replaced the glass cards
///
/// The hero used to carry a full `ActiveJobCard` per tracker — a status pill, an 18pt title, a
/// client line, four 40×38 timer tiles and an "Apri attività" button — roughly 130dp for one
/// running clock, plus a schedule-derived card for jobs that were not running at all. Two clocks
/// filled the screen before any content, and stopping one meant leaving the dashboard, finding
/// the right screen and pressing stop there.
///
/// A running clock needs three things and no more: which one, how long, and stop. Everything else
/// on that card was answering a question nobody had while the meter was going.
///
/// ## What each kind can actually do
///
/// The three clocks are genuinely different and the row says so rather than pretending otherwise:
///
/// - **attendance** — the working day. Pauses and resumes (a break), and ends. Both go through the
///   local punch queue, so they work with no signal.
/// - **cantiere** — a site session. Ends only; the backend has no pause for it. A session this
///   device checked into offline is closed in the local punch log and uploaded on reconnect, so
///   the stop works with no signal too.
/// - **ticket** — labour on one job. Ends only.
///
/// A pause button that silently did nothing on two of three kinds would be worse than its absence,
/// so it is only drawn where it exists.
///
/// ## QrOnly tenants
///
/// The three controls are copies of the Timbra screen's buttons, and that screen already knows a
/// tenant can require a kiosk scan: `ButtonOnly`/`QrOnly` swaps its buttons for "Scansiona QR".
/// This row did not, so under `QrOnly` the same technician could start and end a break from Home
/// without ever scanning (the app allowed it; only the server refused the *button* punch, and the
/// pause path never reached the wire) while "Ferma" — which does hit the wire — failed. Both are
/// now the one action that can complete on a `QrOnly` tenant that has not approved today as a
/// remote day: open the scanner, where the server's `availableActions` decide which transition to
/// offer.
///
/// On an *approved* smart-working day the server relaxes that gate
/// (`WorkLogService.EnsureClockInMethodAllowedAsync`), so the row gets its Pausa/Ferma back. A
/// running day must always keep a control that finishes it — see [isButtonPunchWithheld] — and the
/// decision is that function's, never a local `== 'QrOnly'`, so this row and Home's prompt cannot
/// drift apart.
class ActiveTrackerStrip extends ConsumerWidget {
  const ActiveTrackerStrip({super.key, required this.trackers});

  final List<ActiveTracker> trackers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One clock for the whole strip. Until it emits, the rows still show a correct elapsed time
    // computed from the device clock rather than a placeholder.
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < trackers.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _TrackerRow(tracker: trackers[i], now: now),
        ],
      ],
    );
  }
}

class _TrackerRow extends ConsumerStatefulWidget {
  const _TrackerRow({required this.tracker, required this.now});

  final ActiveTracker tracker;
  final DateTime now;

  @override
  ConsumerState<_TrackerRow> createState() => _TrackerRowState();
}

class _TrackerRowState extends ConsumerState<_TrackerRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(activeTrackersProvider);
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: switch (e) {
          TicketWorkflowFailure() => e.message,
          OfflineRemoteShiftException() => e.message,
          _ => 'Operazione non riuscita.',
        },
        tone: ToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() {
    final t = widget.tracker;
    // Under a QrOnly tenant that has not approved today, the row draws one scanner action instead
    // of these two — but a punch the server is guaranteed to refuse must not be reachable at all,
    // and a mid-session revocation can flip the row under a technician's finger. The guard costs
    // nothing and turns that into the scanner, which is the transition the server will accept.
    if (t.kind == ActiveTrackerKind.attendance && _qrOnly) return _openScanner();
    return _run(() async {
      switch (t.kind) {
        case ActiveTrackerKind.attendance:
          await ref.read(punchNotifierProvider.notifier).punch(ref.read(timbraStateProvider));
          _throwIfPunchFailed();
        case ActiveTrackerKind.cantiere:
          // A site session this device is holding locally (checked in with no signal) has no
          // server log to end: `endCantiere()` would come back a 4xx and the technician would stay
          // clocked in on a screen that told them nothing useful. Closing the interval in the
          // punch log is exactly what the Timbra screen's own clock-out does offline, and the sync
          // service uploads the pair when the signal returns.
          //
          // Awaited rather than read: Drift answers on a microtask, so a synchronous read here
          // would sample the provider before its first emission and decide "nothing local" — the
          // one decision that must not be wrong.
          final local = await ref.read(localCantiereTimersProvider.future);
          if (local.any((l) => l.entityId == t.entityId)) {
            await ref.read(cantiereSessionRepositoryProvider).addEvent(
              id: const Uuid().v4(),
              eventTime: DateTime.now().toUtc(),
              eventType: 'uscita',
            );
            unawaited(ref.read(cantiereTimbraSyncServiceProvider).syncNow());
            if (mounted) {
              showAppToast(
                context,
                message: 'Uscita cantiere registrata: verrà inviata al ritorno della connessione.',
                tone: ToastTone.warning,
              );
            }
          } else {
            final clockDisagreement =
                await ref.read(cantiereWorklogApiClientProvider).endCantiere();
            // Same banner as the punch screens: this is the other door the same close comes
            // through, and the server's answer is the only place the advice exists.
            if (clockDisagreement != null) {
              ref.read(cantiereClockDisagreementProvider.notifier).record(clockDisagreement);
            }
          }
        case ActiveTrackerKind.ticket:
          final id = t.entityId;
          if (id == null) throw const TicketWorkflowFailure('Intervento non identificato.');
          // The same clock as the ticket detail's timer bar, through the same function: this
          // branch used to call the API directly, so "Ferma" with no signal showed "Operazione non
          // riuscita" and left the clock running. `stopTicketTimer` writes the close to the mirror
          // and queues it, and says so when the close exists only on this device.
          final queued = await stopTicketTimer(ref, id);
          if (queued && mounted) {
            showAppToast(
              context,
              message: 'Fermata registrata: verrà inviata al ritorno della connessione.',
              tone: ToastTone.warning,
            );
          }
      }
    });
  }

  Future<void> _togglePause() {
    if (_qrOnly) return _openScanner();
    return _run(() async {
      await ref.read(punchNotifierProvider.notifier).togglePause(ref.read(timbraStateProvider));
      _throwIfPunchFailed();
    });
  }

  /// Whether the button punch this row would fire is one the server would refuse — only an
  /// explicit non-approved answer on a `QrOnly` tenant reaches this, never an unknown one: the
  /// technician's totem is on site, and this row may be the only control they have out in the
  /// field, so an unanswered /auth/me keeps the buttons and lets the server decide.
  ///
  /// `hasOpenShift` is `true` because this row exists only while something is running — a fact
  /// `startOnly` does not consult today, and deliberately so: on a QrOnly tenant the row's scanner
  /// alternative is the sanctioned way to close a day the tenant has not approved, while the timbra
  /// panel (whose button is the only control there) must never lose its finish. Stated rather than
  /// passed as `false`, so a later move to `startOrFinish` cannot silently inherit a lie.
  bool get _qrOnly => isButtonPunchWithheld(
    surface: ButtonPunchSurface.startOnly,
    clockInMethod: ref.read(effectiveClockInMethodProvider),
    smartWorkingToday: ref.read(smartWorkingTodayProvider),
    hasOpenShift: true,
  );

  Future<void> _openScanner() async => context.push(AppRoutes.timbraQr);

  /// `PunchNotifier.punch()`/`togglePause()` never throw — a repo failure is caught internally
  /// and parked in the notifier's own `state` as `AsyncError`, which is exactly the contract
  /// TimbraScreen's `ref.listen` relies on. `_run`'s try/catch above expects a thrown exception,
  /// the same contract `endCantiere()`/`stopTimer()` (the other two branches) actually honor —
  /// without this check, a genuine failure closing the worklog or toggling a break from here
  /// completed "successfully" as far as `_run` could tell: no toast, nothing thrown, nothing any
  /// log would ever show. Reading the state right back out and re-raising it here is what puts
  /// the attendance branch on the same footing as the other two.
  void _throwIfPunchFailed() {
    final result = ref.read(punchNotifierProvider);
    if (result is AsyncError) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracker;
    // The tracker's own `state` is authoritative (it may describe a break started on another
    // device); rows without one (older servers) fall back to this device's local state.
    final localOnPause = ref.watch(timbraStateProvider).isOnPause;
    final onBreak =
        t.kind == ActiveTrackerKind.attendance &&
        (t.state == null ? localOnPause : t.state == ActiveTrackerState.onBreak);

    // Pause exists for the working day only. The guard is the server's, so a payroll-locked month
    // states its reason instead of failing on tap.
    //
    // Neither control is drawn while the button punch would be refused: see this class's own doc
    // comment. The elapsed clock, the "in pausa" badge and the label still come from the tracker,
    // so the row keeps telling the technician what is running while it sends them to the totem to
    // change it.
    //
    // The rule is [isButtonPunchWithheld]'s, `startOnly` surface: the scanner below is always the
    // row's alternative, so this is the swap that can never strand a running day. Only an explicit
    // non-approved answer swaps; an unknown one leaves Ferma/Pausa working, which is the same
    // answer the timbra panel gives.
    final qrOnly =
        t.kind == ActiveTrackerKind.attendance &&
        isButtonPunchWithheld(
          surface: ButtonPunchSurface.startOnly,
          clockInMethod: ref.watch(effectiveClockInMethodProvider),
          smartWorkingToday: ref.watch(smartWorkingTodayProvider),
          hasOpenShift: true,
        );
    final canPause = t.kind == ActiveTrackerKind.attendance && !qrOnly;
    final pauseGuard = canPause ? ref.watch(pauseGuardProvider) : null;

    // A running ticket clock is the mockup's "hero-task" chip — the job this elapsed time is
    // for, one tap from its detail. Attendance/cantiere clocks have no single entity to open.
    final ticketId = t.kind == ActiveTrackerKind.ticket ? t.entityId : null;

    final labelColumn = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.label ?? _title(t.kind),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onDarkMuted,
            ),
          ),
          Text(
            formatElapsed(t.elapsedAt(widget.now)),
            style: TextStyle(
              fontFamily: 'Archivo Narrow',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: onBreak ? AppColors.onDarkMuted : AppColors.onDark,
              // Tabular figures: without them the whole row shifts every second as digit
              // widths change, which is unreadable on a clock you are watching.
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.WHITE.withAlpha(40))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            // The live indicator — an equipment lamp, not a status pill. See LiveDot's own doc
            // comment for why it's green, deliberately not the accent.
            const LiveDot(),
            const SizedBox(width: AppSpacing.sm),
            Icon(_glyph(t.kind), size: 16, color: AppColors.onDarkMuted),
            const SizedBox(width: AppSpacing.sm),
            if (ticketId != null)
              Expanded(
                child: InkWell(
                  onTap: () => context.push(AppRoutes.ticketDetailPath(ticketId)),
                  child: Row(
                    children: [
                      labelColumn,
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevronRight, size: 14, color: AppColors.onDarkMuted),
                    ],
                  ),
                ),
              )
            else
              labelColumn,
            if (onBreak)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Text(
                  'in pausa',
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onDarkMuted,
                  ),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.WHITE),
                ),
              )
            else ...[
              if (qrOnly)
                _GlassAction(
                  icon: LucideIcons.scanLine,
                  label: 'Timbra con QR',
                  onTap: _openScanner,
                )
              else ...[
                if (canPause)
                  _GlassAction(
                    icon: onBreak ? LucideIcons.play : LucideIcons.coffee,
                    label: onBreak ? 'Riprendi' : 'Pausa',
                    blockedReason: pauseGuard != null && pauseGuard.blocked
                        ? pauseGuard.reason
                        : null,
                    onTap: _togglePause,
                  ),
                _GlassAction(icon: LucideIcons.square, label: 'Ferma', onTap: _stop),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static IconData _glyph(ActiveTrackerKind k) => switch (k) {
    ActiveTrackerKind.attendance => LucideIcons.clock,
    ActiveTrackerKind.cantiere => LucideIcons.hardHat,
    ActiveTrackerKind.ticket => LucideIcons.wrench,
  };

  static String _title(ActiveTrackerKind k) => switch (k) {
    ActiveTrackerKind.attendance => 'Giornata di lavoro',
    ActiveTrackerKind.cantiere => 'Cantiere',
    ActiveTrackerKind.ticket => 'Intervento',
  };
}

/// A compact action on the hero's glass.
///
/// Was a hand-rolled `Material`/`InkWell` icon button — the only tap target in this row not built
/// on the shared `AppButton` its sibling in `work_queue_section.dart`'s "Apri" already uses.
/// `AppButton` has no icon-only variant (an icon always pairs with a visible label — see
/// `app_button.dart`'s own build()), so this keeps the label visible rather than inventing one;
/// `.dark` is the closest fit for a small solid tap target that reads clearly against the hero's
/// flat `AppColors.Y` ground regardless of theme (its own `bg`/`fg` are visible on both). When the
/// server refuses the action, the reason is still spoken via [Semantics]/[Tooltip] rather than the
/// control silently doing nothing.
class _GlassAction extends StatelessWidget {
  const _GlassAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.blockedReason,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final blocked = blockedReason != null;

    return Semantics(
      button: true,
      enabled: !blocked,
      label: blocked ? '$label — $blockedReason' : label,
      child: Tooltip(
        message: blocked ? blockedReason! : label,
        child: AppButton.dark(
          label: label,
          icon: Icon(icon),
          size: AppButtonSize.sm,
          fullWidth: false,
          onPressed: blocked ? null : onTap,
        ),
      ),
    );
  }
}
