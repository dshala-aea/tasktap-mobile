// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereTimbraScreen
//
// Clock-in / clock-out for a cantiere (worksite), launched contextually from
// the Ticket detail screen.
//
// Behaviour:
//   - Derives "am I on site" from the local event log first, falling back to the backend's
//     active-session answer only when local has nothing open (see cantiereActiveSessionProvider).
//   - If no active session: shows a cantiere picker (from the local Drift
//     mirror kept fresh by SyncService, preferring cantieri matching the
//     ticket's customerId) + a big "Timbra ingresso cantiere" button, with a
//     secondary "Altri dettagli" affordance for the occasional rich fields.
//   - If an active session exists: shows session info + a "Timbra uscita
//     cantiere" button.
//   - OFFLINE-FIRST: the online start/end endpoints are tried first (they are
//     the only path that carries the full rich-field set — see
//     cantiere_worklog_api_client.dart's own doc comment on why the offline
//     batch endpoint is narrower); a network-unreachable failure falls back
//     to a local Drift queue (`cantiere_punches`, via
//     CantiereSessionRepository) that CantiereTimbraSyncService pushes once
//     connectivity returns. "Am I on site" is derived primarily from that
//     local queue — see cantiereActiveSessionProvider below — so the screen
//     stays usable with no signal at all, matching the personal Timbra
//     screen's own offline model.
//
// This screen flips light/dark (`context.colors.bg2`), unlike personal Timbra's permanently-dark
// ground — so its one remaining `context.vetro` reference (the active-session status dot/label,
// via `context.vetro.statusGood`) reads the flipping semantic-status tokens rather than the fixed
// `AppVetroColors` pair personal Timbra uses. Everything else on this screen is AppCard/AppButton.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/utils/error_message.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/timbratura/cantiere_timbra_sync_service.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../cantiere/cantiere_providers.dart';
import 'chiudi_turno_screen.dart';
import 'gps_status_indicator.dart';
import 'teammate_picker_sheet.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

const _uuid = Uuid();

// ── Providers ─────────────────────────────────────────────────────────────────

/// All active cantieri from the local Drift cache, alphabetical.
/// Status 0 = Active (CantiereStatusEnum.Active).
///
/// Reads the local mirror `SyncService._upsertCantieri` fills on every sync (app launch,
/// resume, and every pull-to-refresh elsewhere in the app — see HomeShell). Nothing here needs
/// a live network call of its own: a normal app session already keeps this populated.
final cantieriProvider = StreamProvider.autoDispose<List<CantieriData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)
        ..where((c) => c.status.equals(0))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

/// AsyncNotifier that loads the current open CantiereWorkLogDto (or null).
///
/// Purely a "richer detail when reachable" source now — see [cantiereActiveSessionProvider] for
/// the offline-durable signal the screen actually gates its body on.
class ActiveCantiereLogNotifier extends AutoDisposeAsyncNotifier<CantiereWorkLogDto?> {
  @override
  Future<CantiereWorkLogDto?> build() async {
    final client = ref.watch(cantiereWorklogApiClientProvider);
    final logs = await client.getActive();
    return logs.isNotEmpty ? logs.first : null;
  }

  /// Refresh from the backend.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(cantiereWorklogApiClientProvider);
      final logs = await client.getActive();
      return logs.isNotEmpty ? logs.first : null;
    });
  }

  /// Clears the active log locally (after a successful — online or offline-queued — end call).
  void clearActive() => state = const AsyncData(null);
}

final activeCantiereLogProvider =
    AutoDisposeAsyncNotifierProvider<ActiveCantiereLogNotifier, CantiereWorkLogDto?>(() {
      return ActiveCantiereLogNotifier();
    });

/// Today's local cantiere punch events, in chronological order — the offline-durable record.
final todayCantiereEventsProvider = StreamProvider.autoDispose<List<CantierePunche>>((ref) {
  final repo = ref.watch(cantiereSessionRepositoryProvider);
  return repo.watchTodayEvents();
});

/// True when at least one of today's local cantiere events has not yet been synced.
final cantiereHasPendingSyncProvider = Provider.autoDispose<bool>((ref) {
  final events = ref.watch(todayCantiereEventsProvider).valueOrNull ?? [];
  return events.any((e) => e.isPendingSync);
});

/// Sums today's *closed* (ingresso→uscita) intervals on [cantiereId] into a total duration.
///
/// Deliberately excludes a still-open interval at the end of the list — that portion needs a
/// live per-second tick to stay accurate, which a value recomputed only when the event list
/// changes can't give you. The UI combines this closed-interval total with a separately-ticking
/// "current session" elapsed widget (see `_CantiereElapsedTicker`) to show the running total.
///
/// Scoped to one cantiere (not a cross-cantiere daily total) — matches the screen's own context:
/// "how much have I worked *here* today."
final cantiereTodayHoursProvider = Provider.autoDispose.family<Duration, String>((
  ref,
  cantiereId,
) {
  final events = ref.watch(todayCantiereEventsProvider).valueOrNull ?? [];
  CantierePunche? opener;
  var total = Duration.zero;
  for (final e in events) {
    switch (e.eventType) {
      case 'ingresso':
        opener = e;
      case 'uscita':
        if (opener != null && opener.cantiereId == cantiereId) {
          total += e.eventTime.difference(opener.eventTime);
        }
        opener = null;
    }
  }
  return total;
});

/// "Xh Ym" — zero-padded minutes, no seconds. Shared by the check-in body's "OGGI" header and the
/// active-session body's hero card (previously duplicated as `_ActiveSessionBody._formatElapsed`).
String formatHoursMinutes(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${h}h ${m}m';
}

/// Resolves a cantiere's name from the local mirror for display on the active-session card —
/// falls back to the raw id if the mirror doesn't have it yet (matches the same
/// not-found-falls-back-to-itself contract used elsewhere in this screen, e.g. colleague names).
String _cantiereNameFor(WidgetRef ref, String cantiereId) {
  return ref.watch(cantiereByIdProvider(cantiereId)).valueOrNull?.name ?? cantiereId;
}

