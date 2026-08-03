// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';

/// Single schedule by id from Drift cache.
final adminScheduleDetailProvider =
    StreamProvider.autoDispose.family<Schedule?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)..where((s) => s.id.equals(id)))
      .watchSingleOrNull();
});

/// Admin schedule detail — read-only with edit FAB.
class AdminScheduleDetailScreen extends ConsumerWidget {
  const AdminScheduleDetailScreen({super.key, required this.scheduleId});

  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(adminScheduleDetailProvider(scheduleId));

    return Scaffold(
      backgroundColor: AppColors.BG2,
      floatingActionButton: AppFab(
        icon: LucideIcons.pencil,
        tooltip: 'Modifica',
        onPressed: () async {
          await context.push<bool>(
            '/altro/pianificazioni/$scheduleId/modifica',
          );
        },
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (schedule) {
          if (schedule == null) {
            return const Center(child: Text('Pianificazione non trovata'));
          }
          return _ScheduleDetailBody(
            schedule: schedule,
            scheduleId: scheduleId,
          );
        },
      ),
    );
  }
}

class _ScheduleDetailBody extends StatelessWidget {
  const _ScheduleDetailBody({
    required this.schedule,
    required this.scheduleId,
  });

  final Schedule schedule;
  final String scheduleId;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it')
        .format(schedule.activityDate.toLocal());
    final timeLabel =
        '${_fmtTime(schedule.timeStartMinutes)} — ${_fmtTime(schedule.timeEndMinutes)}';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
            subtitle: dateLabel,
            showBack: true,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Modifica'),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'edit') {
                    context.push('/altro/pianificazioni/$scheduleId/modifica');
                  }
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Titolo', value: schedule.title.isNotEmpty ? schedule.title : '—'),
                _InfoRow(label: 'Data', value: dateLabel),
                _InfoRow(label: 'Orario', value: timeLabel),
                _InfoRow(
                    label: 'Note',
                    value: schedule.description.isNotEmpty
                        ? schedule.description
                        : '—'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.MUTED,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
