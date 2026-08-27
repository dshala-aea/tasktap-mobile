// dart format width=100
import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/row_icon_tile.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/vetro_glass.dart';
import '../../data/local/app_database.dart';
import '../dashboard/active_trackers_provider.dart' show nowProvider;
import 'timbra_providers.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TimbraScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Dark clock-in / clock-out screen — Vetro (2026-08-26 redesign, module #1).
///
/// Layout unchanged from the Cassetta version; materials are not:
///   - `ScreenHeader(dark: true)` — "Timbra", no back (root tab), no actions (nothing on this
///     screen is a notification or a profile setting, so none are offered). Not yet re-themed —
///     shared across every screen, so it stays Cassetta until whichever module owns app chrome
///     takes its turn; this file only owns what's below it.
///   - Date label (uppercase, Inter 13 muted)
///   - Live clock (Inter 72 **w800**, tint colour, ticking every second)
///   - Circular punch button — gradient fill (tint→tintStrong starting, stop→stopDark ending),
///     soft shadow, still no [InkWell] splash (see [_PunchButton]'s own doc comment for why)
///   - Pause/resume pill — now [VetroGlass] (blurred), was a flat [AppTappable] pill
///   - "Sessioni di oggi" card — now [VetroGlass], was a solid CHARCOAL panel
///
/// Gradient + blur was a real question here, not a given: this screen is documented as read at
/// arm's length in direct sun, which is the one condition glass/blur genuinely degrades under.
/// Resolved with a side-by-side glare simulation (flat-fill vs. gradient+glass, both under a
/// simulated sunlight wash) — gradient/glass was kept anyway, deliberately, not by default.
class TimbraScreen extends ConsumerStatefulWidget {
  const TimbraScreen({super.key});

  @override
  ConsumerState<TimbraScreen> createState() => _TimbraScreenState();
}

class _TimbraScreenState extends ConsumerState<TimbraScreen> with TickerProviderStateMixin {
  // Pulse animation for the clock dot while on shift.
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _updatePulse(bool isOnShift) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    if (isOnShift && !reducedMotion) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(timbraStateProvider);
    final sessionsAsync = ref.watch(todaySessionsProvider);
    final punchState = ref.watch(punchNotifierProvider);
    final total = ref.watch(totalWorkedTodayProvider);
    // Only shown when the server actually offers it (see submitGuardProvider's own doc comment
    // for why "server unreachable" cannot mean "show it anyway" the way it does for punch/pause).
    final submitAction = ref.watch(giornataProvider).valueOrNull?.action('Submit');
    final submitState = ref.watch(submitDayNotifierProvider);

    _updatePulse(shiftState.isOnShift);

