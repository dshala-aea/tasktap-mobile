import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../presentation/providers/auth_providers.dart';
import 'notifiche_provider.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
      backgroundColor: context.colors.bg2,
      body: Rack(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: ScreenHeader(title: 'Altro')),

              // ── Dark user card ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _UserCard(displayName: displayName, email: user?.email),
              ),

              // ── Gestione section ───────────────────────────────────────────
              const SliverToBoxAdapter(child: SectionTitle(title: 'Gestione')),
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
              const SliverToBoxAdapter(child: SectionTitle(title: 'Sistema')),
              SliverToBoxAdapter(child: _SistemaSection()),

              // ── Danger: Logout ─────────────────────────────────────────────
              SliverToBoxAdapter(child: _LogoutRow(ref: ref)),

              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGestioneTiles(BuildContext context) {
    return [
      _GestioneTile(
        icon: LucideIcons.clipboardList,
        label: 'Interventi',
        onTap: () => context.go(AppRoutes.ticket),
      ),
      _GestioneTile(
        icon: LucideIcons.fileText,
        label: 'Rapportini',
        onTap: () => context.go(AppRoutes.altroRapportini),
      ),
      _GestioneTile(
        icon: LucideIcons.users,
        label: 'Clienti',
        onTap: () => context.push(AppRoutes.altroClienti),
      ),
      _GestioneTile(
        icon: LucideIcons.mapPin,
        label: 'Sedi',
        onTap: () => context.push('/altro/sedi'),
      ),
      _GestioneTile(
        icon: LucideIcons.hardHat,
        label: 'Cantieri',
        onTap: () => context.push('/altro/cantieri'),
      ),
      _GestioneTile(
        icon: LucideIcons.package,
        label: 'Prodotti',
        onTap: () => context.push('/altro/prodotti'),
      ),
      _GestioneTile(
        icon: LucideIcons.warehouse,
        label: 'Magazzino',
        onTap: () => context.push(AppRoutes.altroMagazzino),
      ),
      _GestioneTile(
        icon: LucideIcons.fileSignature,
        label: 'Contratti',
        onTap: () => context.push('/altro/contratti'),
      ),
      _GestioneTile(
        icon: LucideIcons.users2,
        label: 'Squadre',
        onTap: () => context.push('/altro/squadre'),
      ),
      _GestioneTile(
        icon: LucideIcons.calendarDays,
        label: 'Pianificazioni',
        onTap: () => context.push('/altro/pianificazioni'),
      ),
    ];
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
          borderRadius: AppRack.freeShape,
          boxShadow: context.colors.shadow,
        ),
        child: Row(
          children: [
            AppAvatar(name: displayName.isNotEmpty ? displayName : (email ?? '?'), size: 52),
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

/// A drawer in the parts wall.
///
/// This was a saturated colour tile — ten of them, in ten hues. The colour was decoration, not
/// information: cyan meant Rapportini and also Squadre, blue meant Interventi and also
/// Pianificazioni, so no hue identified anything and the grid read as a toybox above a list of
/// dense work screens. Operate mode spends the accent on primary actions, current selection and
/// state; this was none of those.
///
/// It is now a labelled cell like every other container in the app. What distinguishes ten
/// drawers in a real van is the label and the silhouette on it, which is exactly what is left.
class _GestioneTile extends StatelessWidget {
  const _GestioneTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RackCell(
      onTap: onTap,
      flush: false,
      minHeight: 84,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: c.inkFaint),
          const SizedBox(height: 14),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sistema section
// ══════════════════════════════════════════════════════════════════════════════

class _SistemaSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Notifiche — unread badge
            ListRow(
              leading: _sistemaTileIcon(LucideIcons.bell, context.colors.blue),
              title: 'Notifiche',
              subtitle: 'Avvisi e aggiornamenti',
              meta: ref.watch(notificheUnreadCountProvider) > 0
                  ? AppBadge(
                      label: '${ref.watch(notificheUnreadCountProvider)}',
                      bgColor: context.colors.red,
                    )
                  : null,
              showDivider: true,
              onTap: () => context.push(AppRoutes.altroNotifiche),
            ),
            // Audit log
            ListRow(
              leading: _sistemaTileIcon(LucideIcons.clipboardCheck, context.colors.green),
              title: 'Audit log',
              subtitle: 'Cronologia attività',
              showDivider: true,
              onTap: () => context.push(
                AppRoutes.altroNonDisponibile,
                extra: (
                  titolo: 'Audit log',
                  motivo:
                      "Il backend registra un log di controllo (/api/admin/audit-log) ma il client mobile non lo scarica ancora.",
                ),
              ),
            ),
            // Impostazioni
            ListRow(
              leading: _sistemaTileIcon(LucideIcons.settings, AppColors.CHARCOAL),
              title: 'Impostazioni',
              subtitle: 'App, notifiche, account',
              showDivider: true,
              onTap: () => context.push(AppRoutes.altroImpostazioni),
            ),
            // Ruoli e permessi
            ListRow(
              leading: _sistemaTileIcon(LucideIcons.shieldCheck, context.colors.amber),
              title: 'Ruoli e permessi',
              subtitle: 'Gestione accessi',
              showDivider: false,
              onTap: () => context.push(
                AppRoutes.altroNonDisponibile,
                extra: (
                  titolo: 'Ruoli e permessi',
                  motivo:
                      "La matrice ruoli/permessi esiste lato server (/api/admin/role-permissions) ma la sua gestione non è ancora stata costruita nel client mobile.",
                ),
              ),
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
      decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8)),
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
              color: context.colors.redSoft,
              borderRadius: AppRack.insetShape,
            ),
            child: Icon(LucideIcons.logOut, size: 18, color: context.colors.red),
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
        content: const Text('Sei sicuro di voler uscire dall\'account?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
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
