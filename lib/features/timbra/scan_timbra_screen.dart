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
// Split into two screens (scan, then confirm) rather than one stateful screen toggling
// between phases: KioskConfirmTimbraScreen takes the scanned token as a plain constructor
// parameter, so its error-handling logic is directly widget-testable without driving the real
// camera — the same reason `mobile_scanner`-touching flows elsewhere in this app (see
// step_materiali_fold_test.dart) only test that the scan button renders, never the camera itself.
// The first of the two no longer draws a prompt of its own: see ScanTimbraScreen's doc comment.
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
import 'timbra_providers.dart';

/// Opens the camera sheet and returns the raw scanned string, or null if the technician backs
/// out. Injectable so the flow's two outcomes can be driven without a camera — the same reason
/// [KioskConfirmTimbraScreen] takes its token as a plain constructor parameter.
typedef ScanOpener = Future<String?> Function(BuildContext context);

/// Entry screen: the scanner itself.
///
/// There used to be a page here — header, a sentence about the totem, and a second "Scansiona QR"
/// button — so clocking in from the dashboard, the Timbra header or the QR-required notice cost
/// two taps and a screen that asked nothing. Nothing on that page was a decision; it only
/// restated where the technician had already chosen to go. The camera now opens on the way in,
/// and the route exists purely to own the scan → confirm → pop sequence.
class ScanTimbraScreen extends StatefulWidget {
  const ScanTimbraScreen({super.key, this.openScanner = _openTotemScanner});

  static Future<String?> _openTotemScanner(BuildContext context) =>
      openBarcodeScanSheet(context, title: 'Scansiona il totem');

  final ScanOpener openScanner;

  @override
  State<ScanTimbraScreen> createState() => _ScanTimbraScreenState();
}

