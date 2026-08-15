import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// Dashboard screen — Hero + active job(s) + stats + quick actions + upcoming.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.displayName ?? user?.email ?? 'Tecnico';
    final stats = ref.watch(dashboardStatsProvider);
    final trackers = ref.watch(visibleTrackersProvider);
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

            // ── Stats 2×2 ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 16, 19, 0),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: StatsGrid(
                    items: [
                      StatItem(label: 'Interventi\noggi', value: stats.todayCount.toString()),
                      StatItem(label: 'In corso', value: stats.inProgressCount.toString()),
                      StatItem(label: 'Completati', value: stats.completedCount.toString()),
                      StatItem(label: 'Prossimi', value: stats.upcomingCount.toString()),
                    ],
                  ),
                ),
              ),
            ),

            // ── Quick Actions ─────────────────────────────────────────────────
            //
            // All four were decorative: `QuickAction` has an `onTap` and not one of them passed it,
            // so the dashboard drew four yellow discs that answered nothing. "Nuova pianificazione"
            // is also gone — mobile has no create-schedule route to send it to, and a control whose
            // only honest destination is a placeholder should not be on the first screen. It is
            // replaced by the cantiere clock-in, which is a thing a technician actually starts from
            // here and which does have a route.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 10, 19, 0),
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
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.fileText,
                        label: 'Rapportini',
                        onTap: () => context.push(AppRoutes.altroRapportini),
                      ),
                    ),
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.package,
                        label: 'Magazzino',
                        onTap: () => context.push(AppRoutes.altroMagazzino),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Prossimi interventi ───────────────────────────────────────────
            const SliverToBoxAdapter(child: SectionTitle(title: 'Prossimi interventi')),

            upcomingAsync.when(
              data: (schedules) => schedules.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 19),
                        child: EmptyState(
                          icon: LucideIcons.calendarOff,
                          title: 'Nessun intervento in programma',
                          body: 'I prossimi interventi appariranno qui dopo la sincronizzazione.',
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Padding(
                          padding: EdgeInsets.fromLTRB(19, i == 0 ? 0 : 8, 19, 8),
                          child: _UpcomingItem(schedule: schedules[i]),
                        ),
                        childCount: schedules.length,
                      ),
                    ),
              loading: () => const SliverToBoxAdapter(
                child: Center(
                  child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
                ),
              ),
              error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Bottom padding so the last card clears the floating bottom nav.
            SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
          ],
        ),
      ),
    );
  }
}

// ── No active job empty state (inside hero) ────────────────────────────────────

// ── Hero loading ───────────────────────────────────────────────────────────────

class _UpcomingItem extends ConsumerWidget {
  const _UpcomingItem({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationByIdProvider(schedule.locationId)).valueOrNull;
    final customerName = location != null
        ? ref.watch(customerByIdProvider(location.customerId)).valueOrNull?.companyName
        : null;

    final dateLabel = DateFormat('EEE d MMM', 'it').format(schedule.activityDate.toLocal());
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
                  style: GoogleFonts.manrope(
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
                    style: GoogleFonts.manrope(fontSize: 12, color: context.colors.inkMuted),
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
              Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colors.ink,
                ),
              ),
              Text(
                timeLabel,
                style: GoogleFonts.manrope(fontSize: 11, color: context.colors.inkMuted),
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