/// Elapsed time since [startTime], clamped so it never counts time before local midnight — a
/// session that started yesterday and is still open must only contribute its since-midnight
/// portion to a "today" reading. Uses the exact same midnight expression as
/// `CantiereSessionRepository._todayBounds()`.
Duration clampedElapsedSinceMidnight(DateTime startTime, DateTime now) {
  final localNow = now.toLocal();
  final todayStartUtc = DateTime(localNow.year, localNow.month, localNow.day).toUtc();
  final effectiveStart = startTime.isAfter(todayStartUtc) ? startTime : todayStartUtc;
  return now.difference(effectiveStart);
}

/// Live-ticking elapsed-time text, clamped to today (see [clampedElapsedSinceMidnight]). Same
/// Ticker-based pattern as `rapportino/step_ore.dart`'s `_RunningTimerBadge`.
class _CantiereElapsedTicker extends StatefulWidget {
  const _CantiereElapsedTicker({
    required this.startTime,
    required this.style,
    this.clock = DateTime.now,
  });

  final DateTime startTime;
  final TextStyle style;

  /// Injectable so tests can control "now" instead of depending on the real wall clock.
  final DateTime Function() clock;

  @override
  State<_CantiereElapsedTicker> createState() => _CantiereElapsedTickerState();
}

class _CantiereElapsedTickerState extends State<_CantiereElapsedTicker>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = clampedElapsedSinceMidnight(widget.startTime, widget.clock());
    return Text(formatHoursMinutes(elapsed), style: widget.style);
  }
}

/// Test-only construction hook for [_CantiereElapsedTicker] — the widget itself stays private
/// (an internal detail of this screen), but a test file is a separate Dart library and so can't
/// name it directly; this lets a test pump the ticker on its own, with a fixed [clock], instead
/// of only asserting its presence by runtime-type string on the whole screen.
@visibleForTesting
Widget cantiereElapsedTickerForTest({
  required DateTime startTime,
  required TextStyle style,
  required DateTime Function() clock,
}) => _CantiereElapsedTicker(startTime: startTime, style: style, clock: clock);

/// The "OGGI" total on the active-session card: closed-interval hours (recomputed only when the
/// event list changes) plus the live-ticking current session — added together and re-rendered
/// every tick, so the grand total visibly climbs in real time while checked in.
class _CantiereTodayTotal extends StatefulWidget {
  const _CantiereTodayTotal({
    required this.closedHours,
    required this.sessionStart,
    this.clock = DateTime.now,
  });

  final Duration closedHours;
  final DateTime sessionStart;

  /// Injectable so tests can control "now" instead of depending on the real wall clock.
  final DateTime Function() clock;

  @override
  State<_CantiereTodayTotal> createState() => _CantiereTodayTotalState();
}

