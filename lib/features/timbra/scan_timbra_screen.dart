// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// ScanTimbraScreen / KioskConfirmTimbraScreen
//
// The technician-facing half of kiosk attendance: scan the rotating QR a totem shows
// (KioskDisplayScreen, mobile/lib/features/kiosk/kiosk_display_screen.dart) and clock in/out.
// The backend endpoint this calls (POST /api/worklog/kiosk/scan, WorkLogController.KioskScan)
// has existed and been security-hardened for a while — nothing in the app ever called it before
// this screen.
//
// No site picker here: the kiosk device carries its own fixed Location/Customer, registered once
// on the web admin's "Dispositivi kiosk" page, and KioskScan resolves it server-side from the
// device — a fixed wall tablet's site doesn't change scan to scan, so the technician is never
// asked. Scan, confirm, done.
//
// Split into two screens (scan prompt, then confirm) rather than one stateful screen toggling
// between phases: KioskConfirmTimbraScreen takes the scanned token as a plain constructor
// parameter, so its error-handling logic is directly widget-testable without driving the real
// camera — the same reason `mobile_scanner`-touching flows elsewhere in this app (see
// step_materiali_fold_test.dart) only test that the scan button renders, never the camera itself.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scanner/barcode_scan_sheet.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../../data/timbratura/worklog_api_client.dart';
import '../../presentation/providers/auth_providers.dart';

/// Entry screen: prompts for a camera scan of the totem's QR, then pushes
/// [KioskConfirmTimbraScreen] with the scanned token.
class ScanTimbraScreen extends StatefulWidget {
  const ScanTimbraScreen({super.key});

  @override
  State<ScanTimbraScreen> createState() => _ScanTimbraScreenState();
}

class _ScanTimbraScreenState extends State<ScanTimbraScreen> {
  Future<void> _scan() async {
    final value = await openBarcodeScanSheet(context, title: 'Scansiona il totem');
    if (value == null || !mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => KioskConfirmTimbraScreen(token: value.trim())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Timbra con QR', showBack: true),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Inquadra il codice QR mostrato dal totem presenze per registrare '
                      'ingresso o uscita.',
                      style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    AppButton(
                      label: 'Scansiona QR',
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      onPressed: _scan,
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

/// Submits the scanned [token] to `POST /api/worklog/kiosk/scan` — automatically, on mount, no
/// picker or confirm button: the kiosk device already knows its own site. Standalone/
/// constructor-driven so it's testable without a camera — see this file's own header comment.
class KioskConfirmTimbraScreen extends ConsumerStatefulWidget {
  const KioskConfirmTimbraScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<KioskConfirmTimbraScreen> createState() => _KioskConfirmTimbraScreenState();
}

class _KioskConfirmTimbraScreenState extends ConsumerState<KioskConfirmTimbraScreen> {
  bool _submitting = true;
  bool _terminal = false;
  // Whether a Riprova (retry) makes sense, vs. the token itself being dead and needing a fresh
  // scan (Torna indietro). Same distinction the old picker-based screen drew.
  bool _canRetry = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Post-frame so ref.read inside an async chain never races the very first build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final userId = await ref.read(internalUserIdProvider.future);
    if (userId == null) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _terminal = true;
          _error = 'Impossibile identificare l\'utente. Riprova ad accedere.';
        });
      }
      return;
    }

    try {
      final result = await ref
          .read(worklogApiClientProvider)
          .kioskScan(token: widget.token, userId: userId);
      if (!mounted) return;
      showAppToast(
        context,
        message: result.action == 'out' ? 'Uscita registrata' : 'Ingresso registrato',
        tone: ToastTone.success,
      );
      Navigator.of(context).pop();
    } on KioskScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _terminal = true;
        switch (e.reason) {
          case KioskScanFailureReason.invalidOrExpiredToken:
            // The QR rotates every ~45-60s (see KioskDisplayScreen) — a stale scan is the
            // expected failure mode, not a dead end. The token itself is dead, so retrying this
            // same submit can never succeed — only a fresh scan can.
            _canRetry = false;
            _error = 'Codice scaduto o non valido. Torna indietro e inquadra di nuovo il QR.';
          case KioskScanFailureReason.deviceRevoked:
            _canRetry = false;
            _error = 'Questo totem è stato disattivato. Contatta l\'ufficio.';
          case KioskScanFailureReason.notEntitled:
            _canRetry = true;
            _error = 'Il modulo Kiosk non è attivo per questa azienda.';
          case KioskScanFailureReason.forbidden:
            _canRetry = true;
            _error = 'Non hai i permessi per timbrare da questo totem.';
          case KioskScanFailureReason.network:
            _canRetry = true;
            _error = 'Connessione assente. Controlla la rete e riprova.';
          case KioskScanFailureReason.unknown:
            _canRetry = true;
            _error = 'Errore imprevisto. Riprova.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Conferma timbratura', showBack: true),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                child: Center(
                  child: _submitting
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) _ErrorBanner(message: _error!),
                            if (_terminal) ...[
                              const SizedBox(height: AppSpacing.base),
                              AppButton(
                                label: _canRetry ? 'Riprova' : 'Torna indietro',
                                onPressed: () {
                                  if (_canRetry) {
                                    _submit();
                                  } else {
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.red.withAlpha(20),
        border: Border.all(color: context.colors.red.withAlpha(80)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: AppTextStyles.bodySmall.copyWith(color: context.colors.red)),
    );
  }
}
