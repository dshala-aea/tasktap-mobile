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
// VETRO (2026-08-26, module #1) — this screen flips light/dark (`context.colors.bg2`), unlike
// personal Timbra's permanently-dark ground, so it reads `context.vetro` rather than the fixed
// `AppVetroColors`. Re-skinned so far: the cantiere picker (VetroCard) and the primary clock-in/
// clock-out actions (VetroButton). `AppCard`/`AppButton` call sites elsewhere on this screen —
// the progressive-disclosure detail forms — are next, not yet touched.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/utils/error_message.dart';
import '../../core/widgets/vetro_button.dart';
import '../../core/widgets/vetro_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/timbratura/cantiere_timbra_sync_service.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/schedule_providers.dart';
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
  const CantiereTimbraScreen({super.key, this.ticketId, this.customerId});

  /// The ticket that launched this screen (optional context link).
  final String? ticketId;

  /// The customerId from the ticket (used to pre-filter the cantiere list).
  final String? customerId;

  @override
  ConsumerState<CantiereTimbraScreen> createState() => _CantiereTimbraScreenState();
}

class _CantiereTimbraScreenState extends ConsumerState<CantiereTimbraScreen> {
  CantieriData? _selectedCantiere;
  bool _isLoading = false;
  String? _errorMessage;

  // ── Progressive-disclosure rich fields (occasional, not every-punch friction) ──
  // Check-in side — mirrors StartCantiereRequest's optional fields.
  String? _description;
  String? _workOrderNumber;
  String? _equipmentUsed;
  int? _teamSize;
  String? _weatherConditions;

  // Check-out side — mirrors EndCantiereRequest's optional fields.
  String? _closingDescription;
  String? _safetyNotes;

  bool get _hasCheckInDetails =>
      [
        _description,
        _workOrderNumber,
        _equipmentUsed,
        _weatherConditions,
      ].any((v) => v != null && v.isNotEmpty) ||
      _teamSize != null;

