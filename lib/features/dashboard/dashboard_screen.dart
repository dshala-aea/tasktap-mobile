import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/widgets.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/auth_providers.dart';
import 'active_tracker_strip.dart';
import 'active_trackers_provider.dart';
import 'dashboard_providers.dart';
import 'id_plate_hero_comp.dart';
import 'work_queue_section.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The technician's day, in the order they need it.
///
/// Running clocks, then the work queue (five named tiers, see WorkQueueSection), then the two
/// things worth starting from here. The stat grid that used to sit above all of it is gone — see
/// the Oggi section.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.displayName ?? user?.email ?? 'Tecnico';
    final stats = ref.watch(dashboardStatsProvider);
    final trackers = ref.watch(visibleTrackersProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      // The hero paints over the rail, so the rail starts below it. Without this the world's
      // most load-bearing mark is hidden behind the one panel guaranteed to be on screen.
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).performSync(),
        child: CustomScrollView(
          slivers: [
            // ── Hero ──────────────────────────────────────────────────────────
            // Cantiere safety-signage direction, approved after proving on Dashboard, Ticket
            // detail and the Rapportino wizard. Replaced the old gradient DashboardHero, now
            // dead code (removed along with the ActiveJobCard glass card it alone depended on).
            SliverToBoxAdapter(
              child: IdPlateHeroComp(
                userName: userName,
                todayCount: stats.todayCount,
                completedCount: stats.completedCount,
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
                child: trackers.isEmpty
                    ? null
                    : ActiveTrackerStrip(trackers: trackers),
              ),
            ),

            // ── Coda di lavoro ────────────────────────────────────────────────
            //
            // Was two flat lists — "Oggi" (today, unordered by urgency) then "Prossimi" (the next
            // seven days) — with a 2×2 stat grid above them nobody could act on ("Completati 2").
            // Replaced by five named tiers (Live/Da fare/In attesa/Programmato/Fatto), explainable
            // rather than ranked: a technician can say *why* a job is in Da fare ("nothing else is
            // open yet today"), which an opaque priority score never lets them do. See
            // WorkQueueSection's own doc comment for the fuller reasoning and what this replaced.
            SliverToBoxAdapter(
              child: SectionTitle(
                title: 'Oggi',
                trailing: stats.completedCount > 0
                    ? '${stats.completedCount} di ${stats.todayCount} completati'
                    : null,
              ),
            ),
            const SliverToBoxAdapter(child: WorkQueueSection()),

            // ── Start something ───────────────────────────────────────────────
            //
            // Below the work, not above it. These are the two things a technician *starts* from
            // here; "Rapportini" and "Magazzino" were also here and are places to *go*, which the
            // Altro tab already is. A shortcut to a screen one tap away is not a shortcut.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.lg,
                  AppSpacing.pagePadding,
                  0,
                ),
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
            SliverPadding(
              padding: EdgeInsets.only(bottom: context.navClearance),
            ),
          ],
        ),
      ),
    );
  }
}

