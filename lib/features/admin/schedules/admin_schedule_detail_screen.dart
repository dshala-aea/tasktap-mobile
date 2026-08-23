// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
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

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/pianificazioni/$scheduleId/modifica');
          },
        ),
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(adminScheduleDetailProvider(scheduleId))),
        data: (schedule) {
          if (schedule == null) {
            return const UnavailableState(
              icon: LucideIcons.calendarDays,
              titolo: 'Pianificazione non disponibile',
              motivo:
                  "L'elenco pianificazioni non è ancora sincronizzato sul "
                  'dispositivo, quindi questa pianificazione non può essere '
                  'letta dalla cache locale anche se esiste sul server.',
            );
          }
          return _ScheduleDetailBody(schedule: schedule, scheduleId: scheduleId);
        },
      ),
    );
  }
}

class _ScheduleDetailBody extends StatelessWidget {
  const _ScheduleDetailBody({required this.schedule, required this.scheduleId});

  final Schedule schedule;
  final String scheduleId;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(schedule.activityDate.toLocal());
    final timeLabel =
        '${_fmtTime(schedule.timeStartMinutes)} — ${_fmtTime(schedule.timeEndMinutes)}';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
            subtitle: dateLabel,
            showBack: true,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                children: [
                  KeyVal(label: 'Titolo', value: schedule.title.isNotEmpty ? schedule.title : '—'),
                  KeyVal(label: 'Data', value: dateLabel),
                  KeyVal(label: 'Orario', value: timeLabel),
                  KeyVal(
                    label: 'Note',
                    value: schedule.description.isNotEmpty ? schedule.description : '—',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ),

        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }

  String _fmtTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
