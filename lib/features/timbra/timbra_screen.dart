// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/app_database.dart';
import 'timbra_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TimbraScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Dark clock-in / clock-out screen.
///
/// Layout:
///   - Date label (uppercase, Manrope 13 muted)
///   - Live clock (Sora 72 thin, yellow, ticking every second)
///   - Circular punch button (radial yellow gradient)
///   - "Sessioni di oggi" card (session rows + running total)
class TimbraScreen extends ConsumerStatefulWidget {
  const TimbraScreen({super.key});

  @override
  ConsumerState<TimbraScreen> createState() => _TimbraScreenState();
}

class _TimbraScreenState extends ConsumerState<TimbraScreen>
    with TickerProviderStateMixin {
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
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
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
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
      'GEN', 'FEB', 'MAR', 'APR', 'MAG', 'GIU',
      'LUG', 'AGO', 'SET', 'OTT', 'NOV', 'DIC',
    ];
    final day = dayNames[now.weekday - 1];
    final month = monthNames[now.month - 1];
    final formatted = '$day ${now.day} $month ${now.year}';
    return Text(
      formatted,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.MUTED,
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
          style: GoogleFonts.sora(
            fontSize: 72,
            fontWeight: FontWeight.w100,
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
  });

  final TimbraState shiftState;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOnShift = shiftState.isOnShift;
    final label = isOnShift ? 'FINE TURNO' : 'INIZIA TURNO';
    final icon = isOnShift ? LucideIcons.square : LucideIcons.play;

    // Radial gradient: yellow centre → dark rim (or red-ish when ending)
    final gradient = isOnShift
        ? const RadialGradient(
            center: Alignment(0, -0.3),
            radius: 0.85,
            colors: [Color(0xFFFF6B6B), Color(0xFFCC3333)],
          )
        : const RadialGradient(
            center: Alignment(0, -0.3),
            radius: 0.85,
            colors: [AppColors.Y, AppColors.YDark],
          );

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: isOnShift
                    ? const Color(0xFFCC3333).withAlpha(100)
                    : AppColors.Y.withAlpha(80),
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
                      color: Color(0xFF1A1A1A),
                      strokeWidth: 3,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 36,
                      color: isOnShift ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color:
                            isOnShift ? Colors.white : const Color(0xFF1A1A1A),
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
// _SessionsCard  — "Sessioni di oggi"
// ══════════════════════════════════════════════════════════════════════════════

class _SessionsCard extends StatelessWidget {
  const _SessionsCard({
    required this.sessions,
    required this.total,
    required this.now,
  });

  final List<WorkSession> sessions;
  final Duration total;
  final DateTime now;

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
          // Section title
          Text(
            'SESSIONI DI OGGI',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.MUTED,
            ),
          ),
          const SizedBox(height: 16),

          if (sessions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Nessuna timbratura oggi',
                  style: const TextStyle(
                    color: AppColors.MUTED,
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

  Color _color(String type) {
    switch (type) {
      case 'ingresso':
        return AppColors.GREEN;
      case 'fine':
        return AppColors.RED;
      case 'pausa':
        return AppColors.AMBER;
      case 'ripresa':
        return AppColors.CYAN;
      default:
        return AppColors.MUTED;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(session.eventTime.toLocal());
    final color = _color(session.eventType);

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
