// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/app_database.dart';
import 'timbra_providers.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TimbraScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Dark clock-in / clock-out screen.
///
/// Layout:
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 32, 24, context.navClearance),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Date ──────────────────────────────────────────────────────
              _DateLabel(now: _now),
              const SizedBox(height: 8),

              // ── Live clock ────────────────────────────────────────────────
              _LiveClock(now: _now, pulseAnim: _pulseAnim),
              const SizedBox(height: 40),

              // ── Punch button ──────────────────────────────────────────────
              _PunchButton(
                shiftState: shiftState,
                isLoading: punchState is AsyncLoading,
                guard: ref.watch(punchGuardProvider),
                onTap: () {
                  ref.read(punchNotifierProvider.notifier).punch(shiftState);
                },
              ),
              const SizedBox(height: 12),

              // ── Error snack (shown inline below button) ───────────────────
              if (punchState is AsyncError<void>)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Errore: ${punchState.error}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              // ── Pause / resume (only meaningful while on shift) ───────────
              if (shiftState.isOnShift) ...[
                const SizedBox(height: 16),
                _PauseButton(
                  shiftState: shiftState,
                  isLoading: punchState is AsyncLoading,
                  guard: ref.watch(pauseGuardProvider),
                  onTap: () {
                    ref.read(punchNotifierProvider.notifier).togglePause(shiftState);
                  },
                ),
              ],

              const SizedBox(height: 40),

              // ── Sessioni di oggi ─────────────────────────────────────────
              sessionsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text(
                  'Errore sessioni: $e',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
                data: (sessions) => _SessionsCard(
                  sessions: sessions,
                  total: total,
                  now: _now,
                  hasPendingSync: ref.watch(hasPendingSyncProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

    // Radial gradient: yellow centre → dark rim (or red-ish when ending)
    final gradient = isOnShift
        ? const RadialGradient(
            center: Alignment(0, -0.3),
            radius: 0.85,
            colors: [AppColors.stopLight, AppColors.stopDark],
          )
        : const RadialGradient(
            center: Alignment(0, -0.3),
            radius: 0.85,
            colors: [AppColors.Y, AppColors.YDark],
          );

    // Dimmed and inert rather than hidden: a button that disappears leaves the user with no
    // idea what happened, and the reason is printed underneath so it is readable without a
    // long-press or a tooltip this platform would not show anyway.
    final button = Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && guard.reason != null ? '$label — ${guard.reason}' : label,
      // The one press target deliberately left without a splash. It is a 180dp gradient disc
      // with a coloured glow; ink over that reads as a smudge rather than a press, and the
      // control answers a tap within the frame anyway — it swaps to a spinner while the
      // timbratura is recorded. The secondary pause button below it did get converted, because
      // it is flat and its own state change is a small icon swap.
      child: GestureDetector(
        onTap: isLoading || blocked ? null : onTap,
        child: Opacity(
          opacity: blocked ? 0.4 : 1,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              boxShadow: [
                BoxShadow(
                  color: isOnShift ? AppColors.stopDark.withAlpha(100) : AppColors.Y.withAlpha(80),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
  });

  final List<WorkSession> sessions;
  final Duration total;
  final DateTime now;
  final bool hasPendingSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13), // ~5% white — translucent card
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
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

          if (sessions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Nessuna timbratura oggi',
                  style: TextStyle(
                    color: context.colors.inkMuted,
                    fontSize: 13,
                    fontFamily: 'Manrope',
                  ),
                ),
              ),
            )
          else ...[
            ...sessions.map((s) => _SessionRow(session: s)),
            const Divider(color: Colors.white12, height: 24),
          ],

          // Total row
          _TotalRow(total: total),
        ],
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Totale ore',
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
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
