// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereTimbraScreen
//
// Clock-in / clock-out for a cantiere (worksite), launched contextually from
// the Ticket detail screen.
//
// Behaviour:
//   - Loads the current user's active cantiere session from the backend.
//   - If no active session: shows a cantiere picker (from cached Drift data,
//     preferring cantieri matching the ticket's customerId) + a big
//     "Timbra ingresso cantiere" button.
//   - If an active session exists: shows session info + a "Timbra uscita
//     cantiere" button.
//   - ONLINE-FIRST: requires network; shows Italian error messages on failure.
//
// TODO(D6 follow-up): offline-first cantiere timbratura needs a backend
// idempotent session-upsert (like /worklog/mobile/sessions); currently
// online-only.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/error_message.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// All active cantieri from the local Drift cache, alphabetical.
/// Status 0 = Active (CantiereStatusEnum.Active).
///
/// Reads the local mirror the sync now fills.
final cantieriProvider = StreamProvider.autoDispose<List<CantieriData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)
        ..where((c) => c.status.equals(0))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

/// AsyncNotifier that loads the current open CantiereWorkLogDto (or null).
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

  /// Clears the active log locally (after a successful end call).
  void clearActive() => state = const AsyncData(null);
}

final activeCantiereLogProvider =
    AutoDisposeAsyncNotifierProvider<ActiveCantiereLogNotifier, CantiereWorkLogDto?>(() {
      return ActiveCantiereLogNotifier();
    });

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

  @override
  Widget build(BuildContext context) {
    final activeLogAsync = ref.watch(activeCantiereLogProvider);
    final cantieriAsync = ref.watch(cantieriProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(title: 'Timbra cantiere', showBack: true),
            Expanded(
              child: activeLogAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorBody(
                  message: _networkErrorMessage(e),
                  onRetry: () => ref.read(activeCantiereLogProvider.notifier).refresh(),
                ),
                data: (activeLog) {
                  if (activeLog != null) {
                    return _ActiveSessionBody(
                      activeLog: activeLog,
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      onEnd: () => _handleEndCantiere(activeLog),
                    );
                  }
                  return _CheckInBody(
                    customerId: widget.customerId,
                    ticketId: widget.ticketId,
                    cantieriAsync: cantieriAsync,
                    selectedCantiere: _selectedCantiere,
                    isLoading: _isLoading,
                    errorMessage: _errorMessage,
                    onCantiereSelected: (c) => setState(() => _selectedCantiere = c),
                    onStart: _handleStartCantiere,
                  );
                },
              ),
            ),
          ],
        ),
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

    try {
      final location = await ref.read(locationServiceProvider).getCurrentPosition();
      final client = ref.read(cantiereWorklogApiClientProvider);
      await client.startCantiere(
        StartCantiereRequest(
          cantiereId: cantiere.id,
          customerId: cantiere.customerId ?? widget.customerId ?? '',
          ticketId: widget.ticketId,
          arrivalLatitude: location?.lat,
          arrivalLongitude: location?.lng,
        ),
      );
      if (mounted) {
        await ref.read(activeCantiereLogProvider.notifier).refresh();
        setState(() => _isLoading = false);
      }
    } on DioException catch (e) {
      if (mounted) {
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

  Future<void> _handleEndCantiere(CantiereWorkLogDto activeLog) async {
    if (!await _confirmGpsPurpose()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final location = await ref.read(locationServiceProvider).getCurrentPosition();
      final client = ref.read(cantiereWorklogApiClientProvider);
      await client.endCantiere(
        EndCantiereRequest(departureLatitude: location?.lat, departureLongitude: location?.lng),
      );
      if (mounted) {
        ref.read(activeCantiereLogProvider.notifier).clearActive();
        setState(() {
          _isLoading = false;
          _selectedCantiere = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uscita cantiere registrata con successo.'),
            backgroundColor: context.colors.green,
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
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

  String _networkErrorMessage(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == null ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        return 'Connessione richiesta per la timbratura cantiere.';
      }
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
    return 'Connessione richiesta per la timbratura cantiere.';
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
    required this.onCantiereSelected,
    required this.onStart,
  });

  final String? customerId;
  final String? ticketId;
  final AsyncValue<List<CantieriData>> cantieriAsync;
  final CantieriData? selectedCantiere;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<CantieriData?> onCantiereSelected;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    // `cantieriProvider` reads a Drift table nothing ever populates today
    // (see the TODO on the provider above), so once the stream has emitted
    // at least once, an empty list is permanent — not "still loading" —
    // and the clock-in button below must not offer an action that can
    // never succeed.
    final cantieriValue = cantieriAsync.valueOrNull;
    final noCantieriAvailable = cantieriValue != null && cantieriValue.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Context banner (linked ticket)
          if (ticketId != null) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(LucideIcons.link, size: 16, color: context.colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collegato al ticket',
                      style: TextStyle(
                        fontFamily: 'Manrope',
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
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),

          cantieriAsync.when(
            loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Impossibile caricare i cantieri.',
                style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: context.colors.red),
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
                  titolo: 'Selezione cantiere non disponibile',
                  motivo:
                      "L'elenco cantieri non è ancora sincronizzato su "
                      'questo dispositivo: non è possibile scegliere un '
                      'cantiere né timbrare l\'ingresso finché questa '
                      'sincronizzazione non sarà collegata.',
                );
              }

              return AppCard(
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
                          ? const BorderRadius.vertical(top: Radius.circular(12))
                          : (isLast
                                ? const BorderRadius.vertical(bottom: Radius.circular(12))
                                : BorderRadius.zero),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.YSoft : Colors.transparent,
                          border: isLast
                              ? null
                              : Border(
                                  bottom: BorderSide(
                                    color: context.colors.borderMedium,
                                    width: 0.5,
                                  ),
                                ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.hardHat,
                              size: 18,
                              color: isSelected ? context.colors.ink : context.colors.inkMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.colors.ink,
                                    ),
                                  ),
                                  if (c.city != null && c.city!.isNotEmpty)
                                    Text(
                                      c.city!,
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 12,
                                        color: context.colors.inkMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(LucideIcons.checkCircle2, size: 18, color: context.colors.ink),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Error message
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          // Clock-in button — disabled (not hidden) when there is nothing to
          // select, so the reason above stays visible instead of the row
          // just disappearing.
          AppButton(
            label: 'Timbra ingresso cantiere',
            icon: const Icon(LucideIcons.mapPin),
            isLoading: isLoading,
            onPressed: (isLoading || noCantieriAvailable) ? null : onStart,
            size: AppButtonSize.lg,
          ),
        ],
      ),
    );
  }
}