class _CantiereTodayTotalState extends State<_CantiereTodayTotal>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveElapsed = clampedElapsedSinceMidnight(widget.sessionStart, widget.clock());
    return Text(
      formatHoursMinutes(widget.closedHours + liveElapsed),
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: context.colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Test-only construction hook for [_CantiereTodayTotal] — same reasoning as
/// [cantiereElapsedTickerForTest] above: the widget stays private, this lets a test pump it
/// directly with a fixed [clock] to prove the closed-hours + live-elapsed sum.
@visibleForTesting
Widget cantiereTodayTotalForTest({
  required Duration closedHours,
  required DateTime sessionStart,
  required DateTime Function() clock,
}) => _CantiereTodayTotal(closedHours: closedHours, sessionStart: sessionStart, clock: clock);

/// The minimal "am I on site" signal the screen needs — offline-durable, derived from the local
/// event log the same way `timbraStateProvider` derives shift state for personal Timbra.
class CantiereActiveSession {
  const CantiereActiveSession({
    required this.cantiereId,
    required this.customerId,
    this.ticketId,
    required this.startTime,
    this.pendingSync = false,
  });

  final String cantiereId;
  final String? customerId;
  final String? ticketId;
  final DateTime startTime;
  final bool pendingSync;
}

/// The most recent local 'ingresso' with no closing 'uscita' after it, or null.
CantiereActiveSession? deriveLocalActiveCantiereSession(List<CantierePunche> events) {
  CantierePunche? opener;
  for (final e in events) {
    switch (e.eventType) {
      case 'ingresso':
        opener = e;
      case 'uscita':
        opener = null;
    }
  }
  if (opener == null || opener.cantiereId == null) return null;
  return CantiereActiveSession(
    cantiereId: opener.cantiereId!,
    customerId: opener.customerId,
    ticketId: opener.ticketId,
    startTime: opener.eventTime,
    pendingSync: opener.isPendingSync,
  );
}

/// Whether the technician is currently on a cantiere, and since when.
///
/// Local state wins whenever it has an opinion — it is what this device itself just recorded and
/// survives having no signal at all. Only when local has nothing open does this fall back to the
/// last-known server answer, which covers a session started from another device or surface (e.g.
/// the office) with nothing queued locally.
final cantiereActiveSessionProvider = Provider.autoDispose<CantiereActiveSession?>((ref) {
  final localEvents = ref.watch(todayCantiereEventsProvider).valueOrNull ?? [];
  final local = deriveLocalActiveCantiereSession(localEvents);
  if (local != null) return local;

  final serverLog = ref.watch(activeCantiereLogProvider).valueOrNull;
  if (serverLog == null) return null;
  return CantiereActiveSession(
    cantiereId: serverLog.cantiereId,
    customerId: serverLog.customerId,
    ticketId: serverLog.ticketId,
    startTime: _combineWorkDateAndStartTime(serverLog.workDate, serverLog.startTime),
  );
});

/// Crew assignments for a cantiere — GET /api/cantieri/{id}/assegnazioni. Used to derive whether
/// the current user is lead (see [isLeadForCantiereProvider]) and to populate the teammate
/// picker's checkbox list.
///
/// A live fetch-and-derive provider, not a Drift mirror: this concept is new and has no local
/// offline table of its own. Failing (including offline) leaves this provider in `AsyncError`,
/// which [isLeadForCantiereProvider] reads as "not lead" — the explicit single-button fallback per
/// the plan's Global Constraints, not a bug.
final cantiereCrewAssignmentsProvider = FutureProvider.autoDispose
    .family<List<CantiereCrewAssignmentDto>, String>((ref, cantiereId) async {
      final client = ref.watch(cantiereWorklogApiClientProvider);
      return client.getAssegnazioni(cantiereId);
    });

/// Whether the signed-in technician is the lead for the given cantiere, derived from
/// [cantiereCrewAssignmentsProvider].
///
/// False (never null) while loading, on error, or offline — this screen only ever needs a yes/no
/// answer to decide which button set to render, and a lead-only affordance has no business
/// blocking anyone else's — or a temporarily-unreachable lead's — plain single-button clock-in.
final isLeadForCantiereProvider = Provider.autoDispose.family<bool, String>((ref, cantiereId) {
  // The internal database Guid, not currentUserProvider.id (the Zitadel OIDC sub) — assignment
  // rows' userId is the internal Guid, so comparing against the sub never matched anyone.
  final userId = ref.watch(internalUserIdProvider).valueOrNull;
  final assignments = ref.watch(cantiereCrewAssignmentsProvider(cantiereId)).valueOrNull;
  if (userId == null || assignments == null) return false;
  return assignments.any((a) => a.userId == userId && a.isLead);
});

/// Combines a server work log's date-only `workDate` with its `startTime` ("HH:mm:ss") into the
/// actual clock-in instant.
///
/// The fallback used to hand `workDate` itself (midnight) straight to [CantiereActiveSession] as
/// `startTime`, silently dropping the actual time-of-day the backend sent — every displayed
/// ingresso time for a server-only session (no local Drift row) was midnight shifted by the
/// device's UTC offset, not the real check-in time. `.utc(...)`, not the plain constructor: the
/// backend stores/transmits these as UTC, so building a local-naive `DateTime` here would double
/// the offset once the caller's own `.toLocal()` runs.
DateTime _combineWorkDateAndStartTime(DateTime workDate, String startTime) {
  final parts = startTime.split(':');
  final h = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
  final m = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
  final s = int.tryParse(parts.elementAtOrNull(2) ?? '') ?? 0;
  return DateTime.utc(workDate.year, workDate.month, workDate.day, h, m, s);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CantiereTimbraScreen extends ConsumerStatefulWidget {
  const CantiereTimbraScreen({super.key, this.ticketId, this.customerId, this.cantiereId});

  /// The ticket that launched this screen (optional context link).
  final String? ticketId;

  /// The customerId from the ticket (used to pre-filter the cantiere list).
  final String? customerId;

  /// When set, this screen skips its cantiere picker entirely and acts on this cantiere directly
  /// — the entry point from CantiereDetailScreen (and, transitively, the Cantieri tab). `ticketId`
  /// stays honored alongside it when both are present (arrived via the ticket-detail chip), so the
  /// resulting session is still tagged with that ticket.
  final String? cantiereId;

  @override
  ConsumerState<CantiereTimbraScreen> createState() => _CantiereTimbraScreenState();
}

class _CantiereTimbraScreenState extends ConsumerState<CantiereTimbraScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  // ── Progressive-disclosure rich fields (occasional, not every-punch friction) ──
  // Check-in side — mirrors StartCantiereRequest's optional fields.
  String? _description;
  String? _workOrderNumber;
  String? _equipmentUsed;
  int? _teamSize;
  String? _weatherConditions;

  // ── Lead "chi timbra" choice — always-visible three-way pick, lead-only (see isLead). ──
  _ChiTimbra _chiTimbra = _ChiTimbra.io;

  /// Who "Seleziona squadra" resolved to — null before the lead has picked anyone (including
  /// right after choosing that mode, before the picker sheet resolves), non-null and non-empty
  /// once confirmed. Never empty-but-non-null: the picker sheet's own "Conferma" stays disabled
  /// until at least one person is checked (see teammate_picker_sheet.dart), and a dismiss without
  /// confirming resolves to null, not `[]`.
  List<String>? _squadraSelection;

  bool get _hasCheckInDetails =>
      [
        _description,
        _workOrderNumber,
        _equipmentUsed,
        _weatherConditions,
      ].any((v) => v != null && v.isNotEmpty) ||
      _teamSize != null;

  /// The cantiere this screen currently intends to act on.
  ///
  /// Read by both `build()` (for display) and `_handleStartCantiere` (for the actual clock-in)
  /// so the two can never disagree. `ref.read`, not `ref.watch`: `build()` already watches
  /// `cantiereByIdProvider` for itself below, and this getter only needs the cached value, not a
  /// subscription of its own — including when called imperatively from `_handleStartCantiere`,
  /// which must not create a new watch mid-callback. Null when `widget.cantiereId` itself is null
  /// — unreachable through any real navigation today (every caller resolves a cantiereId first;
  /// see this file's own header comment) but kept honest rather than force-unwrapped, so a
  /// malformed deep link reads as "cantiere not found" instead of crashing.
  CantieriData? get _effectiveCantiere => widget.cantiereId == null
      ? null
      : ref.read(cantiereByIdProvider(widget.cantiereId!)).valueOrNull;

  @override
  Widget build(BuildContext context) {
    // A session that ended elsewhere (ChiudiTurnoScreen, pushed from _ActiveSessionBody's end
    // button below) leaves this screen mounted underneath — it never navigates away on its own,
    // matching the old in-place end flow's own behaviour. So the transition back to "no active
    // session" is the one moment to clear this screen's own leftover check-in state, rather than
    // an `_onEndedSuccessfully`-style callback this screen no longer runs itself.
    ref.listen(cantiereActiveSessionProvider, (previous, next) {
      if (previous != null && next == null) {
        setState(() {
          _description = null;
          _workOrderNumber = null;
          _equipmentUsed = null;
          _teamSize = null;
          _weatherConditions = null;
          _chiTimbra = _ChiTimbra.io;
          _squadraSelection = null;
        });
      }
    });

    final localEventsAsync = ref.watch(todayCantiereEventsProvider);
    final active = ref.watch(cantiereActiveSessionProvider);
    final serverLog = ref.watch(activeCantiereLogProvider).valueOrNull;
    final hasPendingSync = ref.watch(cantiereHasPendingSyncProvider);

    // Watched here (not just read via `_effectiveCantiere`) so the screen rebuilds once this
    // resolves — the fixed-cantiere card below also needs its loading/error/not-found states,
    // which the plain `CantieriData?` value alone can't distinguish. `AsyncData(null)` when
    // `widget.cantiereId` itself is null (see `_effectiveCantiere`'s own doc comment) — the
    // check-in body then renders the same "not found" card a real not-yet-synced id would.
    final fixedCantiereAsync = widget.cantiereId != null
        ? ref.watch(cantiereByIdProvider(widget.cantiereId!))
        : const AsyncData<CantieriData?>(null);

    // Only meaningful once a cantiere is resolved — before then there is nothing to be lead *of*,
    // so this reads as "not lead" like any other loading/error case (see
    // isLeadForCantiereProvider's own doc comment).
    final effectiveCantiereId = _effectiveCantiere?.id;
    final isLead = effectiveCantiereId != null
        ? ref.watch(isLeadForCantiereProvider(effectiveCantiereId))
        : false;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(title: 'Timbra cantiere', showBack: true),
            Expanded(
              child: localEventsAsync.hasError
                  ? _ErrorBody(
                      message: 'Impossibile leggere le timbrature cantiere su questo dispositivo.',
                      onRetry: () => ref.invalidate(todayCantiereEventsProvider),
                    )
                  : !localEventsAsync.hasValue
                  ? const Center(child: CircularProgressIndicator())
                  : active != null
                  ? _ActiveSessionBody(
                      local: active,
                      serverLog: serverLog,
                      hasPendingSync: hasPendingSync,
                      onEnd: () => _navigateToChiudiTurno(active, serverLog?.ticketId),
                    )
                  : _CheckInBody(
                      ticketId: widget.ticketId,
                      cantiereId: effectiveCantiereId,
                      fixedCantiereAsync: fixedCantiereAsync,
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      hasDetails: _hasCheckInDetails,
                      isLead: isLead,
                      chiTimbra: _chiTimbra,
                      squadraSelectionCount: _squadraSelection?.length ?? 0,
                      onChiTimbraChanged: _handleChiTimbraChanged,
                      onStart: _primaryStartAction(fixedCantiereAsync),
                      onOpenDetails: _openDetailsSheet,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The primary "Inizia timbratura" button's action for the currently chosen [_chiTimbra] mode —
  /// null (disabled) while loading, while the cantiere hasn't resolved, or while "Seleziona
  /// squadra" is chosen but nobody's been picked yet.
  VoidCallback? _primaryStartAction(AsyncValue<CantieriData?> fixedCantiereAsync) {
    if (_isLoading || fixedCantiereAsync.valueOrNull == null) return null;
    switch (_chiTimbra) {
      case _ChiTimbra.io:
        return _handleStartCantiere;
      case _ChiTimbra.squadra:
        final selection = _squadraSelection;
        if (selection == null || selection.isEmpty) return null;
        return () => _handleBatchStart(selection);
      case _ChiTimbra.tutta:
        return _handleTuttaLaSquadra;
    }
  }

  // ── Progressive disclosure sheets ─────────────────────────────────────────────

  void _openDetailsSheet() {
    openCompartmentSheet(
      context,
      label: 'Altri dettagli',
      content: _CantiereCheckInDetailsForm(
        description: _description,
        workOrderNumber: _workOrderNumber,
        equipmentUsed: _equipmentUsed,
        teamSize: _teamSize,
        weatherConditions: _weatherConditions,
        onDescriptionChanged: (v) => setState(() => _description = v),
        onWorkOrderNumberChanged: (v) => setState(() => _workOrderNumber = v),
        onEquipmentUsedChanged: (v) => setState(() => _equipmentUsed = v),
        onTeamSizeChanged: (v) => setState(() => _teamSize = v),
        onWeatherConditionsChanged: (v) => setState(() => _weatherConditions = v),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Handles a tap on any of the three "chi timbra" pills. Choosing "Seleziona squadra" opens the
  /// crew picker right away — same continuation a tap naturally invites — but the pill itself
  /// stays the persistent record of the chosen mode: a dismiss without confirming leaves the mode
  /// selected with nobody picked yet, which `_primaryStartAction` reads as "disabled" rather than
  /// silently falling back to solo.
  Future<void> _handleChiTimbraChanged(_ChiTimbra mode) async {
    setState(() {
      _chiTimbra = mode;
      if (mode != _ChiTimbra.squadra) _squadraSelection = null;
    });
    if (mode != _ChiTimbra.squadra) return;

    final cantiere = _effectiveCantiere;
    if (cantiere == null) return;
    final assignments = ref.read(cantiereCrewAssignmentsProvider(cantiere.id)).valueOrNull ?? [];
    final selected = await openTeammatePickerSheet(context, assignments: assignments);
    if (!mounted) return;
    setState(() => _squadraSelection = selected);
  }

  Future<void> _handleStartCantiere() async {
    final cantiere = _effectiveCantiere;
    if (cantiere == null) {
      setState(() => _errorMessage = 'Seleziona un cantiere prima di timbrare.');
      return;
    }
    // Asked before the spinner goes up, not underneath it: a system dialog appearing over a
    // half-started clock-in reads as the app malfunctioning, and the technician cannot tell whether
    // their timbratura went through while they decide.
    if (!await confirmGpsPurpose(context, ref)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final customerId = cantiere.customerId ?? widget.customerId ?? '';
    // Fetched once, outside the try/catch below: `LocationService` never throws (see its own doc
    // comment), and both the online call and the offline fallback need the same position.
    final location = await ref.read(locationServiceProvider).getCurrentPosition();

    try {
      final client = ref.read(cantiereWorklogApiClientProvider);
      // Online-first: the only path that carries the full rich-field set (see this file's own
      // header comment).
      await client.startCantiere(
        StartCantiereRequest(
          cantiereId: cantiere.id,
          customerId: customerId,
          ticketId: widget.ticketId,
          description: _description,
          workOrderNumber: _workOrderNumber,
          equipmentUsed: _equipmentUsed,
          teamSize: _teamSize,
          arrivalLatitude: location?.lat,
          arrivalLongitude: location?.lng,
          weatherConditions: _weatherConditions,
        ),
      );
      if (mounted) {
        await ref.read(activeCantiereLogProvider.notifier).refresh();
        setState(() => _isLoading = false);
      }
      // Solo check-in used to leave no feedback at all beyond the screen swapping to the
      // active-session body — the batch-start path already toasts its result (see
      // _handleBatchStart below); this brings the solo path to parity. Folds in a GPS warning
      // rather than staying silent about it when `location` came back null — see this method's
      // own GPS-purpose comment above for why a null position is allowed to proceed at all.
      // Re-checked (not reused from above): the `refresh()` await just ran, so `mounted` needs a
      // fresh read immediately before this `context` use.
      if (mounted) {
        showAppToast(
          context,
          message: location == null
              ? 'Ingresso cantiere registrato senza posizione GPS.'
              : 'Ingresso cantiere registrato con successo.',
          tone: location == null ? ToastTone.warning : ToastTone.success,
        );
      }
    } on DioException catch (e) {
      if (isOfflineFailure(e)) {
        // Not reachable — queue locally instead of failing the punch outright. The batch upsert
        // this syncs through only carries description among the rich fields (see
        // cantiere_worklog_api_client.dart); the rest are captured for the online path only.
        await ref
            .read(cantiereSessionRepositoryProvider)
            .addEvent(
              id: _uuid.v4(),
              eventTime: DateTime.now().toUtc(),
              eventType: 'ingresso',
              cantiereId: cantiere.id,
              customerId: customerId,
              ticketId: widget.ticketId,
              description: _description,
              latitude: location?.lat,
              longitude: location?.lng,
            );
        unawaited(ref.read(cantiereTimbraSyncServiceProvider).syncNow());
        if (mounted) {
          setState(() => _isLoading = false);
          // Contrast: chiudi_turno_screen.dart's equivalent offline clock-out already toasts this
          // — the clock-in side used to stay silent, a real gap for a safety/payroll-relevant
          // record that a technician has no other way of knowing was captured only locally.
          showAppToast(
            context,
            message: location == null
                ? 'Ingresso registrato offline e senza posizione GPS: verrà inviato al ritorno '
                      'della connessione.'
                : 'Ingresso registrato offline: verrà inviato al ritorno della connessione.',
            tone: ToastTone.warning,
          );
        }
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = cantiereNetworkErrorMessage(e);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Errore imprevisto. Riprova.';
        });
      }
    }
  }

  /// "Tutta la squadra" — batch-starts every person this cantiere has an assignment row for
  /// (lead included, since the lead is themselves assigned).
  Future<void> _handleTuttaLaSquadra() async {
    final cantiere = _effectiveCantiere;
    if (cantiere == null) return;
    final assignments = ref.read(cantiereCrewAssignmentsProvider(cantiere.id)).valueOrNull ?? [];
    if (assignments.isEmpty) return;
    await _handleBatchStart(assignments.map((a) => a.userId).toList());
  }

  /// Shared batch-start call for both "Seleziona squadra" and "Tutta la squadra" — mirrors
  /// [_handleStartCantiere]'s shape (GPS purpose confirmation, spinner, rich fields) but has no
  /// offline fallback: batch-start is online-only per the plan's Global Constraints, so a
  /// connection failure here surfaces as an error rather than queueing locally.
  Future<void> _handleBatchStart(List<String> userIds) async {
    final cantiere = _effectiveCantiere;
    if (cantiere == null) {
      setState(() => _errorMessage = 'Seleziona un cantiere prima di timbrare.');
      return;
    }
    if (!await confirmGpsPurpose(context, ref)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final customerId = cantiere.customerId ?? widget.customerId ?? '';
    final location = await ref.read(locationServiceProvider).getCurrentPosition();

    try {
      final client = ref.read(cantiereWorklogApiClientProvider);
      final response = await client.batchStart(
        BatchStartCantiereRequest(
          cantiereId: cantiere.id,
          customerId: customerId,
          userIds: userIds,
          description: _description,
          workOrderNumber: _workOrderNumber,
          equipmentUsed: _equipmentUsed,
          teamSize: _teamSize,
          arrivalLatitude: location?.lat,
          arrivalLongitude: location?.lng,
          weatherConditions: _weatherConditions,
        ),
      );
      if (!mounted) return;
      await ref.read(activeCantiereLogProvider.notifier).refresh();
      setState(() => _isLoading = false);
      // The lead's own screen state doesn't change on a teammates-only batch, so without this a
      // fully successful batch was indistinguishable from nothing happening at all. Shown
      // regardless of whether some people also failed — alongside the failures dialog below, not
      // instead of it — so the lead always gets a count of what worked, not just what didn't.
      final successCount = response.results.where((r) => r.success).length;
      if (mounted) {
        final baseMessage = successCount == 1
            ? 'Timbrata 1 persona'
            : 'Timbrate $successCount persone';
        // Same GPS-null note _handleStartCantiere's own toast carries — the batch call shares one
        // position fetch for the whole crew, so a missing fix is worth surfacing here too.
        showAppToast(
          context,
          message: location == null ? '$baseMessage (senza posizione GPS)' : baseMessage,
          tone: location == null ? ToastTone.warning : ToastTone.success,
        );
      }
      final failures = response.results.where((r) => !r.success).toList();
      if (failures.isNotEmpty && mounted) _showBatchFailuresDialog(failures);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = cantiereNetworkErrorMessage(e);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Errore imprevisto. Riprova.';
        });
      }
    }
  }

  /// Names every offender rather than silently dropping a person or failing the whole batch —
  /// mirrors the endpoint's own "name every offender" contract. Deliberately a plain dialog, not a
  /// new bespoke widget: a handful of "name: reason" lines is the whole of what this needs.
  void _showBatchFailuresDialog(List<BatchStartResult> failures) {
    showDialog<void>(
      context: context,
      // Vetro chrome, not a stock AlertDialog — same AppCard shell as the rest of the app's
      // dialogs (see altro_hub_screen.dart's logout confirmation). Still scrollable: a large
      // crew (or large accessibility text scaling) can overflow a plain min-size Column.
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alcuni membri non sono stati avviati',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ctx.colors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: failures.map((f) {
                      final reason = switch (f.error) {
                        'AlreadyOpen' => 'ha già una timbratura aperta',
                        'NotAssigned' => 'non risulta assegnato a questo cantiere',
                        _ => 'errore sconosciuto',
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        // A plain `showDialog` builder never rebuilds on its own, so
                        // `colleagueNameProvider` — a StreamProvider backed by a Drift
                        // watchSingleOrNull() query that resolves asynchronously — must be
                        // watched from a Consumer scoped to just this row, not read once from
                        // the enclosing method. `ref.read` here would capture whatever the
                        // provider's state happened to be at that exact instant (almost always
                        // still loading) and never update. Same fallback contract as everywhere
                        // else colleagueNameProvider is read (see teammate_picker_sheet.dart).
                        child: Consumer(
                          builder: (context, ref, _) {
                            final name =
                                ref.watch(colleagueNameProvider(f.userId)).valueOrNull ??
                                f.userId;
                            return Text(
                              '$name: $reason',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: ctx.colors.ink),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(label: 'OK', onPressed: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      ),
    );
  }

  /// Pushes ChiudiTurnoScreen — the end-of-session summary/closing-notes/confirm flow that
  /// replaced this button calling `_handleEndCantiere` directly in place. A plain
  /// `Navigator.push`, not a go_router route: this screen is reachable only from an active
  /// cantiere session (never deep-linked to on its own), the same reasoning
  /// `attachment_viewer.dart`'s fullscreen image viewer already uses for the same kind of
  /// in-flow-only screen. `active`/`ticketId` are captured at the moment of the tap (from this
  /// screen's own already-watched `cantiereActiveSessionProvider`/`activeCantiereLogProvider`),
  /// so ChiudiTurnoScreen doesn't need to re-derive "am I on site" for itself — it just acts on
  /// the session it was handed.
  void _navigateToChiudiTurno(CantiereActiveSession active, String? ticketId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChiudiTurnoScreen(
          cantiereId: active.cantiereId,
          ticketId: ticketId,
          startTime: active.startTime,
        ),
      ),
    );
  }
}

// ── Shared check-in/check-out helpers ────────────────────────────────────────
//
// Used by both this screen's check-in side and ChiudiTurnoScreen's own end-of-session flow —
// pulled out of _CantiereTimbraScreenState (where they used to be private instance methods) so
// neither screen has to reimplement the GPS-purpose gating, offline-fallback detection, or error
// humanising the check-in side already had right.

/// States what the coordinates are for, before the OS asks for them.
///
/// Returns false only when the technician declines the *explanation*. Declining here cancels the
/// timbratura rather than clocking in without a position, because on a cantiere the arrival and
/// departure coordinates are the point: a site presence record with no location is not the same
/// record, and silently downgrading it would hide that from both the technician and the office.
///
/// Returns true when no dialog would appear at all — permission already held, already refused
/// permanently, or the setting turned off. In those cases the existing null-position path is the
/// honest one and there is nothing to explain.
Future<bool> confirmGpsPurpose(BuildContext context, WidgetRef ref) async {
  if (!await ref.read(locationServiceProvider).willPromptForPermission()) return true;
  if (!context.mounted) return false;

  return askPermissionPurpose(
    context,
    icon: LucideIcons.mapPin,
    titolo: 'Timbratura di cantiere',
    motivo:
        'Registriamo dove sei quando entri e quando esci dal cantiere. Serve a dimostrare la '
        'tua presenza in cantiere, per la sicurezza e per le ore. Due punti, non un percorso.',
    senzaDiEsso:
        'Senza posizione la timbratura di cantiere non viene registrata. La timbratura normale '
        'della giornata, nella scheda Timbra, funziona senza GPS.',
    cta: 'Consenti la posizione',
  );
}

/// A network error the device cannot reach the server to answer — as opposed to one the server
/// answered (a conflict, a lock), which must surface rather than fall back to a local queue.
bool isOfflineFailure(DioException e) {
  final status = e.response?.statusCode;
  return status == null ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError;
}

String cantiereNetworkErrorMessage(DioException e) {
  final status = e.response?.statusCode;
  if (status == 400) {
    return 'Esiste già una sessione cantiere attiva. Chiudila prima.';
  }
  if (status == 404) {
    return 'Nessuna sessione cantiere attiva trovata.';
  }
  // A 403 the backend tagged specifically "NotAssigned" (same error-code field/value the
  // batch-start response uses for the analogous per-person check — see BatchStartResult.error)
  // reads to a technician as "you lack a permission", but the actual fact is narrower and more
  // useful: they're just not on this cantiere's crew. Anything else still falls through to the
  // shared humaniser's generic permission-denied copy below.
  if (status == 403 && cantiereErrorCode(e) == 'NotAssigned') {
    return 'Non risulti assegnato a questo cantiere. Chiedi in ufficio.';
  }
  // Everything else goes through the shared humaniser. This used to end in
  // `Errore server ($status)` — a number the technician cannot use, in the one line telling
  // them their presence on site was not recorded.
  return humanErrorMessage(e);
}

/// The backend's own error code from a JSON error body, when present — e.g. `"NotAssigned"`.
String? cantiereErrorCode(DioException e) {
  final data = e.response?.data;
  return data is Map ? data['error'] as String? : null;
}

/// The lead's "who am I timbrando for" choice — an always-visible three-way pick (see
/// _CheckInBody's own segmented-pill UI), replacing the old "Per: Me ▾" popup menu.
enum _ChiTimbra { io, squadra, tutta }

// ── _CheckInBody ──────────────────────────────────────────────────────────────

class _CheckInBody extends ConsumerWidget {
  const _CheckInBody({
    required this.ticketId,
    required this.cantiereId,
    required this.fixedCantiereAsync,
    required this.isLoading,
    required this.errorMessage,
    required this.hasDetails,
    required this.isLead,
    required this.chiTimbra,
    required this.squadraSelectionCount,
    required this.onChiTimbraChanged,
    required this.onStart,
    required this.onOpenDetails,
  });

  final String? ticketId;

  /// The resolved cantiere's id, or null when `widget.cantiereId` itself is null (see
  /// `_effectiveCantiere`'s own doc comment). Feeds the "OGGI" header's
  /// `cantiereTodayHoursProvider` watch — null shows a static "0h 00m" with no provider call.
  final String? cantiereId;

  /// The fixed cantiere's own load state. Every real entry into this screen resolves a cantiereId
  /// before arriving (see this file's own header comment) — this is `AsyncData(null)` rather than
  /// a nullable `AsyncValue?` precisely so that invariant needs no separate "was there ever a
  /// cantiere to look up" branch here: a missing/not-yet-synced cantiere and a not-yet-resolved
  /// one render through the exact same "not found" card below.
  final AsyncValue<CantieriData?> fixedCantiereAsync;
  final bool isLoading;
  final String? errorMessage;
  final bool hasDetails;

  /// Whether the current user is the lead on the resolved cantiere — gates the "chi timbra" pills
  /// below the main button. False while no cantiere is resolved yet, on fetch error, or offline
  /// (see isLeadForCantiereProvider) — the explicit fallback to the plain single-button flow.
  final bool isLead;

  /// The lead's currently chosen "chi timbra" mode (meaningless, and not rendered, when
  /// `!isLead`).
  final _ChiTimbra chiTimbra;

  /// How many teammates "Seleziona squadra" currently resolves to — 0 both before anyone's been
  /// picked and right after choosing the mode (see `_handleChiTimbraChanged`'s own doc comment).
  /// Drives the inline "nobody selected" hint; the primary button's own disablement is computed
  /// by the parent (see `onStart` being null already covering it).
  final int squadraSelectionCount;
  final ValueChanged<_ChiTimbra> onChiTimbraChanged;

  /// Null disables the primary button — already accounts for `isLoading`, an unresolved cantiere,
  /// and (in `_ChiTimbra.squadra` mode) nobody picked yet. See `_primaryStartAction`.
  final VoidCallback? onStart;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayHours = cantiereId != null
        ? ref.watch(cantiereTodayHoursProvider(cantiereId!))
        : Duration.zero;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "OGGI" header — plain text hierarchy, not another elevated card, per the redesign's
          // own stated reasoning: stacking a card onto an already-card-heavy screen would just be
          // clutter restyled, not clutter removed.
          Text(
            'OGGI',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatHoursMinutes(todayHours),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: context.colors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: context.colors.borderLight, height: 1),
          const SizedBox(height: 16),

          // Context banner (linked ticket)
          if (ticketId != null) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.link, size: 16, color: context.colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collegato al ticket',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          AppCard(
            child: fixedCantiereAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.base),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                child: Text(
                  'Impossibile caricare il cantiere.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: context.colors.red),
                ),
              ),
              data: (c) => c == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                      child: Text(
                        'Cantiere non trovato su questo dispositivo.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: context.colors.red,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.hardHat, size: 18, color: context.colors.ink),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c.name,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const GpsStatusIndicator(),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          if (errorMessage != null) ...[
            TimbraErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          if (isLead) ...[
            Text(
              'Per chi registri l\'ingresso?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ChiTimbraPill(
                  label: 'Solo io',
                  selected: chiTimbra == _ChiTimbra.io,
                  onTap: isLoading ? null : () => onChiTimbraChanged(_ChiTimbra.io),
                ),
                const SizedBox(width: 8),
                _ChiTimbraPill(
                  label: 'Seleziona squadra',
                  selected: chiTimbra == _ChiTimbra.squadra,
                  onTap: isLoading ? null : () => onChiTimbraChanged(_ChiTimbra.squadra),
                ),
                const SizedBox(width: 8),
                _ChiTimbraPill(
                  label: 'Tutta la squadra',
                  selected: chiTimbra == _ChiTimbra.tutta,
                  onTap: isLoading ? null : () => onChiTimbraChanged(_ChiTimbra.tutta),
                ),
              ],
            ),
            if (chiTimbra == _ChiTimbra.squadra && squadraSelectionCount == 0) ...[
              const SizedBox(height: 6),
              Text(
                'Scegli almeno una persona per avviare la timbratura.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.amber),
              ),
            ] else if (chiTimbra == _ChiTimbra.squadra) ...[
              const SizedBox(height: 6),
              Text(
                squadraSelectionCount == 1
                    ? '1 persona selezionata'
                    : '$squadraSelectionCount persone selezionate',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: context.colors.inkMuted,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],

          AppButton(
            label: 'Inizia timbratura',
            icon: const Icon(LucideIcons.mapPin),
            isLoading: isLoading,
            onPressed: onStart,
          ),

          const SizedBox(height: 16),

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: AppTappable(
                onTap: onOpenDetails,
                borderRadius: AppRack.insetShape,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.base,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasDetails ? LucideIcons.checkCircle2 : LucideIcons.plus,
                      size: 14,
                      color: hasDetails ? context.colors.green : context.colors.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasDetails ? 'Altri dettagli aggiunti' : 'Altri dettagli',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasDetails ? context.colors.green : context.colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pill of the lead's "chi timbra" three-way choice — replaces the old "Per: Me ▾" popup
/// menu with an always-visible pick, matching this screen's existing selected-row visual language
/// (the brand accent at low alpha — see the old cantiere picker row / teammate picker row this
/// screen and `teammate_picker_sheet.dart` already used the same treatment for).
class _ChiTimbraPill extends StatelessWidget {
  const _ChiTimbraPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppTappable(
        onTap: onTap,
        color: selected ? AppColors.Y.withAlpha(31) : Colors.transparent,
        border: Border.all(color: selected ? AppColors.Y : context.colors.borderLight),
        borderRadius: AppRack.insetShape,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.Y : context.colors.inkMuted,
          ),
        ),
      ),
    );
  }
}

// ── Progressive-disclosure forms ─────────────────────────────────────────────

/// The rich, occasional check-in fields — StartCantiereRequest's optional set beyond the
/// cantiere picker + auto-captured GPS. Reached via a small secondary affordance, never inline
/// in the primary flow (see this file's header comment and PRODUCT.md's outdoor-use scene).
class _CantiereCheckInDetailsForm extends StatefulWidget {
  const _CantiereCheckInDetailsForm({
    required this.description,
    required this.workOrderNumber,
    required this.equipmentUsed,
    required this.teamSize,
    required this.weatherConditions,
    required this.onDescriptionChanged,
    required this.onWorkOrderNumberChanged,
    required this.onEquipmentUsedChanged,
    required this.onTeamSizeChanged,
    required this.onWeatherConditionsChanged,
  });

  final String? description;
  final String? workOrderNumber;
  final String? equipmentUsed;
  final int? teamSize;
  final String? weatherConditions;
  final ValueChanged<String?> onDescriptionChanged;
  final ValueChanged<String?> onWorkOrderNumberChanged;
  final ValueChanged<String?> onEquipmentUsedChanged;
  final ValueChanged<int?> onTeamSizeChanged;
  final ValueChanged<String?> onWeatherConditionsChanged;

  @override
  State<_CantiereCheckInDetailsForm> createState() => _CantiereCheckInDetailsFormState();
}

class _CantiereCheckInDetailsFormState extends State<_CantiereCheckInDetailsForm> {
  late final _descriptionCtrl = TextEditingController(text: widget.description);
  late final _workOrderCtrl = TextEditingController(text: widget.workOrderNumber);
  late final _equipmentCtrl = TextEditingController(text: widget.equipmentUsed);
  late final _teamSizeCtrl = TextEditingController(text: widget.teamSize?.toString() ?? '');
  late final _weatherCtrl = TextEditingController(text: widget.weatherConditions);

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _workOrderCtrl.dispose();
    _equipmentCtrl.dispose();
    _teamSizeCtrl.dispose();
    _weatherCtrl.dispose();
    super.dispose();
  }

  String? _blankToNull(String v) => v.trim().isEmpty ? null : v.trim();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField.multiline(
            label: 'Descrizione del lavoro',
            hint: 'Cosa farai in cantiere…',
            controller: _descriptionCtrl,
            maxLines: 3,
            onChanged: (v) => widget.onDescriptionChanged(_blankToNull(v)),
          ),
          const SizedBox(height: AppSpacing.base),
          AppTextField(
            label: 'N° ordine di lavoro',
            controller: _workOrderCtrl,
            onChanged: (v) => widget.onWorkOrderNumberChanged(_blankToNull(v)),
          ),
          const SizedBox(height: AppSpacing.base),
          AppTextField(
            label: 'Attrezzatura utilizzata',
            controller: _equipmentCtrl,
            onChanged: (v) => widget.onEquipmentUsedChanged(_blankToNull(v)),
          ),
          const SizedBox(height: AppSpacing.base),
          AppTextField(
            label: 'Squadra (n. persone)',
            controller: _teamSizeCtrl,
            keyboardType: TextInputType.number,
            onChanged: (v) => widget.onTeamSizeChanged(int.tryParse(v.trim())),
          ),
          const SizedBox(height: AppSpacing.base),
          AppTextField(
            label: 'Condizioni meteo',
            controller: _weatherCtrl,
            onChanged: (v) => widget.onWeatherConditionsChanged(_blankToNull(v)),
          ),
        ],
      ),
    );
  }
}

