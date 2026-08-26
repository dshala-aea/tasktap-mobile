import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/vetro_glass.dart';
import '../../core/widgets/widgets.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/auth_providers.dart';
import '../altro/notifiche_provider.dart';
import '../timbra/timbra_providers.dart';
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
    final unreadNotifiche = ref.watch(notificheUnreadCountProvider);

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
                    showDot: unreadNotifiche > 0,
                    onTap: () => context.push(AppRoutes.altroNotifiche),
                  ),
                  HeaderIconBtn(
                    icon: LucideIcons.user,
                    label: 'Profilo',
                    glass: true,
                    onTap: () => context.push(AppRoutes.altroProfilo),
                  ),
                ],
                // What is actually running — or, idle, the one thing to do about that.
                //
                // Used to draw nothing at all when idle, on the reasoning that an inert "Non hai
                // interventi attivi al momento" panel carries no information the empty space
                // doesn't already say. That reasoning holds for a passive status message; it
                // doesn't for a real action. Idle is most of the morning, and "punch in" is the
                // one thing a technician actually does from here before anything else is
                // possible — leaving that as a second tap into the Timbra tab, on the one screen
                // that already knows nothing is running, was the actual gap (the Vetro mockup's
                // own "Home — idle" screen calls this out directly).
                child: trackers.isEmpty
                    ? const _ClockInPrompt()
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

/// The idle hero's one action — punch in, right from Home. Reuses [punchNotifierProvider] rather
/// than pushing to the Timbra tab: this screen already knows nothing is running, so a second
/// navigation just to reach the same "ingresso" event this button can fire directly would be a
/// tap this screen exists to save.
class _ClockInPrompt extends ConsumerWidget {
  const _ClockInPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final punchState = ref.watch(punchNotifierProvider);
    final busy = punchState.isLoading;

    return VetroGlass(
      fill: AppVetroColors.glassFillOnDark,
      border: AppVetroColors.glassBorderOnDark,
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy
              ? null
              : () => ref
                    .read(punchNotifierProvider.notifier)
                    .punch(ref.read(timbraStateProvider)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 14),
            child: Row(
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.WHITE),
                  )
                else
                  const Icon(LucideIcons.clock, size: 18, color: AppColors.WHITE),
                const SizedBox(width: 10),
                const Text(
                  'Timbra ingresso',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.WHITE,
                  ),
                ),
                const Spacer(),
                Icon(LucideIcons.chevronRight, size: 16, color: AppColors.WHITE.withAlpha(179)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

