import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/worklogs/active_tracker_api_client.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
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

    final inProgressAsync = ref.watch(inProgressSchedulesProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final upcomingAsync = ref.watch(upcomingSchedulesProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: Rack(
        child: RefreshIndicator(
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
                  // What is running right now, from GET /api/worklog/active, in preference to what
                  // the calendar says should be. A schedule marked in-progress is an intention; a
                  // running tracker is the clock somebody is being paid against, and the two disagree
                  // whenever a technician starts late, stays on, or is somewhere else entirely.
                  child: ref
                      .watch(activeTrackersProvider)
                      .when(
                        data: (trackers) => trackers.isEmpty
                            ? inProgressAsync.when(
                                data: (jobs) => jobs.isEmpty
                                    ? const _NoActiveJobGlass()
                                    : _ActiveJobSection(jobs: jobs),
                                loading: () => const _HeroLoadingIndicator(),
                                error: (err, stack) => const _NoActiveJobGlass(),
                              )
                            : _ActiveTrackersSection(trackers: trackers),
                        loading: () => const _HeroLoadingIndicator(),
                        // The endpoint being unreachable is not evidence that nothing is running, so
                        // fall back to the calendar rather than claiming the day is idle.
                        error: (err, stack) => inProgressAsync.when(
                          data: (jobs) => jobs.isEmpty
                              ? const _NoActiveJobGlass()
                              : _ActiveJobSection(jobs: jobs),
                          loading: () => const _HeroLoadingIndicator(),
                          error: (e, st) => const _NoActiveJobGlass(),
                        ),
                      ),
                ),
              ),

              // ── Stats 2×2 ─────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(19, 20, 19, 0),
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
      ),
    );
  }
}

// ── No active job empty state (inside hero) ────────────────────────────────────

class _NoActiveJobGlass extends StatelessWidget {
  const _NoActiveJobGlass();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: EmptyState(
        icon: LucideIcons.briefcase,
        title: 'Nessuna attività in corso',
        body: 'Non hai interventi attivi al momento.',
        action: AppButton(
          label: 'Cerca ticket aperti',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.dark,
          // Was `onPressed: null`, which renders a disabled button inside an empty state whose
          // whole job is to offer the way out of it.
          onPressed: () => context.push(AppRoutes.ticket),
        ),
      ),
    );
  }
}

// ── Hero loading ───────────────────────────────────────────────────────────────

class _HeroLoadingIndicator extends StatelessWidget {
  const _HeroLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(color: AppColors.WHITE),
      ),
    );
  }
}

// ── Active job section (shows the first in-progress job) ──────────────────────

class _ActiveJobSection extends ConsumerWidget {
  const _ActiveJobSection({required this.jobs});

  final List<Schedule> jobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show the first in-progress job; timer is static for now (live timer in P3).
    final job = jobs.first;
    final location = ref.watch(locationByIdProvider(job.locationId)).valueOrNull;
    final customerName = location != null
        ? ref.watch(customerByIdProvider(location.customerId)).valueOrNull?.companyName
        : null;

    return ActiveJobCard(
      stato: 'In corso',
      title: job.title.isNotEmpty ? job.title : 'Intervento',
      client: customerName,
      // Null, not '00:00:00'. This branch is the *calendar's* opinion that a job is in progress;
      // no clock is running behind it, and drawing a zeroed timer told the technician one was.
      elapsed: null,
      onOpen: job.ticketId != null
          ? () => context.push(AppRoutes.ticketDetailPath(job.ticketId!))
          : null,
    );
  }
}

// ── Running timers ─────────────────────────────────────────────────────────────

/// Every tracker that is running, one card each.
///
/// A list, not a value: attendance, cantiere and ticket time are three independent clocks and all
/// three can run at once — clocked in, on a site, with a ticket open. Showing one would hide the
/// other two, and the hidden one is the one that gets left running overnight.
class _ActiveTrackersSection extends ConsumerWidget {
  const _ActiveTrackersSection({required this.trackers});

  final List<ActiveTracker> trackers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One clock for the whole section, ticking each second. Until it produces its first value the
    // cards still show a correct elapsed time — computed from the device clock, not from nothing.
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < trackers.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          ActiveJobCard(
            stato: _statoFor(trackers[i].kind),
            title: trackers[i].label ?? _titleFor(trackers[i].kind),
            client: null,
            elapsed: formatElapsed(trackers[i].elapsedAt(now)),
            onOpen: null,
          ),
        ],
      ],
    );
  }

  static String _statoFor(ActiveTrackerKind kind) => switch (kind) {
    ActiveTrackerKind.attendance => 'Timbrato',
    ActiveTrackerKind.cantiere => 'In cantiere',
    ActiveTrackerKind.ticket => 'In corso',
  };

  /// Attendance is against the day rather than a thing, so the kind is the only honest title.
  static String _titleFor(ActiveTrackerKind kind) => switch (kind) {
    ActiveTrackerKind.attendance => 'Giornata di lavoro',
    ActiveTrackerKind.cantiere => 'Cantiere',
    ActiveTrackerKind.ticket => 'Intervento',
  };
}

// ── Upcoming intervento card ───────────────────────────────────────────────────

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
