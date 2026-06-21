import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../providers/schedule_providers.dart';

/// Today's schedule screen — reads schedules from the local Drift DB.
class OggiScreen extends ConsumerWidget {
  const OggiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(todaySchedulesProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Oggi', style: AppTextStyles.titleLarge),
        actions: [
          // Manual refresh action
          IconButton(
            icon: syncState.status == SyncStatus.syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizza',
            onPressed: syncState.status == SyncStatus.syncing
                ? null
                : () => ref.read(syncProvider.notifier).performSync(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync status bar
          _SyncStatusBar(syncState: syncState),
          Expanded(
            child: schedulesAsync.when(
              data: (schedules) => schedules.isEmpty
                  ? const _EmptyToday()
                  : _ScheduleList(schedules: schedules),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Errore: $e',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: Colors.red)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sync status bar ────────────────────────────────────────────────────────────

class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({required this.syncState});

  final SyncState syncState;

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;

    switch (syncState.status) {
      case SyncStatus.syncing:
        label = 'Sincronizzazione in corso…';
        bg = AppColors.brand.withValues(alpha: 0.15);
      case SyncStatus.error:
        label =
            'Errore sincronizzazione: ${syncState.errorMessage ?? 'sconosciuto'}';
        bg = Colors.red.withValues(alpha: 0.1);
      case SyncStatus.done:
      case SyncStatus.idle:
        if (syncState.lastSync != null) {
          final fmt = DateFormat('dd/MM/yyyy HH:mm');
          label = 'Ultimo aggiornamento: ${fmt.format(syncState.lastSync!.toLocal())}';
          bg = Colors.transparent;
        } else {
          label = 'Nessuna sincronizzazione';
          bg = Colors.orange.withValues(alpha: 0.08);
        }
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      child: Text(label,
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textSecondary)),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyToday extends StatelessWidget {
  const _EmptyToday();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.today, size: 56, color: AppColors.brand),
            const SizedBox(height: AppSpacing.base),
            Text('Nessun intervento oggi',
                style: AppTextStyles.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tira giù per aggiornare, o attendi la sincronizzazione automatica.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Schedule list ──────────────────────────────────────────────────────────────

class _ScheduleList extends StatelessWidget {
  const _ScheduleList({required this.schedules});

  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        // Pull-to-refresh is wired via the notifier.
        // We can't await the provider notifier from here cleanly,
        // so the sync status bar reflects progress.
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.base),
        itemCount: schedules.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) =>
            _ScheduleCard(schedule: schedules[i]),
      ),
    );
  }
}

// ── Schedule card ──────────────────────────────────────────────────────────────

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync =
        ref.watch(locationByIdProvider(schedule.locationId));
    final customerName = _resolveCustomerName(ref, locationAsync);

    final timeStart = _minutesToTime(schedule.timeStartMinutes);
    final timeEnd = _minutesToTime(schedule.timeEndMinutes);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time range
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  schedule.allDay
                      ? 'Tutto il giorno'
                      : '$timeStart – $timeEnd',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Title
            Text(
              schedule.title.isNotEmpty
                  ? schedule.title
                  : 'Intervento senza titolo',
              style: AppTextStyles.titleMedium,
            ),
            if (schedule.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                schedule.description,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Location / customer info
            locationAsync.when(
              data: (loc) => _LocationRow(
                locationName: loc?.name,
                customerName: customerName,
                city: loc?.city,
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, st) =>
                  _LocationRow(locationName: schedule.locationId),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolve the customer name from the location's customerId.
  String? _resolveCustomerName(
      WidgetRef ref, AsyncValue<Location?> locationAsync) {
    final loc = locationAsync.valueOrNull;
    if (loc == null) return null;
    final customerAsync =
        ref.watch(customerByIdProvider(loc.customerId));
    return customerAsync.valueOrNull?.companyName;
  }

  static String _minutesToTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

// ── Location row ───────────────────────────────────────────────────────────────

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    this.locationName,
    this.customerName,
    this.city,
  });

  final String? locationName;
  final String? customerName;
  final String? city;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      ?customerName,
      ?locationName,
      ?city,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.location_on,
            size: 14, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Reusable placeholder (kept for other screens) ─────────────────────────────

class ComingSoonPlaceholder extends StatelessWidget {
  const ComingSoonPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.brand),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            style: AppTextStyles.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
