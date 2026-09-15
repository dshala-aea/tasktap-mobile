import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scanner/barcode_scan_sheet.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../../data/kiosk/kiosk_api_client.dart';
import '../../presentation/providers/kiosk_providers.dart';

/// Turns this handset into a kiosk (attendance totem): enter/scan the `sp_...` credential the
/// web admin's "Registra dispositivo" flow issued once, choose a local exit PIN, and activate.
///
/// Reached only from a deliberately unobvious entry point — a long-press on the logo on
/// [LoginScreen] — because this is not a screen an ordinary technician should stumble into: once
/// activation succeeds the device locks itself into [KioskDisplayScreen] and stops being a normal
/// TaskTap client. See `app_router.dart`'s kiosk redirect for how that lock is enforced app-wide.
class KioskActivationScreen extends ConsumerStatefulWidget {
  const KioskActivationScreen({super.key});

  @override
  ConsumerState<KioskActivationScreen> createState() => _KioskActivationScreenState();
}

class _KioskActivationScreenState extends ConsumerState<KioskActivationScreen> {
  final _rawKeyCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _rawKeyCtrl.dispose();
    _labelCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    // Any QR (or other symbology) content is accepted verbatim as the raw key — the web admin
    // page shows the key as plain text, not a QR, so this only helps a site that has printed or
    // otherwise encoded that string into a scannable code of its own. Manual entry (paste/type)
    // below is the primary path.
    final value = await openBarcodeScanSheet(context, title: 'Scansiona credenziale');
    if (value != null && mounted) {
      setState(() => _rawKeyCtrl.text = value.trim());
    }
  }

  String? _validate() {
    final rawKey = _rawKeyCtrl.text.trim();
    if (rawKey.isEmpty) return 'Inserisci la credenziale del dispositivo.';
    if (_pinCtrl.text.length < 4) return 'Il PIN di uscita deve avere almeno 4 cifre.';
    if (_pinCtrl.text != _pinConfirmCtrl.text) return 'I due PIN non coincidono.';
    return null;
  }

  Future<void> _activate() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(kioskModeProvider.notifier)
          .activate(
            rawKey: _rawKeyCtrl.text.trim(),
            deviceLabel: _labelCtrl.text.trim(),
            exitPin: _pinCtrl.text,
          );
      // Success: kioskModeProvider flips to active, the router's redirect callback (listening to
      // the same provider) takes it from here — no manual navigation needed.
    } on KioskApiException catch (e) {
      setState(() => _error = _messageFor(e.reason));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFor(KioskApiFailureReason reason) {
    switch (reason) {
      case KioskApiFailureReason.invalidOrRevoked:
        return 'Credenziale non valida o revocata. Verifica il codice copiato dalla pagina admin.';
      case KioskApiFailureReason.notEntitled:
        return 'Il modulo Kiosk non è attivo per questa azienda.';
      case KioskApiFailureReason.network:
        return 'Impossibile raggiungere il server. Controlla la connessione e riprova.';
      case KioskApiFailureReason.unknown:
        return 'Errore imprevisto durante l\'attivazione.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg1,
      appBar: AppBar(
        backgroundColor: context.colors.bg1,
        elevation: 0,
        title: const Text('Attiva modalità totem'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Questo dispositivo diventerà un totem presenze a schermo bloccato. Incolla o '
                'scansiona la credenziale mostrata una sola volta dalla pagina "Dispositivi kiosk" '
                'del pannello admin.',
                style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
              ),
              const SizedBox(height: AppSpacing.xxl),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.red.withAlpha(20),
                    border: Border.all(color: context.colors.red.withAlpha(80)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: AppTextStyles.bodySmall.copyWith(color: context.colors.red),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
              ],

              AppTextField(
                key: const ValueKey('kiosk-raw-key'),
                controller: _rawKeyCtrl,
                label: 'Credenziale dispositivo (sp_...)',
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _submitting ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                  label: const Text('Scansiona QR'),
                ),
              ),

              const SizedBox(height: AppSpacing.base),
              AppTextField(
                key: const ValueKey('kiosk-label'),
                controller: _labelCtrl,
                label: 'Nome dispositivo (facoltativo, solo locale)',
              ),

              const SizedBox(height: AppSpacing.xxl),
              Text('PIN di uscita', style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Serve per disattivare la modalità totem su questo dispositivo. Non viene inviato '
                'al server: conservalo tu stesso.',
                style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkFaint),
              ),
              const SizedBox(height: AppSpacing.base),
              AppTextField(
                key: const ValueKey('kiosk-pin'),
                controller: _pinCtrl,
                label: 'PIN (min. 4 cifre)',
                obscureText: true,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.base),
              AppTextField(
                key: const ValueKey('kiosk-pin-confirm'),
                controller: _pinConfirmCtrl,
                label: 'Conferma PIN',
                obscureText: true,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                label: 'Attiva modalità totem',
                onPressed: _submitting ? null : _activate,
                isLoading: _submitting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
