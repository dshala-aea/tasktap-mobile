// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'dashboard_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The dashboard's work queue: five named tiers, not a single ranked list.
///
/// Chosen over a time-plotted agenda strip (the roll's own assigned structure) on direct
/// feedback: a bucketed queue is explainable ("this is Da fare because nothing else is open yet
/// today") where a rank is not, and it reads as the actual job — triage, then act — rather than a
/// calendar the app already has a real one of (Calendario). Live and Da fare carry a visible next
/// step; Programmato/In attesa/Fatto are compact rows, because the day's answer to "what matters
/// now" only has one or two entries in it on an ordinary day.
class WorkQueueSection extends ConsumerWidget {
  const WorkQueueSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(workQueueProvider);

    final sections = <Widget>[];

    for (final schedule in q.live) {
      sections.add(_FocusCard(schedule: schedule, tier: _Tier.live));
    }
    if (q.daFare != null) {
      sections.add(_FocusCard(schedule: q.daFare!, tier: _Tier.daFare));
    }
    if (q.inAttesa.isNotEmpty) {
      sections.add(_CompactTier(title: 'IN ATTESA', schedules: q.inAttesa, tier: _Tier.inAttesa));
    }
    if (q.programmato.isNotEmpty) {
      sections.add(
        _CompactTier(title: 'PROGRAMMATO', schedules: q.programmato, tier: _Tier.programmato),
      );
    }
    if (q.fatto.isNotEmpty) {
      sections.add(_CompactTier(title: 'FATTO', schedules: q.fatto, tier: _Tier.fatto));
    }

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
        child: const EmptyState(
          icon: LucideIcons.calendarOff,
          title: 'Nessun intervento oggi',
          body: 'Buona giornata. I lavori assegnati appariranno qui.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections),
    );
  }
}

enum _Tier { live, daFare, programmato, inAttesa, fatto }

extension on _Tier {
  /// Icon + text together, always — see the signage grammar's own rule: a status is never color
  /// alone.
  (IconData, String) get badge => switch (this) {
    // timer, not a lightning bolt — the same glyph the ticket timer bar already uses for "a clock
    // is running here" (see ticket_detail_screen.dart's _TicketTimerBar), so the two screens read
    // as one vocabulary rather than two.
    _Tier.live => (LucideIcons.timer, 'LIVE'),
    _Tier.daFare => (LucideIcons.circleDot, 'DA FARE'),
    _Tier.programmato => (LucideIcons.calendarDays, 'PROGRAMMATO'),
    // coffee, not a pause glyph — this app already spends "coffee" on Timbra's own pause control,
    // so reusing it here says "paused/waiting" in the same vocabulary rather than inventing a
    // second icon for the same idea.
    _Tier.inAttesa => (LucideIcons.coffee, 'IN ATTESA'),
    _Tier.fatto => (LucideIcons.check, 'FATTO'),
  };
}

// ── Row content (shared between the focus card and the compact row) ─────────────

class _RowContent {
  const _RowContent({required this.title, required this.subtitle, required this.timeLabel});
  final String title;
  final String subtitle;

  /// Null for an all-day schedule — there is no real start time to show (see
  /// `_resolveRow`'s own doc comment), so the badge/meta row omits the time entirely rather
  /// than formatting the placeholder minute values into a literal "00:00". Same gate
  /// `giorno_view.dart`'s `_EventBlock`, `lista_view.dart`'s `_ScheduleListRow` and
  /// `calendario_screen.dart`'s `_ScheduleInfoSheet` already use for the same reason.
  final String? timeLabel;
}

final _weekdayFmt = DateFormat('EEE d', 'it');

/// "14:30" for today; "Dom 21, 14:30" for anything else — Programmato can hold items up to 7
/// days out, and a bare HH:MM told the technician nothing about which day it was for. No shared
/// "today vs. other day" helper exists elsewhere yet (calendario's own views each inline their
/// own `isToday` check against a full day view, not a compact single-line label), so this is a
/// small local one rather than a half-fit reuse.
String _dateQualifiedTimeLabel(DateTime activityDate, int timeStartMinutes) {
  final h = timeStartMinutes ~/ 60;
  final m = timeStartMinutes % 60;
  final time = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(activityDate.year, activityDate.month, activityDate.day);
  if (day == today) return time;

  final label = _weekdayFmt.format(day);
  final capitalised = '${label[0].toUpperCase()}${label.substring(1)}';
  return '$capitalised, $time';
}

