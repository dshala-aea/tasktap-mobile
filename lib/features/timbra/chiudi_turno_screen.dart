// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// ChiudiTurnoScreen
//
// The end-of-session flow for a cantiere clock-out — replaces the old "Note di chiusura" bottom
// sheet (a small text-link affordance on CantiereTimbraScreen's `_ActiveSessionBody`) with a real
// screen: a summary of the session being closed, the departure-GPS indicator, and the closing
// fields (Lavoro svolto / Note di sicurezza) always visible rather than hidden behind a secondary
// link. Pushed from `_ActiveSessionBody`'s "Timbra uscita cantiere" button via a plain
// `Navigator.push` (see that button's own doc comment) — never deep-linked to on its own.
//
// The actual end-of-session call (`_confirm` below) is a deliberate near-verbatim relocation of
// what used to be `_CantiereTimbraScreenState._handleEndCantiere` +
// `_onEndedSuccessfully` in cantiere_timbra_screen.dart: same GPS-purpose confirmation, same
// online-first-with-offline-Drift-queue-fallback, same error humanising. Only the closing-field
// *values* moved (from that screen's own `_closingDescription`/`_safetyNotes` state to this
// screen's own text controllers) — the GPS-purpose gating, offline-fallback detection, and error
// humanising themselves are the exact same shared top-level functions
// (`confirmGpsPurpose`/`isOfflineFailure`/`cantiereNetworkErrorMessage`) cantiere_timbra_screen.dart
// exports for this reason. Do not reimplement that logic differently here.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/timbratura/cantiere_timbra_sync_service.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../cantiere/cantiere_providers.dart';
import 'cantiere_timbra_screen.dart'
    show
        activeCantiereLogProvider,
        cantiereNetworkErrorMessage,
        clampedElapsedSinceMidnight,
        confirmGpsPurpose,
        formatHoursMinutes,
        isOfflineFailure;
import 'gps_status_indicator.dart';

const _uuid = Uuid();

class ChiudiTurnoScreen extends ConsumerStatefulWidget {
  const ChiudiTurnoScreen({
    super.key,
    required this.cantiereId,
    this.ticketId,
    required this.startTime,
  });

  final String cantiereId;
  final String? ticketId;

  /// When the active session started — for the elapsed-time summary. Handed down by the caller
  /// (the active session it already knows about) rather than re-derived here.
  final DateTime startTime;

  @override
  ConsumerState<ChiudiTurnoScreen> createState() => _ChiudiTurnoScreenState();
}

class _ChiudiTurnoScreenState extends ConsumerState<ChiudiTurnoScreen> {
  final _descriptionCtrl = TextEditingController();
  final _safetyNotesCtrl = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _safetyNotesCtrl.dispose();
    super.dispose();
  }

  String? _blankToNull(String v) => v.trim().isEmpty ? null : v.trim();

  /// [skipNotes] is "Esci senza aggiungere note" — it discards whatever's currently typed rather
  /// than just happening to submit it empty, a deliberate fast path distinct from "Conferma
  /// uscita" with blank fields.
  Future<void> _confirm({bool skipNotes = false}) async {
    if (!await confirmGpsPurpose(context, ref)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final description = skipNotes ? null : _blankToNull(_descriptionCtrl.text);
    final safetyNotes = skipNotes ? null : _blankToNull(_safetyNotesCtrl.text);

    try {
      final location = await ref.read(locationServiceProvider).getCurrentPosition();
      final client = ref.read(cantiereWorklogApiClientProvider);
      await client.endCantiere(
        EndCantiereRequest(
          description: description,
          departureLatitude: location?.lat,
          departureLongitude: location?.lng,
          safetyNotes: safetyNotes,
        ),
      );
      _onEndedSuccessfully(offline: false);
    } on DioException catch (e) {
      if (isOfflineFailure(e)) {
        await ref
            .read(cantiereSessionRepositoryProvider)
            .addEvent(
              id: _uuid.v4(),
              eventTime: DateTime.now().toUtc(),
              eventType: 'uscita',
              description: description,
            );
        unawaited(ref.read(cantiereTimbraSyncServiceProvider).syncNow());
        _onEndedSuccessfully(offline: true);
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

  void _onEndedSuccessfully({required bool offline}) {
    if (!mounted) return;
    // The stale server-cached "active" answer must not resurface a session this device just
    // recorded the end of — see cantiereActiveSessionProvider's own doc comment (in
    // cantiere_timbra_screen.dart) on why local takes priority only when it has something open.
    ref.read(activeCantiereLogProvider.notifier).clearActive();
    showAppToast(
      context,
      message: offline
          ? 'Uscita registrata offline: verrà inviata al ritorno della connessione.'
          : 'Uscita cantiere registrata con successo.',
      tone: offline ? ToastTone.warning : ToastTone.success,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cantiereAsync = ref.watch(cantiereByIdProvider(widget.cantiereId));
    final ticketId = widget.ticketId;
    final ticketLabel = ticketId == null
        ? null
        : ref.watch(ticketByIdProvider(ticketId)).valueOrNull?.title;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Timbra uscita', showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.hardHat, size: 18, color: context.colors.ink),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  cantiereAsync.valueOrNull?.name ?? 'Cantiere',
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
                          if (ticketLabel != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 26),
                              child: Text(
                                ticketLabel,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: context.colors.inkMuted,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Divider(color: context.colors.borderLight, height: 1),
                          const SizedBox(height: 12),
                          Text(
                            'TEMPO TRASCORSO',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: context.colors.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _ElapsedSummary(startTime: widget.startTime),
                          const SizedBox(height: 10),
                          const GpsStatusIndicator(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    AppTextField.multiline(
                      label: 'Lavoro svolto',
                      hint: 'Cosa hai fatto in cantiere…',
                      controller: _descriptionCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpacing.base),
                    AppTextField.multiline(
                      label: 'Note di sicurezza',
                      hint: 'Eventuali anomalie o incidenti…',
                      controller: _safetyNotesCtrl,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 16),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: context.colors.redSoft,
                          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
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
                      ),
                      const SizedBox(height: 16),
                    ],

                    AppButton.danger(
                      label: 'Conferma uscita',
                      icon: const Icon(LucideIcons.logOut),
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : () => _confirm(),
                    ),

                    const SizedBox(height: 12),

                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: AppTappable(
                          onTap: _isLoading ? null : () => _confirm(skipNotes: true),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Text(
                            'Esci senza aggiungere note',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.colors.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A static "elapsed since [startTime]" snapshot, computed once per build — deliberately NOT a
/// live-ticking widget. `_CantiereElapsedTicker` (cantiere_timbra_screen.dart, private to that
/// file) uses a real `Ticker` for the active-session screen precisely because that screen is
/// meant to be watched while still on site; this one is a closing summary glanced at once before
/// confirming, and every ticking widget in this app (see that same file's own test-suite comments
/// on `pumpAndSettle`) trades a widget test's ability to ever reach "settled" for a live-updating
/// number — not worth paying twice over for a value nobody watches climb.
class _ElapsedSummary extends StatelessWidget {
  const _ElapsedSummary({required this.startTime});
  final DateTime startTime;

  @override
  Widget build(BuildContext context) {
    final elapsed = clampedElapsedSinceMidnight(startTime, DateTime.now());
    return Text(
      formatHoursMinutes(elapsed),
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: context.colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
