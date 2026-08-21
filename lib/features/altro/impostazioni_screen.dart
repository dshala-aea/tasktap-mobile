import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/config/app_info_provider.dart';
import '../../core/dictation/dictation_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/widgets/widgets.dart';
import '../../presentation/providers/auth_providers.dart';
import 'impostazioni_provider.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ImpostazioniScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Impostazioni screen — P4 spec.
///
/// Sections: profilo card → Notifiche → App → Account → Sistema → version.
class ImpostazioniScreen extends ConsumerWidget {
  const ImpostazioniScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(impostazioniProvider);
    final notifier = ref.read(impostazioniProvider.notifier);
    final appInfoAsync = ref.watch(appInfoProvider);

    final displayName = user?.displayName ?? user?.email ?? '';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(title: 'Impostazioni', showBack: true),
            ),

            // ── Profile card ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _ProfileCard(displayName: displayName, email: user?.email),
            ),

            // ── Notifiche ──────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'Notifiche'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  // The OS prompt now happens here, at the moment the technician asks for
                  // notifications, and only after a sheet has said what will be sent. It used to
                  // fire during `runTaskTapApp()` — the first thing on screen at first launch,
                  // before any context existed to judge it by.
                  _ToggleRow(
                    icon: LucideIcons.bell,
                    title: 'Notifiche push',
                    subtitle: 'Ricevi avvisi in tempo reale',
                    value: settings.pushAbilitate,
                    onChanged: (_) =>
                        _togglePush(context, settings.pushAbilitate, notifier),
                  ),
                  _ToggleRow(
                    icon: LucideIcons.clipboardList,
                    title: 'Interventi',
                    subtitle: 'Nuovi interventi assegnati',
                    value: settings.notificheInterventi,
                    onChanged: (_) =>
                        notifier.toggle(key: 'notificheInterventi'),
                    showDivider: false,
                  ),
                  _ToggleRow(
                    icon: LucideIcons.fileText,
                    title: 'Rapportini',
                    subtitle: 'Aggiornamenti sui rapportini',
                    value: settings.notificheRapportini,
                    onChanged: (_) =>
                        notifier.toggle(key: 'notificheRapportini'),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            // ── App ───────────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'App'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  _ToggleRow(
                    icon: LucideIcons.wifiOff,
                    title: 'Modalità offline',
                    subtitle: 'Sincronizza dati in background',
                    value: settings.syncOffline,
                    onChanged: (_) => notifier.toggle(key: 'syncOffline'),
                  ),
                  _ToggleRow(
                    icon: LucideIcons.mapPin,
                    title: 'Geolocalizzazione',
                    subtitle: 'Registra la posizione a inizio e fine cantiere',
                    value: settings.geoLocazione,
                    onChanged: (_) => notifier.toggle(key: 'geoLocazione'),
                  ),
                  _ToggleRow(
                    icon: LucideIcons.moon,
                    title: 'Tema scuro',
                    subtitle: 'Interfaccia scura',
                    value: settings.temaScuro,
                    onChanged: (_) => notifier.toggle(key: 'temaScuro'),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            // ── Account ───────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'Account'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  _ToggleRow(
                    icon: LucideIcons.fingerprint,
                    title: 'Autenticazione biometrica',
                    subtitle: 'Richiedi impronta o Face ID all\'apertura',
                    value: settings.autenticazioneBiometrica,
                    onChanged: (_) => _toggleBiometrics(context, ref, settings),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            // ── Dettatura ─────────────────────────────────────────────────
            //
            // A readout, not a switch. Whether dictation works is decided by the handset — an
            // on-device recogniser, the Italian language pack, microphone permission — and none
            // of that is something the app can turn on. What it can do is say which part is
            // missing, so a technician who cannot find the microphone gets an answer instead of
            // filing a bug, and so a fleet can be checked without instrumenting a build.
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'Dettatura'),
            ),
            const SliverToBoxAdapter(
              child: _SettingsGroup(children: [_DictationDiagnosticsRow()]),
            ),

            // ── Sistema ───────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'Sistema'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(children: [_LogoutSettingRow(ref: ref)]),
            ),

            // ── Version footer ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.xxl,
                  AppSpacing.pagePadding,
                  0,
                ),
                child: Center(
                  child: appInfoAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (info) => Text(
                      'TaskTap v${info.displayVersion}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        color: context.colors.inkDisabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.only(bottom: context.navClearance),
            ),
          ],
        ),
      ),
    );
  }

  /// Turning push on is the moment to ask the OS — and the moment to say why first.
  ///
  /// Turning it *off* asks nothing: an OS permission the technician granted once is theirs to keep,
  /// and revoking the app's own setting is not a reason to touch it.
  ///
  /// A denial reverts the switch rather than leaving it on. A control that reports a state the
  /// system will not honour is the same defect as the biometric toggle below, and the same defect
  /// as a settings switch wired to nothing: it tells the technician they will be notified when they
  /// will not be.
  Future<void> _togglePush(
    BuildContext context,
    bool currentlyOn,
    ImpostazioniNotifier notifier,
  ) async {
    if (currentlyOn) {
      notifier.toggle(key: 'pushAbilitate');
      return;
    }

    if (!NotificationService.isAvailable) {
      // Firebase never initialised — an explicitly supported degraded path. Say so instead of
      // flipping a switch that cannot deliver anything.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le notifiche non sono disponibili su questo dispositivo.',
          ),
        ),
      );
      return;
    }

    final service = NotificationService.instance;

    // Already granted in a previous run: no purpose sheet, no OS dialog, just honour the switch.
    if (!await service.hasPermission()) {
      if (!context.mounted) return;
      final wants = await askPermissionPurpose(
        context,
        icon: LucideIcons.bell,
        titolo: 'Avvisi sul lavoro',
        motivo:
            'Ti avvisiamo quando ti viene assegnato un intervento, quando cambia un appuntamento '
            'e quando un rapportino ha bisogno di te. Nient\'altro.',
        senzaDiEsso:
            'Senza notifiche l\'app funziona lo stesso: trovi tutto in Dashboard e in Calendario, '
            'ma lo scopri quando apri l\'app.',
        cta: 'Attiva le notifiche',
      );
      if (!wants) return;

      if (!await service.ensurePermission()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Le notifiche restano bloccate dal sistema. Puoi consentirle dalle impostazioni '
              'del telefono.',
            ),
          ),
        );
        return;
      }
    }

    notifier.toggle(key: 'pushAbilitate');
  }
}

