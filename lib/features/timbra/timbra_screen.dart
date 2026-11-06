// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/time/business_time.dart' show BusinessTime;
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/compartment_sheet.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/status_stamp.dart';
import '../../data/entitlements/entitlement_providers.dart';
import '../../data/local/app_database.dart';
import '../dashboard/active_trackers_provider.dart' show nowProvider;
import '../../data/timbratura/remote_shift.dart' show OfflineRemoteShiftException;
import '../../presentation/providers/clock_disagreement_provider.dart';
import 'clock_disagreement_note.dart';
import 'day_rail.dart';
import 'day_rail_view.dart';
import 'timbra_providers.dart';
import 'work_log_live_refresh.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TimbraScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Clock-in / clock-out screen.
///
///   - (2026-08-26 redesign, module #1; hero restructured 2026-08-30, "Status-First Hero"; chrome
///     removed 2026-08-30, "Hybrid Card Hero"; hero card dropped entirely 2026-08-30, full flip;
///     flat Documento material, no more gradients, 2026-09-04.)
///   - The screen used to be permanently dark, top to bottom, with its own fixed `ScreenHeader`
///     plate. A first pass narrowed that to one dark "hero card" wrapping just the punch control
///     (the sun-glare argument for a dark, high-contrast surface was real — see the git history on
///     this file). That card didn't land: it read as a second, disconnected surface rather than
///     part of the page. The sun-glare property is kept differently — the punch/pause controls are
///     a saturated flat fill with white text/icon, legible regardless of the surrounding theme.
///   - Punch/pause are full-width rounded-rect buttons, not a floating disc/small pill.
///   - "Invia ore" (day-level submit-for-approval) removed entirely — the approval workflow it
///     fed had no real consumer.
///   - Punch failures route through [showAppToast], the shared feedback surface, so the layout
///     never shifts to make room for an error line.
///   - **2026-11-04 — the day became a line.** Two defects drove this rebuild. (1) The list and
///     the total came from this phone's own table only: a punch made on the totem, on another
///     device, or corrected by the office was invisible, so the total undercounted and the
///     technician could not tell it was wrong. (2) The screen is pushed on the root navigator and
///     its header declared no leading control — Android's system back was the only way out.
///
///     The fix for (1) is not a longer list. `SESSIONI DI OGGI` showed moments and left the
///     subtraction to the reader; the rail (`day_rail_view.dart`) shows stretches and voids with
///     their own durations, so the total is legible as the sum of what is drawn. The merge behind
///     it lives in `day_rail.dart` (phone events + server rows, joined on the client id). Every
///     stretch says where it came from, because "the office corrected this" and "this phone
///     recorded it" are different facts and the whole bug was their conflation.
///
///     The fix for (2) is `showBack: true` — the shared header already carries the chevron.
///
///     The punch control moved out of the scrolling content into a docked deck above the safe
///     area: the one action the technician came here to take should not be able to scroll away,
///     and the rail needs the vertical room more than the controls do.
class TimbraScreen extends ConsumerWidget {
  const TimbraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The punch controls act on the whole-log state, not today's: a shift opened at 22:00 is still
    // open at 00:01 and must keep both its finish and its "FINE TURNO" label. See
    // actionableShiftStateProvider — the rail below stays day-scoped through dayRailProvider.
    final shiftState = ref.watch(actionableShiftStateProvider);
    final punchState = ref.watch(punchNotifierProvider);
    final clockInMethod = ref.watch(effectiveClockInMethodProvider);
    final smartWorking = ref.watch(smartWorkingTodayProvider);
    final day = ref.watch(dayRailProvider);
    // Whether the server's own day answered at all. A failed read is not an error screen — the
    // phone's own punches still draw — but it must not be silently indistinguishable from "the
    // server says there is nothing", which is the exact claim this screen was rebuilt to stop
    // making. See serverDayProvider.
    final serverDay = ref.watch(serverDayProvider);
    final serverFailed = serverDay.hasError;
    final serverResolved = serverDay.hasValue;
    final localFailure = ref.watch(todaySessionsProvider).error;
    // What an empty rail may claim depends on BOTH sources: a failed server read allows only this
    // phone's truth, and a failed local read leaves the day unknown — the screen cannot then say
    // "nothing happened today" beside its own "impossibile leggere le timbrature", nor offer a
    // punch that would open a second shift on a day nobody has seen.
    final coverage = localFailure != null
        ? DayCoverage.unknown
        : (serverResolved ? DayCoverage.complete : DayCoverage.phoneOnly);
    final rejected = ref.watch(syncFailedSessionsProvider).valueOrNull ?? const <WorkSession>[];
    final punchGuard = ref.watch(punchGuardProvider);
    final pauseGuard = ref.watch(pauseGuardProvider);
    final clockDisagreement = ref.watch(timbraClockDisagreementProvider);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    ref.listen<AsyncValue<void>>(punchNotifierProvider, (previous, next) {
      if (next is AsyncError) {
        showAppToast(
          context,
          message: next.error is OfflineRemoteShiftException
              ? (next.error as OfflineRemoteShiftException).message
              : 'Errore durante la timbratura. Riprova.',
          tone: ToastTone.error,
        );
      }
    });