// ── _ActiveSessionBody ────────────────────────────────────────────────────────

class _ActiveSessionBody extends ConsumerWidget {
  const _ActiveSessionBody({
    required this.activeLog,
    required this.isLoading,
    required this.errorMessage,
    required this.onEnd,
  });

  final CantiereWorkLogDto activeLog;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = DateFormat('dd/MM/yyyy', 'it').format(activeLog.workDate.toLocal());

    // The session carries a ticket id and nothing else, so the row read `#3f2a1c8e`. Resolved
    // against the local mirror to the job's own name — which is what the technician is standing
    // in front of — and dropped entirely when the mirror does not hold it, rather than printing
    // the id back at them.
    final ticketId = activeLog.ticketId;
    final ticketLabel = ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(ticketId)).valueOrNull?.title;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active session card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sessione cantiere attiva',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                KeyVal(label: 'Data', value: dateLabel),
                KeyVal(
                  label: 'Ingresso',
                  value: activeLog.startTime.length >= 5
                      ? activeLog.startTime.substring(0, 5)
                      : activeLog.startTime,
                ),
                if (ticketLabel != null)
                  KeyVal(label: 'Ticket', value: ticketLabel, showDivider: false),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Error message
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: 16),
          ],

          // Clock-out button
          AppButton.danger(
            label: 'Timbra uscita cantiere',
            icon: const Icon(LucideIcons.logOut),
            isLoading: isLoading,
            onPressed: isLoading ? null : onEnd,
            size: AppButtonSize.lg,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.colors.redSoft, borderRadius: AppRack.insetShape),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Manrope',
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

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wifiOff, size: 48, color: context.colors.inkMuted),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Manrope',
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
