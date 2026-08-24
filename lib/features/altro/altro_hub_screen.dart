import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../data/entitlements/entitlement_providers.dart';
import '../../data/entitlements/entitlement_repository.dart';
import '../../presentation/providers/auth_providers.dart';
import 'notifiche_provider.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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
      body: SafeArea(
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.4,
                ),
                delegate: SliverChildListDelegate(
                  _buildGestioneTiles(
                    context,
                    ref.watch(cachedEntitlementProvider).valueOrNull,
                  ),
                ),
              ),
            ),

            // ── Sistema section ────────────────────────────────────────────
            const SliverToBoxAdapter(child: SectionTitle(title: 'Sistema')),
            SliverToBoxAdapter(child: _SistemaSection()),

            // ── Danger: Logout ─────────────────────────────────────────────
            SliverToBoxAdapter(child: _LogoutRow(ref: ref)),

            SliverPadding(
              padding: EdgeInsets.only(bottom: context.navClearance),
            ),
          ],
        ),
      ),
    );
  }

  /// The hub's tiles, minus the modules this tenant does not hold.
  ///
  /// Every one of these used to be drawn for everybody. Cantieri, Contratti, Prodotti and
  /// Magazzino are sold separately, so on a tenant without them the tile led to a screen the
  /// server answers with a refusal — a technician found out three taps in, and could not tell
  /// "not for you" from "broken". PRODUCT.md's rule is that the client renders what the server
  /// allows; it was not being applied to modules at all.
  ///
  /// Keys are `ModuleKeys` from the backend (`src/TaskTapAPI.Core/Billing/ModuleKeys.cs`).
  /// Never gate on a key that is not in that file — a typo reads as "not entitled" and silently
  /// removes a screen.
  List<Widget> _buildGestioneTiles(
    BuildContext context,
    Entitlement? entitlement,
  ) {
    final tiles =
        <({IconData icon, String label, String module, VoidCallback onTap})>[
          (
            icon: LucideIcons.clipboardList,
            label: 'Interventi',
            module: 'interventi',
            onTap: () => context.go(AppRoutes.ticket),
          ),
          (
            icon: LucideIcons.fileText,
            label: 'Rapportini',
            module: 'rapportini',
            onTap: () => context.go(AppRoutes.altroRapportini),
          ),
          (
            icon: LucideIcons.users,
            label: 'Clienti',
            module: 'clienti',
            onTap: () => context.push(AppRoutes.altroClienti),
          ),
          // Sedi are customer sites: the same always-on module, not one of its own.
          (
            icon: LucideIcons.mapPin,
            label: 'Sedi',
            module: 'clienti',
            onTap: () => context.push('/altro/sedi'),
          ),
          (
            icon: LucideIcons.hardHat,
            label: 'Cantieri',
            module: 'cantieri',
            onTap: () => context.push('/altro/cantieri'),
          ),
          (
            icon: LucideIcons.package,
            label: 'Prodotti',
            module: 'prodotti',
            onTap: () => context.push('/altro/prodotti'),
          ),
          (
            icon: LucideIcons.warehouse,
            label: 'Magazzino',
            module: 'magazzino',
            onTap: () => context.push(AppRoutes.altroMagazzino),
          ),
          (
            icon: LucideIcons.fileSignature,
            label: 'Contratti',
            module: 'contratti',
            onTap: () => context.push('/altro/contratti'),
          ),
          // Squadre is crew management — the always-on `team` module.
          (
            icon: LucideIcons.users2,
            label: 'Squadre',
            module: 'team',
            onTap: () => context.push('/altro/squadre'),
          ),
          (
            icon: LucideIcons.calendarDays,
            label: 'Pianificazioni',
            module: 'pianificazione',
            onTap: () => context.push('/altro/pianificazioni'),
          ),
        ];

    return [
      for (final t in tiles)
        if (moduleIsOffered(t.module, entitlement))
          CompartmentTile(icon: t.icon, label: t.label, onTap: t.onTap),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      // A RackCell, not a hand-rolled Container. This was the one card on the screen that bypassed
      // the shared primitive, and it did so by reintroducing exactly what the world refuses: a
      // rounded rectangle floating on a drop shadow. Depth here is a border, like everywhere else.
      //
      // ledgeColor is explicit rather than the theme default: this card is a fixed CHARCOAL plate
      // regardless of light/dark mode, and the default border token is tuned for the bone label
      // card it usually sits on — on a fixed dark ground it would read close to invisible, the
      // same problem active_tracker_strip's own border already solved with translucent white. Not
      // the accent: that means attention-required or selected, and this static identity plate is
      // neither — same reasoning as the dashboard hero's own DA FARE readout staying white when
      // nothing is outstanding.
      child: RackCell(
        flush: false,
        background: AppColors.CHARCOAL,
        ledgeColor: Colors.white.withAlpha(60),
        padding: const EdgeInsets.all(AppSpacing.lg),
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
                    style: TextStyle(
                      fontFamily: 'Sora',
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
                      style: TextStyle(
                        fontFamily: 'Manrope',
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
// ══════════════════════════════════════════════════════════════════════════════
// Sistema section
// ══════════════════════════════════════════════════════════════════════════════

class _SistemaSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
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
            leading: _sistemaTileIcon(
              LucideIcons.clipboardCheck,
              context.colors.green,
            ),
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
          // I miei dati — the subject-access surface. Above Impostazioni rather than buried in it:
          // it is not a preference, it is the answer to "what do you know about me", and the
          // backend has served it since before this app shipped with nothing on the client asking.
          ListRow(
            leading: _sistemaTileIcon(
              LucideIcons.shieldCheck,
              context.colors.blue,
            ),
            title: 'I miei dati',
            subtitle: 'Cosa registra l\'azienda su di te',
            showDivider: true,
            onTap: () => context.push(AppRoutes.altroIMieiDati),
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
            leading: _sistemaTileIcon(
              LucideIcons.shieldCheck,
              context.colors.amber,
            ),
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
    );
  }

  Widget _sistemaTileIcon(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: AppRack.insetShape,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.xl,
        AppSpacing.pagePadding,
        0,
      ),
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