    // The one shared rule (entitlement_providers.dart's isButtonPunchWithheld), on the same
    // `startOnly` surface as Home: an effective QrOnly user gets the scanner and no punch keys at
    // all, open shift or not — they close the day by scanning, or the office closes it from the
    // web panel. Only an approved smart-working day (true) or an unknown answer (null) keeps keys.
    final hidePunch = isButtonPunchWithheld(
      surface: ButtonPunchSurface.startOnly,
      clockInMethod: clockInMethod,
      smartWorkingToday: smartWorking,
      hasOpenShift: shiftState.isOnShift,
    );

    final banners = <Widget>[
      // The server compared this phone's clock with its own receipt instant and found them far
      // apart. Only the server can make that comparison, so this banner says what the technician
      // could not otherwise discover. Advisory: the hours are already recorded.
      if (clockDisagreement != null) ...[
        ClockDisagreementNote(
          seconds: clockDisagreement,
          onDismiss: () => ref.read(timbraClockDisagreementProvider.notifier).dismiss(),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      // A punch the server refused is a fact about the shift the technician is about to add to.
      if (rejected.isNotEmpty) ...[
        _RejectedPunchesBanner(sessions: rejected),
        const SizedBox(height: AppSpacing.md),
      ],
      // Both guard reasons, promoted out of the buttons themselves: the deck is a fixed strip at
      // the bottom of the screen and has no room to grow a paragraph under it. Above the rail, the
      // reason is read before the tap rather than after it.
      for (final guard in [punchGuard, pauseGuard])
        if (guard.blocked && guard.reason != null) ...[
          AnimatedSize(
            duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            curve: Curves.easeInOut,
            child: _GuardBanner(reason: guard.reason!),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      // An approved remote day, said before the control it explains.
      if (smartWorking == true) ...[
        const _SmartWorkingChip(),
        const SizedBox(height: AppSpacing.md),
      ],
      // A failure to read *this phone's own* table, unlike an unreachable server (which leaves the
      // phone's own line intact and is not an error state — see day_rail.dart). Silently showing
      // an empty rail here would look exactly like a day with no punches.
      if (localFailure != null) ...[
        _InlineFailure(message: '$localFailure'),
        const SizedBox(height: AppSpacing.md),
      ],
      // The opposite failure: this phone is fine, the server's day is not. The rail still shows
      // every punch made here; what it cannot show is anything recorded elsewhere, and only this
      // line can say so. When there is nothing to draw at all, the rail's own empty state says it
      // instead — one sentence, not two.
      if (serverFailed && !day.isEmpty) ...[
        const _ServerDayUnknown(),
        const SizedBox(height: AppSpacing.md),
      ],
    ];

    return WorkLogLiveRefresh(
      child: Scaffold(
        // bg1, not bg2: the header, the rail's sheet and the deck are all `surface` (Sheet). In
        // light mode bg1 and bg2 are the same Paper value, so nothing moves; in dark they differ
        // (#17181C vs #1E1F24), and bg2 left the three Sheet surfaces floating on a ground of their
        // own tone — the paper-to-sheet step simply absent from a whole theme.
        backgroundColor: context.colors.bg1,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ScreenHeader(
                title: 'Timbra',
                subtitle: _formatDateLabel(ref.watch(businessTimeProvider)),
                // This route is pushed on the root navigator, so the app's own tab bar — the only
                // other way back — is not on screen. Without this the Android system gesture was
                // the sole exit, which is a missing affordance, not a shortcut.
                showBack: true,
                // ButtonOnly: no server endpoint would accept a kiosk-QR punch anyway (backend
                // EnsureClockInMethodAllowedAsync), so the entry point is hidden rather than
                // shown-but-doomed.
                actions: clockInMethod == 'ButtonOnly'
                    ? const []
                    : [
                        HeaderIconBtn(
                          icon: Icons.qr_code_scanner,
                          label: 'Timbra con QR',
                          onTap: () => context.push(AppRoutes.timbraQr),
                        ),
                      ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.md,
                    AppSpacing.pagePadding,
                    0,
                  ),
                  // Fixed when there is room, scrolling when there is not. The rail is the only
                  // elastic element, so a short viewport shrinks it to _kRailMinHeight and then the
                  // page scrolls — the head and the banners keep their natural heights either way.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tight = constraints.maxHeight < _kComfortableMinHeight;

                      if (tight) {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _DayHead(shiftState: shiftState, day: day),
                              const SizedBox(height: AppSpacing.md),
                              ...banners,
                              SizedBox(
                                height: _kRailMinHeight,
                                child: DayRailView(day: day, coverage: coverage),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DayHead(shiftState: shiftState, day: day),
                          const SizedBox(height: AppSpacing.md),
                          ...banners,
                          Expanded(child: DayRailView(day: day, coverage: coverage)),
                        ],
                      );
                    },
                  ),
                ),
              ),
              _PunchDeck(
                shiftState: shiftState,
                isLoading: punchState is AsyncLoading,
                punchGuard: punchGuard,
                pauseGuard: pauseGuard,
                hidePunch: hidePunch,
                onPunch: () => ref.read(punchNotifierProvider.notifier).punch(shiftState),
                onPause: () => ref.read(punchNotifierProvider.notifier).togglePause(shiftState),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Below this the rail would be too short to read as a time axis, so the whole body scrolls and the
/// rail takes [_kRailMinHeight] instead. Counted against a head of ≈110dp and up to three banners
/// of ≈60dp each; the deck is outside this box, so it never eats into the figure.
const double _kComfortableMinHeight = 460;

const double _kRailMinHeight = 300;

// ══════════════════════════════════════════════════════════════════════════════
// Date label
// ══════════════════════════════════════════════════════════════════════════════

/// The business-zone calendar date, not the clock — this never needs the per-second tick the live
/// clock does, so it reads the clock once per build rather than watching `nowProvider`. Feeds
/// `ScreenHeader`'s `subtitle`.
///
/// Locale-neutral format to avoid requiring `initializeDateFormatting`. Renders as e.g.
/// "LUN 22 GIU 2026".
String _formatDateLabel(BusinessTime businessTime) {
  final now = businessTime.businessToday();
  const dayNames = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'];
  const monthNames = [
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
  return '$day ${now.day} $month ${now.year}';
}

String _formatHoursMinutes(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${h}h ${m}m';
}

// ══════════════════════════════════════════════════════════════════════════════
// _DayHead  — the live state, the running total, the clock
// ══════════════════════════════════════════════════════════════════════════════

/// The two things a technician glances at this screen for: "am I clocked in" and "how much is in
/// the day". The state is the app's own stamp device, not a fresh pill; the total is the merged
/// day's count, so a totem punch and an office correction are inside it.
///
/// The total re-derives from [nowProvider] only while a stretch is running — a closed day returns
/// the same number on every tick, and this widget still rebuilds for the clock beside it.
class _DayHead extends ConsumerWidget {
  const _DayHead({required this.shiftState, required this.day});

  final TimbraState shiftState;
  final DayRail day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticking = ref.watch(nowProvider).valueOrNull ?? DateTime.now();
    final worked = day.workedAt(day.isOpen ? ticking : day.now);
    final paused = day.pausedAt(day.isOpen ? ticking : day.now);
    // Above the system font's own default the caption goes UNDER the figure instead of beside it.
    // Side by side, the pair is wider than the phone at 1.3 and the FittedBox below has nowhere to
    // go but down — shrinking the one number this screen exists to show. Stacked, the figure keeps
    // its full size and only a caption that no longer fits is scaled.
    final stackedHead = MediaQuery.textScalerOf(context).scale(1) > 1.15;

    final label = switch (shiftState) {
      TimbraState(isOnShift: true, isOnPause: true) => 'In pausa',
      TimbraState(isOnShift: true) => 'In turno',
      _ => 'Fuori turno',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatusStamp(stato: label, size: StampSize.large),
            const Spacer(),
            const _LiveClock(),
          ],
        ),
        const SizedBox(height: 14),
        // The app's one running number, and the one place a screen reader needs to be told it
        // changed — a liveRegion on a figure that ticks while a shift is open.
        Semantics(
          liveRegion: true,
          label: 'Ore lavorate oggi ${_formatHoursMinutes(worked)}',
          excludeSemantics: true,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: stackedHead
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _WorkedFigure(worked: worked),
                        const SizedBox(height: 2),
                        _WorkedCaption(paused: paused),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _WorkedFigure(worked: worked),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _WorkedCaption(paused: paused),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The day's worked total — the app's one running number.
class _WorkedFigure extends StatelessWidget {
  const _WorkedFigure({required this.worked});

  final Duration worked;

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatHoursMinutes(worked),
      style: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 46,
        fontWeight: FontWeight.w600,
        // accentInk, not AppColors.Y: this Scaffold's `bg1` flips with the theme, and Y-as-text
        // only clears 2.91:1 in dark mode — under even the relaxed 3:1 large-text floor at this
        // size. See AppPalette.accentInk's own note.
        color: context.colors.accentInk,
        letterSpacing: -1,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// What the figure counts, and how much of it is pause.
class _WorkedCaption extends StatelessWidget {
  const _WorkedCaption({required this.paused});

  final Duration paused;

  @override
  Widget build(BuildContext context) {
    return Text(
      paused > Duration.zero
          ? 'lavorate · ${_formatHoursMinutes(paused)} in pausa'
          : 'lavorate oggi',
      style: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 9.5,
        height: 1.1,
        letterSpacing: 0.6,
        color: context.colors.inkMuted,
      ),
    );
  }
}

/// The business-zone clock, at the weight of a secondary readout: the technician's other question
/// is whether this phone agrees with the wall clock. The one per-second-ticking widget up here —
/// only this rebuilds on the tick.
class _LiveClock extends ConsumerWidget {
  const _LiveClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessTime = ref.watch(businessTimeProvider);
    final now = ref.watch(nowProvider).valueOrNull ?? businessTime.nowInstant();
    final timeStr = businessTime.formatInZone(now, 'HH:mm:ss');
    // A semantics label, NOT a live region. The label changes every second, so a live region here
    // makes TalkBack read the wall clock aloud on every tick and renders the screen unusable with a
    // screen reader. The one live region on this screen is the worked total, which changes at most
    // once a minute and is the number the technician came to hear.
    return Semantics(
      label: 'Ora corrente $timeStr',
      excludeSemantics: true,
      child: Text(
        timeStr,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
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
// _InlineFailure
// ══════════════════════════════════════════════════════════════════════════════

/// A failure to read this phone's own database — never the server's, which is an expected
/// condition on a site with no signal and is handled inside the rail.
///
/// Wears the screen's one "needs attention" treatment (`statusWarnBg` + `amberInk`, the same pair
/// as [_GuardBanner] and [_ServerDayUnknown]) rather than red 12px prose on Paper: `colors.red` at
/// this size measures 4.30:1 on the Paper ground, and a bare sentence here was the only failure on
/// the screen that did not look like one.
class _InlineFailure extends StatelessWidget {
  const _InlineFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: v.statusWarnBg,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: v.statusWarn.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 15, color: v.statusWarn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Impossibile leggere le timbrature di questo telefono: $message',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                height: 1.35,
                color: context.colors.amberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _GuardBanner
// ══════════════════════════════════════════════════════════════════════════════

/// Full-width, seen-before-the-tap treatment for a punch refusal the device already knows about
/// (closed payroll period, a shift another device opened). Reuses `context.vetro.statusWarn`/
/// `statusWarnBg` — the same "needs attention" pair, not a fresh colour invented for this banner.
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
        borderRadius: AppRack.freeShape,
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
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                height: 1.35,
                color: context.colors.amberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ServerDayUnknown
// ══════════════════════════════════════════════════════════════════════════════

/// The day on the rail may be incomplete, and this says so above it.
///
/// The rail still draws — this phone's own punches are not lost when the server is unreachable —
/// but the merged day is exactly what this screen exists to be, so a partial one must not look
/// like a complete one. Same "needs attention" pair as [_GuardBanner], and the same amberInk body
/// colour for the same reason: `statusWarn` as a fill is tuned against white ink, and falls under
/// 4.5:1 as text on these surfaces.
class _ServerDayUnknown extends StatelessWidget {
  const _ServerDayUnknown();

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: v.statusWarnBg,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: v.statusWarn.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 15, color: v.statusWarn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'La giornata del server non è raggiungibile: le timbrature fatte al totem o da un '
              'altro dispositivo potrebbero mancare.',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                height: 1.35,
                color: context.colors.amberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _RejectedPunchesBanner
// ══════════════════════════════════════════════════════════════════════════════

/// Says out loud what the app used to say once and then forget: the server refused N punches.
///
/// Those rows stay on the phone under `syncFailedMarker` and are hidden from the rail on purpose —
/// a rejected opener would double the day. The consequence is that every number on this screen is
/// correct while the technician still cannot see that part of their day never reached the office.
/// The notice names the count and opens the list; it disappears when the rows fall out of the
/// repository's 7-day window, not on a tap, because dismissing it would restore exactly the silence
/// it exists to remove.
class _RejectedPunchesBanner extends StatelessWidget {
  const _RejectedPunchesBanner({required this.sessions});

  final List<WorkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final n = sessions.length;
    final titolo = n == 1
        ? '1 timbratura non registrata dal server'
        : '$n timbrature non registrate dal server';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openCompartmentSheet(
        context,
        label: n == 1 ? 'Timbratura non registrata' : 'Timbrature non registrate',
        content: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.sm,
            AppSpacing.pagePadding,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Il server le ha rifiutate perché un altro dispositivo aveva già un turno aperto. '
                'Restano su questo telefono e non entrano nel totale: se le ore sono reali, '
                'segnalale all\'ufficio.',
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 13,
                  height: 1.4,
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final s in sessions) _RejectedPunchRow(session: s),
            ],
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: v.statusWarnBg,
          borderRadius: AppRack.freeShape,
          border: Border.all(color: v.statusWarn.withAlpha(80)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.alertTriangle, size: 15, color: v.statusWarn),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titolo,
                    style: TextStyle(
                      fontFamily: 'Archivo',
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: context.colors.amberInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tocca per i dettagli',
                    style: TextStyle(
                      fontFamily: 'Archivo',
                      fontSize: 12,
                      height: 1.35,
                      color: context.colors.amberInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One refused punch, with the business day it belongs to and its time.
class _RejectedPunchRow extends ConsumerWidget {
  const _RejectedPunchRow({required this.session});

  final WorkSession session;

  String _label(String type) => switch (type) {
    'ingresso' => 'Ingresso',
    'fine' => 'Fine turno',
    'pausa' => 'Pausa',
    'ripresa' => 'Ripresa',
    _ => type,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessTime = ref.watch(businessTimeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _label(session.eventType),
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.colors.ink.withAlpha(220),
              ),
            ),
          ),
          Text(
            businessTime.formatInZone(session.eventTime, 'dd/MM HH:mm'),
            style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SmartWorkingChip
// ══════════════════════════════════════════════════════════════════════════════

/// Pill for an approved smart-working day — rendered only for [smartWorkingTodayProvider]'s
/// `true`, never for `null`. See [isButtonPunchWithheld] for why an unknown answer may not be
/// treated as "not approved".
///
/// `liveRegion`: /auth/me is re-read on every resume, so an approval that lands while the screen is
/// open has to be announced, not silently drawn.
class _SmartWorkingChip extends StatelessWidget {
  const _SmartWorkingChip();

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Giornata di smart working approvata',
        liveRegion: true,
        // The visible text says the same thing, so leaving it in the tree would have a screen
        // reader announce the chip twice ("… approvata, Smart working").
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: v.statusGoodBg,
              borderRadius: AppRack.freeShape,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A laptop, not LucideIcons.home — that is the Dashboard tab's own glyph in
                // bottom_nav.dart and would read as a navigation affordance here.
                Icon(LucideIcons.laptop, size: 13, color: v.statusGood),
                const SizedBox(width: 6),
                Text(
                  'Smart working',
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: v.statusGood,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PunchDeck  — the docked controls
// ══════════════════════════════════════════════════════════════════════════════

/// The punch control, docked above the safe area and separated from the body by a hairline.
///
/// It used to sit inside the scrolling column, under the guard banner and the smart-working chip —
/// which meant that on a short phone, or with two banners up, the one thing the technician opened
/// the screen for could be pushed below the fold. The deck cannot scroll away, and it is where a
/// thumb already rests.
class _PunchDeck extends StatelessWidget {
  const _PunchDeck({
    required this.shiftState,
    required this.isLoading,
    required this.punchGuard,
    required this.pauseGuard,
    required this.hidePunch,
    required this.onPunch,
    required this.onPause,
  });

  final TimbraState shiftState;
  final bool isLoading;
  final TimbraGuard punchGuard;
  final TimbraGuard pauseGuard;
  final bool hidePunch;
  final VoidCallback onPunch;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.borderLight)),
      ),
      // The deck owns the bottom inset itself: it sits outside the SafeArea that wraps the header,
      // and a full-bleed fill has to reach the very edge of the glass before the padding starts.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      child: hidePunch
          ? const _QrOnlyDeck()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  // Both keys carry their own fixed height; `stretch` here would ask an
                  // unbounded Column for an infinite height.
                  children: [
                    Expanded(
                      flex: 3,
                      child: _PunchKey(
                        shiftState: shiftState,
                        isLoading: isLoading,
                        guard: punchGuard,
                        onTap: onPunch,
                      ),
                    ),
                    if (shiftState.isOnShift) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _PauseKey(
                          shiftState: shiftState,
                          isLoading: isLoading,
                          guard: pauseGuard,
                          onTap: onPause,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

/// Full-width primary action. Flat saturated fill (no gradient — DESIGN.md's Documento material has
/// none), no shadow: Il Documento is paper and ink, and the glow this control used to carry was the
/// one piece of glass on the screen.
///
/// `AppColors.Y` for "starting" and `AppColors.stopDark` for "ending" are theme-invariant on
/// purpose: white text/icon on top of them has to stay legible under BOTH themes, and the flipping
/// `red`/`redSoft` pair is tuned to invert (`redSoft` goes near-white in light mode, `red` goes a
/// light salmon in dark mode) — either one under fixed white text fails contrast in one theme or
/// the other.
class _PunchKey extends StatefulWidget {
  const _PunchKey({
    required this.shiftState,
    required this.isLoading,
    required this.onTap,
    this.guard = TimbraGuard.allowed,
  });

  final TimbraState shiftState;
  final bool isLoading;
  final VoidCallback onTap;

  /// A refusal the server already told us about — a closed payroll period, a shift another device
  /// opened. The reason text itself is not rendered here; the parent promotes it to a banner above
  /// the rail, before the tap is even attempted. This only governs the dimmed/inert visuals.
  final TimbraGuard guard;

  @override
  State<_PunchKey> createState() => _PunchKeyState();
}

class _PunchKeyState extends State<_PunchKey> {
  // A brief AnimatedScale press-down instead of an ink splash: a splash over a saturated fill read
  // as a smudge on a real device, and the control answers a tap within the frame by swapping to a
  // spinner anyway.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isOnShift = widget.shiftState.isOnShift;
    final label = isOnShift ? 'FINE TURNO' : 'INIZIA TURNO';
    final icon = isOnShift ? LucideIcons.square : LucideIcons.play;
    final blocked = widget.guard.blocked;
    final enabled = !widget.isLoading && !blocked;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final fillColor = isOnShift ? AppColors.stopDark : AppColors.Y;

    // Dimmed and inert rather than hidden: a button that disappears leaves the user with no idea
    // what happened, and the reason is in the banner above.
    return Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && widget.guard.reason != null ? '$label — ${widget.guard.reason}' : label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: blocked ? 0.4 : 1,
            child: AnimatedContainer(
              duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
              height: _deckKeyHeight(context),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: AppRack.freeShape,
                color: fillColor,
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: AppColors.WHITE, strokeWidth: 3),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 20, color: AppColors.WHITE),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontFamily: 'Archivo Narrow',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                              color: AppColors.WHITE,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action, a flat outlined key in the pause ink. Deliberately quieter than [_PunchKey]:
/// starting and ending the shift is the primary action; pause/resume happens mid-shift.
class _PauseKey extends StatefulWidget {
  const _PauseKey({
    required this.shiftState,
    required this.isLoading,
    required this.onTap,
    this.guard = TimbraGuard.allowed,
  });

  final TimbraState shiftState;
  final bool isLoading;
  final VoidCallback onTap;

  /// Same server-driven refusal as [_PunchKey.guard], applied to StartBreak/EndBreak. The reason
  /// itself is promoted to a banner above the rail, same as the punch guard's.
  final TimbraGuard guard;

  @override
  State<_PauseKey> createState() => _PauseKeyState();
}

class _PauseKeyState extends State<_PauseKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isOnPause = widget.shiftState.isOnPause;
    final label = isOnPause ? 'RIPRENDI' : 'PAUSA';
    final icon = isOnPause ? LucideIcons.play : LucideIcons.coffee;
    // amberInk, not amber: the paused control is a glyph and a hairline border on Sheet, and the
    // fill value clears only 4.27:1 there. The fill is still amber where it is a fill (the band's
    // solid, the icon's own chip).
    final accent = context.colors.amberInk;
    final blocked = widget.guard.blocked;
    final enabled = !widget.isLoading && !blocked;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      enabled: !blocked,
      label: blocked && widget.guard.reason != null ? '$label — ${widget.guard.reason}' : label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: blocked ? 0.4 : 1,
            child: Container(
              height: _deckKeyHeight(context),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: AppRack.freeShape,
                color: context.colors.surface,
                border: Border.all(color: accent.withAlpha(150)),
              ),
              child: widget.isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 17, color: accent),
                          const SizedBox(width: 7),
                          Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Archivo Narrow',
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
        ),
      ),
    );
  }
}

const double _kDeckKeyHeight = 60;

/// The deck key's height under the user's own font size, clamped.
///
/// The label sits in a [FittedBox] so a long word never overflows, but a FittedBox alone answers a
/// larger system font by shrinking the label back to its base size — the control that is supposed
/// to grow stays exactly as big as it was. Growing its box is what lets the label keep the size the
/// user asked for; the clamp keeps the deck from eating the rail on the largest settings.
double _deckKeyHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
  return _kDeckKeyHeight * scaler.scale(1);
}

// ══════════════════════════════════════════════════════════════════════════════
// QR paths
// ══════════════════════════════════════════════════════════════════════════════

/// Shown instead of the punch controls when the effective clock-in method is QrOnly — the server
/// would reject a button punch anyway (WorkLogService.EnsureClockInMethodAllowedAsync), so this
/// avoids a round trip to a state the client already knows about. In the deck, not above it: on
/// such a tenant the scanner IS the primary action, and it belongs where the primary action lives.
class _QrOnlyDeck extends StatelessWidget {
  const _QrOnlyDeck();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'La tua azienda richiede la timbratura con QR.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Archivo', fontSize: 12, color: context.colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: _deckKeyHeight(context),
          width: double.infinity,
          child: Material(
            color: context.colors.ink,
            borderRadius: AppRack.freeShape,
            child: InkWell(
              borderRadius: AppRack.freeShape,
              onTap: () => context.push(AppRoutes.timbraQr),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, size: 20, color: AppColors.WHITE),
                  const SizedBox(width: 8),
                  Text(
                    'TIMBRA CON QR',
                    style: TextStyle(
                      fontFamily: 'Archivo Narrow',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: AppColors.WHITE,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
