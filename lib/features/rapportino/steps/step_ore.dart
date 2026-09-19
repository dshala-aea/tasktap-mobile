// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/timbratura/cantiere_worklog_api_client.dart' show CantiereWorkLogDto;
import '../../../data/timbratura/worklog_api_client.dart'
    show UserWorkLogDto, worklogApiClientProvider;
// Uses StepLabel — the padding-free sibling of SectionTitle, for headings inside a padded card.
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../cantiere/cantiere_providers.dart' show cantiereWorklogsProvider;
import '../../ticket/ticket_providers.dart' show ticketWorklogsProvider;
import '../../ticket/ticket_workflow_api_client.dart' show TicketWorkLogDto;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 — Ore
//
// Per-technician hours tiles (HH/MM) + km/travel + start/stop timer.
// Dark "Totale ore" summary card at the bottom.
// Folds old step_staff.dart logic with design-system styling.
// ══════════════════════════════════════════════════════════════════════════════

class StepOre extends ConsumerWidget {
  const StepOre({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final totalOre = state.staffRows.fold<double>(0, (sum, r) => sum + r.effectiveHours);

    // The ticket's own server-tracked labour sessions, when this report is for a ticket and the
    // fetch succeeds — offline or no ticketId both just mean no suggestions, not an error state
    // (ticketWorklogsProvider is online-only by design, see its own doc comment).
    final ticketId = state.ticketId;
    final worklogEntries = ticketId != null
        ? ref.watch(ticketWorklogsProvider(ticketId)).valueOrNull
        : null;

    // Cantiere tier: only relevant when this report has no ticket-tier suggestion to offer
    // (either no ticketId at all, or the fetch hasn't turned up anything for a given row — see
    // the per-row tiering below) — a cantiere-linked report has no server-tracked ticket
    // sessions of its own, and the office wants the same "suggest, don't silently fill" idiom.
    final cantiereId = state.cantiereId;

    // A Column, not a ListView: this sits inside the compartment sheet's own ambient
    // SingleChildScrollView now, not a screen-height-bounded Expanded body — an inner scrollable
    // here would fight the outer one for an unbounded height and crash on layout.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepLabel(title: 'Tecnici / Ore lavorate'),
          const SizedBox(height: 12),
          if (state.staffRows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(
                child: Text(
                  'Nessun tecnico aggiunto.\nPremi il pulsante per aggiungere.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.inkMuted, fontSize: 15),
                ),
              ),
            )
          else
            ...state.staffRows.map((row) {
              // Tiered fallback, ticket → cantiere → plain timbratura. Each tier's own provider
              // is watched independently (Riverpod resolves them in parallel, not sequentially —
              // there is no reason to wait on one before asking the next), but only a tier whose
              // fetch has actually come back with a match wins: an earlier tier that is still
              // loading or genuinely has nothing correctly falls through to the next one below.
              var suggestion = worklogEntries == null
                  ? null
                  : _worklogSuggestionFor(worklogEntries, row);

              if (suggestion == null && cantiereId != null) {
                final cantiereEntries = ref
                    .watch(cantiereWorklogsProvider((userId: row.userId, cantiereId: cantiereId)))
                    .valueOrNull;
                if (cantiereEntries != null) {
                  suggestion = _cantiereWorklogSuggestionFor(cantiereEntries, row);
                }
              }

              if (suggestion == null) {
                final recentEntries = ref.watch(recentWorkLogProvider(row.userId)).valueOrNull;
                if (recentEntries != null) {
                  suggestion = _recentWorkLogSuggestionFor(recentEntries, row);
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _StaffTile(
                  row: row,
                  worklogSuggestion: suggestion,
                  onUpdate: (updated) => notifier.updateStaff(updated),
                  onRemove: () => notifier.removeStaff(row.id),
                  onStartTimer: () => notifier.startTimer(row.id),
                  onStopTimer: () => notifier.stopTimer(row.id),
                ),
              );
            }),

          // Add staff button
          AppButton.secondary(
            label: 'Aggiungi tecnico',
            icon: const Icon(LucideIcons.userPlus),
            onPressed: () => _showAddStaffDialog(context, ref),
          ),
          const SizedBox(height: 20),

          // ── Totale ore dark card ───────────────────────────────────────
          _TotalOreCard(totalOre: totalOre, staffCount: state.staffRows.length),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Picks a colleague from the synced list.
  ///
  /// This used to be two text boxes — a name, and the colleague's **user id**. Nobody on a roof
  /// knows a UUID, so the id was left blank, and the code then invented `user-<timestamp>`. Those
  /// hours reached payroll and the customer's invoice attributed to a person who does not exist,
  /// and nothing anywhere said so.
  ///
  /// A picker also means no keyboard: one thumb, gloves on, in the rain.
  void _showAddStaffDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final alreadyAdded = ref
        .read(reportEditorProvider(reportId))
        .staffRows
        .map((r) => r.userId)
        .toSet();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, innerRef, _) {
          final colleagues = innerRef.watch(allColleaguesProvider);

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: colleagues.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) =>
                    const _StaffPickerMessage(text: 'Impossibile leggere l\'elenco dei colleghi.'),
                data: (all) {
                  // Someone already on this rapportino is not offered again — re-adding them
                  // would double their hours, and the list is short enough that a disabled row
                  // would just be noise.
                  final selectable = all.where((c) => !alreadyAdded.contains(c.id)).toList();

                  if (all.isEmpty) {
                    return const _StaffPickerMessage(
                      text:
                          'Nessun collega disponibile.\n\n'
                          'L\'elenco arriva dalla sincronizzazione: collegati a internet una '
                          'volta e riprova.',
                    );
                  }
                  if (selectable.isEmpty) {
                    return const _StaffPickerMessage(
                      text: 'Hai già aggiunto tutti i colleghi disponibili.',
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.xs,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        child: Text(
                          'Chi ha lavorato con te?',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: selectable.length,
                          itemBuilder: (_, i) {
                            final c = selectable[i];
                            return ListTile(
                              // 56dp, not the Material default — this list is tapped with a
                              // gloved thumb, one-handed, and a mis-tap adds the wrong person's
                              // hours to a customer's invoice.
                              minVerticalPadding: 16,
                              leading: const Icon(LucideIcons.user, size: 28),
                              title: Text(
                                c.displayName,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                              onTap: () {
                                notifier.addStaff(
                                  StaffRow(
                                    id: 'staff-${c.id}',
                                    userId: c.id,
                                    displayName: c.displayName,
                                  ),
                                );
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Anything the picker has to say instead of a list — always a reason and a way forward, never a
/// bare empty box. A technician who cannot add a colleague needs to know whether to wait for
/// signal or call the office.
class _StaffPickerMessage extends StatelessWidget {
  const _StaffPickerMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 16, height: 1.4, color: context.colors.inkFaint),
      ),
    );
  }
}

// ── Staff tile ─────────────────────────────────────────────────────────────────

// ── Worklog → hours suggestion ────────────────────────────────────────────────
//
// A ticket's own labour sessions (TicketWorkLogDto, server-tracked, independent of this report's
// own manual start/stop timer above) are keyed by userId, so a suggestion only ever applies to
// the specific staff row whose userId matches — never a blind average across everyone on the job.
// Explicit-apply only (a tappable chip, not a silent overwrite): the technician's own typed time
// is never touched without them choosing to replace it.

/// [startTime]/[endTime] are non-null only when exactly one completed session matched — combining
/// several unrelated sessions into one fabricated time range would be dishonest, so multi-session
/// matches surface a summed [hours] total with no synthesized range.
class WorklogHoursSuggestion {
  const WorklogHoursSuggestion({required this.hours, this.startTime, this.endTime});

  final double hours;
  final DateTime? startTime;
  final DateTime? endTime;
}

/// The suggestion for [row], or null when there's nothing to suggest.
///
/// Only completed sessions count (a still-running entry has no endTime — see
/// TicketWorkLogDto.isRunning — and suggesting hours from a clock that hasn't stopped yet would
/// be actively wrong). A multi-session sum is suppressed when the row already has its own
/// start/end range (from this report's own timer): StaffRow.copyWith has no way to clear
/// startTime/endTime, and effectiveHours prefers that range over hoursWorked whenever both are
/// set — so setting hoursWorked alongside an existing range would silently do nothing visible,
/// which is worse than not offering the suggestion at all.
WorklogHoursSuggestion? _worklogSuggestionFor(List<TicketWorkLogDto> entries, StaffRow row) {
  // .duration (not a hand-derived endTime-startTime/workDate+endTime) is what handles an
  // overnight session correctly — see TicketWorkLogDto.duration's doc comment. A completed entry
  // with a null duration (a malformed/legacy payload missing durationHours) is excluded rather
  // than risked here.
  final completed = entries
      .where((e) => e.userId == row.userId && !e.isRunning && e.duration != null)
      .toList();
  if (completed.isEmpty) return null;

  if (completed.length == 1) {
    final e = completed.single;
    final start = e.workDate.add(e.startTime);
    final end = start.add(e.duration!);
    return WorklogHoursSuggestion(
      hours: e.duration!.inMinutes / 60.0,
      startTime: start,
      endTime: end,
    );
  }

  if (row.startTime != null || row.endTime != null) return null;
  final totalMinutes = completed.fold<int>(0, (sum, e) => sum + e.duration!.inMinutes);
  return WorklogHoursSuggestion(hours: totalMinutes / 60.0);
}

/// Combines a calendar day with a backend "HH:mm:ss" time-of-day string into one [DateTime] —
/// [CantiereWorkLogDto.startTime]/[UserWorkLogDto.startTime] carry the same bare TimeSpan shape
/// `TicketWorkLogDto` moved away from (see that class's own [Duration]-typed `startTime`), so
/// this is the cantiere/plain-tier equivalent of `e.workDate.add(e.startTime)` above.
DateTime _combineWorkDateAndHms(DateTime workDate, String hms) {
  final parts = hms.split(':');
  final hours = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
  final minutes = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
  final seconds = int.tryParse(parts.elementAtOrNull(2) ?? '') ?? 0;
  return workDate.add(Duration(hours: hours, minutes: minutes, seconds: seconds));
}

/// Cantiere tier — same matching/summing shape as [_worklogSuggestionFor], against this
/// cantiere's own CantiereWorkLog sessions instead of a ticket's. Only reached (see the tiering
/// in `StepOre.build`) when the ticket tier found nothing for this row.
WorklogHoursSuggestion? _cantiereWorklogSuggestionFor(
  List<CantiereWorkLogDto> entries,
  StaffRow row,
) {
  final completed = entries
      .where((e) => e.userId == row.userId && !e.isActive && e.duration != null)
      .toList();
  if (completed.isEmpty) return null;

  if (completed.length == 1) {
    final e = completed.single;
    final start = _combineWorkDateAndHms(e.workDate, e.startTime);
    final end = start.add(e.duration!);
    return WorklogHoursSuggestion(
      hours: e.duration!.inMinutes / 60.0,
      startTime: start,
      endTime: end,
    );
  }

  if (row.startTime != null || row.endTime != null) return null;
  final totalMinutes = completed.fold<int>(0, (sum, e) => sum + e.duration!.inMinutes);
  return WorklogHoursSuggestion(hours: totalMinutes / 60.0);
}

/// Plain-timbratura tier — the last resort, offered only when neither the ticket nor the
/// cantiere tier suggested anything for this row. Unlike the two tiers above, this never sums:
/// a plain WorkLog carries no ticket/cantiere in common to justify combining several unrelated
/// days into one figure, so only the single most recent completed entry is ever suggested.
WorklogHoursSuggestion? _recentWorkLogSuggestionFor(List<UserWorkLogDto> entries, StaffRow row) {
  final completed = entries
      .where((e) => e.userId == row.userId && e.endTime != null && e.duration != null)
      .toList();
  if (completed.isEmpty) return null;

  completed.sort(
    (a, b) => _combineWorkDateAndHms(
      b.workDate,
      b.startTime,
    ).compareTo(_combineWorkDateAndHms(a.workDate, a.startTime)),
  );
  final e = completed.first;
  final start = _combineWorkDateAndHms(e.workDate, e.startTime);
  final end = start.add(e.duration!);
  return WorklogHoursSuggestion(hours: e.duration!.inMinutes / 60.0, startTime: start, endTime: end);
}

/// The plain-timbratura fallback provider (StepOre's third tier) — same online-only posture as
/// [ticketWorklogsProvider]/`cantiereWorklogsProvider`, for the same reason: a live network call
/// against a table this device does not otherwise sync. 30 days back is generous enough to catch
/// "last time this person logged hours" without pulling a user's entire history for a single
/// suggestion chip.
final recentWorkLogProvider = FutureProvider.autoDispose.family<List<UserWorkLogDto>, String>((
  ref,
  userId,
) async {
  if (!ref.watch(isOnlineProvider)) return const [];
  final api = ref.watch(worklogApiClientProvider);
  final now = DateTime.now();
  return api.fetchForUser(
    userId: userId,
    dateFrom: now.subtract(const Duration(days: 30)),
    dateTo: now,
  );
});

class _StaffTile extends StatefulWidget {
  const _StaffTile({
    required this.row,
    this.worklogSuggestion,
    required this.onUpdate,
    required this.onRemove,
    required this.onStartTimer,
    required this.onStopTimer,
  });

  final StaffRow row;
  final WorklogHoursSuggestion? worklogSuggestion;
  final ValueChanged<StaffRow> onUpdate;
  final VoidCallback onRemove;
  final VoidCallback onStartTimer;
  final VoidCallback onStopTimer;

  @override
  State<_StaffTile> createState() => _StaffTileState();
}

class _StaffTileState extends State<_StaffTile> {
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _kmCtrl;

  @override
  void initState() {
    super.initState();
    _hoursCtrl = TextEditingController(text: widget.row.hoursWorked?.toStringAsFixed(1) ?? '');
    _kmCtrl = TextEditingController(
      text: widget.row.kmTraveled > 0 ? widget.row.kmTraveled.toStringAsFixed(1) : '',
    );
  }

  @override
  void didUpdateWidget(covariant _StaffTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // hoursWorked changing from outside this field's own onChanged — applying a multi-session
    // worklog suggestion (no time range, so the "Ore effettive" readout below never renders to
    // show it) is the only path that does this today. Without resyncing here, tapping the
    // suggestion chip would persist the value but show no visible change at all.
    if (widget.row.hoursWorked != oldWidget.row.hoursWorked) {
      final text = widget.row.hoursWorked?.toStringAsFixed(1) ?? '';
      if (_hoursCtrl.text != text) _hoursCtrl.text = text;
    }
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _kmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const RowIconTile(icon: LucideIcons.user, size: 36, iconSize: 18, circle: true),
              const SizedBox(width: 10),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) => Text(
                    row.displayName.isNotEmpty
                        ? row.displayName
                        : (ref.watch(colleagueNameProvider(row.userId)).valueOrNull ?? row.userId),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: context.colors.ink,
                    ),
                  ),
                ),
              ),
              // Timer badge / start button
              if (row.timerRunning)
                _RunningTimerBadge(startedAt: row.timerStartedAt, onStop: widget.onStopTimer)
              else
                IconButton(
                  icon: Icon(LucideIcons.timer, color: context.colors.inkMuted),
                  tooltip: 'Avvia timer',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: widget.onStartTimer,
                ),
              IconButton(
                icon: Icon(LucideIcons.trash2, color: context.colors.red),
                tooltip: 'Rimuovi',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // HH / MM tiles
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: _hoursCtrl,
                  label: 'Ore',
                  suffix: 'h',
                  onChanged: (v) {
                    final h = double.tryParse(v);
                    widget.onUpdate(row.copyWith(hoursWorked: h));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumField(
                  controller: _kmCtrl,
                  label: 'Km percorsi',
                  suffix: 'km',
                  onChanged: (v) {
                    final km = double.tryParse(v) ?? 0.0;
                    widget.onUpdate(row.copyWith(kmTraveled: km));
                  },
                ),
              ),
            ],
          ),

          if (widget.worklogSuggestion != null) ...[
            const SizedBox(height: 8),
            _WorklogSuggestionChip(
              suggestion: widget.worklogSuggestion!,
              onApply: () {
                final s = widget.worklogSuggestion!;
                widget.onUpdate(
                  row.copyWith(hoursWorked: s.hours, startTime: s.startTime, endTime: s.endTime),
                );
              },
            ),
          ],

          // Timer time range display
          if (row.startTime != null) ...[
            const SizedBox(height: 8),
            Text(
              'Inizio: ${_fmtTime(row.startTime!)}'
              '${row.endTime != null ? ' → Fine: ${_fmtTime(row.endTime!)}' : ' (in corso)'}',
              style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
            ),
            Text(
              'Ore effettive: ${row.effectiveHours.toStringAsFixed(2)}h',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: context.colors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Worklog suggestion chip ─────────────────────────────────────────────────────

class _WorklogSuggestionChip extends StatelessWidget {
  const _WorklogSuggestionChip({required this.suggestion, required this.onApply});

  final WorklogHoursSuggestion suggestion;
  final VoidCallback onApply;

  static String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hoursLabel = suggestion.hours.toStringAsFixed(1).replaceAll('.', ',');
    final label = suggestion.startTime != null
        ? 'Da worklog: ${hoursLabel}h (${_fmtTime(suggestion.startTime!)}–'
              '${_fmtTime(suggestion.endTime!)})'
        : 'Da worklog: ${hoursLabel}h';

    return AppTappable(
      onTap: onApply,
      color: AppColors.Y.withAlpha(31),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.Y),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // accentInk, not raw AppColors.Y: this chip's own translucent Y fill sits over the
          // screen's flipping background, and raw Y text on top only clears 2.91:1 in dark mode
          // (see AppPalette.accentInk's own doc comment). The border below stays raw Y — a 1px
          // outline isn't held to the same text-contrast floor.
          Icon(LucideIcons.clock, size: 14, color: context.colors.accentInk),
          const SizedBox(width: 6),
          // Flexible, not a bare Text: a Row with mainAxisSize.min has no flexible child to
          // absorb overflow, and this label is a formatted string ("Da worklog: 12,5h
          // (08:00–17:30)") that can run long at large accessibility text scale on a narrow phone.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: context.colors.ink,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· Usa',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: context.colors.accentInk,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Running timer badge ────────────────────────────────────────────────────────

class _RunningTimerBadge extends StatefulWidget {
  const _RunningTimerBadge({this.startedAt, required this.onStop});

  final DateTime? startedAt;
  final VoidCallback onStop;

  @override
  State<_RunningTimerBadge> createState() => _RunningTimerBadgeState();
}

class _RunningTimerBadgeState extends State<_RunningTimerBadge>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.startedAt != null
        ? DateTime.now().toUtc().difference(widget.startedAt!)
        : Duration.zero;
    final hh = elapsed.inHours.toString().padLeft(2, '0');
    final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    final label = '$hh:$mm:$ss';
    return Semantics(
      liveRegion: true,
      button: true,
      label: 'Timer in corso $label, tocca per fermare',
      child: AppTappable(
        onTap: widget.onStop,
        color: AppColors.Y.withAlpha(31),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.Y),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ExcludeSemantics(
          // The tappable's own Semantics above already carries the label + liveRegion; excluding
          // this Text keeps a screen reader from announcing the raw digits a second time.
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: context.colors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Numeric input field ────────────────────────────────────────────────────────

class _NumField extends StatelessWidget {
  const _NumField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // AppTextField, like every other field. This one used to hand-roll a TextFormField inside
    // AppFieldShell, which duplicated AppTextField's own label-above treatment instead of reusing
    // it, and hand-rolled its border radius and padding, so an ore box did not match the box
    // beside it.
    return AppTextField(
      label: label,
      controller: controller,
      suffixIcon: suffix.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                widthFactor: 1,
                child: Text(suffix, style: TextStyle(color: context.colors.inkMuted)),
              ),
            ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: onChanged,
    );
  }
}

// ── Totale ore dark card ──────────────────────────────────────────────────────

class _TotalOreCard extends StatelessWidget {
  const _TotalOreCard({required this.totalOre, required this.staffCount});

  final double totalOre;
  final int staffCount;

  @override
  Widget build(BuildContext context) {
    // Flat AppColors.Y fill — same "Compilazione N di 4" readout job as
    // rapportino_form_screen.dart's own _CompletionCard, same reasoning for the switch.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRack.freeShape,
        color: AppColors.Y,
        boxShadow: [
          BoxShadow(color: AppColors.Y.withAlpha(90), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Totale ore',
                style: TextStyle(
                  fontFamily: 'Archivo',
                  color: Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${totalOre.toStringAsFixed(1)} h',
                style: const TextStyle(
                  fontFamily: 'Archivo Narrow',
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Tecnici',
                style: TextStyle(
                  fontFamily: 'Archivo',
                  color: Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$staffCount',
                style: const TextStyle(
                  fontFamily: 'Archivo Narrow',
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
