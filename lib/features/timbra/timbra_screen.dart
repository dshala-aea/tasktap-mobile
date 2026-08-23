// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/screen_header.dart';
import '../../data/local/app_database.dart';
import 'timbra_providers.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TimbraScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Dark clock-in / clock-out screen.
///
/// Layout:
///   - `ScreenHeader(dark: true)` — "Timbra", no back (root tab), no actions (nothing on this
///     screen is a notification or a profile setting, so none are offered)
///   - Date label (uppercase, Manrope 13 muted)
///   - Live clock (Sora 72 thin, yellow, ticking every second)
///   - Circular punch button (radial yellow gradient)
///   - Pause/resume pill (only while on shift)
///   - "Sessioni di oggi" card (session rows + running total)
class TimbraScreen extends ConsumerStatefulWidget {
  const TimbraScreen({super.key});

  @override
  ConsumerState<TimbraScreen> createState() => _TimbraScreenState();
}

class _TimbraScreenState extends ConsumerState<TimbraScreen> with TickerProviderStateMixin {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  // Pulse animation for the clock dot while on shift.
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

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
    _clockTimer.cancel();
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
                      _DateLabel(now: _now),
                      const SizedBox(height: 6),
                      _LiveClock(now: _now, pulseAnim: _pulseAnim),
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
                      const SizedBox(height: 20),
                    ];

                    final sessions = sessionsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => Text(
                        'Errore sessioni: $e',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                      data: (list) => _SessionsCard(
                        sessions: list,
                        total: total,
                        now: _now,
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

// ══════════════════════════════════════════════════════════════════════════════
// _DateLabel
// ══════════════════════════════════════════════════════════════════════════════

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
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
        fontFamily: 'Manrope',
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
// _LiveClock
// ══════════════════════════════════════════════════════════════════════════════

class _LiveClock extends StatelessWidget {
  const _LiveClock({required this.now, required this.pulseAnim});
  final DateTime now;
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
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
              fontFamily: 'Sora',
              fontSize: 72,
              // w300, not w100. This is the number a technician checks at arm's length, outdoors,
              // to decide whether they are on the clock. Hairline strokes at 72px look elegant on a
              // desk monitor and disappear under sun glare on a scratched screen — the one viewing
              // condition this screen is actually used in. Still light enough to stay display type.
              fontWeight: FontWeight.w300,
              color: AppColors.Y,
              letterSpacing: -2,
              height: 1.0,
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

    // Flat fill, not the gradient+glow disc this used to be: every other control in the app is a
    // solid fill with no shadow (see AppButton._shadows — a soft shadow disappears outdoors, and a
    // gradient is banned everywhere else in the app's own token language), and the one control a
    // technician looks at hardest in direct sun cannot be the one exception to that.
    final fill = isOnShift ? AppColors.stopLight : AppColors.Y;

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
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        color: AppColors.punchGround,
                        strokeWidth: 3,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 36, color: isOnShift ? Colors.white : AppColors.punchGround),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: isOnShift ? Colors.white : AppColors.punchGround,
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
            style: TextStyle(fontFamily: 'Manrope', fontSize: 12, color: context.colors.inkMuted),
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
        child: AppTappable(
          onTap: isLoading || blocked ? null : onTap,
          color: Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withAlpha(120)),
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
                  fontFamily: 'Manrope',
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
            style: TextStyle(fontFamily: 'Manrope', fontSize: 12, color: context.colors.inkMuted),
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
    required this.now,
    required this.hasPendingSync,
    required this.fillHeight,
  });

  final List<WorkSession> sessions;
  final Duration total;
  final DateTime now;
  final bool hasPendingSync;

  /// True when the card was given a bounded box to fill, so its rows scroll inside it. False in
  /// the scrolling fallback, where the card is its natural height and the page moves instead.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13), // ~5% white — translucent card
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title + optional pending-sync indicator
          Row(
            children: [
              Text(
                'SESSIONI DI OGGI',
                style: TextStyle(
                  fontFamily: 'Manrope',
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
          if (sessions.isNotEmpty) const Divider(color: Colors.white12, height: 24),

          // Total row
          _TotalRow(total: total),
        ],
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
          style: TextStyle(color: context.colors.inkMuted, fontSize: 13, fontFamily: 'Manrope'),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_icon(session.eventType), size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _label(session.eventType),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withAlpha(220),
              ),
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
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
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _format(total),
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.Y,
          ),
        ),
      ],
    );
  }
}
