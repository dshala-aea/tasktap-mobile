import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../presentation/providers/auth_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AltroHubScreen
// ══════════════════════════════════════════════════════════════════════════════

/// Altro tab hub — P4 "Altro" spec.
///
/// Dark user card → Gestione 2-col grid → Sistema list → Logout.
class AltroHubScreen extends ConsumerWidget {
  const AltroHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final displayName = user?.displayName ?? user?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(title: 'Altro'),
            ),

            // ── Dark user card ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _UserCard(displayName: displayName, email: user?.email),
            ),

            // ── Gestione section ───────────────────────────────────────────
            const SliverToBoxAdapter(
              child: SectionTitle(title: 'Gestione'),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.4,
                ),
                delegate: SliverChildListDelegate(_buildGestioneTiles(context)),
              ),
            ),

            // ── Sistema section ────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: SectionTitle(title: 'Sistema'),
            ),
            SliverToBoxAdapter(
              child: _SistemaSection(),
            ),

            // ── Danger: Logout ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _LogoutRow(ref: ref),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGestioneTiles(BuildContext context) {
    return [
      _GestioneTile(
        icon: LucideIcons.clipboardList,
        label: 'Interventi',
        color: const Color(0xFF2563EB), // BLUE
        onTap: () => context.go(AppRoutes.ticket),
      ),
      _GestioneTile(
        icon: LucideIcons.fileText,
        label: 'Rapportini',
        color: const Color(0xFF06AED5), // CYAN
        onTap: () => context.go(AppRoutes.altroRapportini),
      ),
      _GestioneTile(
        icon: LucideIcons.users,
        label: 'Clienti',
        color: const Color(0xFF4CAF50), // GREEN
        onTap: () => context.push(AppRoutes.altroClienti),
      ),
      _GestioneTile(
        icon: LucideIcons.package,
        label: 'Prodotti',
        color: const Color(0xFFF4A261), // warm orange
        // Prodotti data not cached on device — use ComingSoon.
        onTap: () => _pushComingSoon(context, 'Prodotti'),
      ),
      _GestioneTile(
        icon: LucideIcons.warehouse,
        label: 'Magazzino',
        color: const Color(0xFFFFB200), // AMBER
        onTap: () => context.push(AppRoutes.altroMagazzino),
      ),
      _GestioneTile(
        icon: LucideIcons.receipt,
        label: 'Fatture',
        color: const Color(0xFF7C3AED), // violet
        // TODO(D5): wire Fatture list
        onTap: () => _pushComingSoon(context, 'Fatture'),
      ),
      _GestioneTile(
        icon: LucideIcons.users2,
        label: 'Team',
        color: const Color(0xFF06AED5), // CYAN
        // TODO(D5): wire Team list
        onTap: () => _pushComingSoon(context, 'Team'),
      ),
      _GestioneTile(
        icon: LucideIcons.tag,
        label: 'Tag',
        color: const Color(0xFFEF4444), // red
        // TODO(D5): wire Tag list
        onTap: () => _pushComingSoon(context, 'Tag'),
      ),
    ];
  }

  void _pushComingSoon(BuildContext context, String title) {
    context.push(AppRoutes.altroComingSoon, extra: title);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// User Card
// ══════════════════════════════════════════════════════════════════════════════

class _UserCard extends StatelessWidget {
  const _UserCard({required this.displayName, this.email});

  final String displayName;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.CHARCOAL,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.SH,
        ),
        child: Row(
          children: [
            AppAvatar(
              name: displayName.isNotEmpty ? displayName : (email ?? '?'),
              size: 52,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName.isNotEmpty ? displayName : (email ?? '—'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.WHITE,
                    ),
                  ),
                  if (displayName.isNotEmpty && email != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.WHITE.withAlpha(153),
                      ),
                    ),
                  ],
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
// Gestione tile
// ══════════════════════════════════════════════════════════════════════════════

class _GestioneTile extends StatelessWidget {
  const _GestioneTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.SH,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 22, color: AppColors.WHITE),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.WHITE,
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

// ══════════════════════════════════════════════════════════════════════════════
// Sistema section
// ══════════════════════════════════════════════════════════════════════════════

class _SistemaSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Notifiche — unread badge (0 for now)
            ListRow(
              leading: _sistemaTileIcon(LucideIcons.bell, AppColors.BLUE),
              title: 'Notifiche',
              subtitle: 'Avvisi e aggiornamenti',
              meta: AppBadge(label: '0', bgColor: AppColors.BG3),
              showDivider: true,
              onTap: () => context.push(AppRoutes.altroNotifiche),
            ),
            // Audit log
            ListRow(
              leading:
                  _sistemaTileIcon(LucideIcons.clipboardCheck, AppColors.GREEN),
              title: 'Audit log',
              subtitle: 'Cronologia attività',
              showDivider: true,
              onTap: () =>
                  context.push(AppRoutes.altroComingSoon, extra: 'Audit log'),
            ),
            // Impostazioni
            ListRow(
              leading:
                  _sistemaTileIcon(LucideIcons.settings, AppColors.CHARCOAL),
              title: 'Impostazioni',
              subtitle: 'App, notifiche, account',
              showDivider: true,
              onTap: () => context.push(AppRoutes.altroImpostazioni),
            ),
            // Ruoli e permessi
            ListRow(
              leading: _sistemaTileIcon(LucideIcons.shieldCheck, AppColors.AMBER),
              title: 'Ruoli e permessi',
              subtitle: 'Gestione accessi',
              showDivider: false,
              onTap: () => context.push(AppRoutes.altroComingSoon,
                  extra: 'Ruoli e permessi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sistemaTileIcon(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Logout row
// ══════════════════════════════════════════════════════════════════════════════

class _LogoutRow extends StatelessWidget {
  const _LogoutRow({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 24, 19, 0),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListRow(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.REDSOFT,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.logOut, size: 18,
                color: Color(0xFFAA0000)),
          ),
          title: 'Esci dall\'account',
          subtitle: 'Disconnetti questo dispositivo',
          showDivider: false,
          onTap: () => _confirmLogout(context),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Esci dall\'account'),
        content: const Text(
          'Sei sicuro di voler uscire dall\'account?',
        ),
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
