// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// ScanTimbraScreen / KioskConfirmTimbraScreen
//
// The technician-facing half of kiosk attendance: scan the rotating QR a totem shows
// (KioskDisplayScreen, mobile/lib/features/kiosk/kiosk_display_screen.dart) and clock in/out.
// The backend endpoint this calls (POST /api/worklog/kiosk/scan, WorkLogController.KioskScan)
// has existed and been security-hardened for a while — nothing in the app ever called it before
// this screen. See KioskScanRequest's own shape: the kiosk device's own registered CantiereId
// (set at registration on the web admin's "Dispositivi kiosk" page) is NOT read by that endpoint
// at all — it takes LocationId/CustomerId directly from the caller instead. So unlike
// CantiereTimbraScreen (which resolves a whole Cantiere), this only needs a Sede (Location — a
// customer's site, already carries its own CustomerId) to satisfy the wire contract; there is no
// "generic, no site" option today because both fields are non-nullable on the request DTO.
//
// Split into two screens (scan prompt, then confirm) rather than one stateful screen toggling
// between phases: KioskConfirmTimbraScreen takes the scanned token as a plain constructor
// parameter, so its own picker/confirm/error-handling logic is directly widget-testable without
// driving the real camera — the same reason `mobile_scanner`-touching flows elsewhere in this app
// (see step_materiali_fold_test.dart) only test that the scan button renders, never the camera
// itself.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/scanner/barcode_scan_sheet.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/timbratura/worklog_api_client.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/schedule_providers.dart';

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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KioskConfirmTimbraScreen(token: value.trim())),
    );
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

/// Picks a Sede (Location) and submits the scanned [token] to
/// `POST /api/worklog/kiosk/scan`. Standalone/constructor-driven so it's testable without a
/// camera — see this file's own header comment.
class KioskConfirmTimbraScreen extends ConsumerStatefulWidget {
  const KioskConfirmTimbraScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<KioskConfirmTimbraScreen> createState() => _KioskConfirmTimbraScreenState();
}

class _KioskConfirmTimbraScreenState extends ConsumerState<KioskConfirmTimbraScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Location? _selectedLocation;
  bool _submitting = false;
  bool _expired = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final location = _selectedLocation;
    if (location == null) return;

    final userId = await ref.read(internalUserIdProvider.future);
    if (userId == null) {
      if (mounted) {
        setState(() => _error = 'Impossibile identificare l\'utente. Riprova ad accedere.');
      }
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(worklogApiClientProvider)
          .kioskScan(
            token: widget.token,
            userId: userId,
            locationId: location.id,
            customerId: location.customerId,
          );
      if (!mounted) return;
      showAppToast(
        context,
        message: result.action == 'out' ? 'Uscita registrata' : 'Ingresso registrato',
        tone: ToastTone.success,
      );
      Navigator.of(context).pop();
    } on KioskScanException catch (e) {
      if (!mounted) return;
      switch (e.reason) {
        case KioskScanFailureReason.invalidOrExpiredToken:
          // The QR rotates every ~45-60s (see KioskDisplayScreen) — a stale scan is the expected
          // failure mode, not a dead end. Send the technician back to rescan rather than leaving
          // them staring at a picker bound to a token that will never validate.
          setState(() {
            _expired = true;
            _error = 'Codice scaduto o non valido. Torna indietro e inquadra di nuovo il QR.';
          });
        case KioskScanFailureReason.deviceRevoked:
          setState(() {
            _expired = true;
            _error = 'Questo totem è stato disattivato. Contatta l\'ufficio.';
          });
        case KioskScanFailureReason.notEntitled:
          setState(() => _error = 'Il modulo Kiosk non è attivo per questa azienda.');
        case KioskScanFailureReason.forbidden:
          setState(() => _error = 'Non hai i permessi per timbrare da questo totem.');
        case KioskScanFailureReason.network:
          setState(() => _error = 'Connessione assente. Controlla la rete e riprova.');
        case KioskScanFailureReason.unknown:
          setState(() => _error = 'Errore imprevisto. Riprova.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _matches(Location l, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return l.name.toLowerCase().contains(q) || (l.city?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Conferma timbratura', showBack: true),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                ),
                child: _ErrorBanner(message: _error!),
              ),
            if (_expired)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                ),
                child: AppButton(
                  label: 'Torna indietro',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Codice acquisito — seleziona la sede in cui ti trovi.',
                  style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
                ),
              ),
              AppSearchBar(
                controller: _searchController,
                hint: 'Cerca sede per nome o città…',
                onChanged: (v) => setState(() => _query = v),
              ),
              Expanded(
                child: locationsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => const UnavailableState(
                    icon: LucideIcons.mapPin,
                    titolo: 'Impossibile caricare le sedi',
                    motivo: 'Riprova tra poco.',
                  ),
                  data: (locations) {
                    final filtered = locations.where((l) => _matches(l, _query)).toList();
                    if (filtered.isEmpty) {
                      return UnavailableState(
                        icon: LucideIcons.searchX,
                        titolo: 'Nessun risultato',
                        motivo: _query.isEmpty
                            ? 'Non risultano sedi sincronizzate su questo dispositivo.'
                            : 'Nessuna sede corrisponde a "$_query".',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.xxl,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final l = filtered[i];
                        final selected = _selectedLocation?.id == l.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard.pressable(
                            onTap: () => setState(() => _selectedLocation = l),
                            child: Row(
                              children: [
                                RowIconTile(
                                  icon: LucideIcons.mapPin,
                                  color: selected ? context.colors.green : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.name,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: context.colors.ink,
                                        ),
                                      ),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          final customerName = ref
                                              .watch(customerNameProvider(l.customerId))
                                              .valueOrNull;
                                          final subtitle = [
                                            ?customerName,
                                            if (l.city != null && l.city!.isNotEmpty) l.city,
                                          ].join(' · ');
                                          if (subtitle.isEmpty) return const SizedBox.shrink();
                                          return Text(
                                            subtitle,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 12,
                                              color: context.colors.inkMuted,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    LucideIcons.checkCircle,
                                    size: 18,
                                    color: context.colors.green,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.pagePadding + context.navClearance,
                ),
                child: AppButton(
                  label: _submitting ? 'Invio in corso...' : 'Conferma timbratura',
                  isLoading: _submitting,
                  onPressed: (_selectedLocation == null || _submitting) ? null : _confirm,
                ),
              ),
            ],
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