/// Turn the biometric lock on only if this device can actually honour it.
///
/// The toggle used to flip a bool unconditionally, with no biometrics package in the project at
/// all — a technician could switch it on and believe the data on their phone was protected. Two
/// things have to be true before it may go on: the hardware exists with something enrolled, and
/// the technician can pass the prompt right now. Enabling a lock nobody can open is its own
/// failure mode.
Future<void> _toggleBiometrics(
  BuildContext context,
  WidgetRef ref,
  ImpostazioniState settings,
) async {
  final notifier = ref.read(impostazioniProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);

  // Turning it off needs no ceremony: the user is already past the lock.
  if (settings.autenticazioneBiometrica) {
    notifier.toggle(key: 'autenticazioneBiometrica');
    return;
  }

  final service = ref.read(biometricServiceProvider);

  if (!await service.isAvailable()) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Nessuna impronta o Face ID configurati su questo dispositivo. '
          'Aggiungili nelle impostazioni del telefono, poi riprova.',
        ),
      ),
    );
    return;
  }

  // Prove it works before relying on it.
  final ok = await service.authenticate(
    reason: 'Conferma la tua identità per attivare il blocco biometrico',
  );

  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Verifica non riuscita. Blocco biometrico non attivato.'),
      ),
    );
    return;
  }

  notifier.toggle(key: 'autenticazioneBiometrica');
}

