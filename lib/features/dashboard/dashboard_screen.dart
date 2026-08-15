import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'active_tracker_strip.dart';
import 'active_trackers_provider.dart';
import 'dashboard_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// The technician's day, in the order they need it.
///
/// Running clocks, today's interventi, the next seven days, then the two things worth starting
/// from here. The stat grid that used to sit above all of it is gone — see the Oggi section.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.displayName ?? user?.email ?? 'Tecnico';
    final stats = ref.watch(dashboardStatsProvider);
    final trackers = ref.watch(visibleTrackersProvider);
    final todayAsync = ref.watch(todaySchedulesProvider);
    final upcomingAsync = ref.watch(upcomingSchedulesProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      // The hero paints over the rail, so the rail starts below it. Without this the world's
      // most load-bearing mark is hidden behind the one panel guaranteed to be on screen.
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).performSync(),
        child: CustomScrollView(
          slivers: [
            // ── Hero ──────────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: DashboardHero(
                userName: userName,
                actions: [
                  HeaderIconBtn(
                    icon: LucideIcons.bell,
                    label: 'Notifiche',
                    glass: true,
                    onTap: () => context.push(AppRoutes.altroNotifiche),
                  ),
                  HeaderIconBtn(
                    icon: LucideIcons.user,
                    label: 'Profilo',
                    glass: true,
                    onTap: () => context.push(AppRoutes.altroProfilo),
                  ),
                ],
                // Only what is actually running, and nothing at all when nothing is.
                //
                // A placeholder here was still a placeholder: the hero drew a grey glass panel
                // reading "Non hai interventi attivi al momento" for the ordinary condition of
                // being between jobs, which is most of the morning. There is no information in
                // it — the absence of rows already says it — and it was the first thing on the
                // screen. Nothing running now costs nothing on screen.
                child: trackers.isEmpty ? null : ActiveTrackerStrip(trackers: trackers),
              ),
            ),

            // ── Oggi ──────────────────────────────────────────────────────────
            //
            // Today's interventi were a number in a 2×2 stat grid — `Interventi oggi  3` — while
            // the only list on the screen started at tomorrow. The one question a technician opens
            // this app to answer was the one thing rendered as a digit.
            //
            // The grid is gone with it. Four counts derivable from the two lists beneath them,
            // taking the width of the screen above the fold, is the hero-metric template doing
            // nothing: nobody acts on "Completati 2". What survives is the one count that is not
            // visible in the list itself — how many of today's jobs are already done — folded into
            // the section heading.
            SliverToBoxAdapter(
              child: SectionTitle(
                title: 'Oggi',
                trailing: stats.completedCount > 0
                    ? '${stats.completedCount} di ${stats.todayCount} completati'
                    : null,
              ),
            ),
            _ScheduleSliver(
              schedules: todayAsync,
              emptyTitle: 'Nessun intervento oggi',
              emptyBody: 'Buona giornata. I lavori assegnati appariranno qui.',
              showDate: false,
            ),

            // ── Prossimi interventi ───────────────────────────────────────────
            const SliverToBoxAdapter(child: SectionTitle(title: 'Prossimi')),
            _ScheduleSliver(
              schedules: upcomingAsync,
              emptyTitle: 'Nessun intervento in programma',
              emptyBody: 'I prossimi interventi appariranno qui dopo la sincronizzazione.',
            ),

            // ── Start something ───────────────────────────────────────────────
            //
            // Below the work, not above it. These are the two things a technician *starts* from
            // here; "Rapportini" and "Magazzino" were also here and are places to *go*, which the
            // Altro tab already is. A shortcut to a screen one tap away is not a shortcut.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 20, 19, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.ticket,
                        label: 'Nuovo\nticket',
                        onTap: () => context.push('/ticket/new'),
                      ),
                    ),
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.clock,
                        label: 'Timbra\ncantiere',
                        onTap: () => context.push(AppRoutes.cantiereTimbra),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom padding so the last card clears the floating bottom nav.
            SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
          ],
        ),
      ),
    );
  }
}

/// A list of interventi, or the reason there isn't one. Used for both Oggi and Prossimi.
class _ScheduleSliver extends StatelessWidget {
  const _ScheduleSliver({
    required this.schedules,
    required this.emptyTitle,
    required this.emptyBody,
    this.showDate = true,
  });

  final AsyncValue<List<Schedule>> schedules;

  /// False for today's list, where every row would carry the same date.
  final bool showDate;
  final String emptyTitle;
  final String emptyBody;

  @override
  Widget build(BuildContext context) {
    return schedules.when(
      data: (list) => list.isEmpty
          ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 19),
                child: EmptyState(
                  icon: LucideIcons.calendarOff,
                  title: emptyTitle,
                  body: emptyBody,
                ),
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.fromLTRB(19, i == 0 ? 0 : 8, 19, 8),
                  child: _UpcomingItem(schedule: list[i], showDate: showDate),
                ),
                childCount: list.length,
              ),
            ),
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
        ),
      ),
      error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

class _UpcomingItem extends ConsumerWidget {
  const _UpcomingItem({required this.schedule, this.showDate = true});

  final Schedule schedule;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationByIdProvider(schedule.locationId)).valueOrNull;
    final customerName = location != null
        ? ref.watch(customerByIdProvider(location.customerId)).valueOrNull?.companyName
        : null;

    // Built only when it is going to be shown — today's rows never render a date, and formatting
    // one there costs a locale lookup to throw the result away.
    final dateLabel = showDate
        ? DateFormat('EEE d MMM', 'it').format(schedule.activityDate.toLocal())
        : '';
    final timeLabel = _minutesToTime(schedule.timeStartMinutes);
    final subtitle = [
      customerName,
      location?.city,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    final ticketId = schedule.ticketId;

    // Was `AppCard.pressable(onTap: () {})` — a card that rippled under the thumb and went
    // nowhere. A scheduled intervento opens its ticket where it has one; where it has none there
    // is nothing to open, so it renders as a plain cell and does not invite the tap at all.
    return AppCard(
      onTap: ticketId != null ? () => context.push(AppRoutes.ticketDetailPath(ticketId)) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  schedule.title.isNotEmpty ? schedule.title : 'Intervento',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: context.colors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // On today's list the date is the same on every row, so it says nothing and the
              // time — the thing that orders the day — gets the weight instead.
              if (showDate)
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                  ),
                ),
              Text(
                timeLabel,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: showDate ? 11 : 15,
                  fontWeight: showDate ? FontWeight.w400 : FontWeight.w700,
                  color: showDate ? context.colors.inkMuted : context.colors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _minutesToTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
