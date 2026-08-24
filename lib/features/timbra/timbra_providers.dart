// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_service.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/timbratura/timbra_sync_service.dart';
import '../../data/timbratura/work_session_repository.dart';
import '../../data/timbratura/worklog_api_client.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const _kIngresso = 'ingresso';
const _kFine = 'fine';
const _kPausa = 'pausa';
const _kRipresa = 'ripresa';

const _uuid = Uuid();

// ── Repository provider ───────────────────────────────────────────────────────

/// Provides the [WorkSessionRepository] backed by the local Drift DB.
final workSessionRepositoryProvider = Provider<IWorkSessionRepository>((ref) {
  return WorkSessionRepository(ref.watch(appDatabaseProvider));
});

// ── Today's sessions (reactive stream) ───────────────────────────────────────

/// Stream of today's [WorkSession]s in chronological order.
final todaySessionsProvider = StreamProvider.autoDispose<List<WorkSession>>((ref) {
  final repo = ref.watch(workSessionRepositoryProvider);
  return repo.watchTodaySessions();
});

/// True when at least one of today's events has not yet been synced.
final hasPendingSyncProvider = Provider.autoDispose<bool>((ref) {
  final sessions = ref.watch(todaySessionsProvider).valueOrNull ?? [];
  return sessions.any((s) => s.isPendingSync);
});

// ── Shift state notifier ──────────────────────────────────────────────────────

/// Current shift state derived from today's sessions.
class TimbraState {
  const TimbraState({
    this.isOnShift = false,
    this.isOnPause = false,
    this.shiftStartTime,
    this.pauseStartTime,
  });

  final bool isOnShift;
  final bool isOnPause;
  final DateTime? shiftStartTime;
  final DateTime? pauseStartTime;

  TimbraState copyWith({
    bool? isOnShift,
    bool? isOnPause,
    DateTime? shiftStartTime,
    Object? pauseStartTime = _sentinel,
  }) => TimbraState(
    isOnShift: isOnShift ?? this.isOnShift,
    isOnPause: isOnPause ?? this.isOnPause,
    shiftStartTime: shiftStartTime ?? this.shiftStartTime,
    pauseStartTime: identical(pauseStartTime, _sentinel)
        ? this.pauseStartTime
        : pauseStartTime as DateTime?,
  );
}

const _sentinel = Object();

/// Derives [TimbraState] from a list of today's sessions.
TimbraState deriveShiftState(List<WorkSession> sessions) {
  DateTime? shiftStart;
  DateTime? latestPauseStart;
  bool isOnShift = false;
  bool isOnPause = false;

  for (final s in sessions) {
    if (s.eventType == _kIngresso) {
      isOnShift = true;
      isOnPause = false;
      shiftStart = s.eventTime;
      latestPauseStart = null;
    } else if (s.eventType == _kFine) {
      isOnShift = false;
      isOnPause = false;
      shiftStart = null;
      latestPauseStart = null;
    } else if (s.eventType == _kPausa) {
      isOnPause = true;
      latestPauseStart = s.eventTime;
    } else if (s.eventType == _kRipresa) {
      isOnPause = false;
      latestPauseStart = null;
    }
  }

  return TimbraState(
    isOnShift: isOnShift,
    isOnPause: isOnPause,
    shiftStartTime: shiftStart,
    pauseStartTime: latestPauseStart,
  );
}

/// Provides the current [TimbraState] derived from today's session stream.
final timbraStateProvider = Provider.autoDispose<TimbraState>((ref) {
  final sessions = ref.watch(todaySessionsProvider).valueOrNull ?? [];
  return deriveShiftState(sessions);
});

// ── Computed total (minutes worked today, excluding pauses) ───────────────────

/// Returns the total minutes worked today (wall-clock minus pauses).
///
/// Exported as a pure function so it can be tested without Riverpod.
Duration computeTotalWorked(List<WorkSession> sessions, DateTime now) {
  Duration total = Duration.zero;
  DateTime? segStart;

  for (final s in sessions) {
    if (s.eventType == _kIngresso) {
      segStart = s.eventTime;
    } else if (s.eventType == _kFine) {
      if (segStart != null) {
        total += s.eventTime.difference(segStart);
        segStart = null;
      }
    } else if (s.eventType == _kPausa) {
      // Close the current working segment at pause start.
      if (segStart != null) {
        total += s.eventTime.difference(segStart);
        segStart = null;
      }
    } else if (s.eventType == _kRipresa) {
      // Resume: open a new working segment from ripresa time.
      segStart = s.eventTime;
    }
  }

  // If still on shift (no 'fine' yet), add time to now.
  if (segStart != null) {
    total += now.difference(segStart);
  }

  return total;
}

