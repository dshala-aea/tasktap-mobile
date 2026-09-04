// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/row_icon_tile.dart';
import '../../data/local/app_database.dart';
import '../dashboard/active_trackers_provider.dart' show nowProvider;
import 'timbra_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TimbraScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Clock-in / clock-out screen.
///
///   - (2026-08-26 redesign, module #1; hero restructured 2026-08-30, "Status-First Hero"; chrome
///     removed 2026-08-30, "Hybrid Card Hero"; hero card dropped entirely 2026-08-30, full flip;
///     flat Documento material, no more gradients, 2026-09-04 — see below.)
///   - The screen used to be permanently dark, top to bottom, with its own fixed `ScreenHeader`
///     plate. A first pass narrowed that to one dark "hero card" wrapping just the punch control
///     (the sun-glare argument for a dark, high-contrast surface was real — see the git history on
///     this file). That card didn't land: on a real device it read as a second, disconnected
///     surface rather than part of the page, and its fixed 156dp circular button and generous
///     internal padding left the top of a tall phone looking sparse against a big session-list gap
///     below it. This pass drops the card: every surface on this page, including the punch/pause
///     controls, now reads `context.colors`/`context.vetro` and flips with the app theme like
///     every other screen. The sun-glare property is kept differently — the punch/pause buttons
///     are still a saturated flat fill with white text/icon, which stays legible regardless of
///     the surrounding theme, without needing a dedicated dark ground under them.
///   - `ScreenHeader` is gone. The title and date are plain inline text at the top of the page.
///   - Punch/pause are now full-width rounded-rect buttons, not a floating disc/small pill — more
///     touch target, no wasted side margins, and closer in shape to `AppButton`'s own full-width
///     convention used everywhere else in the app.
///   - "Invia ore" (day-level submit-for-approval) removed entirely — the approval workflow it
///     fed had no real consumer (payroll already reads a raw Excel export, ignoring approval
///     status; the office edits/deletes hours directly). Removed from mobile only for now; the
///     backend/web-frontend side of the same workflow is a tracked follow-up, not done here.
///   - Punch failures used to render as inline red text under the button — now routed through
///     [showAppToast], the same shared feedback surface every other screen in the app uses, so
///     the layout doesn't shift to make room for an error line.
///   - The punch button gets a brief `AnimatedScale` press-down instead of an ink splash (a splash
///     over a saturated fill read as a smudge, not a press — still true, still avoided), and its
///     fill/state crossfades on tap instead of snapping; the status badge crossfades on state
///     change; the guard banner animates its own height in/out instead of popping.
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

    _updatePulse(shiftState.isOnShift);

    // A failed punch used to render as red text wedged under the button, shifting everything
    // below it. Routed through the shared toast instead, same as every other transient-feedback
    // site in the app now.
    ref.listen<AsyncValue<void>>(punchNotifierProvider, (previous, next) {
      if (next is AsyncError) {
        showAppToast(context, message: 'Errore durante la timbratura. Riprova.', tone: ToastTone.error);
      }
    });

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Padding(
          // pagePadding (19), the same horizontal grid every rack screen in the app reads its
          // rail from — this screen no longer has a ScreenHeader drawing that line for it.
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.lg,
            AppSpacing.pagePadding,
            context.navClearance,
          ),
          // Fixed when there is room, scrolling when there is not — see _kFixedLayoutMinHeight.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fits = constraints.maxHeight >= _kFixedLayoutMinHeight;
              final punchGuard = ref.watch(punchGuardProvider);
              final reducedMotion = MediaQuery.disableAnimationsOf(context);

              final content = <Widget>[
                const _ScreenTitle(),
                const SizedBox(height: 28),
                _HeroStatus(shiftState: shiftState, total: total, pulseAnim: _pulseAnim),
                const SizedBox(height: 24),
                // The blocked reason used to be conditionally inserted into the Column outright —
                // an abrupt pop. AnimatedSize gives it a height transition in/out instead, without
                // needing to know its own content's height up front.
                AnimatedSize(
                  duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  curve: Curves.easeInOut,
                  child: punchGuard.blocked && punchGuard.reason != null
                      ? Column(
                          children: [
                            _GuardBanner(reason: punchGuard.reason!),
                            const SizedBox(height: 16),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                _PunchButton(
                  shiftState: shiftState,
                  isLoading: punchState is AsyncLoading,
                  guard: punchGuard,
                  onTap: () {
                    ref.read(punchNotifierProvider.notifier).punch(shiftState);
                  },
                ),
                if (shiftState.isOnShift) ...[
                  const SizedBox(height: 14),
                  _PauseButton(
                    shiftState: shiftState,
                    isLoading: punchState is AsyncLoading,
                    guard: ref.watch(pauseGuardProvider),
                    onTap: () {
                      ref.read(punchNotifierProvider.notifier).togglePause(shiftState);
                    },
                  ),
                ],
                const SizedBox(height: 28),
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
    );
  }
}

/// Below this the controls alone would leave the session list unreadable, so the page scrolls.
const double _kFixedLayoutMinHeight = 640;

// ══════════════════════════════════════════════════════════════════════════════
// Shared duration formatting
// ══════════════════════════════════════════════════════════════════════════════

String _formatHoursMinutes(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${h}h ${m}m';
}

String _formatHoursMinutesSeconds(Duration d) {
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${_formatHoursMinutes(d)} ${s}s';
}

// ══════════════════════════════════════════════════════════════════════════════
// _ScreenTitle
// ══════════════════════════════════════════════════════════════════════════════

/// Replaces the old fixed-dark `ScreenHeader` — plain inline title + date, on the same flipping
/// ground as the rest of the page. No back chevron (root tab) and no actions (nothing here is a
/// notification or a profile setting).
class _ScreenTitle extends StatelessWidget {
  const _ScreenTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Timbra',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.colors.ink,
          ),
        ),
        const SizedBox(height: 4),
        const _DateLabel(),
      ],
    );
  }
}

