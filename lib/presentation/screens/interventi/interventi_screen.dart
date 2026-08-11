import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Schedules list for today + next 7 days — reads from the local Drift DB.
class InterventiScreen extends ConsumerWidget {
  const InterventiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(weekSchedulesProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: context.colors.bg1,
      appBar: AppBar(
        title: Text('Interventi', style: AppTextStyles.titleLarge),
        actions: [
          IconButton(
            icon: syncState.status == SyncStatus.syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw),
            tooltip: 'Sincronizza',
            onPressed: syncState.status == SyncStatus.syncing
                ? null
                : () => ref.read(syncProvider.notifier).performSync(),
          ),
        ],
      ),
      body: schedulesAsync.when(
        data: (schedules) => schedules.isEmpty
            ? _EmptyWeek(syncState: syncState)
            : _WeekList(schedules: schedules),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Errore: $e',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: Colors.red)),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek({required this.syncState});

  final SyncState syncState;

  @override
  Widget build(BuildContext context) {
    String hint;
    if (syncState.lastSync == null) {
      hint = 'Effettua il login e sincronizza per vedere i tuoi interventi.';
    } else {
      hint = 'Nessun intervento nei prossimi 7 giorni.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wrench, size: 56, color: AppColors.brand),
            const SizedBox(height: AppSpacing.base),
            Text('Nessun intervento',
                style: AppTextStyles.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hint,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: context.colors.inkFaint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Week list ──────────────────────────────────────────────────────────────────

class _WeekList extends StatelessWidget {
  const _WeekList({required this.schedules});

  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    // Group by date
    final grouped = <DateTime, List<Schedule>>{};
    for (final s in schedules) {
      final day = DateTime(
          s.activityDate.year, s.activityDate.month, s.activityDate.day);
      grouped.putIfAbsent(day, () => []).add(s);
    }

    final days = grouped.keys.toList()..sort();
    final dayFmt = DateFormat('EEEE d MMMM', 'it');

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final daySchedules = grouped[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm),
              child: Text(
                dayFmt.format(day),
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.brand),
              ),
            ),
            ...daySchedules
                .map((s) => Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _InterventiCard(schedule: s),
                    ))
                ,
          ],
        );
      },
    );
  }
}

// ── Interventi card ────────────────────────────────────────────────────────────

class _InterventiCard extends ConsumerWidget {
  const _InterventiCard({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync =
        ref.watch(locationByIdProvider(schedule.locationId));
    final location = locationAsync.valueOrNull;

    final customerName = location != null
        ? ref
            .watch(customerByIdProvider(location.customerId))
            .valueOrNull
            ?.companyName
        : null;

    final timeStart = _minutesToTime(schedule.timeStartMinutes);
    final timeEnd = _minutesToTime(schedule.timeEndMinutes);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs),
        leading: Container(
          width: 4,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(
          schedule.title.isNotEmpty ? schedule.title : 'Intervento',
          style: AppTextStyles.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              schedule.allDay
                  ? 'Tutto il giorno'
                  : '$timeStart – $timeEnd',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.colors.inkFaint),
            ),
            if (customerName != null || location != null)
              Text(
                [
                  ?customerName,
                  ?location?.city,
                ].join(' · '),
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.colors.inkFaint),
              ),
          ],
        ),
      ),
    );
  }

  static String _minutesToTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
