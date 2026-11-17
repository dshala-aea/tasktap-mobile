// dart format width=100
// lib/features/cantiere/cantiere_close_sheet.dart
//
// The clock-out flow as a bottom sheet on the cantiere detail, per the "Il giorno" redesign. The
// session-ending call is intentionally the same sequence as ChiudiTurnoScreen: GPS-purpose
// confirmation, online end, offline Drift queue fallback, clock-disagreement capture, and the same
// error humanising. Keeping it here lets the technician close the visit without leaving the day's
// ledger they are looking at.

import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/timbratura/cantiere_timbra_sync_service.dart';
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/clock_disagreement_provider.dart';
import '../timbra/cantiere_timbra_screen.dart'
    show
        TimbraErrorBanner,
        activeCantiereLogProvider,
        cantiereNetworkErrorMessage,
        requestGpsPermission,
        isOfflineFailure;
import '../timbra/gps_status_indicator.dart';
import 'cantiere_day.dart';
import 'cantiere_design.dart';

const _uuid = Uuid();

Future<void> showCantiereCloseSheet(
  BuildContext context, {
  required String cantiereId,
  required String cantiereName,
  required DateTime startTime,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CantiereCloseSheet(
      cantiereId: cantiereId,
      cantiereName: cantiereName,
      startTime: startTime,
    ),
  );
}

class CantiereCloseSheet extends ConsumerStatefulWidget {
  const CantiereCloseSheet({
    super.key,
    required this.cantiereId,
    required this.cantiereName,
    required this.startTime,
  });

  final String cantiereId;
  final String cantiereName;
  final DateTime startTime;

  @override
  ConsumerState<CantiereCloseSheet> createState() => _CantiereCloseSheetState();
}

class _CantiereCloseSheetState extends ConsumerState<CantiereCloseSheet> {
  final _descriptionCtrl = TextEditingController();
  final _safetyNotesCtrl = TextEditingController();

  bool _isConfirmLoading = false;
  bool _isSkipLoading = false;
  bool get _isBusy => _isConfirmLoading || _isSkipLoading;

  String? _errorMessage;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _safetyNotesCtrl.dispose();
    super.dispose();
  }

  String? _blankToNull(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _confirm({bool skipNotes = false}) async {
    await requestGpsPermission(ref);
    if (!mounted) return;

    setState(() {
      if (skipNotes) {
        _isSkipLoading = true;
      } else {
        _isConfirmLoading = true;
      }
      _errorMessage = null;
    });

    final description = skipNotes ? null : _blankToNull(_descriptionCtrl.text);
    final safetyNotes = skipNotes ? null : _blankToNull(_safetyNotesCtrl.text);

    final location = await ref.read(locationServiceProvider).getCurrentPosition();

    try {
      final client = ref.read(cantiereWorklogApiClientProvider);
      final clockDisagreement = await client.endCantiere(
        EndCantiereRequest(
          description: description,
          departureLatitude: location?.lat,
          departureLongitude: location?.lng,
          safetyNotes: safetyNotes,
          deviceUtc: DateTime.now().toUtc(),
        ),
      );
      if (clockDisagreement != null) {
        ref.read(cantiereClockDisagreementProvider.notifier).record(clockDisagreement);
      }
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
              safetyNotes: safetyNotes,
              departureLatitude: location?.lat,
              departureLongitude: location?.lng,
            );
        unawaited(ref.read(cantiereTimbraSyncServiceProvider).syncNow());
        _onEndedSuccessfully(offline: true);
      } else if (mounted) {
        setState(() {
          _isConfirmLoading = false;
          _isSkipLoading = false;
          _errorMessage = cantiereNetworkErrorMessage(e);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isConfirmLoading = false;
          _isSkipLoading = false;
          _errorMessage = 'Errore imprevisto. Riprova.';
        });
      }
    }
  }

  void _onEndedSuccessfully({required bool offline}) {
    if (!mounted) return;
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

  InputDecoration _fieldDecoration(BuildContext context, String hint) {
    final c = context.colors;
    OutlineInputBorder border() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(color: c.borderLight),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: cantiereBody(context, 10.5, color: c.inkMuted),
      filled: true,
      fillColor: c.bg2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // `.sheet`: sheet fill, a 1px rule on top only, square corners.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.borderLight)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox(width: 34, height: 4),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Chiudi turno',
                    style: cantiereDisplay(context, 17, weight: FontWeight.w700),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('TEMPO TRASCORSO', style: cantiereMini(context)),
                      CantiereLiveElapsed(
                        start: widget.startTime,
                        clock: true,
                        style: cantiereTimer(context, size: 19),
                      ),
                    ],
                  ),
                ),
                const GpsStatusIndicator(),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionCtrl,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: cantiereBody(context, 10.5),
                  decoration: _fieldDecoration(context, 'Lavoro svolto…'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _safetyNotesCtrl,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: cantiereBody(context, 10.5),
                  decoration: _fieldDecoration(context, 'Note di sicurezza…'),
                ),
                const SizedBox(height: 8),
                if (_errorMessage != null) ...[
                  TimbraErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 8),
                ],
                CantiereButton(
                  label: 'Conferma uscita',
                  loading: _isConfirmLoading,
                  onPressed: _isBusy ? null : () => _confirm(),
                ),
                const SizedBox(height: 10),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: AppTappable(
                      onTap: _isBusy ? null : () => _confirm(skipNotes: true),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: _isSkipLoading
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Esci senza aggiungere note',
                              style: cantiereBody(context, 10, color: c.inkMuted),
                            ),
                    ),
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