    return Scaffold(
      backgroundColor: AppColors.punchGround,
      // The screen had zero top framing — the dark Column ran straight from the status bar into
      // the date label, the one root tab with no anchor at all. `ScreenHeader` is the same
      // primitive every other screen hangs its top edge on; its `dark` variant already exists for
      // exactly a fixed-dark ground (see `new_ticket_form_screen.dart`), so this is adoption, not
      // invention. No back chevron — root tab — and no bell/profile actions bolted on: nothing on
      // this screen is notifications or account settings, and a control with no honest
      // destination is worse than no control (see the dashboard's former `onTap: () {}` pair).
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Timbra', dark: true),
            Expanded(
              // The whole screen used to be one SingleChildScrollView, so the punch button — the
              // only reason to open this screen — could be scrolled off it, and on a small phone
              // it started that way: roughly 500dp of clock and gaps sat above the session list
              // before anything scrolled. A clock-in control you have to go looking for is the
              // wrong control.
              //
              // The controls are fixed now and only the list of today's sessions scrolls, inside
              // its own box. Gaps came down with it — 40dp twice, and a 180dp disc, on a surface
              // that has to fit an iPhone SE.
              child: Padding(
                // pagePadding (19), not a bespoke 24: this is the same horizontal grid the header
                // above just drew a line across, and the one every rack screen in the app reads
                // its rail from.
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.lg,
                  AppSpacing.pagePadding,
                  context.navClearance,
                ),
                // Fixed when there is room, scrolling when there is not.
                //
                // The screen was one SingleChildScrollView, so the punch button — the only reason
                // to open it — could be scrolled off, and on a small phone it started that way.
                // Pinning everything instead is the other failure: the controls take about 400dp,
                // so on a 600dp viewport the session list is squeezed to a few pixels and shows
                // nothing.
                //
                // So: measure. Above the threshold the controls hold still and only the sessions
                // move, which is what a technician glancing at the screen needs. Below it the
                // page scrolls as a whole, because a crushed list is worse than a scroll.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fits = constraints.maxHeight >= _kFixedLayoutMinHeight;
                    final content = <Widget>[
                      const _DateLabel(),
                      const SizedBox(height: 6),
                      _LiveClock(pulseAnim: _pulseAnim),
                      const SizedBox(height: 28),
                      _PunchButton(
                        shiftState: shiftState,
                        isLoading: punchState is AsyncLoading,
                        guard: ref.watch(punchGuardProvider),
                        onTap: () {
                          ref.read(punchNotifierProvider.notifier).punch(shiftState);
                        },
                      ),
                      if (punchState is AsyncError<void>)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            'Errore durante la timbratura. Riprova.',
                            style: TextStyle(color: context.colors.red, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (shiftState.isOnShift) ...[
                        const SizedBox(height: 12),
                        _PauseButton(
                          shiftState: shiftState,
                          isLoading: punchState is AsyncLoading,
                          guard: ref.watch(pauseGuardProvider),
                          onTap: () {
                            ref.read(punchNotifierProvider.notifier).togglePause(shiftState);
                          },
                        ),
                      ],
                      if (submitAction != null) ...[
                        const SizedBox(height: 12),
                        _SubmitButton(
                          isLoading: submitState is AsyncLoading,
                          guard: ref.watch(submitGuardProvider),
                          onTap: () {
                            ref.read(submitDayNotifierProvider.notifier).submit();
                          },
                        ),
                        if (submitState is AsyncError<void>)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Text(
                              'Impossibile inviare le ore. Riprova.',
                              style: TextStyle(color: context.colors.red, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                      const SizedBox(height: 20),
                    ];

                    final sessions = sessionsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => Text(
                        'Errore sessioni: $e',
                        style: TextStyle(color: context.colors.red, fontSize: 12),
                      ),
                      data: (list) => _SessionsCard(
                        sessions: list,
                        total: total,
                        hasPendingSync: ref.watch(hasPendingSyncProvider),
                        fillHeight: fits,
                      ),
                    );

                    if (!fits) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [...content, sessions],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ...content,
                        Expanded(child: sessions),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Below this the controls alone would leave the session list unreadable, so the page scrolls.
const double _kFixedLayoutMinHeight = 640;

/// `RowIconTile`'s fill for [_SessionRow], on this screen only.
///
/// A solid indigo-tinted dark, not a real [VetroGlass] blur: [_SessionsCard] renders one row per
/// session in a `ListView.builder`, and a `BackdropFilter` per row is the "many small blurred
/// instances" cost [VetroGlass]'s own doc comment warns against. This reads as the same glass
/// family at a glance (same hue as [AppVetroColors.tint], same rough alpha [VetroGlass] would
/// produce over `punchGround`) without the per-row backdrop sample.
const Color _kSessionTileFill = Color(0xFF262B45);

// ══════════════════════════════════════════════════════════════════════════════
// _DateLabel
// ══════════════════════════════════════════════════════════════════════════════

class _DateLabel extends StatelessWidget {
  const _DateLabel();

  @override
  Widget build(BuildContext context) {
    // The calendar date, not the clock — this never needs the per-second tick _LiveClock does,
    // so it reads DateTime.now() once per rebuild rather than watching nowProvider.
    final now = DateTime.now();
    // Use locale-neutral format to avoid requiring initializeDateFormatting.
    // Displays as e.g. "LUN 22 GIU 2026"
    final dayNames = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'];
    final monthNames = [
      'GEN',
      'FEB',
      'MAR',
      'APR',
      'MAG',
      'GIU',
      'LUG',
      'AGO',
      'SET',
      'OTT',
      'NOV',
      'DIC',
    ];
    final day = dayNames[now.weekday - 1];
    final month = monthNames[now.month - 1];
    final formatted = '$day ${now.day} $month ${now.year}';
    return Text(
      formatted,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.onDarkMuted,
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _LiveClock
// ══════════════════════════════════════════════════════════════════════════════

class _LiveClock extends ConsumerWidget {
  const _LiveClock({required this.pulseAnim});
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scoped to this one widget, not the whole screen: TimbraScreen used to hold `now` in its
    // own State and `setState` it from a local Timer every second, which reran the entire
    // screen's build() — LayoutBuilder, the sessions list, all of it — to update three digits.
    // nowProvider (shared with the dashboard's ActiveTrackerStrip) ticks once for whoever is
    // listening; only this widget rebuilds now.
    final now = ref.watch(nowProvider).valueOrNull?.toLocal() ?? DateTime.now();
    final timeStr = DateFormat('HH:mm:ss').format(now);
    return Semantics(
      label: 'Ora corrente $timeStr',
      liveRegion: true,
      child: ScaleTransition(
        scale: pulseAnim,
        // Scales down rather than overflowing. At 72px "HH:mm:ss" wants 327dp, which is wider
        // than a 360dp phone once the screen's horizontal gutters are taken off — the clock was
        // overflowing on every common Android width and clipping on the narrow ones. scaleDown
        // never enlarges, so on a normal phone this is exactly the size it was.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            timeStr,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 72,
              // w800, heavier than the w300 this replaced — not a reversal of that rationale, an
              // extension of it: the prior comment's own physics (hairline strokes vanish under
              // sun glare, so w300 not w100) argues for going *further* toward bold once the
              // system's type language is "oversized bold" by design, not against it.
              fontWeight: FontWeight.w800,
              color: AppVetroColors.tint,
              letterSpacing: -2,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PunchButton
// ══════════════════════════════════════════════════════════════════════════════

class _PunchButton extends StatelessWidget {
  const _PunchButton({
    required this.shiftState,
    required this.isLoading,
    required this.onTap,
    this.guard = TimbraGuard.allowed,
  });

  final TimbraState shiftState;
  final bool isLoading;
  final VoidCallback onTap;

  /// A refusal the server already told us about — a closed payroll period, a shift another
  /// device opened. Blocking here turns a rejection the user would otherwise meet after a
  /// silent sync into one they see at the moment of the tap.
  final TimbraGuard guard;

  @override
  Widget build(BuildContext context) {
    final isOnShift = shiftState.isOnShift;
    final label = isOnShift ? 'FINE TURNO' : 'INIZIA TURNO';
    final icon = isOnShift ? LucideIcons.square : LucideIcons.play;
    final blocked = guard.blocked;

    // Gradient fill, not the flat one this replaced (see this class's own historical note above)
    // — checked against a simulated direct-sunlight wash before being kept; the prior flat-fill
    // reasoning was real, it was just weighed against the glass system's own trade-off and the
    // gradient version won on that specific test. Both stops reuse existing colours rather than
    // inventing a Vetro-specific "stop" gradient: [AppColors.stopLight]/[stopDark] were already
    // this exact red family.
    final gradientColors = isOnShift
        ? const [AppColors.stopLight, AppColors.stopDark]
        : const [AppVetroColors.tint, AppVetroColors.tintStrong];

    // Dimmed and inert rather than hidden: a button that disappears leaves the user with no
    // idea what happened, and the reason is printed underneath so it is readable without a
    // long-press or a tooltip this platform would not show anyway.
    final button = Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && guard.reason != null ? '$label — ${guard.reason}' : label,
      // The one press target deliberately left without a splash. It is a 156dp gradient disc
      // with a coloured glow; ink over that reads as a smudge rather than a press, and the
      // control answers a tap within the frame anyway — it swaps to a spinner while the
      // timbratura is recorded. The secondary pause button below it did get converted, because
      // it is flat and its own state change is a small icon swap.
      child: GestureDetector(
        onTap: isLoading || blocked ? null : onTap,
        child: Opacity(
          opacity: blocked ? 0.4 : 1,
          child: Container(
            // 156, down from 180. Still three and a half times the minimum target and the
            // largest thing on the screen after the clock; the extra 24dp was buying nothing and
            // was the difference between the session list being readable on a small phone and
            // being a sliver.
            width: 156,
            height: 156,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradientColors.first.withAlpha(110),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(color: AppColors.WHITE, strokeWidth: 3),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // White on both gradients now — unlike the old flat orange, both tint and
                      // stop are dark/saturated enough that white reads clearly on either, so the
                      // isOnShift-conditional ink colour this used to need goes away.
                      Icon(icon, size: 36, color: AppColors.WHITE),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: AppColors.WHITE,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!blocked || guard.reason == null) return button;

    return Column(
      children: [
        button,
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Text(
            guard.reason!,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.onDarkMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PauseButton
// ══════════════════════════════════════════════════════════════════════════════

/// Small secondary pill button for break start/end, shown only while on shift.
///
/// Deliberately understated next to [_PunchButton]: starting/ending the shift is the
/// primary action, pause/resume is a secondary one that happens mid-shift.
///
/// `borderRadius: 24` (a true pill, not `AppRack.cellRadius`) was checked against the rest of the
/// app for an established pill token: `AppRack` documents rail/cell/inset radii but no pill —
/// the only other fully-rounded control in the app is `step_materiali_fold.dart`'s fold controls,
/// which use this same 24/22 pair. No formal token exists yet, so this stays the documented,
/// still-consistent one-off it already was rather than inventing a new app-wide constant here.
class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.shiftState,
    required this.isLoading,
    required this.onTap,
    this.guard = TimbraGuard.allowed,
  });

  final TimbraState shiftState;
  final bool isLoading;
  final VoidCallback onTap;

  /// Same server-driven refusal as [_PunchButton.guard], applied to StartBreak/EndBreak.
  final TimbraGuard guard;

  @override
  Widget build(BuildContext context) {
    final isOnPause = shiftState.isOnPause;
    final label = isOnPause ? 'RIPRENDI' : 'PAUSA';
    final icon = isOnPause ? LucideIcons.play : LucideIcons.coffee;
    final accent = isOnPause ? context.colors.cyan : context.colors.amber;
    final blocked = guard.blocked;

    final button = Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && guard.reason != null ? '$label — ${guard.reason}' : label,
      child: Opacity(
        opacity: blocked ? 0.4 : 1,
        // VetroGlass paints the blur + tint fill; AppTappable sits inside it purely for the
        // splash (transparent `color`, so it isn't painting a second fill on top of the glass).
        // Fixed on-dark values, not `context.vetro` — this screen doesn't flip, see file header.
        child: VetroGlass(
          borderRadius: BorderRadius.circular(24),
          fill: AppVetroColors.glassFillOnDark,
          border: AppVetroColors.glassBorderOnDark,
          child: AppTappable(
            onTap: isLoading || blocked ? null : onTap,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                else
                  Icon(icon, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  color: accent,
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );

    if (!blocked || guard.reason == null) return button;

    return Column(
      children: [
        button,
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Text(
            guard.reason!,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.onDarkMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SubmitButton
// ══════════════════════════════════════════════════════════════════════════════

/// "Invia le ore" — sends the day's finished hours for approval.
///
/// Same visual weight and guard-driven disabled/reason treatment as [_PauseButton]; shown only
/// when the caller has already confirmed the server offers `Submit` (see the `submitAction` null
/// check at this widget's call site) — a control offering something the server never mentioned
/// would fail on tap for reasons the technician cannot see coming.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isLoading,
    required this.onTap,
    this.guard = TimbraGuard.allowed,
  });

  final bool isLoading;
  final VoidCallback onTap;
  final TimbraGuard guard;

  @override
  Widget build(BuildContext context) {
    const label = 'INVIA ORE';
    final blocked = guard.blocked;
    final accent = context.colors.green;

    final button = Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && guard.reason != null ? '$label — ${guard.reason}' : label,
      child: Opacity(
        opacity: blocked ? 0.4 : 1,
        // Same VetroGlass-wraps-AppTappable composition as _PauseButton — see its comment.
        child: VetroGlass(
          borderRadius: BorderRadius.circular(24),
          fill: AppVetroColors.glassFillOnDark,
          border: AppVetroColors.glassBorderOnDark,
          child: AppTappable(
            onTap: isLoading || blocked ? null : onTap,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                else
                  Icon(LucideIcons.send, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!blocked || guard.reason == null) return button;

    return Column(
      children: [
        button,
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Text(
            guard.reason!,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.onDarkMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SessionsCard  — "Sessioni di oggi"
// ══════════════════════════════════════════════════════════════════════════════

class _SessionsCard extends StatelessWidget {
  const _SessionsCard({
    required this.sessions,
    required this.total,
    required this.hasPendingSync,
    required this.fillHeight,
  });

  final List<WorkSession> sessions;
  final Duration total;
  final bool hasPendingSync;

  /// True when the card was given a bounded box to fill, so its rows scroll inside it. False in
  /// the scrolling fallback, where the card is its natural height and the page moves instead.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      // Now the ~5% white glass the old CHARCOAL panel deliberately wasn't — Vetro's material
      // language is glass everywhere, including a standalone panel like this one; the prior
      // reasoning (match the ScreenHeader plate's case-shell material) doesn't carry over because
      // the header hasn't moved to Vetro yet either (see this file's header comment). Fixed
      // on-dark glass values, not `context.vetro` — same reasoning as [_PauseButton].
      child: VetroGlass(
        borderRadius: AppRack.freeShape,
        fill: AppVetroColors.glassFillOnDark,
        border: AppVetroColors.glassBorderOnDark,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
        // Matches the empty-state Expanded below: a min-sized Column asked to also host a flex
        // child is an unstable combination (its own reported size and the flex child's allocated
        // space can disagree), and `fillHeight` already tells this widget exactly which sizing it
        // was actually given — max when the parent handed it a bounded box to fill, min when it's
        // sitting in a scrolling fallback with unbounded height and must size to its own content.
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title + optional pending-sync indicator
          Row(
            children: [
              Text(
                'SESSIONI DI OGGI',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.onDarkMuted,
                ),
              ),
              if (hasPendingSync) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Non sincronizzato',
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: context.colors.amber, shape: BoxShape.circle),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // The heading and the running total are pinned; only the rows between them move. A
          // long shift with many pauses used to push the day's total off the bottom, which is
          // the one number on this card anybody is looking for.
          if (sessions.isEmpty)
            if (fillHeight) const Expanded(child: _NoSessionsYet()) else const _NoSessionsYet()
          else
            Flexible(
              fit: FlexFit.loose,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: fillHeight
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: sessions.length,
                itemBuilder: (context, i) => _SessionRow(session: sessions[i]),
              ),
            ),
          if (sessions.isNotEmpty)
            const Divider(color: AppVetroColors.glassBorderOnDark, height: 24),

          // Total row
          _TotalRow(total: total),
        ],
        ),
      ),
    );
  }
}

class _NoSessionsYet extends StatelessWidget {
  const _NoSessionsYet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
        child: Text(
          'Nessuna timbratura oggi',
          style: TextStyle(color: AppColors.onDarkMuted, fontSize: 13, fontFamily: 'Inter'),
        ),
      ),
    );
  }
}

// ── _SessionRow ───────────────────────────────────────────────────────────────

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final WorkSession session;

  String _label(String type) {
    switch (type) {
      case 'ingresso':
        return 'Ingresso';
      case 'fine':
        return 'Fine turno';
      case 'pausa':
        return 'Pausa';
      case 'ripresa':
        return 'Ripresa';
      default:
        return type;
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'ingresso':
        return LucideIcons.logIn;
      case 'fine':
        return LucideIcons.logOut;
      case 'pausa':
        return LucideIcons.coffee;
      case 'ripresa':
        return LucideIcons.play;
      default:
        return LucideIcons.clock;
    }
  }

  Color _color(BuildContext context, String type) {
    switch (type) {
      case 'ingresso':
        return context.colors.green;
      case 'fine':
        return context.colors.red;
      case 'pausa':
        return context.colors.amber;
      case 'ripresa':
        return context.colors.cyan;
      default:
        return AppColors.onDarkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(session.eventTime.toLocal());
    final color = _color(context, session.eventType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Every other list row in the app cuts its leading icon into a RowIconTile case-shell
          // square; this was the one bare Icon left. Default CHARCOAL would nearly vanish against
          // this screen's own punchGround (both are near-black), so a lighter blend is used
          // instead — still a fixed value, not a theme-flipping token, per this screen's
          // permanently-dark-surface rule.
          RowIconTile(
            size: 32,
            color: _kSessionTileFill,
            child: Icon(_icon(session.eventType), size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _label(session.eventType),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.WHITE.withAlpha(220),
              ),
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.WHITE,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _TotalRow ─────────────────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.total});
  final Duration total;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    // Two unconstrained Texts in a spaceBetween Row overflowed the card on any narrow phone —
    // 55dp at 320 and still 15dp at 360, the commonest Android width there is. The label yields,
    // because the number is the reason the row exists.
    return Row(
      children: [
        Flexible(
          child: Text(
            'Totale ore',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.WHITE,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _format(total),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppVetroColors.tint,
          ),
        ),
      ],
    );
  }
}
