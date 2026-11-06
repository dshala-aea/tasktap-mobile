// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/time/business_time.dart' show formatWorkDate;
import '../../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../../../features/calendario/calendario_providers.dart' show scheduleStatusName;
import '../../../presentation/providers/schedule_providers.dart';

/// Single schedule by id from Drift cache.
final adminScheduleDetailProvider = StreamProvider.autoDispose.family<Schedule?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)..where((s) => s.id.equals(id))).watchSingleOrNull();
});

/// The contract behind the linked ticket, from the same local mirror.
///
/// The contract list's own provider resolves through `referenceCacheProvider` and can issue a
/// network refresh; a detail screen must not. This reads the already-synced table only.
final _contractByIdProvider = StreamProvider.autoDispose.family<Contract?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.contracts)..where((c) => c.id.equals(id))).watchSingleOrNull();
});

/// Admin schedule detail — the wave-0 summary shell: hero + `Modifica`, then Sintesi (the
/// impegno), Relazioni (cliente, ticket, contratto) and Attività (nota, stato).
class AdminScheduleDetailScreen extends ConsumerWidget {
  const AdminScheduleDetailScreen({super.key, required this.scheduleId});

  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(adminScheduleDetailProvider(scheduleId));

    return scheduleAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Pianificazione'),
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Pianificazione',
        icon: LucideIcons.alertTriangle,
        title: 'Pianificazione non disponibile',
        reason: 'Non è stato possibile leggere la pianificazione salvata su questo telefono.',
        onRetry: () => ref.invalidate(adminScheduleDetailProvider(scheduleId)),
      ),
      data: (schedule) {
        if (schedule == null) {
          // Missing on a synced device means the schedule is gone (deleted, or reassigned out
          // of this user's visibility) — not that the mirror is still waiting to arrive.
          final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
          return DetailScaffold.unavailable(
            screenTitle: 'Pianificazione',
            icon: neverSynced ? LucideIcons.cloudOff : LucideIcons.calendarDays,
            title: neverSynced ? 'Pianificazione non disponibile' : 'Pianificazione non trovata',
            reason: neverSynced
                ? "L'elenco pianificazioni non è ancora sincronizzato sul dispositivo, quindi "
                      'questa pianificazione non può essere letta dalla cache locale anche se '
                      'esiste sul server.'
                : 'Questa pianificazione non è più disponibile: potrebbe essere stata eliminata.',
          );
        }
        return _ScheduleDetailBody(schedule: schedule, scheduleId: scheduleId);
      },
    );
  }
}

class _ScheduleDetailBody extends ConsumerWidget {
  const _ScheduleDetailBody({required this.schedule, required this.scheduleId});

  final Schedule schedule;
  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final businessTime = ref.watch(businessTimeProvider);
    final today = businessTime.businessToday();
    final date = DateTime.utc(
      schedule.activityDate.toUtc().year,
      schedule.activityDate.toUtc().month,
      schedule.activityDate.toUtc().day,
    );
    final tomorrow = today.add(const Duration(days: 1));

    final dateLabel = _capitalise(formatWorkDate(date, 'EEEE d MMMM y', locale: 'it'));
    final timeLabel = schedule.allDay
        ? 'Tutto il giorno'
        : '${_fmtTime(schedule.timeStartMinutes)} – ${_fmtTime(schedule.timeEndMinutes)}';

    // The stamp is the day the impegno falls on, like the prototype's `Oggi`; the real schedule
    // status lives in Attività so the same fact is not printed twice.
    final dayStamp = date == today
        ? 'Oggi'
        : date == tomorrow
        ? 'Domani'
        : _capitalise(formatWorkDate(date, 'd MMM', locale: 'it'));
    final dayTone = date == today || date == tomorrow ? DetailStatusTone.info : null;

    final directAssigneeName = ref.watch(colleagueNameProvider(schedule.userId)).valueOrNull;
    // A squadra-only schedule has no direct assignee — `schedule.userId` is the all-zeros GUID
    // the server sends for "nobody directly assigned". The squadra's own name is not synced, but
    // its members are, via `ScheduleAssignees`, so show who they are instead of a blank.
    final assignees = ref.watch(scheduleAssigneesProvider(scheduleId)).valueOrNull ?? const [];
    final teamMemberIds = assignees.where((a) => a.isTeam).map((a) => a.userId).toList();
    final teamMemberNames = teamMemberIds
        .map((id) => ref.watch(colleagueNameProvider(id)).valueOrNull)
        .whereType<String>()
        .toList();
    final assigneeName =
        directAssigneeName ??
        (teamMemberNames.isEmpty ? null : 'Squadra: ${teamMemberNames.join(', ')}');

