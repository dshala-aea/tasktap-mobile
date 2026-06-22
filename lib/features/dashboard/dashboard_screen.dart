import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'dashboard_providers.dart';

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
      backgroundColor: AppColors.BG2,
      body: CustomScrollView(
        slivers: [
          // ── Hero ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: DashboardHero(
              userName: userName,
              actions: [
                HeaderIconBtn(
                  icon: LucideIcons.bell,
                  glass: true,
                  onTap: () {},
                ),
                HeaderIconBtn(
                  icon: LucideIcons.user,
                  glass: true,
                  onTap: () {},
                ),
              ],
              child: inProgressAsync.when(
                data: (jobs) =>
                    jobs.isEmpty ? const _NoActiveJobGlass() : _ActiveJobSection(jobs: jobs),
                loading: () => const _HeroLoadingIndicator(),
                error: (err, stack) => const _NoActiveJobGlass(),
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
                    StatItem(
                        label: 'Interventi\noggi',
                        value: stats.todayCount.toString()),
                    StatItem(
                        label: 'In corso',
                        value: stats.inProgressCount.toString()),
                    StatItem(
                        label: 'Completati',
                        value: stats.completedCount.toString()),
                    StatItem(
                        label: 'Prossimi',
                        value: stats.upcomingCount.toString()),
                  ],
                ),
              ),
            ),
          ),

          // ── Quick Actions ─────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(19, 20, 19, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: QuickAction(
                      icon: LucideIcons.history,
                      label: 'Storico',
                    ),
                  ),
                  Expanded(
                    child: QuickAction(
                      icon: LucideIcons.calendarPlus,
                      label: 'Nuova\npianificazione',
                    ),
                  ),
                  Expanded(
                    child: QuickAction(
                      icon: LucideIcons.ticket,
                      label: 'Nuovo\nticket',
                    ),
                  ),
                  Expanded(
                    child: QuickAction(
                      icon: LucideIcons.fileText,
                      label: 'Nuovo\nreport',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Prossimi interventi ───────────────────────────────────────────
          const SliverToBoxAdapter(
            child: SectionTitle(title: 'Prossimi interventi'),
          ),

          upcomingAsync.when(
            data: (schedules) => schedules.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 19),
                      child: EmptyState(
                        icon: LucideIcons.calendarOff,
                        title: 'Nessun intervento in programma',
                        body:
                            'I prossimi interventi appariranno qui dopo la sincronizzazione.',
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
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (err, stack) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // Bottom padding so the last card clears the floating bottom nav.
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

// ── No active job empty state (inside hero) ────────────────────────────────────

class _NoActiveJobGlass extends StatelessWidget {
  const _NoActiveJobGlass();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: EmptyState(
        icon: LucideIcons.briefcase,
        title: 'Nessuna attività in corso',
        body: 'Non hai interventi attivi al momento.',
        action: AppButton(
          label: 'Cerca ticket aperti',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.dark,
          onPressed: null,
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
        ? ref
            .watch(customerByIdProvider(location.customerId))
            .valueOrNull
            ?.companyName
        : null;

    return ActiveJobCard(
      stato: 'In corso',
      title: job.title.isNotEmpty ? job.title : 'Intervento',
      client: customerName,
      elapsed: '00:00:00',
      onOpen: null,
    );
  }
}

// ── Upcoming intervento card ───────────────────────────────────────────────────

class _UpcomingItem extends ConsumerWidget {
  const _UpcomingItem({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationByIdProvider(schedule.locationId)).valueOrNull;
    final customerName = location != null
        ? ref
            .watch(customerByIdProvider(location.customerId))
            .valueOrNull
            ?.companyName
        : null;

    final dateLabel =
        DateFormat('EEE d MMM', 'it').format(schedule.activityDate.toLocal());
    final timeLabel = _minutesToTime(schedule.timeStartMinutes);
    final subtitle = [customerName, location?.city]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');

    return AppCard.pressable(
      onTap: () {},
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
                    color: AppColors.DARK,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.MUTED,
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
              Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.DARK,
                ),
              ),
              Text(
                timeLabel,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: AppColors.MUTED,
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
