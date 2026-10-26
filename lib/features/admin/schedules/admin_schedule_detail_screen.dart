// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../../../features/calendario/calendario_providers.dart' show scheduleStatusName;
import '../../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Single schedule by id from Drift cache.
final adminScheduleDetailProvider = StreamProvider.autoDispose.family<Schedule?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)..where((s) => s.id.equals(id))).watchSingleOrNull();
});

/// Admin schedule detail — read-only with edit FAB.
class AdminScheduleDetailScreen extends ConsumerWidget {
  const AdminScheduleDetailScreen({super.key, required this.scheduleId});

  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(adminScheduleDetailProvider(scheduleId));
    // An approved absence arrives as an ordinary schedule row (that is how the server blocks the
    // day), and the backend refuses every write to it (`absence_schedule_read_only`). Offering
    // Modifica here invites an edit that can only fail; the absence it stands for is managed where
    // it lives, from Ferie e Permessi. Null while loading, so the FAB is not flickered in first.
    final lockedByAbsence = scheduleAsync.valueOrNull?.isAssenza ?? false;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: lockedByAbsence
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: context.fabSafeBottom),
              child: AppFab(
                icon: LucideIcons.pencil,
                tooltip: 'Modifica',
                onPressed: () async {
                  await context.push<bool>('/altro/pianificazioni/$scheduleId/modifica');
                },
              ),
            ),
      body: SafeArea(
        child: scheduleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(adminScheduleDetailProvider(scheduleId))),
          data: (schedule) {
            if (schedule == null) {
              // Missing on a synced device means the schedule is gone (deleted, or reassigned out
              // of this user's visibility) — not that the mirror is still waiting to arrive.
              return ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false
                  ? const UnavailableState(
                      icon: LucideIcons.cloudOff,
                      titolo: 'Pianificazione non disponibile',
                      motivo:
                          "L'elenco pianificazioni non è ancora sincronizzato sul "
                          'dispositivo, quindi questa pianificazione non può essere '
                          'letta dalla cache locale anche se esiste sul server.',
                    )
                  : const UnavailableState(
                      icon: LucideIcons.calendarDays,
                      titolo: 'Pianificazione non trovata',
                      motivo: 'Questa pianificazione non è più disponibile: potrebbe essere '
                          'stata eliminata.',
                    );
            }
            return _ScheduleDetailBody(schedule: schedule, scheduleId: scheduleId);
          },
        ),
      ),
    );
  }
}

class _ScheduleDetailBody extends ConsumerWidget {
  const _ScheduleDetailBody({required this.schedule, required this.scheduleId});

  final Schedule schedule;
  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(schedule.activityDate.toLocal());
    final timeLabel =
        '${_fmtTime(schedule.timeStartMinutes)} — ${_fmtTime(schedule.timeEndMinutes)}';

    // The DTO already carries all of this (Schedule.userId/locationId/statusId/ticketId — see
    // app_database.dart) — it was just never rendered here. Resolved through the same lookups the
    // rest of the app already uses (colleagueNameProvider, allLocationsProvider,
    // scheduleStatusName, allTicketsProvider), never re-derived.
    final directAssigneeName = ref.watch(colleagueNameProvider(schedule.userId)).valueOrNull;
    // A squadra-only schedule has no direct assignee — `schedule.userId` is the all-zeros GUID the
    // server sends for "nobody directly assigned" (see `SyncScheduleDto.From`'s doc comment), which
    // `colleagueNameProvider` never resolves. The squadra's own name/id is not synced to the device
    // (only `GET /api/schedules/{id}`, online-only, resolves it — see
    // `teamAssignedScheduleIdsProvider`'s doc comment), but its members are, via `ScheduleAssignees`
    // — so this shows who they are instead of leaving the row blank.
    final assignees = ref.watch(scheduleAssigneesProvider(scheduleId)).valueOrNull ?? const [];
    final teamMemberIds = assignees.where((a) => a.isTeam).map((a) => a.userId).toList();
    final teamMemberNames = teamMemberIds
        .map((id) => ref.watch(colleagueNameProvider(id)).valueOrNull)
        .whereType<String>()
        .toList();
    final assigneeName =
        directAssigneeName ??
        (teamMemberNames.isEmpty ? null : 'Squadra: ${teamMemberNames.join(', ')}');
    final locations = ref.watch(allLocationsProvider).valueOrNull ?? const [];
    final sedeName = _findLocationName(locations, schedule.locationId);
    final statusName = scheduleStatusName(schedule.statusId);
    final tickets = ref.watch(allTicketsProvider).valueOrNull ?? const [];
    final linkedTicketTitle = schedule.ticketId == null
        ? null
        : _findTicketTitle(tickets, schedule.ticketId!);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
            subtitle: dateLabel,
            showBack: true,
          ),
        ),
        // The FAB is gone for these rows, so the screen has to say why — an office user who came
        // here to move a job must not read the absence as "this one just cannot be edited".
        if (schedule.isAssenza)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.base,
                AppSpacing.pagePadding,
                0,
              ),
              child: InlineAlert(
                icon: LucideIcons.calendarX,
                color: context.colors.amber,
                message:
                    'Assenza approvata: questa voce è creata dalla richiesta di ferie, permesso '
                    'o malattia e non si può modificare da qui. Per cambiarla, annulla la '
                    'richiesta dalle assenze.',
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                children: [
                  // Titolo, Sede, Ticket collegato and Note are free text of unknown length, so
                  // they stack label-over-value and wrap: the horizontal row right-aligns the value
                  // on a single line and ellipsizes it, which hid the rest of a note the office had
                  // written over four lines. The short facts (date, hours, assignee, status) stay
                  // horizontal — a two-column pair reads faster for a value that always fits.
                  KeyVal(
                    label: 'Titolo',
                    value: schedule.title.isNotEmpty ? schedule.title : '—',
                    vertical: true,
                  ),
                  KeyVal(label: 'Data', value: dateLabel),
                  KeyVal(label: 'Orario', value: timeLabel),
                  KeyVal(label: 'Assegnato a', value: assigneeName ?? '—'),
                  KeyVal(label: 'Sede', value: sedeName ?? '—', vertical: true),
                  KeyVal(label: 'Stato', value: statusName),
                  KeyVal(
                    label: 'Ticket collegato',
                    value: linkedTicketTitle ?? '—',
                    vertical: true,
                    showDivider: schedule.description.isNotEmpty,
                  ),
                  if (schedule.description.isNotEmpty)
                    KeyVal(
                      label: 'Note',
                      value: schedule.description,
                      vertical: true,
                      showDivider: false,
                    ),
                ],
              ),
            ),
          ),
        ),

        SliverPadding(padding: EdgeInsets.only(bottom: context.fabSafeBottom)),
      ],
    );
  }

  String? _findLocationName(List<Location> locations, String locationId) {
    for (final l in locations) {
      if (l.id == locationId) return l.name;
    }
    return null;
  }

  String? _findTicketTitle(List<Ticket> tickets, String ticketId) {
    for (final t in tickets) {
      if (t.id == ticketId) return t.title;
    }
    return null;
  }

  String _fmtTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