final totalWorkedTodayProvider = Provider.autoDispose<Duration>((ref) {
  final sessions = ref.watch(todaySessionsProvider).valueOrNull ?? [];
  return computeTotalWorked(sessions, DateTime.now());
});

// ── What the server will accept (backend ADR-0013 §C.5) ──────────────────────

/// The server's view of today, or null when it could not be reached.
///
/// Errors resolve to null rather than propagating: offline is the normal condition of a phone
/// in the field, not a failure to report. The screen keeps working from local events; this
/// only ever adds what the device cannot know by itself.
final giornataProvider = FutureProvider.autoDispose<GiornataDto?>((ref) async {
  final client = ref.watch(worklogApiClientProvider);
  try {
    return await client.getGiornata();
  } catch (_) {
    return null;
  }
});

/// A refusal the device is willing to enforce before the punch is even recorded.
class TimbraGuard {
  const TimbraGuard({required this.blocked, this.reason});

  final bool blocked;
  final String? reason;

  static const allowed = TimbraGuard(blocked: false);
}

/// Human-readable text for a server reason code, falling back to the server's own prose.
String? _guardReason(GiornataActionDto action) {
  const known = <String, String>{
    'payroll_locked': 'Il periodo è chiuso per le buste paga: chiedi all\'amministrazione.',
    'already_clocked_in': 'Risulti già in servizio.',
    'not_clocked_in': 'Non risulti in servizio.',
    'on_break': 'Risulti in pausa.',
    'not_on_break': 'Non risulti in pausa.',
    'still_clocked_in': 'Chiudi la giornata prima di inviare le ore.',
    'nothing_to_submit': 'Non ci sono ore da inviare.',
    'already_submitted': 'Le ore di oggi sono già state inviate.',
  };
  final code = action.reasonCode;
  if (code != null && known.containsKey(code)) return known[code];
  return action.reason;
}

/// Decides whether the device should refuse [action] before recording it locally.
///
/// The web client can simply render `availableActions`; this one cannot, and the difference is
/// the point of the offline model:
///
/// - **No server answer** — allow. The phone works from its own events when there is no
///   network, which is most of why it exists.
/// - **Unsynced events pending** — allow, *except* for a payroll lock. The server has not seen
///   the events sitting in the local queue, so its idea of "are you clocked in" is stale by
///   construction and would refuse a perfectly good punch. A closed payroll period is not
///   about those events at all: it is true whatever this device has queued, so it still holds.
/// - **Fresh answer, nothing pending** — the server decides, and its reason is shown. This is
///   the case where the device would otherwise let someone punch into a state the server will
///   reject on sync, turning a refusal the user could have seen now into a mystery later.
///
/// Not a security boundary either way: the server re-validates every write. This exists so the
/// user finds out at the moment of the tap rather than after a sync they never watch.
TimbraGuard resolveGuard({
  required GiornataDto? giornata,
  required bool hasPendingSync,
  required String action,
}) {
  if (giornata == null) return TimbraGuard.allowed;

  final availability = giornata.action(action);
  if (availability == null || availability.enabled) return TimbraGuard.allowed;

  final isLock = availability.reasonCode == 'payroll_locked';
  if (hasPendingSync && !isLock) return TimbraGuard.allowed;

  return TimbraGuard(blocked: true, reason: _guardReason(availability));
}

/// The guard for the punch button, whose action depends on whether a shift is open.
final punchGuardProvider = Provider.autoDispose<TimbraGuard>((ref) {
  final shift = ref.watch(timbraStateProvider);
  return resolveGuard(
    giornata: ref.watch(giornataProvider).valueOrNull,
    hasPendingSync: ref.watch(hasPendingSyncProvider),
    action: shift.isOnShift ? 'ClockOut' : 'ClockIn',
  );
});

/// The guard for the pause/resume control, whose action depends on whether a break is open.
///
/// Mirrors [punchGuardProvider] exactly — same `resolveGuard` merge rule, different action pair
/// (`StartBreak` / `EndBreak` instead of `ClockIn` / `ClockOut`).
final pauseGuardProvider = Provider.autoDispose<TimbraGuard>((ref) {
  final shift = ref.watch(timbraStateProvider);
  return resolveGuard(
    giornata: ref.watch(giornataProvider).valueOrNull,
    hasPendingSync: ref.watch(hasPendingSyncProvider),
    action: shift.isOnPause ? 'EndBreak' : 'StartBreak',
  );
});

// ── Punch action ──────────────────────────────────────────────────────────────

/// Notifier for punch-in / punch-out / pause / resume.
class PunchNotifier extends StateNotifier<AsyncValue<void>> {
  PunchNotifier(this._repo, [this._syncService, ILocationService? locationService])
    : _locationService = locationService ?? const DisabledLocationService(),
      super(const AsyncData(null));