    final location = ref.watch(locationByIdProvider(schedule.locationId)).valueOrNull;
    final ticket = schedule.ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(schedule.ticketId!)).valueOrNull;
    final customerId = location?.customerId ?? ticket?.customerId;
    final customer = customerId == null
        ? null
        : ref.watch(customerByIdProvider(customerId)).valueOrNull;
    final contract = ticket?.contractId == null
        ? null
        : ref.watch(_contractByIdProvider(ticket!.contractId!)).valueOrNull;

    final statusName = scheduleStatusName(schedule.statusId);
    final locationName = location?.name;
    final lockedByAbsence = schedule.isAssenza;
    final lockedByBlock = schedule.isBlockOccupied;

    final relations = <({String title, String meta, VoidCallback? onTap})>[
      if (customer != null && customerId != null)
        (
          title: 'Cliente',
          meta: customer.companyName,
          onTap: () => context.push(AppRoutes.clientiDetail(customerId)),
        ),
      if (ticket != null)
        (
          title: 'Ticket',
          meta: ticket.title,
          onTap: () => context.push(AppRoutes.ticketDetailPath(ticket.id)),
        )
      else if (schedule.ticketId != null)
        (
          title: 'Ticket',
          meta: 'Collegato',
          onTap: () => context.push(AppRoutes.ticketDetailPath(schedule.ticketId!)),
        ),
      if (contract != null) (title: 'Contratto', meta: contract.name, onTap: null),
    ];

    final hasNote = schedule.description.trim().isNotEmpty;

    return DetailScaffold(
      screenTitle: 'Pianificazione',
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · impegno',
        kicker: 'Summary',
        kickerContext: 'impegno',
        title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
        status: DetailStatus(label: dayStamp, tone: dayTone),
        primaryAction: lockedByAbsence || lockedByBlock
            ? null
            : DetailAction(
                label: 'Modifica',
                onPressed: () async {
                  await context.push<bool>('/altro/pianificazioni/$scheduleId/modifica');
                },
              ),
      ),
      expandedExtra: (lockedByAbsence || lockedByBlock)
          ? Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (lockedByAbsence)
                    InlineAlert(
                      icon: LucideIcons.calendarX,
                      color: colors.amber,
                      message:
                          'Assenza approvata: questa voce è creata dalla richiesta di ferie, '
                          'permesso o malattia e non si può modificare da qui. Per cambiarla, '
                          'annulla la richiesta dalle assenze.',
                    ),
                  if (lockedByAbsence && lockedByBlock) const SizedBox(height: AppSpacing.sm),
                  if (lockedByBlock)
                    InlineAlert(
                      icon: LucideIcons.calendarDays,
                      color: colors.amber,
                      message:
                          'Piano multi-giorno: questa giornata è occupata da un intervento '
                          'pianificato su più giorni e non si può modificare da qui. Per '
                          "modificare il piano, usa il portale web dell'ufficio.",
                    ),
                ],
              ),
            )
          : null,
      sections: [
        DetailSectionData(
          title: 'Sintesi',
          child: DetailFactsGrid(
            facts: [
              DetailFact(label: 'Data', value: dateLabel),
              DetailFact(label: 'Orario', value: timeLabel),
              DetailFact(label: 'Assegnato a', value: assigneeName ?? '—'),
              DetailFact(label: 'Sede', value: locationName ?? '—'),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Relazioni',
          isEmpty: relations.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < relations.length; i++)
                DetailLinkRow(
                  title: relations[i].title,
                  meta: relations[i].meta,
                  onTap: relations[i].onTap,
                  showDivider: i < relations.length - 1,
                ),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Attività',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailLinkRow(title: 'Stato', meta: statusName, showDivider: hasNote),
              if (hasNote)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NOTA',
                        style: AppTextStyles.docCode.copyWith(
                          fontSize: 8,
                          letterSpacing: 0.64,
                          color: colors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        schedule.description,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 11.5,
                          height: 1.4,
                          color: colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      onRefresh: () => refreshWithFeedback(context, ref),
    );
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static String _fmtTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