// ── _ActiveSessionBody ────────────────────────────────────────────────────────
//
// The closing fields (Lavoro svolto / Note di sicurezza) used to live here as
// `_CantiereClosingDetailsForm`, reached via a small "Note di chiusura" text-link affordance and
// a bottom sheet. They now live directly on ChiudiTurnoScreen instead — always visible, not
// hidden behind a secondary link — which this body's own end button navigates to. See
// ChiudiTurnoScreen's own header comment.

class _ActiveSessionBody extends ConsumerWidget {
  const _ActiveSessionBody({
    required this.local,
    required this.serverLog,
    required this.hasPendingSync,
    required this.onEnd,
  });

  final CantiereActiveSession local;
  final CantiereWorkLogDto? serverLog;
  final bool hasPendingSync;

  /// Pushes ChiudiTurnoScreen — a plain navigation, not the end-of-session call itself (see
  /// ChiudiTurnoScreen's own header comment), so there is no loading/error state to show here.
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketId = serverLog?.ticketId ?? local.ticketId;
    final ticketLabel = ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(ticketId)).valueOrNull?.title;

    final closedTodayHours = ref.watch(cantiereTodayHoursProvider(local.cantiereId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "OGGI" header — same visual continuity as the check-in body, with the live-ticking
          // current-session elapsed folded into the total once it starts. Watching
          // cantiereTodayHoursProvider (closed intervals only) here, then adding the ticker's own
          // live elapsed separately, keeps the "closed sum" and "live tick" concerns apart the
          // same way they're computed apart.
          Text(
            'OGGI',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          _CantiereTodayTotal(closedHours: closedTodayHours, sessionStart: local.startTime),
          const SizedBox(height: 16),
          Divider(color: context.colors.borderLight, height: 1),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Text(
                  'TIMBRATURA ATTIVA',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: context.vetro.statusGood,
                  ),
                ),
              ),
              if (hasPendingSync)
                Tooltip(
                  message: 'Non sincronizzata',
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: context.colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ticketLabel != null
                ? '${_cantiereNameFor(ref, local.cantiereId)} · $ticketLabel'
                : _cantiereNameFor(ref, local.cantiereId),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: _CantiereElapsedTicker(
              startTime: local.startTime,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: context.colors.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),

          const SizedBox(height: 16),

          AppButton.danger(
            label: 'Timbra uscita cantiere',
            icon: const Icon(LucideIcons.logOut),
            onPressed: onEnd,
          ),
        ],
      ),
    );
  }
}

// ── TimbraErrorBanner ────────────────────────────────────────────────────────

/// Shared inline error banner for the cantiere check-in/check-out flow — public (not the usual
/// private `_Foo` for a file-local widget) so `ChiudiTurnoScreen`'s own end-of-session form can
/// reuse it instead of hand-duplicating the same red box (which is exactly what it used to do —
/// see that file's own `_errorMessage` rendering).
class TimbraErrorBanner extends StatelessWidget {
  const TimbraErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: context.colors.redSoft, borderRadius: AppRack.insetShape),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: context.colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _ErrorBody ────────────────────────────────────────────────────────────────
//
// For a genuine local-database failure only — not for the server being unreachable, which the
// offline-first flow above absorbs. See build()'s `localEventsAsync.hasError` branch.

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wifiOff, size: 48, color: context.colors.inkMuted),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.ink,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton.secondary(label: 'Riprova', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
