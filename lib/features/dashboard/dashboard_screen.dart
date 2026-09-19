import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
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
/// Running clocks, then the work queue (five named tiers, see WorkQueueSection), then the
/// quick-action row: two things worth starting from here, plus "Le mie timbrature" — a view, not
/// a start action, grouped in anyway as the personal-Timbra home now that its bottom-nav tab is
/// gone. The stat grid that used to sit above all of it is gone — see the Oggi section.
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
        // performSync() itself never throws — SyncNotifier catches internally and parks the
        // failure in SyncState.status/errorMessage (see sync_service.dart) — so a pull-to-refresh
        // that hit a real failure used to just stop spinning with zero feedback, the technician
        // left to guess whether it actually synced. Same showAppToast/ToastTone.error convention
        // this screen's own _ClockInPrompt already uses for a failed punch below, and
        // ai_draft_action.dart's AI-generation errors use the same way.
        onRefresh: () async {
          await ref.read(syncProvider.notifier).performSync();
          if (!context.mounted) return;
          if (ref.read(syncProvider).status == SyncStatus.error) {
            showAppToast(
              context,
              message: 'Aggiornamento non riuscito. Riprova.',
              tone: ToastTone.error,
            );
          }
        },
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
                //
                // The idle → active swap used to be a raw ternary: two different widget types in
                // the same slot, so Flutter unmounts one and mounts the other on the very next
                // frame — the one moment on this screen where a technician's own tap visibly
                // changes the world (they just started their day) read as a silent pop instead of
                // a transition. A crossfade gives that moment the beat it earns without touching
                // layout height mid-scroll (no SizeTransition — this sits inside a CustomScrollView
                // and a collapsing/growing sliver is its own jank, not a fix for one). A
                // MediaQuery.disableAnimations check collapses it to an instant cut, matching
                // TimbraScreen's own reduced-motion handling for its pulse.
                child: AnimatedSwitcher(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: trackers.isEmpty
                      ? const _ClockInPrompt(key: ValueKey('idle'))
                      : ActiveTrackerStrip(key: const ValueKey('active'), trackers: trackers),
                ),
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
            // Below the work, not above it. "Nuovo ticket" and "Timbra cantiere" are the two
            // things a technician *starts* from here; "Rapportini" and "Magazzino" were also here
            // and are places to *go*, which the Altro tab already is. A shortcut to a screen one
            // tap away is not a shortcut.
            //
            // "Le mie timbrature" is a third tile alongside them, but it's a *view*, not a start
            // action — it's grouped here because it's the personal-Timbra home now that the
            // Timbra bottom-nav tab is gone (AppRoutes.timbra is a standalone pushed route), not
            // because it fits this section's "starts from here" framing exactly.
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
                        // No cantiere context from here — the generic dashboard entry point, as
                        // opposed to CantiereDetailScreen's own "Timbra cantiere" button, which
                        // already knows which cantiere and goes straight to CantiereTimbraScreen.
                        // Lands on the picker; it resolves a cantiereId and hands off from there.
                        onTap: () => context.push(AppRoutes.selezionaCantiere),
                      ),
                    ),
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.timer,
                        label: 'Le mie\ntimbrature',
                        onTap: () => context.push(AppRoutes.timbra),
                      ),
                    ),
                    Expanded(
                      child: QuickAction(
                        icon: LucideIcons.scanLine,
                        label: 'Timbra\ncon QR',
                        // Same destination as TimbraScreen's own header action — there's no
                        // Timbra bottom-nav tab, so this was previously two taps deep (Dashboard →
                        // Timbra → QR) for what's meant to be the fast path when arriving at a
                        // kiosk totem. TimbraScreen keeps its own copy of this action too; nothing
                        // else about that screen changes.
                        onTap: () => context.push(AppRoutes.timbraQr),
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

/// The idle hero's one action — punch in, right from Home. Reuses [punchNotifierProvider] rather
/// than pushing to the Timbra tab: this screen already knows nothing is running, so a second
/// navigation just to reach the same "ingresso" event this button can fire directly would be a
/// tap this screen exists to save.
class _ClockInPrompt extends ConsumerWidget {
  const _ClockInPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final punchState = ref.watch(punchNotifierProvider);
    final busy = punchState.isLoading;

    // A punch fired from here used to hand back control with nothing but the hero swapping
    // shape — the one confirmation TimbraScreen's own inline error text gives a failed punch, a
    // successful one from Home gave none at all. Same success-toast convention
    // new_ticket_form_screen.dart already uses (context.colors.green), so this reads as the same
    // "it worked" language the rest of the app already speaks, not a new one invented here.
    ref.listen<AsyncValue<void>>(punchNotifierProvider, (previous, next) {
      if (previous is AsyncLoading && next is AsyncData && !next.hasError) {
        showAppToast(context, message: 'Turno iniziato', tone: ToastTone.success);
      } else if (next is AsyncError) {
        // The success branch above got a toast; a failed punch fired from here gave zero
        // feedback — the hero just silently stopped loading. Same toast text/mechanism
        // TimbraScreen's own punch failure already uses (timbra_screen.dart), so a failure
        // reads the same whether it started from Home or from the Timbra tab.
        showAppToast(
          context,
          message: 'Errore durante la timbratura. Riprova.',
          tone: ToastTone.error,
        );
      }
    });

    // A CTA, not a passive readout — flat AppColors.Y fill + white ink, same primary-action
    // language AppButton's own primary variant already uses (this replaces the old VetroGlass
    // panel, which only read as an action via its own onTap; AppCard's onTap does that job here
    // instead of a hand-rolled Material/InkWell). AppColors.Y as a raw constant is the sanctioned
    // exception (see the batch's own colour rule) — it's this app's one theme-invariant accent.
    return AppCard(
      padding: EdgeInsets.zero,
      backgroundColor: AppColors.Y,
      onTap: busy
          ? null
          : () => ref.read(punchNotifierProvider.notifier).punch(ref.read(timbraStateProvider)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
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
                fontFamily: 'Archivo',
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
    );
  }
}
