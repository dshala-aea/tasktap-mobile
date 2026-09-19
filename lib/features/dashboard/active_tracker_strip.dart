// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../data/worklogs/active_tracker_api_client.dart';
import '../../features/ticket/ticket_workflow_api_client.dart';
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
/// - **cantiere** — a site session. Ends only; the backend has no pause for it.
/// - **ticket** — labour on one job. Ends only.
///
/// A pause button that silently did nothing on two of three kinds would be worse than its absence,
/// so it is only drawn where it exists.
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
        message: e is TicketWorkflowFailure ? e.message : 'Operazione non riuscita.',
        tone: ToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() {
    final t = widget.tracker;
    return _run(() async {
      switch (t.kind) {
        case ActiveTrackerKind.attendance:
          await ref.read(punchNotifierProvider.notifier).punch(ref.read(timbraStateProvider));
        case ActiveTrackerKind.cantiere:
          await ref.read(cantiereWorklogApiClientProvider).endCantiere();
        case ActiveTrackerKind.ticket:
          final id = t.entityId;
          if (id == null) throw const TicketWorkflowFailure('Intervento non identificato.');
          await ref.read(ticketWorkflowApiClientProvider).stopTimer(id);
      }
    });
  }

  Future<void> _togglePause() => _run(
    () => ref.read(punchNotifierProvider.notifier).togglePause(ref.read(timbraStateProvider)),
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.tracker;
    final onBreak =
        t.kind == ActiveTrackerKind.attendance && ref.watch(timbraStateProvider).isOnPause;

    // Pause exists for the working day only. The guard is the server's, so a payroll-locked month
    // states its reason instead of failing on tap.
    final canPause = t.kind == ActiveTrackerKind.attendance;
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