  bool get _hasClosingDetails =>
      [_closingDescription, _safetyNotes].any((v) => v != null && v.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final cantieriAsync = ref.watch(cantieriProvider);
    final localEventsAsync = ref.watch(todayCantiereEventsProvider);
    final active = ref.watch(cantiereActiveSessionProvider);
    final serverLog = ref.watch(activeCantiereLogProvider).valueOrNull;
    final hasPendingSync = ref.watch(cantiereHasPendingSyncProvider);

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
                      hasClosingDetails: _hasClosingDetails,
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      onEnd: _handleEndCantiere,
                      onOpenClosingDetails: _openClosingDetailsSheet,
                    )
                  : _CheckInBody(
                      customerId: widget.customerId,
                      ticketId: widget.ticketId,
                      cantieriAsync: cantieriAsync,
                      selectedCantiere: _selectedCantiere,
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      hasDetails: _hasCheckInDetails,
                      onCantiereSelected: (c) => setState(() => _selectedCantiere = c),
                      onStart: _handleStartCantiere,
                      onOpenDetails: _openDetailsSheet,
                    ),
            ),
          ],
        ),
      ),
    );
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

  void _openClosingDetailsSheet() {
    openCompartmentSheet(
      context,
      label: 'Note di chiusura',
      content: _CantiereClosingDetailsForm(
        description: _closingDescription,
        safetyNotes: _safetyNotes,
        onDescriptionChanged: (v) => setState(() => _closingDescription = v),
        onSafetyNotesChanged: (v) => setState(() => _safetyNotes = v),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _handleStartCantiere() async {
    final cantiere = _selectedCantiere;
    if (cantiere == null) {
      setState(() => _errorMessage = 'Seleziona un cantiere prima di timbrare.');
      return;
    }
    // Asked before the spinner goes up, not underneath it: a system dialog appearing over a
    // half-started clock-in reads as the app malfunctioning, and the technician cannot tell whether
    // their timbratura went through while they decide.
    if (!await _confirmGpsPurpose()) return;

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
    } on DioException catch (e) {
      if (_isOfflineFailure(e)) {
        // Not reachable — queue locally instead of failing the punch outright. The batch upsert
        // this syncs through only carries description among the rich fields (see
        // cantiere_worklog_api_client.dart); the rest are captured for the online path only.
        await ref.read(cantiereSessionRepositoryProvider).addEvent(
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
        if (mounted) setState(() => _isLoading = false);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _networkErrorMessage(e);
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

  Future<void> _handleEndCantiere() async {
    if (!await _confirmGpsPurpose()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final location = await ref.read(locationServiceProvider).getCurrentPosition();
      final client = ref.read(cantiereWorklogApiClientProvider);
      await client.endCantiere(
        EndCantiereRequest(
          description: _closingDescription,
          departureLatitude: location?.lat,
          departureLongitude: location?.lng,
          safetyNotes: _safetyNotes,
        ),
      );
      _onEndedSuccessfully(offline: false);
    } on DioException catch (e) {
      if (_isOfflineFailure(e)) {
        await ref.read(cantiereSessionRepositoryProvider).addEvent(
          id: _uuid.v4(),
          eventTime: DateTime.now().toUtc(),
          eventType: 'uscita',
          description: _closingDescription,
        );
        unawaited(ref.read(cantiereTimbraSyncServiceProvider).syncNow());
        _onEndedSuccessfully(offline: true);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _networkErrorMessage(e);
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

  void _onEndedSuccessfully({required bool offline}) {
    if (!mounted) return;
    // The stale server-cached "active" answer must not resurface a session this device just
    // recorded the end of — see cantiereActiveSessionProvider's own doc comment on why local
    // takes priority only when it has something open.
    ref.read(activeCantiereLogProvider.notifier).clearActive();
    setState(() {
      _isLoading = false;
      _selectedCantiere = null;
      _closingDescription = null;
      _safetyNotes = null;
    });
    showAppToast(
      context,
      message: offline
          ? 'Uscita registrata offline: verrà inviata al ritorno della connessione.'
          : 'Uscita cantiere registrata con successo.',
      tone: offline ? ToastTone.warning : ToastTone.success,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

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
  Future<bool> _confirmGpsPurpose() async {
    if (!await ref.read(locationServiceProvider).willPromptForPermission()) return true;
    if (!mounted) return false;

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
  bool _isOfflineFailure(DioException e) {
    final status = e.response?.statusCode;
    return status == null ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  String _networkErrorMessage(DioException e) {
    final status = e.response?.statusCode;
    if (status == 400) {
      return 'Esiste già una sessione cantiere attiva. Chiudila prima.';
    }
    if (status == 404) {
      return 'Nessuna sessione cantiere attiva trovata.';
    }
    // Everything else goes through the shared humaniser. This used to end in
    // `Errore server ($status)` — a number the technician cannot use, in the one line telling
    // them their presence on site was not recorded.
    return humanErrorMessage(e);
  }
}

// ── _CheckInBody ──────────────────────────────────────────────────────────────

class _CheckInBody extends StatelessWidget {
  const _CheckInBody({
    required this.customerId,
    required this.ticketId,
    required this.cantieriAsync,
    required this.selectedCantiere,
    required this.isLoading,
    required this.errorMessage,
    required this.hasDetails,
    required this.onCantiereSelected,
    required this.onStart,
    required this.onOpenDetails,
  });

  final String? customerId;
  final String? ticketId;
  final AsyncValue<List<CantieriData>> cantieriAsync;
  final CantieriData? selectedCantiere;
  final bool isLoading;
  final String? errorMessage;
  final bool hasDetails;
  final ValueChanged<CantieriData?> onCantiereSelected;
  final VoidCallback onStart;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    // The picker reads the local Drift mirror `SyncService` keeps warm (see cantieriProvider's own
    // doc comment) — once the stream has emitted at least once, an empty list means this tenant has
    // no active cantieri synced to this device yet, not that the feature is unimplemented.
    final cantieriValue = cantieriAsync.valueOrNull;
    final noCantieriAvailable = cantieriValue != null && cantieriValue.isEmpty;

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
          // Context banner (linked ticket)
          if (ticketId != null) ...[
            VetroCard(
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

          // Section header
          Text(
            'Seleziona cantiere',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),

          cantieriAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              child: Text(
                'Impossibile caricare i cantieri.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: context.colors.red),
              ),
            ),
            data: (cantieri) {
              // Prefer cantieri matching the ticket's customerId.
              final preferred = customerId != null
                  ? cantieri.where((c) => c.customerId == customerId).toList()
                  : <CantieriData>[];
              final others = cantieri.where((c) => !preferred.contains(c)).toList();
              final ordered = [...preferred, ...others];

              if (ordered.isEmpty) {
                return const UnavailableState(
                  icon: LucideIcons.hardHat,
                  titolo: 'Nessun cantiere disponibile',
                  motivo:
                      'Non risultano cantieri attivi sincronizzati su questo dispositivo. Se ne '
                      'è stato creato uno di recente, apri una qualsiasi scheda e trascina in '
                      'basso per aggiornare, oppure riprova tra poco.',
                );
              }

              final v = context.vetro;
              return VetroCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: ordered.asMap().entries.map((entry) {
                    final i = entry.key;
                    final c = entry.value;
                    final isSelected = selectedCantiere?.id == c.id;
                    final isLast = i == ordered.length - 1;

                    return InkWell(
                      onTap: () => onCantiereSelected(c),
                      borderRadius: i == 0
                          ? const BorderRadius.vertical(top: Radius.circular(20))
                          : (isLast
                                ? const BorderRadius.vertical(bottom: Radius.circular(20))
                                : BorderRadius.zero),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          // Vetro's one accent for "selected", not AppColors.YSoft — the tint at
                          // low alpha reads as the same "strapped/active" idea Cassetta's YSoft
                          // signalled, in the new system's own colour.
                          color: isSelected ? v.tint.withAlpha(31) : Colors.transparent,
                          border: isLast ? null : Border(bottom: BorderSide(color: v.hairline)),
                        ),
                        child: Row(
                          children: [
                            const RowIconTile(icon: LucideIcons.hardHat),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.colors.ink,
                                    ),
                                  ),
                                  if (c.city != null && c.city!.isNotEmpty)
                                    Text(
                                      c.city!,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: context.colors.inkMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected) Icon(LucideIcons.checkCircle2, size: 18, color: v.tint),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Progressive disclosure: occasional/optional fields, off the primary flow.
          Center(
            child: ConstrainedBox(
              // A 48dp floor, not padding alone: the visible content (a 14px icon + 13px text)
              // is much smaller than Android's touch-target minimum — same reasoning as
              // HeaderIconBtn's box around its own smaller visible disc.
              constraints: const BoxConstraints(minHeight: 48),
              child: AppTappable(
                onTap: onOpenDetails,
                borderRadius: AppRack.insetShape,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
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

          const SizedBox(height: 16),

          // Error message
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          // Clock-in button — disabled (not hidden) when there is nothing to
          // select, so the reason above stays visible instead of the row
          // just disappearing.
          VetroButton(
            label: 'Timbra ingresso cantiere',
            icon: const Icon(LucideIcons.mapPin),
            isLoading: isLoading,
            onPressed: (isLoading || noCantieriAvailable) ? null : onStart,
          ),
        ],
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

/// The rich, occasional closing fields — EndCantiereRequest's optional set beyond the
/// auto-captured departure GPS.
class _CantiereClosingDetailsForm extends StatefulWidget {
  const _CantiereClosingDetailsForm({
    required this.description,
    required this.safetyNotes,
    required this.onDescriptionChanged,
    required this.onSafetyNotesChanged,
  });

  final String? description;
  final String? safetyNotes;
  final ValueChanged<String?> onDescriptionChanged;
  final ValueChanged<String?> onSafetyNotesChanged;

  @override
  State<_CantiereClosingDetailsForm> createState() => _CantiereClosingDetailsFormState();
}

class _CantiereClosingDetailsFormState extends State<_CantiereClosingDetailsForm> {
  late final _descriptionCtrl = TextEditingController(text: widget.description);
  late final _safetyNotesCtrl = TextEditingController(text: widget.safetyNotes);

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _safetyNotesCtrl.dispose();
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
            label: 'Lavoro svolto',
            hint: 'Cosa hai fatto in cantiere…',
            controller: _descriptionCtrl,
            maxLines: 3,
            onChanged: (v) => widget.onDescriptionChanged(_blankToNull(v)),
          ),
          const SizedBox(height: AppSpacing.base),
          AppTextField.multiline(
            label: 'Note di sicurezza',
            hint: 'Eventuali anomalie o incidenti…',
            controller: _safetyNotesCtrl,
            maxLines: 3,
            onChanged: (v) => widget.onSafetyNotesChanged(_blankToNull(v)),
          ),
        ],
      ),
    );
  }
}

// ── _ActiveSessionBody ────────────────────────────────────────────────────────

class _ActiveSessionBody extends ConsumerWidget {
  const _ActiveSessionBody({
    required this.local,
    required this.serverLog,
    required this.hasPendingSync,
    required this.hasClosingDetails,
    required this.isLoading,
    required this.errorMessage,
    required this.onEnd,
    required this.onOpenClosingDetails,
  });

  final CantiereActiveSession local;
  final CantiereWorkLogDto? serverLog;
  final bool hasPendingSync;
  final bool hasClosingDetails;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onEnd;
  final VoidCallback onOpenClosingDetails;

  /// "Xh Ym" — no seconds, matching personal Timbra's own [_HeroStatus] elapsed reading. Not
  /// live-ticking: recomputed on rebuild only, same non-ticking choice as personal Timbra's
  /// (a number that changes a few times an hour does not need to visibly age in real time).
  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = DateFormat('dd/MM/yyyy', 'it').format(local.startTime.toLocal());
    // Not serverLog.startTime.substring(0, 5) — that's a raw "HH:mm:ss" backend string with no
    // timezone conversion possible on a String, and the backend stores/transmits it as UTC. local
    // carries the same instant as a proper DateTime, so .toLocal() applies correctly.
    final startLabel = DateFormat('HH:mm').format(local.startTime.toLocal());

    // The session carries a ticket id and nothing else, so the row used to read `#3f2a1c8e`.
    // Resolved against the local mirror to the job's own name — which is what the technician is
    // standing in front of — and dropped entirely when the mirror does not hold it, rather than
    // printing the id back at them.
    final ticketId = serverLog?.ticketId ?? local.ticketId;
    final ticketLabel = ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(ticketId)).valueOrNull?.title;

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
          // Active session card
          //
          // Status-first hero (2026-08-30, matches personal Timbra's own hero restructuring):
          // the elapsed-since-check-in reading is now the largest thing on the card — what a
          // technician glances at this screen to answer is "how long have I been on site," the
          // same question the personal screen's own hero answers. Uses the flipping
          // `context.vetro` status tokens (not the fixed AppVetroColors pair personal Timbra
          // uses) because this card, unlike personal Timbra's permanently-dark ground, is on
          // this screen's own light/dark-flipping surface — see this file's own doc comment.
          VetroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.vetro.statusGood,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'IN CANTIERE',
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
                const SizedBox(height: 6),
                Text(
                  _formatElapsed(DateTime.now().difference(local.startTime.toLocal())),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: context.vetro.tint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                KeyVal(label: 'Data', value: dateLabel),
                KeyVal(label: 'Ingresso', value: startLabel),
                if (ticketLabel != null)
                  KeyVal(label: 'Ticket', value: ticketLabel, showDivider: false),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Progressive disclosure for the closing note/safety fields.
          Center(
            child: ConstrainedBox(
              // A 48dp floor, not padding alone: the visible content (a 14px icon + 13px text)
              // is much smaller than Android's touch-target minimum — same reasoning as
              // HeaderIconBtn's box around its own smaller visible disc.
              constraints: const BoxConstraints(minHeight: 48),
              child: AppTappable(
                onTap: onOpenClosingDetails,
                borderRadius: AppRack.insetShape,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasClosingDetails ? LucideIcons.checkCircle2 : LucideIcons.plus,
                      size: 14,
                      color: hasClosingDetails ? context.colors.green : context.colors.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasClosingDetails ? 'Note di chiusura aggiunte' : 'Note di chiusura',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasClosingDetails ? context.colors.green : context.colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Error message
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          // Clock-out button — the same stop-red gradient TimbraScreen's punch button uses for
          // "ending", not the default tint fill: this action is destructive/session-ending, same
          // semantic as there.
          VetroButton(
            label: 'Timbra uscita cantiere',
            icon: const Icon(LucideIcons.logOut),
            isLoading: isLoading,
            onPressed: isLoading ? null : onEnd,
            gradientColors: const [AppColors.stopLight, AppColors.stopDark],
          ),
        ],
      ),
    );
  }
}

// ── _ErrorBanner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
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