  final IWorkSessionRepository _repo;
  final TimbraSyncService? _syncService;
  final ILocationService _locationService;

  /// Best-effort GPS capture for an interval-opening event (ingresso/ripresa).
  ///
  /// Deliberately silent: never prompts for permission (`willPromptForPermission` guard) and
  /// never blocks or fails the punch when a position isn't available. Simple timbra works with
  /// no position at all by design — see cantiere_timbra_screen's own copy, "La timbratura
  /// normale... funziona senza GPS" — this only stops the app from discarding a position it could
  /// have captured for free (permission already granted) instead of ever recording it.
  Future<GpsCoords?> _captureGpsSilently() async {
    try {
      if (await _locationService.willPromptForPermission()) return null;
      return await _locationService.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> punch(TimbraState current) async {
    state = const AsyncLoading();
    try {
      final now = DateTime.now().toUtc();
      if (!current.isOnShift) {
        // Start shift
        final coords = await _captureGpsSilently();
        await _repo.addEvent(
          id: _uuid.v4(),
          eventTime: now,
          eventType: _kIngresso,
          latitude: coords?.lat,
          longitude: coords?.lng,
          gpsAccuracyMeters: coords?.accuracy,
        );
      } else {
        // End shift
        await _repo.addEvent(id: _uuid.v4(), eventTime: now, eventType: _kFine);
      }
      state = const AsyncData(null);
      // Best-effort sync after punch (fire-and-forget; ignore failure).
      _syncService?.syncNow();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> togglePause(TimbraState current) async {
    if (!current.isOnShift) return;
    state = const AsyncLoading();
    try {
      final now = DateTime.now().toUtc();
      if (current.isOnPause) {
        final coords = await _captureGpsSilently();
        await _repo.addEvent(
          id: _uuid.v4(),
          eventTime: now,
          eventType: _kRipresa,
          latitude: coords?.lat,
          longitude: coords?.lng,
          gpsAccuracyMeters: coords?.accuracy,
        );
      } else {
        await _repo.addEvent(id: _uuid.v4(), eventTime: now, eventType: _kPausa);
      }
      state = const AsyncData(null);
      // Best-effort sync after pause/resume (fire-and-forget; ignore failure).
      _syncService?.syncNow();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final punchNotifierProvider = StateNotifierProvider.autoDispose<PunchNotifier, AsyncValue<void>>((
  ref,
) {
  return PunchNotifier(
    ref.watch(workSessionRepositoryProvider),
    ref.watch(timbraSyncServiceProvider),
    ref.watch(locationServiceProvider),
  );
});

// ── Submit-day action ─────────────────────────────────────────────────────────

/// The guard for "invia le ore" (submit today's finished hours for approval).
///
/// Mirrors [punchGuardProvider]/[pauseGuardProvider]'s `resolveGuard` merge rule with the
/// `Submit` action. Unlike punch/pause, submitting has no meaning when the server cannot be
/// reached at all (there is nothing local to fall back to — approval is inherently a
/// server-side workflow), so callers combine this with an explicit check that the server
/// actually offered `Submit` (see `giornataProvider(...).valueOrNull?.action('Submit')`) before
/// showing the control at all; this only governs whether a shown control is tappable.
final submitGuardProvider = Provider.autoDispose<TimbraGuard>((ref) {
  return resolveGuard(
    giornata: ref.watch(giornataProvider).valueOrNull,
    hasPendingSync: ref.watch(hasPendingSyncProvider),
    action: 'Submit',
  );
});

/// Notifier for the day-level "invia le ore" action.
///
/// Backend `POST /api/worklog/today/submit` exists and `GiornataDto.actions` already tells the
/// device when the server is willing to accept it (see `WorkLogController.SubmitToday`); nothing
/// on mobile called it before this.
class SubmitDayNotifier extends StateNotifier<AsyncValue<void>> {
  SubmitDayNotifier(this._client, this._ref) : super(const AsyncData(null));

  final WorklogApiClient _client;
  final Ref _ref;

  Future<void> submit() async {
    state = const AsyncLoading();
    try {
      await _client.submitToday();
      state = const AsyncData(null);
      // The server's view of the day just changed (Submit likely went from offered to refused,
      // reason "already_submitted") — refresh it rather than let the UI show a stale offer.
      _ref.invalidate(giornataProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final submitDayNotifierProvider =
    StateNotifierProvider.autoDispose<SubmitDayNotifier, AsyncValue<void>>((ref) {
      return SubmitDayNotifier(ref.watch(worklogApiClientProvider), ref);
    });
