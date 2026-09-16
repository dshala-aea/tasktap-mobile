import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/kiosk/kiosk_lock_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../data/kiosk/kiosk_api_client.dart';
import '../../presentation/providers/kiosk_providers.dart';

/// The kiosk's only screen once activated: a rotating attendance QR a technician scans with
/// their own phone (`WorkLogController.KioskScan`), refreshed well inside the token's 60s HMAC
/// window (see `GetKioskQr`'s doc comment on `WorkLogController`).
///
/// Exiting is deliberately not a visible button — this screen is meant to survive being handed to
/// anyone walking past. A hidden gesture (7 taps in the top-left corner within 3 seconds) opens a
/// PIN prompt; only the correct exit PIN chosen at activation actually deactivates kiosk mode.
class KioskDisplayScreen extends ConsumerStatefulWidget {
  const KioskDisplayScreen({super.key});

  @override
  ConsumerState<KioskDisplayScreen> createState() => _KioskDisplayScreenState();
}

class _KioskDisplayScreenState extends ConsumerState<KioskDisplayScreen> {
  // Refreshed at 45s — comfortably inside the backend's 60s token window (GetKioskQr) even
  // accounting for a slow poll round-trip, so a technician never scans a code that expires
  // mid-scan.
  static const _refreshInterval = Duration(seconds: 45);
  static const _tapWindow = Duration(seconds: 3);
  static const _tapsToUnlock = 7;

  Timer? _timer;
  Timer? _clockTimer;
  KioskQrToken? _token;
  String? _error;
  bool _loading = true;
  DateTime _now = DateTime.now();

  final List<DateTime> _corners = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final token = await ref.read(kioskModeProvider.notifier).refreshQr();
      if (!mounted) return;
      setState(() {
        _token = token;
        _error = null;
        _loading = false;
      });
    } on KioskApiException catch (e) {
      if (!mounted) return;
      // invalidOrRevoked already forced deactivation inside refreshQr(); the router redirect
      // takes this screen off-stage on the next frame. Any other reason just shows a retry
      // state — the device stays pinned and keeps polling.
      setState(() {
        _error = _messageFor(e.reason);
        _loading = false;
      });
    }
  }

  String _messageFor(KioskApiFailureReason reason) {
    switch (reason) {
      case KioskApiFailureReason.invalidOrRevoked:
        return 'Dispositivo disattivato dal server.';
      case KioskApiFailureReason.notEntitled:
        return 'Modulo Kiosk non attivo per questa azienda.';
      case KioskApiFailureReason.network:
        return 'Connessione assente — nuovo tentativo a breve.';
      case KioskApiFailureReason.unknown:
        return 'Errore imprevisto — nuovo tentativo a breve.';
    }
  }

  void _onCornerTap() {
    final now = DateTime.now();
    _corners.add(now);
    _corners.removeWhere((t) => now.difference(t) > _tapWindow);
    if (_corners.length >= _tapsToUnlock) {
      _corners.clear();
      _showExitDialog();
    }
  }

  Future<void> _showExitDialog() async {
    final pinCtrl = TextEditingController();
    var wrongPin = false;

    final exited = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Disattiva modalità totem'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Inserisci il PIN di uscita impostato all\'attivazione.'),
                  const SizedBox(height: AppSpacing.base),
                  AppTextField(
                    label: 'PIN',
                    controller: pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  if (wrongPin) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text('PIN errato.', style: TextStyle(color: dialogContext.colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annulla'),
                ),
                AppButton(
                  label: 'Disattiva',
                  size: AppButtonSize.sm,
                  onPressed: () async {
                    final ok = await ref.read(kioskModeProvider.notifier).deactivate(pinCtrl.text);
                    if (ok) {
                      if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                    } else {
                      setDialogState(() => wrongPin = true);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // Success routes away automatically (kioskModeProvider flips inactive → router redirect).
    if (exited == true) return;
  }

  @override
  Widget build(BuildContext context) {
    final kioskState = ref.watch(kioskModeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    kioskState.deviceLabel?.isNotEmpty == true
                        ? kioskState.deviceLabel!
                        : 'Totem presenze TaskTap',
                    style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    DateFormat('EEEE d MMMM · HH:mm:ss', 'it').format(_now),
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _loading || _token == null
                        ? const SizedBox(
                            width: 260,
                            height: 260,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : QrImageView(
                            data: _token!.token,
                            size: 260,
                            version: QrVersions.auto,
                            backgroundColor: Colors.white,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Inquadra il codice con la tua app TaskTap per timbrare',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      _error!,
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.orangeAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (kioskState.lockOutcome == KioskLockOutcome.unsupportedPlatform) ...[
                    const SizedBox(height: AppSpacing.base),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                      child: Text(
                        'Blocco schermo non disponibile su questo dispositivo: abilita '
                        'manualmente "Accesso guidato" (iOS) per impedire l\'uscita '
                        'dall\'app.',
                        style: AppTextStyles.bodySmall.copyWith(color: Colors.amber),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Hidden exit gesture — an invisible tap target in the top-left corner, deliberately
            // unlabelled (see this class's own doc comment for why). Bare GestureDetector, not
            // AppTappable — a ripple would announce exactly what a kiosk lock screen exists to
            // hide (see tappable_convention_test.dart's `allowed` entry for this file).
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                onTap: _onCornerTap,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 72, height: 72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