class _ScanTimbraScreenState extends State<ScanTimbraScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Post-frame: opening a route from `initState` would push during this frame's build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_started) return;
    _started = true;

    final value = await widget.openScanner(context);
    if (!mounted) return;

    if (value == null || value.trim().isEmpty) {
      // Cancelled. With no prompt page to fall back to, staying mounted would strand the
      // technician on an empty screen.
      Navigator.of(context).pop();
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => KioskConfirmTimbraScreen(token: value.trim())));

    // The confirmation screen pops itself once the punch lands (or offers its own way back on a
    // failure); this route has served its purpose either way and must not be what the technician
    // lands back on.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Never seen for long: the camera sheet paints over it on the first post-frame. It is the
    // honest thing to show while the camera starts, and it is not a page to come back to.
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Submits the scanned [token] to `POST /api/worklog/kiosk/scan`. The kiosk device already knows
/// its own site, so there is never a site picker. What it cannot know is the technician's
/// intent: when the day is clocked out, a scan can only mean clock-in and submits immediately;
/// when something is already open (working, or on a break), it asks which transition was meant —
/// pausa, riprendi, or fine turno — and sends that as a named action. Without that prompt the
/// endpoint toggles, and a technician scanning the totem again while on a break gets clocked out.
/// Standalone/constructor-driven so it's testable without a camera — see this file's own header
/// comment.
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

  /// Set while the day has something open: the scan has to ask WHICH transition the technician
  /// meant, so the buttons come from the server's own `availableActions` rather than the app
  /// guessing what "scan again" should do.
  GiornataDto? _choice;

  String? _userId;

  @override
  void initState() {
    super.initState();
    // Post-frame so ref.read inside an async chain never races the very first build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  /// Reads the day, then either submits straight away — clocked out is the one state where a
  /// scan can only mean one thing — or offers the transitions the day actually allows.
  Future<void> _begin() async {
    setState(() {
      _submitting = true;
      _error = null;
      _terminal = false;
      _canRetry = false;
      _choice = null;
    });

    final String? userId;
    try {
      userId = _userId ?? await ref.read(internalUserIdProvider.future);
    } catch (_) {
      // The one await in here that is not already guarded, and `_begin` turned the spinner on
      // before it: a failed session read has to land in the same error state as everything else,
      // never in an indeterminate spinner nobody can dismiss.
      if (mounted) _failWithUnexpected();
      return;
    }
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _terminal = true;
        _error = 'Impossibile identificare l\'utente. Riprova ad accedere.';
      });
      return;
    }
    _userId = userId;

    GiornataDto? giornata;
    try {
      giornata = await ref.read(worklogApiClientProvider).getGiornata();
    } catch (_) {
      // No answer is not a reason to strand the technician at the totem — the punch is what they
      // came to do. Without a day to read the scan stays the blind toggle, which is also what
      // every app build before this one sent: the server still decides.
      giornata = null;
    }

    if (!mounted) return;
    if (giornata == null || giornata.status == 'ClockedOut') {
      await _submit(giornata == null ? null : 'ClockIn', userId);
      return;
    }

    setState(() {
      _submitting = false;
      _choice = giornata;
    });
  }

  /// [action] names the transition; null is the legacy toggle, used only when the day could not
  /// be read at all.
  Future<void> _submit(String? action, String userId) async {
    setState(() {
      _submitting = true;
      _choice = null;
      _error = null;
    });

    // The try covers the call and nothing else: once [kioskScan] returns, the punch has landed,
    // and a toast or a pop that fails afterwards must not be reported as a failed punch.
    final KioskScanResult result;
    try {
      result = await ref
          .read(worklogApiClientProvider)
          .kioskScan(token: widget.token, userId: userId, action: action);
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
          case KioskScanFailureReason.conflict:
            // The day moved between the prompt and the tap (another device, a manager, a closed
            // payroll period). The server's own prose explains it; retrying re-reads the day so
            // the prompt matches what is now true instead of repeating the same refusal.
            _canRetry = true;
            _error = e.message ?? 'La giornata è già cambiata. Riprova.';
          case KioskScanFailureReason.network:
            _canRetry = true;
            _error = 'Connessione assente. Controlla la rete e riprova.';
          case KioskScanFailureReason.unknown:
            _canRetry = true;
            _error = 'Errore imprevisto. Riprova.';
        }
      });
      return;
    } catch (_) {
      // Anything the [KioskScanException] cases above do not model — and the one class of failure
      // this screen must never let through regardless: `_submitting` drives an *indeterminate*
      // spinner, so an escaping exception is a screen the technician can no longer leave. That is
      // exactly the field regression this catch exists for: clock-out is the only response that
      // carries `endTime`, the client parsed it as an ISO datetime while the server sends a
      // `TimeSpan`, and the resulting FormatException escaped here and left the spinner up over a
      // punch that had in fact succeeded.
      if (!mounted) return;
      _failWithUnexpected();
      return;
    }

    if (!mounted) return;
    showAppToast(context, message: _toastFor(result.action), tone: ToastTone.success);
    Navigator.of(context).pop();
  }

  /// The unclassified-error state: same copy and same retry as
  /// [KioskScanFailureReason.unknown], because from the technician's side the two are the same
  /// thing — a result this build could not read.
  void _failWithUnexpected() => setState(() {
    _submitting = false;
    _terminal = true;
    _canRetry = true;
    _error = 'Errore imprevisto. Riprova.';
  });

  String _toastFor(String action) => switch (action) {
    'out' => 'Uscita registrata',
    'breakStart' => 'Pausa iniziata',
    'breakEnd' => 'Pausa terminata',
    _ => 'Ingresso registrato',
  };

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
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
                      : choice != null
                      ? _buildPrompt(choice)
                      : _buildError(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) InlineAlert(message: _error!),
        if (_terminal) ...[
          const SizedBox(height: AppSpacing.base),
          AppButton(
            label: _canRetry ? 'Riprova' : 'Torna indietro',
            onPressed: () {
              if (_canRetry) {
                _begin();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ],
    );
  }

  /// The prompt. Every option is one the server said is available for this day; an option it
  /// refused is disabled and explains itself with the same wording the punch guard uses
  /// ([reasonTextFor]), so one reason never reads two ways on two screens.
  Widget _buildPrompt(GiornataDto day) {
    final onBreak = day.status == 'OnBreak';
    final primaryAction = onBreak ? 'EndBreak' : 'StartBreak';
    final primary = day.action(primaryAction);
    final clockOut = day.action('ClockOut');

    String? blockedReason;
    if (primary != null && !primary.enabled) {
      blockedReason = reasonTextFor(primary);
    } else if (clockOut != null && !clockOut.enabled) {
      blockedReason = reasonTextFor(clockOut);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          onBreak ? 'Sei in pausa' : 'Sei in servizio',
          style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Cosa vuoi fare?',
          style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: onBreak ? 'Riprendi il lavoro' : 'Inizia la pausa',
          icon: Icon(onBreak ? Icons.play_arrow : Icons.free_breakfast, size: 18),
          onPressed: (primary?.enabled ?? false)
              ? () => _submit(primaryAction, _userId!)
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(
          label: 'Fine turno',
          icon: const Icon(Icons.logout, size: 18),
          onPressed: (clockOut?.enabled ?? false) ? () => _submit('ClockOut', _userId!) : null,
        ),
        if (blockedReason != null) ...[
          const SizedBox(height: AppSpacing.base),
          InlineAlert(message: blockedReason),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton.ghost(label: 'Annulla', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