class _DateLabel extends StatelessWidget {
  const _DateLabel();

  @override
  Widget build(BuildContext context) {
    // The calendar date, not the clock — this never needs the per-second tick _SmallClock does,
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
        color: context.colors.inkMuted,
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _HeroStatus  — state badge + elapsed time + small live clock
// ══════════════════════════════════════════════════════════════════════════════

/// What the technician actually glances at this screen to answer: not "what time is it" (the
/// status bar already says that), but "am I clocked in, and for how long." That question is the
/// hero — a state badge and the elapsed-today reading, both far larger than the clock, which sits
/// underneath as a small secondary readout.
///
/// [total] is [totalWorkedTodayProvider] — the same "worked so far today" value [_TotalRow] has
/// always shown, not a new computation. It only recomputes on a data change (a punch, pause, or
/// resume) — it does not tick live, and does not need to: a number that changes at most a few
/// times an hour does not need to visibly age in real time.
class _HeroStatus extends StatelessWidget {
  const _HeroStatus({required this.shiftState, required this.total, required this.pulseAnim});

  final TimbraState shiftState;
  final Duration total;
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final (String label, Color color, Color? bg) = switch (shiftState) {
      TimbraState(isOnShift: true, isOnPause: true) => ('IN PAUSA', v.statusWarn, v.statusWarnBg),
      TimbraState(isOnShift: true) => ('IN TURNO', v.statusGood, v.statusGoodBg),
      // Not on shift: no saturated colour — Vetro reserves that for something active, and
      // nothing is active right now. Same inkMuted the rest of this screen's quiet text uses.
      _ => ('FUORI TURNO', context.colors.inkMuted, null),
    };

    return Column(
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: Semantics(
            key: ValueKey(label),
            label: 'Stato: $label',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The pulse moves here — a small dot is a truer "this is live" cue than
                  // pulsing an eight-digit number, and it sits directly next to the state it is
                  // confirming rather than next to the time of day.
                  ScaleTransition(
                    scale: pulseAnim,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatHoursMinutes(total),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: AppColors.Y,
              letterSpacing: -1.5,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 10),
        const _SmallClock(),
      ],
    );
  }
}

/// Small secondary clock under [_HeroStatus]'s elapsed reading — the confirm-the-phone's-right
/// glance at the weight that question actually needs now that "am I clocked in" is the hero. The
/// one per-second-ticking widget on this screen — only this rebuilds on the tick, not the whole
/// card or page.
class _SmallClock extends ConsumerWidget {
  const _SmallClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).valueOrNull?.toLocal() ?? DateTime.now();
    final timeStr = DateFormat('HH:mm:ss').format(now);
    return Semantics(
      label: 'Ora corrente $timeStr',
      liveRegion: true,
      child: Text(
        timeStr,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: context.colors.inkMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _GuardBanner
// ══════════════════════════════════════════════════════════════════════════════

/// Full-width, seen-before-the-tap treatment for a punch refusal the device already knows about
/// (closed payroll period, a shift another device opened). Reuses `context.vetro.statusWarn`/
/// `statusWarnBg` — the same "needs attention" pair [_HeroStatus] uses for "IN PAUSA", not a
/// fresh colour invented for this one banner.
class _GuardBanner extends StatelessWidget {
  const _GuardBanner({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: v.statusWarnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: v.statusWarn.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 15, color: v.statusWarn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, height: 1.35, color: v.statusWarn),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PunchButton
// ══════════════════════════════════════════════════════════════════════════════

class _PunchButton extends StatefulWidget {
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
  /// device opened. The reason text itself is not rendered here — the parent promotes it to
  /// [_GuardBanner], above the button, before the tap is even attempted; this only governs the
  /// dimmed/inert visuals.
  final TimbraGuard guard;

  @override
  State<_PunchButton> createState() => _PunchButtonState();
}

class _PunchButtonState extends State<_PunchButton> {
  // Drives a brief AnimatedScale press-down — see this class's own historical note on why the
  // button has no InkWell splash instead.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isOnShift = widget.shiftState.isOnShift;
    final label = isOnShift ? 'FINE TURNO' : 'INIZIA TURNO';
    final icon = isOnShift ? LucideIcons.square : LucideIcons.play;
    final blocked = widget.guard.blocked;
    final enabled = !widget.isLoading && !blocked;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    // Flat fill (no gradient — DESIGN.md's flat Documento material has none), checked against a
    // simulated direct-sunlight wash before being kept — reads clearly against either app theme
    // on its own, without needing a dedicated dark ground under it. AppColors.Y for "starting",
    // the same theme-invariant brand-accent exception every other primary fill in the app reads;
    // AppColors.stopDark for "ending" — not a flipping `context.colors.red`/`redSoft` pair,
    // because the white icon/text on top of this fill has to stay legible under BOTH themes, and
    // those two tokens are tuned to flip (`redSoft` goes near-white in light mode, `red` goes a
    // light salmon in dark mode — either one under fixed white text fails contrast in one theme
    // or the other). `stopDark` alone clears >7:1 against white regardless of theme, which is the
    // same "does not flip, does not belong in AppPalette" reasoning `AppColors`'s own "Punch
    // clock (theme-invariant)" section already documents this pair for.
    final fillColor = isOnShift ? AppColors.stopDark : AppColors.Y;

    // Dimmed and inert rather than hidden: a button that disappears leaves the user with no
    // idea what happened, and the reason is shown above via _GuardBanner.
    return Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && widget.guard.reason != null ? '$label — ${widget.guard.reason}' : label,
      // The press target deliberately has no splash. It is a full-width saturated fill with a
      // coloured glow; ink over that reads as a smudge rather than a press, and the control
      // already answers a tap within the frame by swapping to a spinner. AnimatedScale gives it
      // a tactile press-down instead, with no smudge risk. The secondary pause button below it
      // did get a real splash, because it is flat and its own state change is a small icon swap.
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.isLoading || blocked ? null : widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: blocked ? 0.4 : 1,
            child: AnimatedContainer(
              duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
              width: double.infinity,
              // 76 — full-width rounded rect instead of a floating disc: more touch target, no
              // wasted side margins, and closer to AppButton's own full-width shape.
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: fillColor,
                boxShadow: [
                  BoxShadow(
                    color: fillColor.withAlpha(110),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: AppColors.WHITE, strokeWidth: 3),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // White on both fills — both AppColors.Y and stopDark are dark/saturated
                        // enough that white reads clearly on either.
                        Icon(icon, size: 24, color: AppColors.WHITE),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.WHITE,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
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
/// Full-width to match [_PunchButton]'s shape, not the pill shape this used when it floated as a
/// small centered chip. `AppCard`'s own default fill/border already flip with the app theme like
/// the rest of the page now that this screen isn't a fixed-dark ground anymore — same
/// `context.colors.surface`/`borderLight` pair `VetroGlass`'s own defaults used to read here.
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
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: AppCard(
            onTap: isLoading || blocked ? null : onTap,
            padding: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                else
                  Icon(icon, size: 18, color: accent),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
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
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.inkMuted),
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
      // A normal flipping AppCard now — the frame around the dark hero reads as the rest of
      // the app, not a permanently-dark plate matching a header that no longer exists.
      child: AppCard(
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
                    color: context.colors.inkMuted,
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
            if (sessions.isNotEmpty) Divider(color: context.colors.divider, height: 24),

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
          style: TextStyle(color: context.colors.inkMuted, fontSize: 13, fontFamily: 'Inter'),
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
        return context.colors.inkMuted;
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
          // Tinted at low alpha with the row's own event colour — the same "icon-coloured tile"
          // pattern every other list row in the app uses, rather than one flat fill for every
          // event type regardless of what it means.
          RowIconTile(
            size: 32,
            color: color.withAlpha(26),
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
                color: context.colors.ink.withAlpha(220),
              ),
            ),
          ),
          Text(
            timeStr,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
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
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _formatHoursMinutesSeconds(total),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.Y,
          ),
        ),
      ],
    );
  }
}
