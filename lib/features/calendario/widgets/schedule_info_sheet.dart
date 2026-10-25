// lib/features/calendario/widgets/schedule_info_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../calendario_providers.dart';

/// Opens the read-only detail card for one [Schedule].
///
/// Lifted out of the calendar screen so the ticket's Pianificazioni box can open the same card:
/// a technician could list a ticket's schedules but never read one, and the admin route
/// (`/altro/pianificazioni/:id`) is gated behind `pianificazione.schedule.write`, which is not what
/// reading your own day should cost. Everything here comes from the local mirror, so it opens with
/// no signal.
void showScheduleInfoSheet(BuildContext context, Schedule schedule) {
  showModalBottomSheet<void>(
    context: context,
    // `useRootNavigator: true` is load-bearing here, unlike every other sheet in the app.
    // Calendario is a StatefulShellBranch, and its shell (HomeShell) renders a Scaffold with
    // `extendBody: true` plus a floating `AppBottomNav` as `bottomNavigationBar`. With the
    // default (branch) navigator the sheet is painted inside the shell body, i.e. *under* that
    // pill — the sheet opens but the nav covers its lower edge (the owner's repro: "for events
    // that are not tickets the sheet opens but it is behind the bottom nav and it is covered").
    // The root navigator sits above the whole shell, so the sheet clears the nav. Every other
    // sheet call site lives on a full-screen route (`parentNavigatorKey: rootNavigatorKey`) or a
    // top-level route, whose context already resolves to the root navigator — the ticket detail
    // screen is one of those, so the flag is harmless there.
    useRootNavigator: true,
    // 16, not 20 — every other bottom sheet in the app uses this radius.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => ScheduleInfoSheet(schedule: schedule),
  );
}

/// What is on a schedule, read-only: status, hours, customer, site, technicians, note.
class ScheduleInfoSheet extends ConsumerWidget {
  const ScheduleInfoSheet({super.key, required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final where = ref
        .watch(scheduleWhereProvider((ticketId: schedule.ticketId, locationId: schedule.locationId)))
        .valueOrNull;
    final tecnici = ref.watch(scheduleAssigneeNamesProvider(schedule.id)).valueOrNull ?? const [];
    // An all-day schedule has no meaningful time-of-day to show — timeStartMinutes/
    // timeEndMinutes on an all-day row are placeholder bounds, not a real range. Gate on
    // `allDay`, not on the minute values, so neither the visible text nor its layout implies
    // a time exists.
    final timeRange = schedule.allDay
        ? null
        : '${formatMinutes(schedule.timeStartMinutes)} – ${formatMinutes(schedule.timeEndMinutes)}';
    final statusName = scheduleStatusName(schedule.statusId);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.base,
        AppSpacing.xl,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 20),
          Text(
            schedule.title,
            style: TextStyle(
              fontFamily: 'Archivo Narrow',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusPill(stato: statusName),
              if (timeRange != null) ...[
                const SizedBox(width: 12),
                Icon(LucideIcons.clock, size: 14, color: context.colors.inkMuted),
                const SizedBox(width: 4),
                Text(
                  timeRange,
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 13,
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
          if (where?.customerName != null) _InfoLine(label: 'Cliente', value: where!.customerName!),
          if (where?.address != null) _InfoLine(label: 'Sede', value: where!.address!),
          if (tecnici.isNotEmpty) _InfoLine(label: 'Tecnici', value: tecnici.join(', ')),
          if (schedule.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              schedule.description,
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 13,
                color: context.colors.inkFaint,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// One labelled fact in the schedule detail sheet.
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}
