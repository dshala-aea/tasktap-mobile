// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/timbratura/timbra_sync_service.dart';
import '../../data/timbratura/work_session_repository.dart';

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
final todaySessionsProvider =
    StreamProvider.autoDispose<List<WorkSession>>((ref) {
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
  }) =>
      TimbraState(
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

// ── Punch action ──────────────────────────────────────────────────────────────

/// Notifier for punch-in / punch-out / pause / resume.
class PunchNotifier extends StateNotifier<AsyncValue<void>> {
  PunchNotifier(this._repo, [this._syncService]) : super(const AsyncData(null));

  final IWorkSessionRepository _repo;
  final TimbraSyncService? _syncService;

  Future<void> punch(TimbraState current) async {
    state = const AsyncLoading();
    try {
      final now = DateTime.now().toUtc();
      if (!current.isOnShift) {
        // Start shift
        await _repo.addEvent(
          id: _uuid.v4(),
          eventTime: now,
          eventType: _kIngresso,
        );
      } else {
        // End shift
        await _repo.addEvent(
          id: _uuid.v4(),
          eventTime: now,
          eventType: _kFine,
        );
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
        await _repo.addEvent(
          id: _uuid.v4(),
          eventTime: now,
          eventType: _kRipresa,
        );
      } else {
        await _repo.addEvent(
          id: _uuid.v4(),
          eventTime: now,
          eventType: _kPausa,
        );
      }
      state = const AsyncData(null);
      // Best-effort sync after pause/resume (fire-and-forget; ignore failure).
      _syncService?.syncNow();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final punchNotifierProvider =
    StateNotifierProvider.autoDispose<PunchNotifier, AsyncValue<void>>((ref) {
  return PunchNotifier(
    ref.watch(workSessionRepositoryProvider),
    ref.watch(timbraSyncServiceProvider),
  );
});
