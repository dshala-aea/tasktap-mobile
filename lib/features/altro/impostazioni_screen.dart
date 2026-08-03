import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/config/app_info_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../presentation/providers/auth_providers.dart';
import 'impostazioni_provider.dart';

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
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Impostazioni',
                showBack: true,
              ),
            ),

            // ── Profile card ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _ProfileCard(
                displayName: displayName,
                email: user?.email,
              ),
            ),

            // ── Notifiche ──────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'Notifiche'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  _ToggleRow(
                    icon: LucideIcons.bell,
                    title: 'Notifiche push',
                    subtitle: 'Ricevi avvisi in tempo reale',
                    value: settings.pushAbilitate,
                    onChanged: (_) => notifier.toggle(key: 'pushAbilitate'),
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
                    subtitle: 'Posizione GPS per i rapportini',
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
                    subtitle: 'Accesso con impronta o Face ID',
                    value: settings.autenticazioneBiometrica,
                    onChanged: (_) =>
                        notifier.toggle(key: 'autenticazioneBiometrica'),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            // ── Sistema ───────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: _SettingsSectionTitle(title: 'Sistema'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  _LogoutSettingRow(ref: ref),
                ],
              ),
            ),

            // ── Version footer ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 32, 19, 0),
                child: Center(
                  child: appInfoAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (info) => Text(
                      'TaskTap v${info.displayVersion}',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: AppColors.DIS,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 60)),
          ],
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 19),
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
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.DARK,
                    ),
                  ),
                  if (displayName.isNotEmpty && email != null)
                    Text(
                      email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.MUTED,
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
      padding: const EdgeInsets.fromLTRB(19, 20, 19, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.MUTED,
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
      padding: const EdgeInsets.symmetric(horizontal: 19),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.BL))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.BG3,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: AppColors.FG2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.DARK,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.MUTED,
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
          color: AppColors.REDSOFT,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(LucideIcons.logOut, size: 17,
            color: Color(0xFFAA0000)),
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
        content:
            const Text('Sei sicuro di voler uscire dall\'account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