_RowContent _resolveRow(WidgetRef ref, Schedule schedule) {
  final location = ref.watch(locationByIdProvider(schedule.locationId)).valueOrNull;
  final customerName = location != null
      ? ref.watch(customerByIdProvider(location.customerId)).valueOrNull?.companyName
      : null;
  final subtitle = [
    customerName,
    location?.city,
  ].where((s) => s != null && s.isNotEmpty).join(' · ');
  // An all-day schedule's timeStartMinutes/timeEndMinutes are placeholder bounds (always
  // 0/0), not a real time of day — formatting them unconditionally produced a literal "00:00"
  // that read as "starts at midnight" rather than "no time, all day". Gate on `allDay` the
  // same way Calendario's own views already do.
  final timeLabel = schedule.allDay
      ? null
      : _dateQualifiedTimeLabel(schedule.activityDate, schedule.timeStartMinutes);
  return _RowContent(
    title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
    subtitle: subtitle,
    timeLabel: timeLabel,
  );
}

void _open(BuildContext context, Schedule schedule) {
  final ticketId = schedule.ticketId;
  if (ticketId != null) context.push(AppRoutes.ticketDetailPath(ticketId));
}

// ── Focus card: Live / Da fare ────────────────────────────────────────────────

class _FocusCard extends ConsumerWidget {
  const _FocusCard({required this.schedule, required this.tier});

  final Schedule schedule;
  final _Tier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final row = _resolveRow(ref, schedule);
    final (icon, label) = tier.badge;
    // Live is an equipment-lamp state (green), not a call to action — the accent is reserved for
    // Da fare, the one tier that actually asks the technician to do something now. Conflating the
    // two would spend the accent on the ordinary state of most of a shift, the same reasoning
    // LiveDot exists for.
    final badgeColor = tier == _Tier.live ? c.green : AppColors.Y;
    final ticketId = schedule.ticketId;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: ticketId != null ? () => _open(context, schedule) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.ink,
                letterSpacing: -0.2,
              ),
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                row.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Archivo', fontSize: 13, color: c.inkMuted),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(icon, size: 14, color: badgeColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: badgeColor,
                  ),
                ),
                if (row.timeLabel != null)
                  Text(
                    '  ·  ${row.timeLabel}',
                    style: TextStyle(
                      fontFamily: 'Archivo',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.inkMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                const Spacer(),
                // Flat AppColors.Y for every tier, live included — was a per-tier gradient
                // override (green for live); AppButton's 5 named variants don't carry a
                // per-instance colour override, and the tier badge just above already carries
                // the live/green vs. other/accent distinction ("a status is never colour alone",
                // see _Tier.badge's own doc comment), so this button no longer needs to repeat it.
                if (ticketId != null)
                  AppButton(
                    label: 'Apri',
                    size: AppButtonSize.sm,
                    fullWidth: false,
                    onPressed: () => _open(context, schedule),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Compact tier: Programmato / In attesa / Fatto ────────────────────────────

class _CompactTier extends StatelessWidget {
  const _CompactTier({required this.title, required this.schedules, required this.tier});

  final String title;
  final List<Schedule> schedules;
  final _Tier tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '$title  ${schedules.length}',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: context.colors.inkMuted,
              ),
            ),
          ),
          for (var i = 0; i < schedules.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _CompactRow(schedule: schedules[i], tier: tier),
            ),
        ],
      ),
    );
  }
}

class _CompactRow extends ConsumerWidget {
  const _CompactRow({required this.schedule, required this.tier});

  final Schedule schedule;
  final _Tier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = _resolveRow(ref, schedule);
    // Fatto rows read as settled, not as a peer of what's still ahead — the same downweight the
    // ticket/rapportino lists give a submitted/completed row.
    final opacity = tier == _Tier.fatto ? 0.6 : 1.0;
    return Opacity(
      opacity: opacity,
      child: ListRow(
        leading: RowIconTile(icon: tier.badge.$1, size: 36, iconSize: 16),
        title: row.title,
        subtitle: row.subtitle,
        meta: row.timeLabel == null
            ? null
            : Text(
                row.timeLabel!,
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
        onTap: schedule.ticketId != null ? () => _open(context, schedule) : null,
      ),
    );
  }
}