// ══════════════════════════════════════════════════════════════════════════════
// Profile Card
// ══════════════════════════════════════════════════════════════════════════════

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.displayName, this.email});

  final String displayName;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: AppCard(
        child: Row(
          children: [
            AppAvatar(
              name: displayName.isNotEmpty ? displayName : (email ?? '?'),
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName.isNotEmpty ? displayName : (email ?? '—'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.ink,
                    ),
                  ),
                  if (displayName.isNotEmpty && email != null)
                    Text(
                      email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: context.colors.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Section title
// ══════════════════════════════════════════════════════════════════════════════

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.lg,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: context.colors.inkMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Settings group card
// ══════════════════════════════════════════════════════════════════════════════

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: children),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Toggle row
// ══════════════════════════════════════════════════════════════════════════════

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: context.colors.borderLight))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.colors.bg3,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: context.colors.inkFaint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          AppToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Logout row
// ══════════════════════════════════════════════════════════════════════════════

class _LogoutSettingRow extends StatelessWidget {
  const _LogoutSettingRow({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.colors.redSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(LucideIcons.logOut, size: 17, color: context.colors.red),
      ),
      title: 'Esci dall\'account',
      subtitle: 'Disconnetti questo dispositivo',
      showDivider: false,
      onTap: () => _confirmLogout(context),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esci dall\'account'),
        content: const Text('Sei sicuro di voler uscire dall\'account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.red),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(loginProvider.notifier).signOut();
    }
  }
}

/// What this handset can and cannot do about dictation, item by item.
///
/// Exists because "voice-assisted entry works" is not a property of the app — it is a property of
/// the phone in someone's hand, and it varies across a fleet. ADR-0017 accepts that and requires
/// the app to degrade honestly rather than reach for the network; this is where the honesty is
/// legible. It is also the fastest way to answer the question the ADR could not: whether offline
/// Italian is actually present on the hardware technicians carry.
class _DictationDiagnosticsRow extends ConsumerWidget {
  const _DictationDiagnosticsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = ref.watch(dictationCapabilityProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        14,
      ),
      child: capability.when(
        loading: () =>
            const _DictationLine(label: 'Verifica in corso…', state: null),
        error: (_, _) =>
            const _DictationLine(label: 'Verifica non riuscita', state: false),
        data: (c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.canDictate
                  ? 'Dettatura disponibile'
                  : 'Dettatura non disponibile',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 10),
            _DictationLine(
              label: 'Riconoscimento vocale',
              state: c.recognizerAvailable,
            ),
            _DictationLine(
              label: c.italianLocaleId == null
                  ? 'Italiano'
                  : 'Italiano (${c.italianLocaleId})',
              state: c.italianAvailable,
            ),
            // The one that decides it. Everything else can be true and dictation still refused,
            // because recognition that needs a server is no use in a plant room and would send
            // site audio off the device.
            _DictationLine(
              label: 'Funziona offline (sul dispositivo)',
              state: c.onDeviceRecognitionAvailable,
            ),
            _DictationLine(
              label: 'Microfono consentito',
              state: c.microphoneGranted,
            ),
            if (!c.canDictate) ...[
              const SizedBox(height: 10),
              Text(
                c.unavailableMessage!,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  height: 1.4,
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Puoi comunque compilare il rapportino scrivendo normalmente.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  height: 1.4,
                  color: context.colors.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DictationLine extends StatelessWidget {
  const _DictationLine({required this.label, required this.state});

  /// Null while the answer is still being fetched.
  final bool? state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (state) {
      true => (LucideIcons.checkCircle2, context.colors.green),
      false => (LucideIcons.alertCircle, context.colors.inkMuted),
      null => (LucideIcons.circle, context.colors.inkDisabled),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                color: context.colors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
