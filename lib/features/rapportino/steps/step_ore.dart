// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/business_time.dart';
import '../../../core/time/business_time_providers.dart';
import '../../../core/time/work_time.dart' show formatTimeSpan, parseTimeSpan;
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/timbratura/cantiere_worklog_api_client.dart' show CantiereWorkLogDto;
import '../../../data/timbratura/timbra_session_assembler.dart' show assembleIntervals;
import '../../../data/timbratura/worklog_api_client.dart'
    show UserWorkLogDto, worklogApiClientProvider;
import '../../../presentation/providers/auth_providers.dart' show internalUserIdProvider;
// Uses StepLabel — the padding-free sibling of SectionTitle, for headings inside a padded card.
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../cantiere/cantiere_providers.dart' show cantiereWorklogsProvider;
import '../../timbra/timbra_providers.dart' show workSessionRepositoryProvider;
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
    final businessTime = ref.watch(businessTimeProvider);
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
                  : worklogSuggestionFor(businessTime, worklogEntries, row);

              if (suggestion == null && cantiereId != null) {
                final cantiereEntries = ref
                    .watch(cantiereWorklogsProvider((userId: row.userId, cantiereId: cantiereId)))
                    .valueOrNull;
                if (cantiereEntries != null) {
                  suggestion = cantiereWorklogSuggestionFor(businessTime, cantiereEntries, row);
                }
              }

              if (suggestion == null) {
                final recentEntries = ref.watch(recentWorkLogProvider(row.userId)).valueOrNull;
                if (recentEntries != null) {
                  suggestion = recentWorkLogSuggestionFor(businessTime, recentEntries, row);
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _StaffTile(
                  row: row,
                  worklogSuggestion: suggestion,
                  businessTime: businessTime,
                  onUpdate: (updated) => notifier.updateStaff(updated),
                  // Not updateStaff: a suggestion applied over recorded intervals has to take
                  // the intervals with it, or the row would carry two totals and the derived one
                  // would win on the next save.
                  onApplySuggestion: (s) => notifier.overrideStaffHours(
                    row,
                    hoursWorked: s.hours,
                    startTime: s.startTime,
                    endTime: s.endTime,
                  ),
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
/// be actively wrong). A sum over several sessions carries no range of its own: no single
/// start→end describes them, and inventing one would be a lie the office could not see through.
/// Applying it clears the row's own span instead (see ReportEditorNotifier.overrideStaffHours).
///
/// Times are real instants: the legacy `workDate` + `HH:mm:ss` label is a Rome wall-clock label
/// (plan Ruling 3, whatever the tenant zone), turned into an instant by
/// [BusinessTime.instantOfLegacyLabel]; the end is that instant plus the server duration.
@visibleForTesting
WorklogHoursSuggestion? worklogSuggestionFor(
  BusinessTime businessTime,
  List<TicketWorkLogDto> entries,
  StaffRow row,
) {
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
    final start = businessTime.instantOfLegacyLabel(e.workDate, e.startTime);
    final end = start.add(e.duration!);
    return WorklogHoursSuggestion(
      hours: e.duration!.inMinutes / 60.0,
      startTime: start,
      endTime: end,
    );
  }

  final totalMinutes = completed.fold<int>(0, (sum, e) => sum + e.duration!.inMinutes);
  return WorklogHoursSuggestion(hours: totalMinutes / 60.0);
}

/// Cantiere tier — same matching/summing shape as [worklogSuggestionFor], against this
/// cantiere's own CantiereWorkLog sessions instead of a ticket's. Only reached (see the tiering
/// in `StepOre.build`) when the ticket tier found nothing for this row.
///
/// An entry whose `startTime` is not a valid time-of-day is skipped, never read as midnight.
@visibleForTesting
WorklogHoursSuggestion? cantiereWorklogSuggestionFor(
  BusinessTime businessTime,
  List<CantiereWorkLogDto> entries,
  StaffRow row,
) {
  final completed = entries
      .where(
        (e) =>
            e.userId == row.userId &&
            !e.isActive &&
            e.duration != null &&
            parseTimeSpan(e.startTime) != null,
      )
      .toList();
  if (completed.isEmpty) return null;

  if (completed.length == 1) {
    final e = completed.single;
    final start = businessTime.instantOfLegacyLabel(e.workDate, parseTimeSpan(e.startTime)!);
    final end = start.add(e.duration!);
    return WorklogHoursSuggestion(
      hours: e.duration!.inMinutes / 60.0,
      startTime: start,
      endTime: end,
    );
  }

  final totalMinutes = completed.fold<int>(0, (sum, e) => sum + e.duration!.inMinutes);
  return WorklogHoursSuggestion(hours: totalMinutes / 60.0);
}

/// Plain-timbratura tier — the last resort, offered only when neither the ticket nor the
/// cantiere tier suggested anything for this row.
///
/// This used to pick the single most-recently-started *completed* WorkLog from the last 30
/// days — but a closed session from days ago says nothing about today's job, and suggesting it
/// silently attributed old hours to whatever ticket happened to be open. The only thing worth
/// suggesting here is this technician's own still-open punch: its start time is real (they
/// clocked in and haven't clocked out), and "now" is an honest end for a rapportino being
/// compiled while that clock is still running. No sum, unlike the two tiers above: an open
/// timbratura is at most one entry, never several to combine.
@visibleForTesting
WorklogHoursSuggestion? recentWorkLogSuggestionFor(
  BusinessTime businessTime,
  List<UserWorkLogDto> entries,
  StaffRow row,
) {
  // Entries with an unparseable startTime are skipped, never read as midnight.
  final active = <(UserWorkLogDto, DateTime)>[];
  for (final e in entries) {
    if (e.userId != row.userId || e.endTime != null) continue;
    final t = parseTimeSpan(e.startTime);
    if (t == null) continue;
    active.add((e, businessTime.instantOfLegacyLabel(e.workDate, t)));
  }
  if (active.isEmpty) return null;

  active.sort((a, b) => b.$2.compareTo(a.$2));
  final start = active.first.$2;
  final end = businessTime.nowInstant();
  final hours = end.difference(start).inMinutes / 60.0;
  return WorklogHoursSuggestion(hours: hours, startTime: start, endTime: end);
}

/// The plain-timbratura fallback provider (StepOre's third tier). Online it asks the API — a live
/// call against a table this device does not otherwise sync; 30 days back is generous enough to
/// catch "this person's still-open punch" without pulling their entire history for one suggestion
/// chip.
///
/// Offline the table is unreachable, but this phone does hold one fact the suggestion needs: its
/// own open timbratura, in `work_sessions`. `work_sessions` carries no user id — those rows are
/// this device's punches, hence the signed-in user's by construction — so a request for anyone
/// else answers empty rather than handing a technician someone else's shift.
final recentWorkLogProvider = FutureProvider.autoDispose.family<List<UserWorkLogDto>, String>((
  ref,
  userId,
) async {
  if (!ref.watch(isOnlineProvider)) {
    final me = await ref.watch(internalUserIdProvider.future);
    if (me == null || me != userId) return const [];

    final businessTime = ref.watch(businessTimeProvider);
    final sessions = await ref
        .watch(workSessionRepositoryProvider)
        .getTodaySessions();
    final open = [
      for (final i in assembleIntervals(
        sessions,
        businessDateOf: businessTime.businessDateOf,
      ))
        if (i.endTime == null) i,
    ];
    if (open.isEmpty) return const [];

    // Same reading as [recentWorkLogSuggestionFor]: an open timbratura is at most one entry, and
    // when a lost close left several, the most recent start is the shift still running.
    final start = open
        .map((i) => i.startTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final (workDate, timeOfDay) = businessTime.legacyLabelOf(start);
    return [
      UserWorkLogDto(
        id: 'local-${start.toUtc().toIso8601String()}',
        userId: userId,
        workDate: workDate,
        startTime: formatTimeSpan(timeOfDay),
        endTime: null,
      ),
    ];
  }
  final api = ref.watch(worklogApiClientProvider);
  // The API reads the y/m/d fields of these as date labels. WorkDate labels live in the legacy
  // (Rome) frame, so the window is anchored there, not on the device zone.
  final today = ref.watch(businessTimeProvider).legacyToday();
  return api.fetchForUser(
    userId: userId,
    dateFrom: today.subtract(const Duration(days: 30)),
    dateTo: today,
  );
});

class _StaffTile extends StatefulWidget {
  const _StaffTile({
    required this.row,
    this.worklogSuggestion,
    required this.businessTime,
    required this.onUpdate,
    required this.onApplySuggestion,
    required this.onRemove,
    required this.onStartTimer,
    required this.onStopTimer,
  });

  final BusinessTime businessTime;
  final StaffRow row;
  final WorklogHoursSuggestion? worklogSuggestion;
  final ValueChanged<StaffRow> onUpdate;
  final ValueChanged<WorklogHoursSuggestion> onApplySuggestion;
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
    //
    // The second half is the same field coming back: applying a suggestion over recorded
    // intervals clears them, and the box that reappears must hold the suggested hours rather
    // than whatever the controller was left holding while the timer readout stood in its place.
    if (widget.row.hoursWorked != oldWidget.row.hoursWorked ||
        (oldWidget.row.segments.isNotEmpty && widget.row.segments.isEmpty)) {
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
    final suggestion = widget.worklogSuggestion;
    // What the tap destroys, for the chip's own words. The confirmation re-reads the predicate
    // from the row as it stands at gate time; here it is only a label, and a label may lag a
    // rebuild — it cannot act.
    final discardsTiming = suggestion != null && _discardsTiming(row, suggestion);
    // The same reading of the row, in the chip's own words. An interval is the timer's, so that
    // tap replaces the timer; a dropped start→end range is not — a row the office sent with
    // 08:00→12:00 never had a timer to replace, and the chip must not claim one.
    final replaceLabel = row.segments.isNotEmpty
        ? '· Sostituisci il timer'
        : (discardsTiming ? '· Sostituisci gli orari' : null);

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
                        : (ref.watch(colleagueNameProvider(row.userId)).valueOrNull ??
                            'Collega non ancora sincronizzato'),
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
          //
          // Ore is a readout, not a field, once the timer has recorded intervals: those hours
          // are measured, and a typed number would be silently reverted on the next save
          // (`_staffToCompanion` persists `effectiveHours`, which sums the intervals). Km has no
          // such twin and stays editable in every case.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: row.segments.isEmpty
                    ? _NumField(
                        controller: _hoursCtrl,
                        label: 'Ore',
                        suffix: 'h',
                        onChanged: (v) {
                          final h = double.tryParse(v);
                          widget.onUpdate(row.copyWith(hoursWorked: h));
                        },
                      )
                    : _ReadOnlyHours(hours: row.effectiveHours),
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

          // Full width, under both tiles: in the half-width slot beside Km this sentence wraps
          // to five lines and drags the pair out of shape.
          if (row.segments.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Calcolate dal timer: le ore si modificano solo sostituendo il timer.',
              style: TextStyle(color: context.colors.inkMuted, fontSize: 11, height: 1.35),
            ),
          ],

          // A chip inside a running timer would overwrite the total the next stop is about to
          // write from the interval, so it is withheld until the run is stopped. A suggestion is a
          // way to fill a row nobody is timing; over a live run it can only compete with the clock.
          if (suggestion != null && !row.timerRunning) ...[
            const SizedBox(height: 8),
            _WorklogSuggestionChip(
              suggestion: suggestion,
              businessTime: widget.businessTime,
              replaceLabel: replaceLabel,
              onApply: () => _applySuggestion(suggestion),
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
              'Ore effettive: ${_formatHours(row.effectiveHours)}h'
              '${row.segments.length > 1 ? ' · ${row.segments.length} intervalli' : ''}',
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

  String _fmtTime(DateTime dt) => widget.businessTime.formatInZone(dt, 'HH:mm');

  /// Whether applying [suggestion] to [row] throws away timing the technician can currently see —
  /// the recorded intervals, or a start→end range the suggestion carries no range of its own to
  /// replace. Shared by the chip's label and the confirmation, so the two cannot drift.
  bool _discardsTiming(StaffRow row, WorklogHoursSuggestion suggestion) =>
      row.segments.isNotEmpty ||
      (suggestion.startTime == null && (row.startTime != null || row.endTime != null));

  /// Applies the chip, asking first when the tap would discard recorded timing.
  ///
  /// The chip already says so, but it is a small target on a card full of controls, and what it
  /// destroys — what the timer saw on site, or the "Inizio/Fine" the office sent — cannot be
  /// recovered from this phone once gone. The confirmation reuses the app's own destructive
  /// dialog, so it reads as the same gesture as every other "this deletes something" in the app.
  ///
  /// The predicate is read from [widget] HERE, not from the build that drew the chip: the apply
  /// path re-resolves the row after this dialog (`overrideStaffHours`), so an interval that arrived
  /// in between would otherwise be deleted having been shown no warning. One window remains — a
  /// sync landing while the modal itself is open — and it is accepted rather than guarded with a
  /// second dialog: the message the technician already confirmed names the hours and the times it
  /// deletes, and that is true of an interval that arrived a moment ago too.
  Future<void> _applySuggestion(WorklogHoursSuggestion suggestion) async {
    if (_discardsTiming(widget.row, suggestion)) {
      final confirmed = await confirmDeleteDialog(
        context,
        title: 'Sostituire gli orari registrati?',
        message:
            'Le ore e gli orari registrati su questa riga verranno cancellati e sostituiti da '
            'quelli del worklog.',
        confirmLabel: 'Sostituisci',
      );
      if (!confirmed || !mounted) return;
    }
    widget.onApplySuggestion(suggestion);
  }
}

// ── Worklog suggestion chip ─────────────────────────────────────────────────────

class _WorklogSuggestionChip extends StatelessWidget {
  const _WorklogSuggestionChip({
    required this.suggestion,
    required this.businessTime,
    required this.replaceLabel,
    required this.onApply,
  });

  final WorklogHoursSuggestion suggestion;
  final BusinessTime businessTime;

  /// What this tap replaces, phrased for the row it sits on: the timer's intervals, or only the
  /// start→end range the suggestion no longer describes. Null means nothing is discarded and the
  /// chip stays a plain "Usa".
  ///
  /// The wording is derived by the caller, from the same expression that gates the confirmation
  /// dialog, so the promise and the warning cannot disagree.
  final String? replaceLabel;
  final VoidCallback onApply;

  String _fmtTime(DateTime dt) => businessTime.formatInZone(dt, 'HH:mm');

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
            replaceLabel ?? '· Usa',
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

/// One decimal, comma separator — the app's hours figure everywhere on this screen (the
/// suggestion chip's "3,8h", the readout, the "Ore effettive" line), so no two values on one tile
/// are written in two different styles.
String _formatHours(double hours) => hours.toStringAsFixed(1).replaceAll('.', ',');

/// The timer's own total, in the footprint the editable Ore field occupies.
///
/// A readout rather than a disabled text field: a greyed-out box still looks like a box waiting
/// for a tap, and "disabled" reads as a missing permission. Nothing is being withheld from the
/// technician here — these hours were measured for them, and the row below says so.
class _ReadOnlyHours extends StatelessWidget {
  const _ReadOnlyHours({required this.hours});

  final double hours;

  @override
  Widget build(BuildContext context) {
    final value = _formatHours(hours);
    return Semantics(
      // One node named and valued like the editable field this replaces. AppTextField merges its
      // label into the input's own node; a bare container does not, so the visible "Ore" label has
      // to be INSIDE this subtree for `excludeSemantics` to fold it in — wrapping only the shell's
      // child leaves it a sibling announcing a second, nameless "ORE".
      //
      // Three loose Texts would read as "ORE", "2,0", "h" — a value with no name, reached by a
      // swipe and then another.
      container: true,
      excludeSemantics: true,
      label: 'Ore',
      value: '$value h',
      child: AppFieldShell(
        label: 'Ore',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: context.colors.bg3,
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
            border: Border.all(color: context.colors.borderLight),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text('h', style: TextStyle(color: context.colors.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

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
